# =============================================================
# world.gd — Mundo por CHUNKS (GDD §2, §3, §6, §9) — FASES 3-4
# Novedades:
#  - Chunks 16x16 con streaming: el cliente pide al servidor los
#    chunks cercanos a su jugador y descarga los lejanos (§2.3).
#  - Renderizado por chunk: cambiar un tile redibuja 1 chunk (§15).
#  - HP por tile (§3.2): minar toma varios golpes; el daño del
#    golpe depende del pico del jugador (el SERVIDOR lo decide).
#  - Árboles de madera (recurso para crafting §8).
#  - Evento del mundo: lluvia de meteoros (§9) — el scheduler del
#    servidor la dispara y sincroniza a todos.
# =============================================================
extends Node2D

const ChunkRendererScript := preload("res://scripts/chunk_renderer.gd")

const TILE := 32
const CHUNK := 16             # tiles por lado de chunk (GDD §2.1)
const W := 160                # 160 * 32 = 5120 px
const H := 60                 # 60 * 32  = 1920 px
const SKY_ROWS := 14
const VIEW_R := 2             # radio de chunks visibles
const UNLOAD_R := 4           # radio de descarga

# Tipos de tile (GDD §3.1). 0 = vacío.
const T_DIRT := 1
const T_STONE := 2
const T_ORE := 3
const T_BEDROCK := 4
const T_WOOD := 5             # tronco — decorativo, no colisiona
const T_LEAF := 6             # hojas — decorativo, no colisiona

const COLORS := {
	T_DIRT: Color(0.55, 0.36, 0.20),
	T_STONE: Color(0.48, 0.50, 0.55),
	T_ORE: Color(0.92, 0.76, 0.18),
	T_BEDROCK: Color(0.15, 0.15, 0.18),
	T_WOOD: Color(0.42, 0.27, 0.13),
	T_LEAF: Color(0.20, 0.55, 0.22),
}

# GDD §3.2: HP y drop por tipo de tile
const HP := {T_DIRT: 40, T_STONE: 100, T_ORE: 140, T_WOOD: 60, T_LEAF: 20}
const DROPS := {T_DIRT: "dirt", T_STONE: "stone", T_ORE: "ore", T_WOOD: "wood"}
const ITEM_TILE := {"dirt": T_DIRT, "stone": T_STONE, "wood": T_WOOD}
const SOLID := {T_DIRT: true, T_STONE: true, T_ORE: true, T_BEDROCK: true}

const REACH := 200.0          # alcance validado por el servidor

var tiles: Dictionary = {}         # coord -> tipo (servidor: mundo completo)
var damage: Dictionary = {}        # coord -> HP restante (SOLO servidor)
var damage_ratio: Dictionary = {}  # coord -> 0..1 (visual, todos los peers)
var loaded: Dictionary = {}        # ccoord -> true (chunks cargados, cliente)
var renderers: Dictionary = {}     # ccoord -> ChunkRenderer
var _pending: Dictionary = {}      # ccoord -> true (peticiones en vuelo)


# -------------------------------------------------------------
# GENERACIÓN (solo servidor)
# -------------------------------------------------------------
func generate() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.04

	for x in W:
		var surface := SKY_ROWS + int((noise.get_noise_1d(float(x)) + 1.0) * 4.0)
		for y in range(surface, H):
			var depth := y - surface
			var t := T_DIRT
			if depth > 5:
				t = T_STONE
				if noise.get_noise_2d(float(x) * 3.0, float(y) * 3.0) > 0.42:
					t = T_ORE
			tiles[Vector2i(x, y)] = t
		tiles[Vector2i(x, H - 1)] = T_BEDROCK
		# Árboles (§8 — fuente de madera para crafting)
		if x > 2 and x < W - 3 and randf() < 0.10:
			_plant_tree(x, surface)


func _plant_tree(x: int, surface: int) -> void:
	var height := randi_range(4, 6)
	for h in height:
		tiles[Vector2i(x, surface - 1 - h)] = T_WOOD
	for lx in range(-1, 2):
		for ly in range(2):
			var c := Vector2i(x + lx, surface - height - 1 - ly)
			if tiles.get(c, 0) == 0:
				tiles[c] = T_LEAF


func surface_spawn(x: int) -> Vector2:
	x = clampi(x, 2, W - 3)
	for y in H:
		if SOLID.has(tiles.get(Vector2i(x, y), 0)):
			return Vector2(x * TILE + TILE * 0.5, y * TILE - 40.0)
	return Vector2(x * TILE, 100.0)


# -------------------------------------------------------------
# CONSULTAS (usadas por la física — GDD §5)
# -------------------------------------------------------------
func chunk_of(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x / CHUNK, coord.y / CHUNK)


