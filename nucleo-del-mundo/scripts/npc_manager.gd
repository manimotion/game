# =============================================================
# npc_manager.gd — NPCs con FSM (GDD §12) — FASE 4
# El SERVIDOR simula todos los NPCs (física + IA) y transmite un
# snapshot (pos, variante, vida) a 10 Hz. Los clientes solo dibujan.
# FSM del slime: idle → wander → chase (persigue al jugador
# cercano saltando hacia él). Contacto = daño al jugador.
# Golpearlo (tap) lo daña según tu pico; al morir suelta botín
# según su variante (KINDS) y estalla en partículas.
# Evento invasión (GDD §9): spawn_wave() crea una ola cerca de
# un jugador — lo dispara el scheduler de main.gd.
# =============================================================
extends Node2D

const SIZE := Vector2(26, 20)
const GRAVITY := 1500.0
const MAX_FALL := 900.0
const MAX_NPCS := 8
const WAVE_CAP := 14           # tope de NPCs contando invasiones
const CHASE_RANGE := 320.0
const CONTACT_COOLDOWN := 0.8
const HIT_REACH := 200.0
const SPAWN_EVERY := 15.0
const BLOCK_CD := 1.0          # cooldown de ataque a tiles (Fase 7)
const SPIKE_DAMAGE := 25       # daño de la trampa de pinchos por contacto (Fase 8)
const SPIKE_CD := 0.5          # cooldown del daño de pinchos (mientras está sobre la trampa)

# Variantes de NPC: stats + botín + tamaño visual (la colisión usa
# SIZE para todas — solo cambia el dibujo). "fly" = vuela sin
# gravedad (murciélago: enemigo NOCTURNO, sale en las oleadas).
const KINDS := {
	"normal": {"hp": 70, "dmg": 8, "speed": 115.0, "coins": 3, "ore": 1,
		"w": 34.0, "h": 26.0, "color": Color("3fae4a")},
	"grande": {"hp": 160, "dmg": 14, "speed": 80.0, "coins": 8, "ore": 2,
		"w": 52.0, "h": 40.0, "color": Color("8a4ad0")},
	"dorado": {"hp": 60, "dmg": 5, "speed": 165.0, "coins": 15, "ore": 0,
		"w": 30.0, "h": 24.0, "color": Color("f0c040")},
	"murcielago": {"hp": 45, "dmg": 6, "speed": 150.0, "coins": 4, "ore": 0,
		"w": 32.0, "h": 18.0, "color": Color("6b5b8e"), "fly": true},
}

# Servidor: id -> {pos, vel, hp, kind, cool, jump_t}
# Clientes: id -> {pos, kind, ratio}
var npcs: Dictionary = {}
var _next_id := 1
var _spawn_t := 6.0
var _sync_t := 0.0
var _vis: Dictionary = {}     # id -> {prev, vy} (squash visual, Fase 5B)

@onready var main: Node2D = get_parent()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_simulate(delta)
		_sync_t += delta
		if _sync_t >= 0.1:
			_sync_t = 0.0
			var snap := {}
			for id: int in npcs:
				snap[id] = [npcs[id].pos, npcs[id].kind, _ratio_of(npcs[id])]
			sync_npcs.rpc(snap)
	# Velocidad vertical estimada por peer (anima el squash sin red extra)
	for id: int in npcs:
		var v: Dictionary = _vis.get(id, {"prev": npcs[id].pos, "vy": 0.0})
		if delta > 0.0:
			v.vy = lerpf(v.vy, (npcs[id].pos.y - v.prev.y) / delta, 0.35)
		v.prev = npcs[id].pos
		_vis[id] = v
	for id: int in _vis.keys():
		if not npcs.has(id):
			_vis.erase(id)
	if not npcs.is_empty():
		queue_redraw()


func _kind_of(n: Dictionary) -> Dictionary:
	return KINDS.get(n.get("kind", "normal"), KINDS["normal"])


## Vida 0..1: el servidor la calcula de hp; los clientes la reciben en el snapshot.
func _ratio_of(n: Dictionary) -> float:
	if n.has("hp"):
		return clampf(float(n.hp) / float(_kind_of(n).hp), 0.0, 1.0)
	return float(n.get("ratio", 1.0))


