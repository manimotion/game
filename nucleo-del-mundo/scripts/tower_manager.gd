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

# Bloque 2 "Progresión elemental" — T_TOWER_MEGA (receta de diamante): más
# alcance, dispara más rápido y hace más daño que la torre de madera/piedra.
const MEGA_RANGE := 480.0     # 15 tiles
const MEGA_COOLDOWN := 0.7
const MEGA_DAMAGE := 40

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
				snap.append({"pos": a.pos, "dir": a.dir, "mega": a.get("mega", false)})
			sync_arrows.rpc(snap)
	if not arrows.is_empty():
		queue_redraw()


func _draw() -> void:
	for a: Dictionary in arrows:
		var pos: Vector2 = a.pos
		var dir: Vector2 = a.get("dir", Vector2.RIGHT)
		# Bloque 2: flechas de la torre_mega llevan estela/tinte celeste-diamante
		var mega: bool = a.get("mega", false)
		var trail: Color = Color(0.6, 0.95, 1.0, 0.3) if mega else Color(1.0, 0.95, 0.75, 0.18)
		var trail2: Color = Color(0.6, 0.95, 1.0, 0.55) if mega else Color(1.0, 0.95, 0.75, 0.38)
		var tint: Color = Color(0.75, 0.95, 1.0) if mega else Color(1.0, 1.0, 1.0)
		# Estela: dos segmentos que se desvanecen detrás del proyectil
		draw_line(pos - dir * 30.0, pos - dir * 12.0, trail, 3.0)
		draw_line(pos - dir * 14.0, pos - dir * 4.0, trail2, 2.0)
		draw_set_transform(pos, dir.angle(), Vector2.ONE)
		draw_texture_rect(Atlas.arrow_tex, Rect2(-10, -4, 20, 8), false, tint)
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
			var tile: int = w.tiles[coord]
			if tile == w.T_TOWER or tile == w.T_TOWER_MEGA:
				var prev: Dictionary = towers.get(coord, {"cool": 0.0})
				current[coord] = {"cool": prev.cool, "kind": tile}
		towers = current

	for coord: Vector2i in towers:
		var t: Dictionary = towers[coord]
		t.cool = maxf(0.0, t.cool - delta)
		if t.cool <= 0.0:
			var mega: bool = t.kind == w.T_TOWER_MEGA
			var range_: float = MEGA_RANGE if mega else RANGE
			var origin := Vector2(coord.x * w.TILE + w.TILE * 0.5, coord.y * w.TILE + w.TILE * 0.25)
			var target_id := _nearest_enemy(origin, npc_mgr, range_)
			if target_id != -1:
				var npos: Vector2 = npc_mgr.npcs[target_id].pos
				var dir: Vector2 = (npos - origin).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				var dmg: int = MEGA_DAMAGE if mega else ARROW_DAMAGE
				arrows.append({"pos": origin, "dir": dir, "vel": dir * ARROW_SPEED,
					"life": ARROW_LIFETIME, "target": target_id, "dmg": dmg, "mega": mega})
				t.cool = MEGA_COOLDOWN if mega else COOLDOWN
				fired_fx.rpc(origin)
				_fired_fx(origin)

	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		a.pos += a.vel * delta
		a.life -= delta
		var hit := false
		if npc_mgr.npcs.has(a.target) and a.pos.distance_to(npc_mgr.npcs[a.target].pos) < ARROW_HIT_DIST:
			npc_mgr.damage_npc(a.target, int(a.get("dmg", ARROW_DAMAGE)))
			hit = true
		if hit or a.life <= 0.0:
			arrows.remove_at(i)


func _nearest_enemy(pos: Vector2, npc_mgr: Node2D, range_: float = RANGE) -> int:
	var best := range_
	var best_id := -1
	for id: int in npc_mgr.npcs:
		var d: float = pos.distance_to(npc_mgr.npcs[id].pos)
		if d < best:
			best = d
			best_id = id
	return best_id


# FX cosmético del disparo (Fase 8, pulido): fogonazo en la tronera
# + sonido si el jugador local está cerca. unreliable: si se pierde
# no pasa nada (el estado real viaja en sync_arrows).
@rpc("authority", "call_remote", "unreliable")
func fired_fx(origin: Vector2) -> void:
	_fired_fx(origin)


func _fired_fx(origin: Vector2) -> void:
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(origin, Color(1.0, 0.92, 0.6), 4, 70.0)
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(origin) < 900.0:
		Sfx.play("flecha")


# -------------------------------------------------------------
# RED: snapshot [pos, dir] (10 Hz) — los clientes solo dibujan.
# -------------------------------------------------------------
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_arrows(snap: Array) -> void:
	arrows = snap