func is_loaded(cc: Vector2i) -> bool:
	return multiplayer.is_server() or loaded.has(cc)


## Un chunk no cargado se trata como SÓLIDO: la física del jugador
## se congela hasta que el área esté lista (ver player.gd).
func is_solid(coord: Vector2i) -> bool:
	if not is_loaded(chunk_of(coord)):
		return true
	return SOLID.has(tiles.get(coord, 0))


func area_ready(pos: Vector2) -> bool:
	var coord := Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
	return is_loaded(chunk_of(coord))


# -------------------------------------------------------------
# STREAMING DE CHUNKS (GDD §2.3)
# main.gd llama esto periódicamente con la posición del jugador
# local. Carga lo cercano, descarga lo lejano (caché local).
# -------------------------------------------------------------
func update_streaming(center: Vector2) -> void:
	var cc := Vector2i(floori(center.x / (TILE * CHUNK)), floori(center.y / (TILE * CHUNK)))
	var maxc := Vector2i(ceili(float(W) / CHUNK) - 1, ceili(float(H) / CHUNK) - 1)

	for cx in range(maxi(cc.x - VIEW_R, 0), mini(cc.x + VIEW_R, maxc.x) + 1):
		for cy in range(maxi(cc.y - VIEW_R, 0), mini(cc.y + VIEW_R, maxc.y) + 1):
			var c := Vector2i(cx, cy)
			if is_loaded(c):
				_ensure_renderer(c)
			elif not _pending.has(c):
				_pending[c] = true
				request_chunk.rpc_id(1, c)

	for c: Vector2i in renderers.keys():
		if absi(c.x - cc.x) > UNLOAD_R or absi(c.y - cc.y) > UNLOAD_R:
			renderers[c].queue_free()
			renderers.erase(c)
			if not multiplayer.is_server():
				loaded.erase(c)
				for x in range(c.x * CHUNK, (c.x + 1) * CHUNK):
					for y in range(c.y * CHUNK, (c.y + 1) * CHUNK):
						var coord := Vector2i(x, y)
						tiles.erase(coord)
						damage_ratio.erase(coord)


