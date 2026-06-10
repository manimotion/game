# =============================================================
# npc_manager.gd — NPCs con FSM (GDD §12) — FASE 4
# El SERVIDOR simula todos los NPCs (física + IA) y transmite un
# snapshot de posiciones a 10 Hz. Los clientes solo dibujan.
# FSM del slime: idle → wander → chase (persigue al jugador
# cercano saltando hacia él). Contacto = daño al jugador.
# Golpearlo (tap) lo daña según tu pico; al morir suelta mineral.
# =============================================================
extends Node2D

const SIZE := Vector2(26, 20)
const GRAVITY := 1500.0
const MAX_FALL := 900.0
const MAX_NPCS := 5
const NPC_HP := 70
const CHASE_RANGE := 320.0
const CONTACT_DMG := 8
const CONTACT_COOLDOWN := 0.8
const HIT_REACH := 200.0
const SPAWN_EVERY := 15.0

# Servidor: id -> {pos, vel, hp, cool, jump_t}
# Clientes: id -> {pos}
var npcs: Dictionary = {}
var _next_id := 1
var _spawn_t := 6.0
var _sync_t := 0.0

@onready var main: Node2D = get_parent()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_simulate(delta)
		_sync_t += delta
		if _sync_t >= 0.1:
			_sync_t = 0.0
			var snap := {}
			for id: int in npcs:
				snap[id] = npcs[id].pos
			sync_npcs.rpc(snap)
	if not npcs.is_empty():
		queue_redraw()


func _draw() -> void:
	for id: int in npcs:
		var p: Vector2 = npcs[id].pos
		draw_circle(p + Vector2(0, 2), 13.0, Color(0.25, 0.75, 0.30, 0.9))
		draw_circle(p + Vector2(-4, -2), 2.5, Color.BLACK)
		draw_circle(p + Vector2(4, -2), 2.5, Color.BLACK)


# -------------------------------------------------------------
# SIMULACIÓN (solo servidor)
# -------------------------------------------------------------
func _simulate(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = SPAWN_EVERY
		_try_spawn()

	var w: Node2D = main.world
	if w == null:
		return

	for id: int in npcs.keys():
		var n: Dictionary = npcs[id]
		n.cool = maxf(0.0, n.cool - delta)
		n.jump_t = maxf(0.0, n.jump_t - delta)

		# FSM: elegir objetivo (jugador más cercano)
		var target: Node2D = null
		var best := 1e9
		for pid: int in main.players:
			var d: float = main.players[pid].position.distance_to(n.pos)
			if d < best:
				best = d
				target = main.players[pid]

		# Saltar: hacia el jugador si está cerca (chase), si no, deambular
		if _on_floor(n, w) and n.jump_t <= 0.0:
			n.jump_t = randf_range(0.8, 1.6)
			n.vel.y = -430.0
			if target != null and best < CHASE_RANGE:
				n.vel.x = signf(target.position.x - n.pos.x) * 115.0
			else:
				n.vel.x = [-1.0, 0.0, 1.0].pick_random() * 70.0

		n.vel.y = minf(n.vel.y + GRAVITY * delta, MAX_FALL)
		_move(n, delta, w)

		# Daño por contacto
		if n.cool <= 0.0:
			for pid: int in main.players:
				var p: Node2D = main.players[pid]
				var prect := Rect2(p.position - p.SIZE * 0.5, p.SIZE)
				if prect.intersects(Rect2(n.pos - SIZE * 0.5, SIZE)):
					n.cool = CONTACT_COOLDOWN
					main.damage_player(pid, CONTACT_DMG)
					break


func _try_spawn() -> void:
	if npcs.size() >= MAX_NPCS or main.players.is_empty() or main.world == null:
		return
	var w: Node2D = main.world
	var p: Node2D = main.players.values().pick_random()
	var x := clampi(floori(p.position.x / w.TILE) + randi_range(-12, 12), 2, w.W - 3)
	var pos: Vector2 = w.surface_spawn(x)
	pos.y -= 4.0
	npcs[_next_id] = {"pos": pos, "vel": Vector2.ZERO, "hp": NPC_HP,
		"cool": 0.0, "jump_t": randf_range(0.0, 1.0)}
	_next_id += 1


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
	npcs[id].hp -= main.get_tool_damage(attacker)
	if npcs[id].hp <= 0:
		npcs.erase(id)
		main.add_item(attacker, "ore")               # recompensa por slime
		main.add_coins(attacker, main.COIN_SLIME)    # MONETIZACIÓN: Núcleos


# -------------------------------------------------------------
# RED: snapshot de posiciones (10 Hz) — los clientes reemplazan
# su estado; los ids ausentes desaparecen (muertos/despawn).
# -------------------------------------------------------------
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_npcs(snap: Dictionary) -> void:
	var fresh := {}
	for id: int in snap:
		fresh[id] = {"pos": snap[id]}
	npcs = fresh
