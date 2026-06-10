# =============================================================
# player.gd — Entidad jugador (GDD §4, §5) — FASES 3-4
# Novedades:
#  - La física se congela hasta que el chunk bajo el jugador esté
#    cargado (streaming §2.3): nunca caes a través de terreno
#    que aún no llegó del servidor.
#  - Minado con HP: TOQUE CORTO = un golpe; MANTENER el dedo sobre
#    un tile = golpes continuos (cada 0.3 s).
#  - Tap sobre un slime = atacarlo (GDD §12).
# =============================================================
extends Node2D

const SIZE := Vector2(24, 44)
const GRAVITY := 1500.0
const MAX_FALL := 950.0
const SPEED := 230.0
const JUMP_VELOCITY := -560.0
const SYNC_INTERVAL := 0.05
const TAP_MAX_MS := 220
const TAP_MAX_DRIFT := 18.0
const HOLD_MINE_MS := 300        # cadencia del minado sostenido
const MINE_REACH := 170.0

var peer_id := 1
var color := Color.WHITE
var skin_id := "default"         # cosmético, lo fija el servidor (MONETIZACIÓN)
var player_name := ""
var velocity := Vector2.ZERO
var on_floor := false
var _skin_t := 0.0               # reloj de la animación de skins "anim"

var _world: Node2D
var _joystick: Control
var _target_pos := Vector2.ZERO
var _sync_accum := 0.0
var _last_sent := Vector2.INF
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
	queue_redraw()


func set_skin(id: String) -> void:
	skin_id = id
	queue_redraw()


func _draw() -> void:
	# Skin equipada (catálogo en main.gd). "default" = color por jugador.
	var s: Dictionary = get_parent().SKINS.get(skin_id, get_parent().SKINS["default"])
	var body: Color = color if skin_id == "default" else s.cuerpo
	if bool(s.anim):
		body = Color.from_hsv(fmod(_skin_t * 0.45, 1.0), 0.85, 0.95)
	var r := Rect2(-SIZE * 0.5, SIZE)
	draw_rect(r, body)
	draw_rect(r, s.borde, false, 2.0)
	draw_circle(Vector2(0, -SIZE.y * 0.5 + 10), 5, s.borde)
	var etiqueta: String = player_name if player_name != "" else "P%d" % peer_id
	draw_string(ThemeDB.fallback_font, Vector2(-60, -SIZE.y * 0.5 - 8), etiqueta,
		HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color.WHITE)


func _process(delta: float) -> void:
	var s: Dictionary = get_parent().SKINS.get(skin_id, {})
	if bool(s.get("anim", false)):
		_skin_t += delta
		queue_redraw()
	if is_multiplayer_authority():
		_process_local(delta)
	else:
		position = position.lerp(_target_pos, minf(1.0, 14.0 * delta))


# -------------------------------------------------------------
# FÍSICA LOCAL
# -------------------------------------------------------------
func _process_local(delta: float) -> void:
	# Streaming gate: sin chunk cargado no hay física (§2.3)
	if _world == null or not _world.area_ready(position):
		return

	var dir_x := Input.get_axis("ui_left", "ui_right")
	var jump := Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_up")
	if _joystick != null:
		var j: Vector2 = _joystick.output
		if absf(j.x) > 0.25:
			dir_x = clampf(j.x * 1.4, -1.0, 1.0)
		if j.y < -0.55:
			jump = true

	velocity.x = dir_x * SPEED
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	if on_floor and jump:
		velocity.y = JUMP_VELOCITY

	on_floor = false
	position.x += velocity.x * delta
	_resolve_collisions(0)
	position.y += velocity.y * delta
	_resolve_collisions(1)
	_clamp_to_world()

	_process_hold_mining()

	_sync_accum += delta
	if _sync_accum >= SYNC_INTERVAL:
		_sync_accum = 0.0
		if position.distance_squared_to(_last_sent) > 0.5:
			_last_sent = position
			sync_position.rpc(position)


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
# RED
# -------------------------------------------------------------
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_position(pos: Vector2) -> void:
	_target_pos = pos