@rpc("any_peer", "call_remote", "reliable")
func request_chunk(c: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var data := {}
	for x in range(c.x * CHUNK, (c.x + 1) * CHUNK):
		for y in range(c.y * CHUNK, (c.y + 1) * CHUNK):
			var coord := Vector2i(x, y)
			var t: int = tiles.get(coord, 0)
			if t != 0:
				data[coord] = t
	receive_chunk.rpc_id(multiplayer.get_remote_sender_id(), c, data)


@rpc("authority", "call_remote", "reliable")
func receive_chunk(c: Vector2i, data: Dictionary) -> void:
	_pending.erase(c)
	loaded[c] = true
	for coord: Vector2i in data:
		tiles[coord] = data[coord]
	_ensure_renderer(c)
	renderers[c].queue_redraw()


func _ensure_renderer(c: Vector2i) -> void:
	if renderers.has(c):
		return
	var r := Node2D.new()
	r.set_script(ChunkRendererScript)
	r.chunk = c
	r.world = self
	r.position = Vector2(c.x * CHUNK * TILE, c.y * CHUNK * TILE)
	add_child(r)
	renderers[c] = r


func _redraw_at(coord: Vector2i) -> void:
	var c := chunk_of(coord)
	if renderers.has(c):
		renderers[c].queue_redraw()


func _set_tile(coord: Vector2i, t: int) -> void:
	if t == 0:
		tiles.erase(coord)
	else:
		tiles[coord] = t
	damage_ratio.erase(coord)
	_redraw_at(coord)


func _draw() -> void:
	# Fondo del mundo (los chunks dibujan los tiles encima)
	draw_rect(Rect2(0, 0, W * TILE, SKY_ROWS * TILE), Color(0.45, 0.65, 0.95))
	draw_rect(Rect2(0, SKY_ROWS * TILE, W * TILE, (H - SKY_ROWS) * TILE), Color(0.10, 0.09, 0.13))


# -------------------------------------------------------------
# MINADO CON HP (GDD §6, §3.2)
# Cada golpe descuenta HP según el pico del jugador. EL SERVIDOR
# decide el daño consultando el inventario real (anti-cheat §16).
# -------------------------------------------------------------
func try_hit(coord: Vector2i) -> void:
	if multiplayer.is_server():
		_do_hit(coord, 1)
	else:
		request_hit.rpc_id(1, coord)


@rpc("any_peer", "call_remote", "reliable")
func request_hit(coord: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	_do_hit(coord, multiplayer.get_remote_sender_id())


func _do_hit(coord: Vector2i, miner_id: int) -> void:
	var t: int = tiles.get(coord, 0)
	if t == 0 or not HP.has(t):
		return                       # vacío o indestructible (bedrock)
	if not _in_reach(miner_id, coord):
		return
	var dmg: int = get_parent().get_tool_damage(miner_id)
	var hp_left: int = damage.get(coord, HP[t]) - dmg
	if hp_left <= 0:
		damage.erase(coord)
		_set_tile(coord, 0)
		apply_tile.rpc(coord, 0)
		var drop: String = DROPS.get(t, "")
		if drop != "":
			get_parent().add_item(miner_id, drop)
	else:
		damage[coord] = hp_left
		damage_ratio[coord] = float(hp_left) / HP[t]
		_redraw_at(coord)
		apply_damage.rpc(coord, damage_ratio[coord])


@rpc("authority", "call_remote", "reliable")
func apply_damage(coord: Vector2i, ratio: float) -> void:
	if not is_loaded(chunk_of(coord)):
		return
	damage_ratio[coord] = ratio
	_redraw_at(coord)


@rpc("authority", "call_remote", "reliable")
func apply_tile(coord: Vector2i, t: int) -> void:
	if not is_loaded(chunk_of(coord)):
		return
	_set_tile(coord, t)


# -------------------------------------------------------------
# COLOCACIÓN (consume inventario — GDD §7)
# -------------------------------------------------------------
func try_place(coord: Vector2i, item: String) -> void:
	if multiplayer.is_server():
		_do_place(coord, item, 1)
	else:
		request_place.rpc_id(1, coord, item)


@rpc("any_peer", "call_remote", "reliable")
func request_place(coord: Vector2i, item: String) -> void:
	if not multiplayer.is_server():
		return
	_do_place(coord, item, multiplayer.get_remote_sender_id())


func _do_place(coord: Vector2i, item: String, placer_id: int) -> void:
	if coord.x < 0 or coord.x >= W or coord.y < 0 or coord.y >= H:
		return
	if tiles.get(coord, 0) != 0:
		return
	if not ITEM_TILE.has(item):
		return
	if not _in_reach(placer_id, coord):
		return
	if SOLID.has(ITEM_TILE[item]) and _overlaps_player(coord):
		return
	if not get_parent().consume_item(placer_id, item):
		return
	_set_tile(coord, ITEM_TILE[item])
	apply_tile.rpc(coord, ITEM_TILE[item])


# -------------------------------------------------------------
# EVENTO DEL MUNDO: METEORO (GDD §9)
# El scheduler de main.gd (servidor) lo dispara periódicamente.
# -------------------------------------------------------------
func meteor_strike() -> Vector2i:
	var x := randi_range(6, W - 7)
	var sy := SKY_ROWS
	for y in H:
		if SOLID.has(tiles.get(Vector2i(x, y), 0)):
			sy = y
			break
	var changes := {}
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if Vector2(dx, dy).length() > 3.2:
				continue
			var c := Vector2i(x + dx, sy + dy)
			var t: int = tiles.get(c, 0)
			if t == 0 or t == T_BEDROCK:
				continue
			changes[c] = 0
	# El meteoro deja mineral en el fondo del cráter
	for dx in range(-1, 2):
		var c := Vector2i(x + dx, sy + 3)
		if tiles.get(c, 0) != 0 and tiles.get(c, 0) != T_BEDROCK and c.y < H - 1:
			changes[c] = T_ORE
	for c: Vector2i in changes:
		_set_tile(c, changes[c])
		damage.erase(c)
	apply_changes.rpc(changes)
	return Vector2i(x, sy)


@rpc("authority", "call_remote", "reliable")
func apply_changes(changes: Dictionary) -> void:
	for c: Vector2i in changes:
		if is_loaded(chunk_of(c)):
			_set_tile(c, changes[c])


# -------------------------------------------------------------
# VALIDACIONES DEL SERVIDOR (GDD §16)
# -------------------------------------------------------------
func _in_reach(peer_id: int, coord: Vector2i) -> bool:
	var p: Node2D = get_parent().players.get(peer_id)
	if p == null:
		return false
	var center := Vector2(coord.x * TILE + TILE * 0.5, coord.y * TILE + TILE * 0.5)
	return p.position.distance_to(center) <= REACH


func _overlaps_player(coord: Vector2i) -> bool:
	var tile_rect := Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)
	for id: int in get_parent().players:
		var p: Node2D = get_parent().players[id]
		if Rect2(p.position - p.SIZE * 0.5, p.SIZE).intersects(tile_rect):
			return true
	return false
