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
const FxScript := preload("res://scripts/fx.gd")

const TILE := 32
const CHUNK := 16             # tiles por lado de chunk (GDD §2.1)
const W := 200                # 200 * 32 = 6400 px
const H := 90                 # 90 * 32  = 2880 px
const SKY_ROWS := 24           # cielo ampliado: más espacio para el bioma aéreo
const DEEP_ROWS := 12          # últimas filas antes del bedrock: bioma subterráneo profundo
const VIEW_R := 2             # radio de chunks visibles
const UNLOAD_R := 4           # radio de descarga

# Tipos de tile (GDD §3.1). 0 = vacío.
const T_DIRT := 1
const T_STONE := 2
const T_ORE := 3
const T_BEDROCK := 4
const T_WOOD := 5             # tronco — decorativo, no colisiona
const T_LEAF := 6             # hojas — decorativo, no colisiona
const T_WALL := 7             # muralla craftable — sólida (Fase 7)
const T_CAMPFIRE := 8         # fogata — respawn + regen, no sólida (Fase 7)
const T_SPIKES := 9           # trampa de pinchos — daña NPCs por contacto (Fase 8)
const T_TOWER := 10           # torre de flechas — sólida, dispara sola (Fase 8)
const T_NEST := 11            # nido — sólido; si no se destruye, escupe enemigos (Fase 10)
const T_CRYSTAL := 12         # cristal — recurso de los biomas aéreo/profundo (sólido)
const T_WATER := 13           # agua — no sólida, decorativa, ralentiza (Bloque 1 "Mundo vivo")
const T_FEATHER := 14         # pluma — bioma aéreo, sólido (Bloque 1)
const T_AETHER := 15          # esencia — bioma aéreo, núcleo raro, sólido (Bloque 1)
const T_DIAMOND := 16         # diamante — bioma profundo, núcleo raro, sólido (Bloque 1)
const T_EMBER := 17           # ascua — bioma profundo, junto a vetas de agua, sólido (Bloque 1)
const T_TOWER_MEGA := 18      # torre mega — craftable con minerales, sólida (Bloque 2)
# Bloque 3 "Mundo vivo II" — exploración y eventos:
const T_RAIL := 19           # vía de tren abandonada — no sólida; al minar da madera x2
const T_CHEST := 20          # cofre de recursos — sólido; al romperlo suelta botín por bioma
const T_SKULL := 21          # calavera (estilo Halo) — sólida; al excavarla, efecto aleatorio

# GDD §3.2: HP y drop por tipo de tile
const HP := {T_DIRT: 40, T_STONE: 100, T_ORE: 140, T_WOOD: 60, T_LEAF: 20,
	T_WALL: 400, T_CAMPFIRE: 200, T_SPIKES: 120, T_TOWER: 250, T_NEST: 150, T_CRYSTAL: 160,
	T_FEATHER: 120, T_AETHER: 180, T_DIAMOND: 220, T_EMBER: 160, T_TOWER_MEGA: 400,
	T_RAIL: 50, T_CHEST: 60, T_SKULL: 140}
const DROPS := {T_DIRT: "dirt", T_STONE: "stone", T_ORE: "ore", T_WOOD: "wood",
	T_WALL: "muralla", T_CAMPFIRE: "fogata", T_SPIKES: "trampa", T_TOWER: "torre", T_CRYSTAL: "cristal",
	T_FEATHER: "pluma", T_AETHER: "esencia", T_DIAMOND: "diamante", T_EMBER: "ascua", T_TOWER_MEGA: "torre_mega"}
const ITEM_TILE := {"dirt": T_DIRT, "stone": T_STONE, "wood": T_WOOD,
	"muralla": T_WALL, "fogata": T_CAMPFIRE, "trampa": T_SPIKES, "torre": T_TOWER, "torre_mega": T_TOWER_MEGA}
const SOLID := {T_DIRT: true, T_STONE: true, T_ORE: true, T_BEDROCK: true, T_WALL: true, T_TOWER: true, T_NEST: true, T_CRYSTAL: true,
	T_FEATHER: true, T_AETHER: true, T_DIAMOND: true, T_EMBER: true, T_TOWER_MEGA: true,
	T_CHEST: true, T_SKULL: true}

# Bloque 3: cuánta madera da una vía de tren (recompensa de exploración x2)
const RAIL_WOOD := 2

