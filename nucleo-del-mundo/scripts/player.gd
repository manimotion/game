# =============================================================
# player.gd — Entidad jugador (GDD §4, §5) — FASES 3-4
# Novedades:
#  - La física se congela hasta que el chunk bajo el jugador esté
#    cargado (streaming §2.3): nunca caes a través de terreno
#    que aún no llegó del servidor.
#  - Minado con HP: TOQUE CORTO = un golpe; MANTENER el dedo sobre
#    un tile = golpes continuos (cada 0.3 s).
#  - Tap sobre un slime = atacarlo (GDD §12).
#  - Movimiento server-authoritative + predicción/reconciliación
#    (GDD §10.2): cada cliente predice localmente (_process_local /
#    _simulate_step) y envía su input al servidor; el servidor simula
#    TODOS los jugadores (_process_remote_authority) y difunde la
#    posición real (main.sync_players); el cliente reconcilia
#    (_reconcile) su propio nodo contra ese snapshot.
# =============================================================
extends Node2D

const SIZE := Vector2(24, 44)
const GRAVITY := 1500.0
const MAX_FALL := 950.0
const SPEED := 230.0
const JUMP_VELOCITY := -560.0
const TAP_MAX_MS := 220
const TAP_MAX_DRIFT := 18.0
const HOLD_MINE_MS := 300        # cadencia del minado sostenido
const MINE_REACH := 170.0
const WATER_SLOW := 0.55         # Bloque 1 "Mundo vivo": ralentización en T_WATER

# --- Movimiento server-authoritative (GDD §10.2) ---
const INPUT_SEND_INTERVAL := 0.05      # 20 Hz, cliente -> servidor
const RECONCILE_SNAP_DIST := 96.0      # ~3 tiles: por encima, salto directo (teleport real)
const RECONCILE_LERP_SPEED := 10.0     # corrección suave (1/seg) si el error es pequeño
const RECONCILE_MIN_ERROR := 2.0       # por debajo, no corregir (evita jitter)
const RECONCILE_EXTRAPOLATION := 0.05  # seg: edad estimada del snapshot al llegar — comparar
                                       # contra pos+vel*esto evita que la corrección tire
                                       # SIEMPRE hacia atrás al correr (rubber-banding)

var peer_id := 1
var color := Color.WHITE
var skin_id := "default"         # cosmético, lo fija el servidor (MONETIZACIÓN)
var player_name := ""
var velocity := Vector2.ZERO
var on_floor := false
var _skin_t := 0.0               # reloj de la animación de skins "anim"
var _anim_t := 0.0               # reloj del ciclo de caminata
var _face := 1.0                 # 1 = derecha, -1 = izquierda
var _vis_vel := Vector2.ZERO     # velocidad visual (remotos: estimada)

var _world: Node2D
var _joystick: Control
var _cam: Camera2D = null
var _shake := 0.0                # sacudida de cámara (solo visual)
var _dust_t := 0.0               # cadencia del polvo al caminar (solo visual)
var _in_water := false           # para la salpicadura al ENTRAR al agua (solo visual)
var _target_pos := Vector2.ZERO  # remotos: posición del snapshot del servidor
var _target_vel := Vector2.ZERO  # remotos: velocidad del snapshot del servidor
var _input_accum := 0.0          # cliente no-host: cadencia de envío de input
var _jump_latch := false         # cliente no-host: retiene un tap de salto entre envíos
var _last_input_dir_x := 0.0     # SOLO servidor: último input recibido de este peer
var _last_input_jump := false    # SOLO servidor: idem
var _touches := {}               # index -> {pos, t, hit}


func _ready() -> void:
	color = Color.from_hsv(float(peer_id % 8) / 8.0, 0.85, 0.95)
	_target_pos = position
	_world = get_node_or_null("../World")

	if is_multiplayer_authority():
		_joystick = get_tree().get_first_node_in_group("joystick")
		var cam := Camera2D.new()
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 8.0
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = _world.W * _world.TILE
		cam.limit_bottom = _world.H * _world.TILE
		add_child(cam)
		cam.make_current()
		cam.reset_smoothing.call_deferred()
		_cam = cam
	queue_redraw()


## Sacudida de cámara (meteoro y otros impactos). Solo cosmético.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func set_skin(id: String) -> void:
	skin_id = id
	queue_redraw()