func _draw() -> void:
	# Slime gelatinoso: se estira al saltar/caer y se aplasta al tocar suelo.
	# Tamaño y textura según la variante; barra de vida si está dañado.
	for id: int in npcs:
		var n: Dictionary = npcs[id]
		var k := _kind_of(n)
		var p: Vector2 = n.pos
		var tex: Texture2D = Atlas.slimes.get(n.get("kind", "normal"), Atlas.slimes["normal"])
		var rect: Rect2
		if bool(k.get("fly", false)):
			# Volador: anclado al centro, con aleteo y vaivén
			var ms := float(Time.get_ticks_msec())
			var w: float = float(k.w) * (1.0 + 0.14 * sin(ms / 90.0 + id))
			var h: float = float(k.h)
			var bob := 3.0 * sin(ms / 130.0 + id * 1.7)
			rect = Rect2(p.x - w * 0.5, p.y - h * 0.5 + bob, w, h)
		else:
			# Slime: anclado al suelo, se estira al saltar/caer
			var vy: float = _vis.get(id, {}).get("vy", 0.0)
			var stretch := clampf(absf(vy) / 700.0, 0.0, 0.30)
			var w2: float = float(k.w) * (1.0 - stretch * 0.6)
			var h2: float = float(k.h) * (1.0 + stretch)
			rect = Rect2(p.x - w2 * 0.5, p.y + 10.0 - h2, w2, h2)
		draw_texture_rect(tex, rect, false)
		var ratio := _ratio_of(n)
		if ratio < 1.0:
			var bw: float = float(k.w)
			var by: float = rect.position.y - 8.0
			draw_rect(Rect2(p.x - bw * 0.5, by, bw, 4.0), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(p.x - bw * 0.5, by, bw * ratio, 4.0), Color(0.85, 0.25, 0.2))