const REACH := 200.0          # alcance validado por el servidor

var tiles: Dictionary = {}         # coord -> tipo (servidor: mundo completo)
var damage: Dictionary = {}        # coord -> HP restante (SOLO servidor)
var damage_ratio: Dictionary = {}  # coord -> 0..1 (visual, todos los peers)
var loaded: Dictionary = {}        # ccoord -> true (chunks cargados, cliente)
var renderers: Dictionary = {}     # ccoord -> ChunkRenderer
var _pending: Dictionary = {}      # ccoord -> true (peticiones en vuelo)
var fx: Node2D = null              # partículas (Fase 5B, solo visual)
var _cloud_t := 0.0                # deriva de las nubes
var _canvas_mod: CanvasModulate = null   # tinte global día/noche


func _ready() -> void:
	fx = Node2D.new()
	fx.set_script(FxScript)
	fx.z_index = 20
	add_child(fx)
	_canvas_mod = CanvasModulate.new()
	add_child(_canvas_mod)


func _process(delta: float) -> void:
	_cloud_t += delta
	# Tinte nocturno sobre todo el canvas (tiles, jugadores, NPCs);
	# la UI vive en un CanvasLayer y no se ve afectada.
	_canvas_mod.color = Color(0.45, 0.5, 0.72).lerp(Color.WHITE, daylight())
	queue_redraw()   # solo redibuja el fondo de este nodo (los chunks son hijos)


# -------------------------------------------------------------
# CICLO DÍA/NOCHE: desde la Fase 6 la luz la gobierna el RELOJ DE
# PARTIDA (main.gd, autoridad del servidor) — ya no la hora del
# sistema. Aquí solo se traduce a luz y posición del sol/luna.
# -------------------------------------------------------------
## 0..0.5 = progreso del día, 0.5..1 = progreso de la noche.
func day_phase() -> float:
	var m: Node2D = get_parent()
	var prog: float = m.phase_progress()
	return (0.5 + prog * 0.5) if m.is_night else prog * 0.5


## 1.0 = pleno día, 0.0 = plena noche, con transiciones suaves.
func daylight() -> float:
	return get_parent().daylight_factor()


# -------------------------------------------------------------
# GENERACIÓN (solo servidor): terreno con cuevas talladas por
# ruido 2D + islas flotantes en el cielo (GDD §3).
# -------------------------------------------------------------
func generate() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.04
	var caves := FastNoiseLite.new()
	caves.seed = randi()
	caves.frequency = 0.08

	for x in W:
		var surface := SKY_ROWS + int((noise.get_noise_1d(float(x)) + 1.0) * 4.0)
		for y in range(surface, H):
			var depth := y - surface
			# Cuevas: bolsas de aire bajo tierra (los 6 primeros tiles
			# de profundidad quedan intactos para no romper el spawn)
			if depth > 5 and y < H - 2 and caves.get_noise_2d(float(x), float(y)) > 0.34:
				continue
			var t := T_DIRT
			if depth > 5:
				var ore_noise := noise.get_noise_2d(float(x) * 3.0, float(y) * 3.0)
				if y >= H - 1 - DEEP_ROWS:
					# Bioma subterráneo profundo: vetas más densas que en la
					# piedra normal, con diamante/cristal/ascua en su núcleo
					# más rico (Bloque 1 "Mundo vivo").
					if ore_noise > 0.60:
						t = T_DIAMOND
					elif ore_noise > 0.55:
						t = T_CRYSTAL
					elif ore_noise > 0.40:
						t = T_EMBER
					elif ore_noise > 0.25:
						t = T_ORE
					else:
						t = T_STONE
				else:
					t = T_STONE
					if ore_noise > 0.42:
						t = T_ORE
			tiles[Vector2i(x, y)] = t
		tiles[Vector2i(x, H - 1)] = T_BEDROCK
		# Árboles (§8 — fuente de madera para crafting; ver también
		# grow_trees(), que repone este recurso cada amanecer)
		if x > 2 and x < W - 3 and randf() < 0.10:
			var t_changes := {}
			_plant_tree(x, surface, t_changes)
			for c: Vector2i in t_changes:
				tiles[c] = t_changes[c]
	_spawn_islands()
	_spawn_lakes()
	# Bloque 3 "Mundo vivo II" — exploración: vías de tren (madera x2),
	# cofres de recursos por bioma y calaveras estilo Halo enterradas.
	_spawn_rails()
	_spawn_chests()
	_spawn_skulls()