## Sprite por capas del Atlas (rediseño 2026-06-13): cada capa del atuendo
## se tiñe con su color de skin (camisa + pantalón + pelo + borde) y encima
## se dibuja el ACCESORIO de identidad (corona/cuernos/capucha/...). La skin
## "default" usa el color por-jugador para la camisa; "arcoíris" anima el tono.
func _draw() -> void:
	var s: Dictionary = get_parent().SKINS.get(skin_id, get_parent().SKINS["default"])
	var camisa: Color = color if skin_id == "default" else s.get("camisa", Color.WHITE)
	var accent: Color = s.get("accent", Color.WHITE)
	if bool(s.get("anim", false)):
		camisa = Color.from_hsv(fmod(_skin_t * 0.45, 1.0), 0.85, 0.95)
		accent = Color.from_hsv(fmod(_skin_t * 0.45 + 0.5, 1.0), 0.7, 1.0)

	# Frame según el movimiento visual: salto > caminar > reposo
	var f: Dictionary
	if absf(_vis_vel.y) > 60.0:
		f = Atlas.player_frames.jump[0]
	elif absf(_vis_vel.x) > 25.0:
		f = Atlas.player_frames.walk[int(_anim_t * 9.0) % 4]
	else:
		f = Atlas.player_frames.idle[0]

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_face, 1.0))
	var r := Rect2(-SIZE * 0.5, SIZE)
	draw_texture_rect(f.outline, r, false, s.get("borde", Color.BLACK))
	draw_texture_rect(f.skin, r, false)                                  # cara/ojos (fija)
	draw_texture_rect(f.hair, r, false, s.get("pelo", Color("4a3220")))
	draw_texture_rect(f.pants, r, false, s.get("pantalon", Color("3a4a6b")))
	draw_texture_rect(f.shirt, r, false, camisa)
	draw_texture_rect(f.boot, r, false)                                  # botas (fija)
	# Accesorio de identidad encima (corona, cuernos, capucha, ...)
	var acc := str(s.get("accesorio", ""))
	if acc != "" and Atlas.player_acc.has(acc):
		draw_texture_rect(Atlas.player_acc[acc], r, false, accent)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Nombre con sombra (legible sobre cualquier fondo)
	var etiqueta: String = player_name if player_name != "" else "P%d" % peer_id
	draw_string(ThemeDB.fallback_font, Vector2(-59, -SIZE.y * 0.5 - 7), etiqueta,
		HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(0, 0, 0, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(-60, -SIZE.y * 0.5 - 8), etiqueta,
		HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color.WHITE)


func _process(delta: float) -> void:
	var s: Dictionary = get_parent().SKINS.get(skin_id, {})
	if bool(s.get("anim", false)):
		_skin_t += delta

	if is_multiplayer_authority():
		# Caso A: mi nodo — predicción local (el host además ES la
		# autoridad real: su predicción nunca se reconcilia).
		_process_local(delta)
		_vis_vel = velocity
		_camera_fx(delta)
	elif multiplayer.is_server():
		# Caso B: nodo de un peer remoto, pero YO soy el servidor —
		# simulo su física real con el último input recibido (GDD §10.2).
		_process_remote_authority(delta)
		_vis_vel = velocity
	else:
		# Caso C: nodo de otro jugador en mi pantalla — lerp visual de siempre.
		var prev := position
		position = position.lerp(_target_pos, minf(1.0, 14.0 * delta))
		if delta > 0.0:   # velocidad estimada para animar a los remotos
			_vis_vel = _vis_vel.lerp((position - prev) / delta, 0.4)

	if absf(_vis_vel.x) > 25.0:
		_anim_t += delta
		_face = 1.0 if _vis_vel.x >= 0.0 else -1.0
	_water_fx()
	queue_redraw()


## Salpicadura al ENTRAR al agua (Bloque 1 "Mundo vivo"). 100% cosmético y
## local: corre sobre la posición visual de CUALQUIER nodo en mi pantalla
## (los 3 casos de _process); el sonido solo si el que se moja soy yo.
func _water_fx() -> void:
	if _world == null:
		return
	var feet_tile := Vector2i(floori(position.x / _world.TILE), floori(position.y / _world.TILE))
	var in_water: bool = _world.tiles.get(feet_tile, 0) == _world.T_WATER
	if in_water and not _in_water:
		if _world.fx != null:
			_world.fx.burst(position + Vector2(0, SIZE.y * 0.25), Color(0.45, 0.7, 0.95, 0.9), 9, 110.0)
		if is_multiplayer_authority():
			Sfx.play("agua")
	_in_water = in_water


## Sacudida de cámara (meteoro y otros impactos). Solo cosmético, solo
## para mi propio nodo (Caso A de _process).
func _camera_fx(delta: float) -> void:
	if _cam == null:
		return
	if _shake > 0.4:
		_shake = maxf(0.0, _shake - 26.0 * delta)
		_cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	else:
		_cam.offset = Vector2.ZERO


# -------------------------------------------------------------
# FÍSICA LOCAL — predicción del cliente (o autoridad real si soy
# además el servidor, es decir, el host).
# -------------------------------------------------------------
func _process_local(delta: float) -> void:
	# Streaming gate: sin chunk cargado no hay física (§2.3). El envío de
	# input sigue corriendo igualmente: congelado se manda input NEUTRO,
	# si no el servidor seguiría simulando con el último input viejo.
	var area_ok: bool = _world != null and _world.area_ready(position)
	var dir_x := 0.0
	var jump := false
	if area_ok:
		dir_x = Input.get_axis("ui_left", "ui_right")
		jump = Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_up")
		if _joystick != null:
			var j: Vector2 = _joystick.output
			if absf(j.x) > 0.25:
				dir_x = clampf(j.x * 1.4, -1.0, 1.0)
			if j.y < -0.55:
				jump = true

		var fall_v := _simulate_step(dir_x, jump, delta)
		_dust_fx(fall_v, delta)
		_process_hold_mining()

	# GDD §10.2: el cliente no-host predice localmente pero la física real
	# corre en el servidor — envía su input para que lo simule
	# (ver _process_remote_authority y main._broadcast_player_snapshot).
	# El salto se RETIENE entre envíos (_jump_latch): un tap más corto que
	# INPUT_SEND_INTERVAL no se pierde (si no, la predicción salta, el
	# servidor no, y la reconciliación "traga" el salto con un snap).
	if not multiplayer.is_server():
		_jump_latch = _jump_latch or jump
		_input_accum += delta
		if _input_accum >= INPUT_SEND_INTERVAL:
			_input_accum = 0.0
			send_input.rpc_id(1, dir_x, _jump_latch)
			_jump_latch = false


## Física pura (gravedad, input, colisión AABB, salto, clamp al mundo).
## Reutilizada por _process_local (predicción/autoridad del host) y por
## _process_remote_authority (servidor simulando nodos remotos). Devuelve
## la velocidad vertical ANTES de resolver la colisión Y (para el FX de
## polvo al aterrizar).
func _simulate_step(dir_x: float, jump: bool, delta: float) -> float:
	velocity.x = dir_x * SPEED
	# Bloque 1 "Mundo vivo": el agua de los ríos profundos ralentiza el
	# desplazamiento horizontal (sin afectar salto/gravedad).
	var feet_tile := Vector2i(floori(position.x / _world.TILE), floori(position.y / _world.TILE))
	if _world.tiles.get(feet_tile, 0) == _world.T_WATER:
		velocity.x *= WATER_SLOW
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	if on_floor and jump:
		velocity.y = JUMP_VELOCITY

	on_floor = false
	position.x += velocity.x * delta
	_resolve_collisions(0)
	var fall_v := velocity.y
	position.y += velocity.y * delta
	_resolve_collisions(1)
	_clamp_to_world()
	return fall_v


## Polvo al aterrizar y al caminar (solo visual, local a quien lo dibuja).
func _dust_fx(fall_v: float, delta: float) -> void:
	if _world.fx == null:
		return
	var feet := position + Vector2(0, SIZE.y * 0.5)
	if on_floor and fall_v > 420.0:
		_world.fx.burst(feet, Color(0.55, 0.45, 0.35), 8, 90.0)
	elif on_floor and absf(velocity.x) > 120.0:
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.18
			_world.fx.burst(feet - Vector2(signf(velocity.x) * 6.0, 0), Color(0.55, 0.45, 0.35), 2, 40.0)


## SOLO el servidor, sobre nodos de jugadores REMOTOS (no mi autoridad):
## simula la física real con el último input recibido del cliente
## (GDD §10.2). Sin streaming gate — el servidor siempre tiene el mundo
## completo (world.gd) — y sin minado por touch (eso es input local de
## cada cliente sobre su propio nodo, vía _touches/_unhandled_input).
func _process_remote_authority(delta: float) -> void:
	var fall_v := _simulate_step(_last_input_dir_x, _last_input_jump, delta)
	_dust_fx(fall_v, delta)


## Llamado por main._apply_player_snapshot cuando llega el snapshot
## autoritativo del servidor para MI nodo (cliente no-host, GDD §10.2).
## Error pequeño -> corrección suave (no "pelea" con la predicción local);
## error grande -> salto directo (teleport/respawn real o desync grave).
func _reconcile(server_pos: Vector2, server_vel: Vector2, server_on_floor: bool) -> void:
	# El snapshot llega con ~un intervalo de edad: la predicción local va
	# ADELANTE del servidor aunque ambos coincidan. Comparar (y corregir)
	# contra la posición extrapolada por la velocidad del servidor, no la
	# cruda — si no, correr en línea recta da un error perpetuo de
	# SPEED*edad (~11 px) que frena al jugador a tirones (rubber-banding).
	var target := server_pos + server_vel * RECONCILE_EXTRAPOLATION
	var error := position.distance_to(target)
	if error > RECONCILE_SNAP_DIST:
		position = server_pos
		velocity = server_vel
		on_floor = server_on_floor
	elif error > RECONCILE_MIN_ERROR:
		position = position.lerp(target, minf(1.0, RECONCILE_LERP_SPEED * (1.0 / 20.0)))


func _resolve_collisions(axis: int) -> void:
	var t: int = _world.TILE
	var r := Rect2(position - SIZE * 0.5, SIZE)
	var min_c := Vector2i(floori(r.position.x / t), floori(r.position.y / t))
	var max_c := Vector2i(floori((r.end.x - 0.001) / t), floori((r.end.y - 0.001) / t))

	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			if not _world.is_solid(Vector2i(cx, cy)):
				continue
			var tile_rect := Rect2(cx * t, cy * t, t, t)
			if not r.intersects(tile_rect):
				continue
			if axis == 0:
				if velocity.x > 0.0:
					position.x = tile_rect.position.x - SIZE.x * 0.5
				elif velocity.x < 0.0:
					position.x = tile_rect.end.x + SIZE.x * 0.5
				velocity.x = 0.0
			else:
				if velocity.y > 0.0:
					position.y = tile_rect.position.y - SIZE.y * 0.5
					on_floor = true
				elif velocity.y < 0.0:
					position.y = tile_rect.end.y + SIZE.y * 0.5
				velocity.y = 0.0
			r = Rect2(position - SIZE * 0.5, SIZE)


func _clamp_to_world() -> void:
	position.x = clampf(position.x, SIZE.x * 0.5, _world.W * _world.TILE - SIZE.x * 0.5)
	position.y = minf(position.y, _world.H * _world.TILE - SIZE.y * 0.5)


# -------------------------------------------------------------
# INTERACCIÓN
#  - toque corto: golpear slime / golpear tile / colocar bloque
#  - mantener sobre un tile: minado continuo
# -------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if not get_parent().is_point_on_ui(event.position):
				_touches[event.index] = {"pos": event.position, "t": Time.get_ticks_msec(), "hit": 0}
		else:
			var rec: Variant = _touches.get(event.index)
			_touches.erase(event.index)
			if rec == null:
				return
			var held: int = Time.get_ticks_msec() - rec.t
			if held < TAP_MAX_MS and event.position.distance_to(rec.pos) < TAP_MAX_DRIFT:
				_tap_at(event.position)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index].pos = event.position