# -------------------------------------------------------------
# SIMULACIÓN (solo servidor)
# -------------------------------------------------------------
func _simulate(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		# De noche la presión sube: spawns más frecuentes (Fase 6)
		_spawn_t = SPAWN_EVERY * (0.45 if main.is_night else 1.0)
		_try_spawn()

	var w: Node2D = main.world
	if w == null:
		return

	for id: int in npcs.keys():
		var n: Dictionary = npcs[id]
		var k := _kind_of(n)
		n.cool = maxf(0.0, n.cool - delta)
		n.jump_t = maxf(0.0, n.jump_t - delta)
		n.block_cd = maxf(0.0, n.get("block_cd", 0.0) - delta)

		# FSM: elegir objetivo (jugador más cercano)
		var target: Node2D = null
		var best := 1e9
		for pid: int in main.players:
			var d: float = main.players[pid].position.distance_to(n.pos)
			if d < best:
				best = d
				target = main.players[pid]

		if bool(k.get("fly", false)):
			# Vuelo (murciélago): persigue en línea recta, sin gravedad
			if target != null and best < CHASE_RANGE * 1.7:
				var dir: Vector2 = (target.position - n.pos).normalized()
				n.vel = n.vel.lerp(dir * float(k.speed), minf(1.0, 3.0 * delta))
			elif n.jump_t <= 0.0:
				n.jump_t = randf_range(1.0, 2.2)
				n.vel = Vector2.from_angle(randf() * TAU) * float(k.speed) * 0.4
		else:
			# Saltar: hacia el jugador si está cerca, si no, deambular
			if _on_floor(n, w) and n.jump_t <= 0.0:
				n.jump_t = randf_range(0.8, 1.6)
				n.vel.y = -430.0
				if target != null and best < CHASE_RANGE:
					n.vel.x = signf(target.position.x - n.pos.x) * float(k.speed)
				else:
					n.vel.x = [-1.0, 0.0, 1.0].pick_random() * 70.0
			n.vel.y = minf(n.vel.y + GRAVITY * delta, MAX_FALL)
		_move(n, delta, w)

		# Fase 8: trampa de pinchos — daña a los NPCs terrestres que la pisan
		if not bool(k.get("fly", false)):
			n.spike_cd = maxf(0.0, n.get("spike_cd", 0.0) - delta)
			if n.spike_cd <= 0.0:
				var under := Vector2i(floori(n.pos.x / w.TILE), floori((n.pos.y + SIZE.y * 0.5 - 1.0) / w.TILE))
				if w.tiles.get(under, 0) == w.T_SPIKES:
					n.spike_cd = SPIKE_CD
					damage_npc(id, SPIKE_DAMAGE)
					if not npcs.has(id):
						continue

		# Fase 7: NPCs terrestres golpean el bloque que les cierra el
		# paso hacia el jugador (murallas, terreno). Los voladores lo
		# esquivan por arriba.
		if not bool(k.get("fly", false)) and target != null \
				and best < CHASE_RANGE and n.block_cd <= 0.0:
			var dir_x := signf(target.position.x - n.pos.x)
			if dir_x != 0.0:
				var bx := floori((n.pos.x + dir_x * (SIZE.x * 0.5 + 2.0)) / w.TILE)
				var by := floori(n.pos.y / w.TILE)
				var bc := Vector2i(bx, by)
				if w.is_solid(bc) and w.HP.has(w.tiles.get(bc, 0)):
					n.block_cd = BLOCK_CD
					w.damage_tile(bc, int(k.dmg))

		# Daño por contacto
		if n.cool <= 0.0:
			for pid: int in main.players:
				var p: Node2D = main.players[pid]
				var prect := Rect2(p.position - p.SIZE * 0.5, p.SIZE)
				if prect.intersects(Rect2(n.pos - SIZE * 0.5, SIZE)):
					n.cool = CONTACT_COOLDOWN
					main.damage_player(pid, int(_kind_of(n).dmg))
					break


func _try_spawn() -> void:
	if npcs.size() >= MAX_NPCS or main.players.is_empty() or main.world == null:
		return
	var kind := _roll_kind_night(main.night_number) if main.is_night else _roll_kind()
	_spawn_one(kind, main.players.values().pick_random())


func _roll_kind() -> String:
	var r := randf()
	if r < 0.06:
		return "dorado"
	if r < 0.22:
		return "grande"
	return "normal"


## De noche entran los murciélagos y las variantes duras escalan
## con el número de noche (Fase 6).
func _roll_kind_night(night: int) -> String:
	var r := randf()
	if r < 0.30:
		return "murcielago"
	if r < 0.30 + 0.04 * night:
		return "grande"
	if r < 0.36 + 0.04 * night:
		return "dorado"
	return "normal"


func _spawn_one(kind: String, near: Node2D) -> void:
	var w: Node2D = main.world
	var x := clampi(floori(near.position.x / w.TILE) + randi_range(-12, 12), 2, w.W - 3)
	var pos: Vector2 = w.surface_spawn(x)
	pos.y -= 4.0
	if bool(KINDS[kind].get("fly", false)):
		pos.y -= randf_range(80.0, 160.0)   # los voladores aparecen en el aire
	npcs[_next_id] = {"pos": pos, "vel": Vector2.ZERO, "hp": int(KINDS[kind].hp),
		"kind": kind, "cool": 0.0, "jump_t": randf_range(0.0, 1.0), "block_cd": 0.0}
	_next_id += 1


## Oleada nocturna (Fase 6): la dispara _set_phase (main.gd) al caer
## la noche. Crece con el número de noche: 3 + noche enemigos.
func night_wave(night: int) -> bool:
	if not multiplayer.is_server() or main.players.is_empty() or main.world == null:
		return false
	var count := mini(3 + night, WAVE_CAP - npcs.size())
	for i in maxi(count, 0):
		_spawn_one(_roll_kind_night(night), main.players.values().pick_random())
	return count > 0


# -------------------------------------------------------------
# FÍSICA DEL NPC (AABB contra el mundo, como el jugador)
# -------------------------------------------------------------
func _on_floor(n: Dictionary, w: Node2D) -> bool:
	var t: int = w.TILE
	var y := floori((n.pos.y + SIZE.y * 0.5 + 1.0) / t)
	for x in range(floori((n.pos.x - SIZE.x * 0.5) / t), floori((n.pos.x + SIZE.x * 0.5 - 0.001) / t) + 1):
		if w.is_solid(Vector2i(x, y)):
			return true
	return false


func _move(n: Dictionary, delta: float, w: Node2D) -> void:
	n.pos.x += n.vel.x * delta
	_resolve(n, 0, w)
	n.pos.y += n.vel.y * delta
	_resolve(n, 1, w)
	n.pos.x = clampf(n.pos.x, 16.0, w.W * w.TILE - 16.0)


func _resolve(n: Dictionary, axis: int, w: Node2D) -> void:
	var t: int = w.TILE
	var r := Rect2(n.pos - SIZE * 0.5, SIZE)
	for cx in range(floori(r.position.x / t), floori((r.end.x - 0.001) / t) + 1):
		for cy in range(floori(r.position.y / t), floori((r.end.y - 0.001) / t) + 1):
			if not w.is_solid(Vector2i(cx, cy)):
				continue
			var tr := Rect2(cx * t, cy * t, t, t)
			if not r.intersects(tr):
				continue
			if axis == 0:
				if n.vel.x > 0.0:
					n.pos.x = tr.position.x - SIZE.x * 0.5
				elif n.vel.x < 0.0:
					n.pos.x = tr.end.x + SIZE.x * 0.5
				n.vel.x = 0.0
			else:
				if n.vel.y > 0.0:
					n.pos.y = tr.position.y - SIZE.y * 0.5
				elif n.vel.y < 0.0:
					n.pos.y = tr.end.y + SIZE.y * 0.5
				n.vel.y = 0.0
			r = Rect2(n.pos - SIZE * 0.5, SIZE)


# -------------------------------------------------------------
# COMBATE: golpear un NPC (cliente pide, servidor valida §16)
# -------------------------------------------------------------
func npc_at(world_pos: Vector2) -> int:
	for id: int in npcs:
		if world_pos.distance_to(npcs[id].pos) < 28.0:
			return id
	return -1


func hit_local(id: int) -> void:
	if multiplayer.is_server():
		_do_hit(id, 1)
	else:
		request_hit.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func request_hit(id: int) -> void:
	if not multiplayer.is_server():
		return
	_do_hit(id, multiplayer.get_remote_sender_id())


func _do_hit(id: int, attacker: int) -> void:
	if not npcs.has(id):
		return
	var p: Node2D = main.players.get(attacker)
	if p == null or p.position.distance_to(npcs[id].pos) > HIT_REACH:
		return
	npcs[id].hp -= main.get_attack_damage(attacker)   # espada, no pico
	if npcs[id].hp <= 0:
		var k := _kind_of(npcs[id])
		if main.world != null and main.world.fx != null:
			main.world.fx.burst(npcs[id].pos, k.color, 16)
		npcs.erase(id)
		for i in int(k.ore):                  # botín según la variante (KINDS)
			main.add_item(attacker, "ore")
		main.add_coins(attacker, int(k.coins))   # MONETIZACIÓN: Núcleos
	elif main.world != null and main.world.fx != null:
		main.world.fx.burst(npcs[id].pos, Color(1, 1, 1), 5, 120.0)   # flash de golpe


# -------------------------------------------------------------
# DAÑO AMBIENTAL (Fase 8): trampas de pinchos y torres de flechas
# matan sin "atacante" jugador. El botín va al jugador más cercano.
# -------------------------------------------------------------
func damage_npc(id: int, dmg: int) -> void:
	if not npcs.has(id):
		return
	npcs[id].hp -= dmg
	if npcs[id].hp <= 0:
		var k := _kind_of(npcs[id])
		var pos: Vector2 = npcs[id].pos
		if main.world != null and main.world.fx != null:
			main.world.fx.burst(pos, k.color, 16)
		npcs.erase(id)
		var nearest := _nearest_player(pos)
		if nearest != -1:
			for i in int(k.ore):
				main.add_item(nearest, "ore")
			main.add_coins(nearest, int(k.coins))
	elif main.world != null and main.world.fx != null:
		main.world.fx.burst(npcs[id].pos, Color(1, 1, 1), 5, 120.0)


func _nearest_player(pos: Vector2) -> int:
	var best := 1e9
	var best_id := -1
	for pid: int in main.players:
		var d: float = main.players[pid].position.distance_to(pos)
		if d < best:
			best = d
			best_id = pid
	return best_id


# -------------------------------------------------------------
# RED: snapshot [pos, kind, ratio] (10 Hz) — los clientes
# reemplazan su estado; los ids ausentes desaparecen (muertos)
# y estallan en partículas (solo visual).
# -------------------------------------------------------------
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_npcs(snap: Dictionary) -> void:
	var fresh := {}
	for id: int in snap:
		var s: Array = snap[id]
		fresh[id] = {"pos": s[0], "kind": s[1], "ratio": s[2]}
	for id: int in npcs:
		if main.world == null or main.world.fx == null:
			break
		if not fresh.has(id):
			main.world.fx.burst(npcs[id].pos, _kind_of(npcs[id]).color, 16)
		elif float(fresh[id].ratio) < float(npcs[id].get("ratio", 1.0)) - 0.01:
			main.world.fx.burst(npcs[id].pos, Color(1, 1, 1), 5, 120.0)   # flash de golpe
	npcs = fresh