## Islas flotantes: óvalos de tierra (césped arriba) con núcleo de
## piedra, mineral y cristal — bioma aéreo, recompensa por construir
## hacia arriba (el cielo ampliado permite más islas que antes).
func _spawn_islands() -> void:
	for i in randi_range(7, 11):
		var cx := randi_range(10, W - 11)
		var cy := randi_range(3, SKY_ROWS - 5)
		var rw := randi_range(4, 7)
		var rh := randi_range(2, 3)
		for dx in range(-rw, rw + 1):
			for dy in range(-rh, rh + 1):
				var nx := float(dx) / float(rw)
				var ny := float(dy) / float(rh)
				if nx * nx + ny * ny > 1.0:
					continue
				var c := Vector2i(cx + dx, cy + dy)
				if dy <= 0:
					tiles[c] = T_DIRT
				elif randf() < 0.10:
					tiles[c] = T_AETHER
				elif randf() < 0.12:
					tiles[c] = T_CRYSTAL
				elif randf() < 0.25:
					tiles[c] = T_FEATHER
				else:
					tiles[c] = T_ORE if randf() < 0.30 else T_STONE
		# Bloque 3: ~55% de las islas tienen un árbol en su cima (madera en
		# el cielo — antes solo crecían en la superficie). La copa cae sobre
		# aire (encima de la isla), así que _plant_tree no pisa nada sólido.
		if randf() < 0.55:
			var top := cy - rh   # fila de tierra más alta de la isla en la columna cx
			if tiles.get(Vector2i(cx, top), 0) == T_DIRT:
				var tree := {}
				_plant_tree(cx, top, tree)
				for c: Vector2i in tree:
					tiles[c] = tree[c]


## Vías de tren abandonadas (Bloque 3): galerías mineras EXCAVADAS en el
## subsuelo con un tendido de T_RAIL sobre su piso. Minar la vía da madera
## x2 — un botín de exploración que premia bajar al subsuelo. Cava el raíl
## + 2 de aire de techo y asegura piso sólido; no toca el bedrock.
func _spawn_rails() -> void:
	for _i in randi_range(3, 5):
		var sx := randi_range(4, W - 20)
		var sy := randi_range(SKY_ROWS + 12, H - 4)
		var length := randi_range(8, 16)
		for k in length:
			var c := Vector2i(sx + k, sy)
			if c.x >= W - 2:
				break
			if tiles.get(c, 0) == T_BEDROCK:
				continue
			# Galería: piso sólido + raíl + 2 de aire de techo (mina abandonada)
			var below := c + Vector2i(0, 1)
			if not SOLID.has(tiles.get(below, 0)):
				tiles[below] = T_STONE
			tiles[c] = T_RAIL
			tiles[c + Vector2i(0, -1)] = 0
			tiles[c + Vector2i(0, -2)] = 0


## Cofres de recursos (Bloque 3): repartidos por los tres ambientes. Para
## cada uno elige una columna y posa el cofre sobre el primer suelo sólido
## que encuentre por debajo de una banda objetivo (cielo/superficie/
## subsuelo), tallando el hueco si hace falta. El botín lo decide
## main.open_chest según el bioma de su posición.
func _spawn_chests() -> void:
	# (banda_min, banda_max) en filas para repartir por zonas
	var bands := [
		Vector2i(3, SKY_ROWS - 3),                       # cielo (islas)
		Vector2i(SKY_ROWS, SKY_ROWS + 6),                # superficie
		Vector2i(SKY_ROWS + 12, H - 1 - DEEP_ROWS),      # cueva
		Vector2i(H - 1 - DEEP_ROWS, H - 3),              # profundo
	]
	for band: Vector2i in bands:
		for _c in 2:   # ~2 cofres por banda
			for _attempt in 25:
				var x := randi_range(3, W - 4)
				var floor_y := -1
				for y in range(band.x, band.y + 1):
					if SOLID.has(tiles.get(Vector2i(x, y), 0)) and tiles.get(Vector2i(x, y - 1), 0) == 0:
						floor_y = y - 1
						break
				if floor_y < 0:
					continue
				tiles[Vector2i(x, floor_y)] = T_CHEST
				break


