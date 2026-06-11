# =============================================================
# tower_manager.gd — Torre de flechas (GDD §16, ROADMAP Fase 8)
# El SERVIDOR escanea periódicamente el mundo en busca de tiles
# T_TOWER, lleva un cooldown por torre y dispara flechas hacia el
# enemigo más cercano en rango. Las flechas son simples segmentos
# de línea recta simulados en servidor; se transmite un snapshot
# (pos, dir) a 10 Hz, igual que npc_manager. Los clientes solo dibujan.
# Las muertes por flecha usan npc_manager.damage_npc (sin atacante
# jugador): el botín va al jugador más cercano.
# =============================================================
extends Node2D

const RANGE := 320.0          # alcance de disparo (10 tiles)
const COOLDOWN := 1.2         # segundos entre disparos por torre
const ARROW_SPEED := 480.0
const ARROW_DAMAGE := 18
const ARROW_LIFETIME := 1.5   # segundos máx de vuelo antes de descartarse
const ARROW_HIT_DIST := 18.0
const SCAN_EVERY := 1.0       # re-escanea el mundo en busca de torres

# Servidor: coord -> {cool: float}. Re-escaneado de world.tiles.
var towers: Dictionary = {}
# Servidor: [{pos, dir, vel, life, target}]. Cliente (tras sync): [{pos, dir}].
var arrows: Array = []
var _scan_t := 0.0
var _sync_t := 0.0

@onready var main: Node2D = get_parent()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_simulate(delta)
		_sync_t += delta
		if _sync_t >= 0.1:
			_sync_t = 0.0
			var snap := []
			for a: Dictionary in arrows:
				snap.append({"pos": a.pos, "dir": a.dir})
			sync_arrows.rpc(snap)
	if not arrows.is_empty():
		queue_redraw()


func _draw() -> void:
	for a: Dictionary in arrows:
		var pos: Vector2 = a.pos
		var dir: Vector2 = a.get("dir", Vector2.RIGHT)
		draw_set_transform(pos, dir.angle(), Vector2.ONE)
		draw_texture_rect(Atlas.arrow_tex, Rect2(-10, -4, 20, 8), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# -------------------------------------------------------------
# SIMULACIÓN (solo servidor)
# -------------------------------------------------------------
func _simulate(delta: float) -> void:
	var w: Node2D = main.world
	var npc_mgr: Node2D = main.npc_mgr
	if w == null or npc_mgr == null:
		return

	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		var current := {}
		for coord: Vector2i in w.tiles:
			if w.tiles[coord] == w.T_TOWER:
				current[coord] = towers.get(coord, {"cool": 0.0})
		towers = current

	for coord: Vector2i in towers:
		var t: Dictionary = towers[coord]
		t.cool = maxf(0.0, t.cool - delta)
		if t.cool <= 0.0:
			var origin := Vector2(coord.x * w.TILE + w.TILE * 0.5, coord.y * w.TILE + w.TILE * 0.25)
			var target_id := _nearest_enemy(origin, npc_mgr)
			if target_id != -1:
				var npos: Vector2 = npc_mgr.npcs[target_id].pos
				var dir: Vector2 = (npos - origin).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				arrows.append({"pos": origin, "dir": dir, "vel": dir * ARROW_SPEED,
					"life": ARROW_LIFETIME, "target": target_id})
				t.cool = COOLDOWN

	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		a.pos += a.vel * delta
		a.life -= delta
		var hit := false
		if npc_mgr.npcs.has(a.target) and a.pos.distance_to(npc_mgr.npcs[a.target].pos) < ARROW_HIT_DIST:
			npc_mgr.damage_npc(a.target, ARROW_DAMAGE)
			hit = true
		if hit or a.life <= 0.0:
			arrows.remove_at(i)


func _nearest_enemy(pos: Vector2, npc_mgr: Node2D) -> int:
	var best := RANGE
	var best_id := -1
	for id: int in npc_mgr.npcs:
		var d: float = pos.distance_to(npc_mgr.npcs[id].pos)
		if d < best:
			best = d
			best_id = id
	return best_id


# -------------------------------------------------------------
# RED: snapshot [pos, dir] (10 Hz) — los clientes solo dibujan.
# -------------------------------------------------------------
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_arrows(snap: Array) -> void:
	arrows = snap