func _process_hold_mining() -> void:
	var now := Time.get_ticks_msec()
	for idx: int in _touches:
		var rec: Dictionary = _touches[idx]
		if now - rec.t >= HOLD_MINE_MS and now - rec.hit >= HOLD_MINE_MS:
			rec.hit = now
			var wp := _to_world(rec.pos)
			if wp.distance_to(global_position) > MINE_REACH:
				continue
			var coord := Vector2i(floori(wp.x / _world.TILE), floori(wp.y / _world.TILE))
			if _world.tiles.get(coord, 0) != 0:
				Sfx.play("golpe")
				_world.try_hit(coord)


func _tap_at(screen_pos: Vector2) -> void:
	if _world == null:
		return
	var wp := _to_world(screen_pos)
	if wp.distance_to(global_position) > MINE_REACH:
		return

	# 1) ¿Hay un slime ahí? Atacar (GDD §12)
	var npcs: Node2D = get_node_or_null("../NPCs")
	if npcs != null:
		var nid: int = npcs.npc_at(wp)
		if nid != -1:
			Sfx.play("golpe")
			npcs.hit_local(nid)
			return

	# 2) ¿Tile? Golpear. ¿Vacío? Colocar el bloque seleccionado.
	var coord := Vector2i(floori(wp.x / _world.TILE), floori(wp.y / _world.TILE))
	if _world.tiles.get(coord, 0) != 0:
		Sfx.play("golpe")
		_world.try_hit(coord)
	else:
		var main: Node = get_parent()
		if main.selected_item != "":
			Sfx.play("poner")
			_world.try_place(coord, main.selected_item)


func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


# -------------------------------------------------------------
# RED — GDD §10.2: el cliente envía su input; el servidor simula y
# difunde la posición autoritativa (ver main.sync_players /
# _apply_player_snapshot, que llama a _reconcile).
# -------------------------------------------------------------
@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(dir_x: float, jump: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if not is_finite(dir_x):
		return   # NaN/inf de un cliente malicioso envenenaría la física (clampf(NAN)==NAN)
	_last_input_dir_x = clampf(dir_x, -1.0, 1.0)
	_last_input_jump = jump