## Calaveras estilo Halo (Bloque 3): enterradas dentro de la roca del
## subsuelo (ocultas hasta excavarlas). Todas se ven igual: el jugador
## no sabe si es buena o mala hasta romperla (main.excavate_skull elige
## el efecto al azar). Reemplaza tiles sólidos NO valiosos por T_SKULL.
func _spawn_skulls() -> void:
	var placed := 0
	for _attempt in 80:
		if placed >= 7:
			break
		var x := randi_range(3, W - 4)
		var y := randi_range(SKY_ROWS + 8, H - 3)
		var c := Vector2i(x, y)
		var t: int = tiles.get(c, 0)
		if t != T_STONE and t != T_DIRT:
			continue   # solo enterrada en roca/tierra común (no pisa mineral)
		tiles[c] = T_SKULL
		placed += 1


## Lagos del subsuelo profundo (Bloque 2 "Progresión elemental"): a
## diferencia del ruido disperso anterior, esto TALLA 2-4 charcos grandes
## y CONTENIDOS de T_WATER (blobs conexos de 18-40 tiles) dentro de la
## banda profunda. Sirven de barrera/ralentización tanto para el jugador
## (player._simulate_step) como para NPCs terrestres (npc_manager._move):
## cruzar un lago cuesta tiempo, dando ventaja a torres/pinchos cercanos.
func _spawn_lakes() -> void:
	for _i in randi_range(2, 4):
		var cx := randi_range(8, W - 9)
		var cy := randi_range(H - DEEP_ROWS, H - 3)
		var size := randi_range(18, 40)
		var queue: Array[Vector2i] = [Vector2i(cx, cy)]
		var filled: Dictionary = {}
		while not queue.is_empty() and filled.size() < size:
			var c: Vector2i = queue.pop_front()
			if filled.has(c) or c.y < H - 1 - DEEP_ROWS or c.y > H - 2:
				continue
			filled[c] = true
			tiles[c] = T_WATER
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = c + d
				if not filled.has(nb) and randf() < 0.85:
					queue.append(nb)


## Calcula las coordenadas de un árbol nuevo (tronco + copa) y las
## escribe en `changes` (coord -> tipo de tile). NO toca `tiles`: cada
## llamador decide cómo aplicarlas (generate() las copia directo;
## grow_trees() las aplica con _set_tile + apply_changes.rpc).
func _plant_tree(x: int, surface: int, changes: Dictionary) -> void:
	var height := randi_range(4, 6)
	for h in height:
		changes[Vector2i(x, surface - 1 - h)] = T_WOOD
	for lx in range(-1, 2):
		for ly in range(2):
			var c := Vector2i(x + lx, surface - height - 1 - ly)
			if tiles.get(c, 0) == 0 and not changes.has(c):
				changes[c] = T_LEAF


## Y del tile sólido más alto con aire encima en la columna x (la
## "superficie" natural, mismo sentido que `surface` en generate());
## -1 si no encuentra ninguno entre SKY_ROWS y el fondo.
func _surface_y(x: int) -> int:
	for y in range(SKY_ROWS, H - 1):
		if SOLID.has(tiles.get(Vector2i(x, y), 0)) and tiles.get(Vector2i(x, y - 1), 0) == 0:
			return y
	return -1


## Crecimiento diario de árboles (GDD — la madera es un recurso
## limitado): al amanecer, main._set_phase(false) llama esto para
## reponer el bosque. Intenta plantar hasta `max_new` árboles en
## superficie despejada y sincroniza los tiles nuevos a todos los
## peers (mismo patrón que meteor_strike/apply_changes). Servidor-only.
func grow_trees(attempts: int = 8, max_new: int = 3) -> void:
	if not multiplayer.is_server():
		return
	var changes := {}
	var planted := 0
	for _i in attempts:
		if planted >= max_new:
			break
		var x := randi_range(3, W - 4)
		var surface := _surface_y(x)
		if surface < 0 or tiles.get(Vector2i(x, surface), 0) != T_DIRT:
			continue
		var clear := true
		for h in 8:   # tronco (hasta 6) + copa (2 filas extra de margen)
			var c := Vector2i(x, surface - 1 - h)
			if tiles.get(c, 0) != 0 or changes.has(c):
				clear = false
				break
		if not clear:
			continue
		_plant_tree(x, surface, changes)
		planted += 1
	if changes.is_empty():
		return
	for c: Vector2i in changes:
		_set_tile(c, changes[c])
	apply_changes.rpc(changes)


func surface_spawn(x: int) -> Vector2:
	x = clampi(x, 2, W - 3)
	# Escanea desde SKY_ROWS: las islas flotantes (más arriba) no
	# cuentan como suelo de spawn.
	for y in range(SKY_ROWS, H):
		if SOLID.has(tiles.get(Vector2i(x, y), 0)):
			return Vector2(x * TILE + TILE * 0.5, y * TILE - 40.0)
	return Vector2(x * TILE, 100.0)


## Nido (Fase 10): reemplaza un tile sólido subterráneo cercano a near_x
## por T_NEST, eligiendo uno con al menos una cara de aire (cueva) para
## que los enemigos que escupa tengan espacio. Vector2i(-1,-1) si falla.
func spawn_nest(near_x: int) -> Vector2i:
	near_x = clampi(near_x, 2, W - 3)
	# Intentos aleatorios (variedad); si todos fallan, BARRIDO determinista
	# en espiral desde near_x (el nido SIEMPRE aparece si hay un hueco viable
	# — antes 20 tiradas con mala suerte lo dejaban sin sembrar).
	for _attempt in 20:
		var x := clampi(near_x + randi_range(-8, 8), 2, W - 3)
		var y := randi_range(SKY_ROWS + 6, H - 3)
		if _try_place_nest(Vector2i(x, y)):
			return Vector2i(x, y)
	for dx in range(0, W):
		for sgn: int in [1, -1]:
			var x: int = near_x + dx * sgn
			if x < 2 or x > W - 3:
				continue
			for y in range(SKY_ROWS + 6, H - 2):
				if _try_place_nest(Vector2i(x, y)):
					return Vector2i(x, y)
			if dx == 0:
				break   # near_x solo una vez
	return Vector2i(-1, -1)


## ¿La celda es sólida (no nido/bedrock) y tiene una cara de aire? Entonces
## coloca un T_NEST ahí. Helper de spawn_nest (aleatorio + barrido).
func _try_place_nest(c: Vector2i) -> bool:
	var t: int = tiles.get(c, 0)
	if not SOLID.has(t) or t == T_NEST or t == T_BEDROCK:
		return false
	var has_air := false
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if not SOLID.has(tiles.get(c + d, 0)):
			has_air = true
			break
	if not has_air:
		return false
	_set_tile(c, T_NEST)
	apply_tile.rpc(c, T_NEST)
	return true


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
	# El chunk de abajo mira ESTOS tiles para decidir su césped: refrescarlo
	var below := c + Vector2i(0, 1)
	if renderers.has(below):
		renderers[below].queue_redraw()


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


func _tile_center(coord: Vector2i) -> Vector2:
	return Vector2(coord.x * TILE + TILE * 0.5, coord.y * TILE + TILE * 0.5)


func _set_tile(coord: Vector2i, t: int) -> void:
	var prev: int = tiles.get(coord, 0)
	if t == 0:
		tiles.erase(coord)
	else:
		tiles[coord] = t
	damage_ratio.erase(coord)
	_redraw_at(coord)
	# El tile de ABAJO cambia de aspecto (césped si queda aire encima):
	# si cae en otro chunk, redibujarlo también.
	var below := coord + Vector2i.DOWN
	if chunk_of(below) != chunk_of(coord):
		_redraw_at(below)
	# Partículas (solo visual)
	if fx != null:
		if t == 0 and prev != 0:
			fx.burst(_tile_center(coord), Atlas.avg_color(prev), 14)
		elif t != 0 and prev == 0:
			fx.burst(_tile_center(coord), Atlas.avg_color(t), 6, 70.0)


# -------------------------------------------------------------
# FONDO (Fase 5B): cielo con degradado, sol, nubes a la deriva,
# colinas en dos planos y subsuelo oscuro. Los chunks (hijos)
# dibujan los tiles encima.
# -------------------------------------------------------------
func _draw() -> void:
	var ww := W * TILE
	var ground_y := (SKY_ROWS + 9) * TILE   # donde empieza el subsuelo de fondo
	var dl := daylight()
	var ph := day_phase()
	draw_texture_rect(Atlas.sky_tex, Rect2(0, 0, ww, ground_y), false)

	# Estrellas titilantes (aparecen al anochecer)
	if dl < 0.85:
		var sa := 1.0 - dl
		for i in 70:
			var sx := Atlas._h(i, 0, 201) * ww
			var sy := Atlas._h(i, 1, 202) * (SKY_ROWS - 4) * TILE
			var tw := 0.5 + 0.5 * sin(_cloud_t * (1.0 + 2.0 * Atlas._h(i, 2, 203)) + i)
			draw_circle(Vector2(sx, sy), 1.5, Color(1, 1, 0.92, sa * (0.35 + 0.5 * tw)))

	# Sol de día / luna de noche, recorriendo el cielo en arco
	if ph < 0.5:
		var p := ph / 0.5
		var sun := Vector2(ww * lerpf(0.06, 0.94, p), (8.5 - 6.5 * sin(PI * p)) * TILE)
		draw_circle(sun, 46.0, Color(Atlas.C_SUN.r, Atlas.C_SUN.g, Atlas.C_SUN.b, 0.25))
		draw_circle(sun, 30.0, Atlas.C_SUN)
	else:
		var p := (ph - 0.5) / 0.5
		var moon := Vector2(ww * lerpf(0.06, 0.94, p), (8.5 - 6.5 * sin(PI * p)) * TILE)
		draw_circle(moon, 34.0, Color(0.93, 0.95, 1.0, 0.18))
		draw_circle(moon, 24.0, Color(0.88, 0.9, 0.98))
		draw_circle(moon + Vector2(-7, -4), 4.0, Color(0.72, 0.75, 0.85))
		draw_circle(moon + Vector2(6, 6), 3.0, Color(0.72, 0.75, 0.85))
		draw_circle(moon + Vector2(8, -7), 2.5, Color(0.72, 0.75, 0.85))

	# Nubes con deriva lenta (envuelven el mundo, se oscurecen de noche)
	var cb := lerpf(0.4, 1.0, dl)
	for i in 7:
		var speed := 6.0 + 6.0 * Atlas._h(i, 0, 91)
		var cw := 140.0 + 80.0 * Atlas._h(i, 1, 92)
		var cx := wrapf(Atlas._h(i, 2, 93) * ww + _cloud_t * speed, -cw, ww)
		var cy := (1.0 + 6.0 * Atlas._h(i, 3, 94)) * TILE
		draw_texture_rect(Atlas.cloud_tex, Rect2(cx, cy, cw, cw * 0.29), false, Color(cb, cb, cb))

	# Colinas lejanas (dos planos = sensación de profundidad)
	_draw_hills(Atlas.hill_far_tex, (SKY_ROWS - 4) * TILE, 2.0, Atlas.C_HILL_FAR, ground_y)
	_draw_hills(Atlas.hill_near_tex, (SKY_ROWS - 2) * TILE, 2.0, Atlas.C_HILL_NEAR, ground_y)

	# Subsuelo: banda de transición y oscuridad
	draw_texture_rect(Atlas.under_tex, Rect2(0, ground_y, ww, 8 * TILE), false)
	draw_rect(Rect2(0, ground_y + 8 * TILE, ww, (H - SKY_ROWS - 17) * TILE), Atlas.C_UNDER_BOT)


func _draw_hills(tex: Texture2D, top: float, sc: float, base: Color, fill_to: float) -> void:
	var tw := tex.get_width() * sc
	var th := tex.get_height() * sc
	var x := 0.0
	while x < W * TILE:
		draw_texture_rect(tex, Rect2(x, top, tw, th), false)
		x += tw
	if top + th < fill_to:   # relleno sólido bajo la silueta
		draw_rect(Rect2(0, top + th, W * TILE, fill_to - (top + th)), base)


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
		if t == T_ORE:   # MONETIZACIÓN: el mineral también da Núcleos
			get_parent().add_coins(miner_id, get_parent().COIN_ORE)
		elif t == T_NEST:   # Fase 10: destruir un nido da una recompensa extra
			get_parent().add_coins(miner_id, get_parent().COIN_NEST)
			get_parent().on_nest_destroyed(coord)
		elif t == T_RAIL:   # Bloque 3: las vías abandonadas dan madera x2
			for _i in RAIL_WOOD:
				get_parent().add_item(miner_id, "wood")
		elif t == T_CHEST:   # Bloque 3: cofre — botín por bioma
			get_parent().open_chest(miner_id, coord)
		elif t == T_SKULL:   # Bloque 3: calavera — efecto aleatorio (bueno/malo)
			get_parent().excavate_skull(miner_id, coord)
	else:
		damage[coord] = hp_left
		damage_ratio[coord] = float(hp_left) / HP[t]
		_redraw_at(coord)
		if fx != null:
			fx.burst(_tile_center(coord), Atlas.avg_color(t), 4, 90.0)
		apply_damage.rpc(coord, damage_ratio[coord])


@rpc("authority", "call_remote", "reliable")
func apply_damage(coord: Vector2i, ratio: float) -> void:
	if not is_loaded(chunk_of(coord)):
		return
	damage_ratio[coord] = ratio
	_redraw_at(coord)
	if fx != null:
		fx.burst(_tile_center(coord), Atlas.avg_color(tiles.get(coord, T_DIRT)), 4, 90.0)


@rpc("authority", "call_remote", "reliable")
func apply_tile(coord: Vector2i, t: int) -> void:
	if not is_loaded(chunk_of(coord)):
		return
	_set_tile(coord, t)


# -------------------------------------------------------------
# DAÑO POR NPC (Fase 7): los enemigos golpean bloques que les
# cierran el paso. Sin drop — solo el jugador recibe botín.
# -------------------------------------------------------------
func damage_tile(coord: Vector2i, dmg: int) -> void:
	if not multiplayer.is_server():
		return
	var t: int = tiles.get(coord, 0)
	if t == 0 or not HP.has(t):
		return
	var hp_left: int = damage.get(coord, HP[t]) - dmg
	if hp_left <= 0:
		damage.erase(coord)
		_set_tile(coord, 0)
		apply_tile.rpc(coord, 0)
	else:
		damage[coord] = hp_left
		damage_ratio[coord] = float(hp_left) / HP[t]
		_redraw_at(coord)
		if fx != null:
			fx.burst(_tile_center(coord), Atlas.avg_color(t), 4, 90.0)
		apply_damage.rpc(coord, damage_ratio[coord])


## Posición de la fogata más cercana (Fase 7). INF si no hay.
func nearest_campfire_pos(pos: Vector2) -> Vector2:
	var best := 1e9
	var best_pos := Vector2.INF
	for c: Vector2i in tiles:
		if tiles[c] == T_CAMPFIRE:
			var cp := Vector2(c.x * TILE + TILE * 0.5, c.y * TILE - 20.0)
			var d := pos.distance_to(cp)
			if d < best:
				best = d
				best_pos = cp
	return best_pos


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
# El scheduler de main.gd (servidor) lo dispara periódicamente,
# con aviso previo (pasa la x anunciada). Impacto = partículas
# + sacudida de cámara en los peers cercanos (solo visual).
# -------------------------------------------------------------
func meteor_strike(x: int = -1) -> Vector2i:
	if x < 0:
		x = randi_range(6, W - 7)
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
	var center := _tile_center(Vector2i(x, sy))
	apply_meteor.rpc(center)
	_meteor_fx(center)
	return Vector2i(x, sy)


@rpc("authority", "call_remote", "reliable")
func apply_changes(changes: Dictionary) -> void:
	for c: Vector2i in changes:
		if is_loaded(chunk_of(c)):
			_set_tile(c, changes[c])


@rpc("authority", "call_remote", "reliable")
func apply_meteor(center: Vector2) -> void:
	_meteor_fx(center)


## Explosión visual del meteoro + sacudida de cámara si el jugador
## local está cerca. Puramente cosmético: no toca estado del juego.
func _meteor_fx(center: Vector2) -> void:
	if fx != null:
		fx.burst(center, Color(1.0, 0.55, 0.2), 36, 320.0)
		fx.burst(center, Color(0.4, 0.34, 0.3), 22, 180.0)
		fx.ring(center, 150.0, Color(1.0, 0.6, 0.25))
	var me: Node2D = get_parent().players.get(multiplayer.get_unique_id())
	if me != null and me.has_method("shake"):
		var d := me.position.distance_to(center)
		if d < 1400.0:
			me.shake(lerpf(14.0, 2.0, d / 1400.0))


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
