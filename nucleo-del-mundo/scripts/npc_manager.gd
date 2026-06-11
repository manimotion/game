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
const BOSS_EVERY := 5          # cada cuántas noches aparece un jefe (Fase 9)
const DIG_CD := 1.2            # cooldown de excavar el bloque de abajo ("digs", Fase 10)
const CHARGE_WINDUP := 0.9     # segundos "cargando" antes de embestir ("charges", Fase 10)
const CHARGE_SPEED := 420.0    # velocidad horizontal durante la embestida
const CHARGE_TILES := 5.0      # cuadros recorridos por la embestida
const CHARGE_COOLDOWN := 3.0   # cooldown tras embestir (o tras chocar)
const MERGE_RADIUS := 46.0     # distancia para que dos slimes empiecen a fusionarse
const MERGE_TIME := 8.0        # segundos juntos antes de fusionarse (Fase 10)
const NEST_SCAN_EVERY := 4.0   # re-escaneo de world.tiles buscando nidos (Fase 10)
const NEST_SPAWN_EVERY := 22.0 # cada cuánto un nido vivo escupe un enemigo

# Variantes de NPC: stats + botín + tamaño visual (la colisión usa
# SIZE para todas — solo cambia el dibujo). "fly" = vuela sin
# gravedad (murciélago: enemigo NOCTURNO, sale en las oleadas).
# "block_dmg" = daño a bloques que le cierran el paso (si falta,
# usa dmg): los grandes y el jefe son rompe-murallas (Fase 9).
# Fase 10: "digs" = excava el bloque de abajo (DIG_CD) y es inmune a
# T_SPIKES (los destruye en vez de recibir daño); "cave" = nace en
# bolsas de aire subterráneas (_spawn_underground); "charges" = carga
# y embiste en horizontal ("charge_dmg" si está embistiendo);
# "boss" + "nombre" = jefe anunciable (HUD/toast genéricos).
const KINDS := {
	"normal": {"hp": 70, "dmg": 8, "speed": 115.0, "coins": 3, "ore": 1,
		"w": 34.0, "h": 26.0, "color": Color("3fae4a")},
	"grande": {"hp": 160, "dmg": 14, "speed": 80.0, "coins": 8, "ore": 2,
		"w": 52.0, "h": 40.0, "color": Color("8a4ad0"), "block_dmg": 24},
	"slime_mega": {"hp": 320, "dmg": 22, "speed": 70.0, "coins": 18, "ore": 3,
		"w": 70.0, "h": 54.0, "color": Color("4a2a70"), "block_dmg": 40},
	"dorado": {"hp": 60, "dmg": 5, "speed": 165.0, "coins": 15, "ore": 0,
		"w": 30.0, "h": 24.0, "color": Color("f0c040")},
	"murcielago": {"hp": 45, "dmg": 6, "speed": 150.0, "coins": 4, "ore": 0,
		"w": 32.0, "h": 18.0, "color": Color("6b5b8e"), "fly": true},
	"taladro": {"hp": 90, "dmg": 10, "speed": 60.0, "coins": 7, "ore": 1,
		"w": 32.0, "h": 28.0, "color": Color("8a8f9b"), "block_dmg": 50, "digs": true},
	"topo": {"hp": 55, "dmg": 6, "speed": 90.0, "coins": 5, "ore": 1,
		"w": 32.0, "h": 24.0, "color": Color("6b4a3a"), "block_dmg": 10,
		"digs": true, "cave": true},
	"embistedor": {"hp": 110, "dmg": 14, "speed": 90.0, "coins": 9, "ore": 2,
		"w": 44.0, "h": 32.0, "color": Color("c46a3a"), "charges": true, "charge_dmg": 24},
	"jefe": {"hp": 500, "dmg": 18, "speed": 65.0, "coins": 50, "ore": 6,
		"w": 64.0, "h": 50.0, "color": Color("d6453f"), "block_dmg": 60,
		"boss": true, "nombre": "Jefe Demonio"},
	"jefe_murcielago": {"hp": 620, "dmg": 20, "speed": 110.0, "coins": 60, "ore": 7,
		"w": 90.0, "h": 60.0, "color": Color("6b5b8e"), "fly": true,
		"boss": true, "nombre": "Murciélago Gigante"},
	"jefe_topo": {"hp": 600, "dmg": 20, "speed": 70.0, "coins": 60, "ore": 7,
		"w": 80.0, "h": 56.0, "color": Color("6b4a3a"), "block_dmg": 70,
		"digs": true, "boss": true, "nombre": "Mega Topo"},
	"jefe_corredor": {"hp": 560, "dmg": 20, "speed": 100.0, "coins": 60, "ore": 7,
		"w": 84.0, "h": 52.0, "color": Color("c46a3a"), "charges": true, "charge_dmg": 35,
		"boss": true, "nombre": "Mega Corredor"},
}
const BOSS_ENRAGE_HP := 0.5    # bajo este % de vida el jefe se enfurece
const BOSS_ENRAGE_SPEED := 1.5 # multiplicador de velocidad enfurecido
const FUSION_CHAIN := {"normal": "grande", "grande": "slime_mega"}  # Fase 10

# Servidor: id -> {pos, vel, hp, kind, cool, jump_t}
# Clientes: id -> {pos, kind, ratio}
var npcs: Dictionary = {}
var _next_id := 1
var _spawn_t := 6.0
var _sync_t := 0.0
var _vis: Dictionary = {}     # id -> {prev, vy} (squash visual, Fase 5B)
var _nests: Dictionary = {}   # coord T_NEST -> tiempo acumulado (Fase 10)
var _nest_scan_t := 0.0

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

	_update_nests(delta, w)

	for id: int in npcs.keys():
		if not npcs.has(id):
			continue
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

		# Fase 10: cualquier "boss" (no solo "jefe") se ENFURECE bajo
		# BOSS_ENRAGE_HP — aplica tanto a jefes terrestres como voladores.
		var enraged := bool(k.get("boss", false)) and _ratio_of(n) < BOSS_ENRAGE_HP
		if bool(k.get("fly", false)):
			# Vuelo (murciélago / jefe_murcielago): persigue en línea recta, sin gravedad
			var fly_spd := float(k.speed) * (BOSS_ENRAGE_SPEED if enraged else 1.0)
			if target != null and best < CHASE_RANGE * 1.7:
				var dir: Vector2 = (target.position - n.pos).normalized()
				n.vel = n.vel.lerp(dir * fly_spd, minf(1.0, 3.0 * delta))
			elif n.jump_t <= 0.0:
				n.jump_t = randf_range(1.0, 2.2)
				n.vel = Vector2.from_angle(randf() * TAU) * fly_spd * 0.4
		elif bool(k.get("charges", false)):
			# Embestidor / jefe_corredor: carga y embiste en horizontal (Fase 10)
			_update_charge(n, k, target, best, delta, w, enraged)
		else:
			# Saltar: hacia el jugador si está cerca, si no, deambular.
			# Cualquier "boss" se ENFURECE bajo BOSS_ENRAGE_HP: corre y salta más (Fase 9/10).
			var spd := float(k.speed)
			var jump := -430.0
			if enraged:
				spd *= BOSS_ENRAGE_SPEED
				jump = -500.0
			if _on_floor(n, w) and n.jump_t <= 0.0:
				n.jump_t = randf_range(0.8, 1.6)
				n.vel.y = jump
				if target != null and best < CHASE_RANGE:
					n.vel.x = signf(target.position.x - n.pos.x) * spd
				else:
					n.vel.x = [-1.0, 0.0, 1.0].pick_random() * 70.0
			n.vel.y = minf(n.vel.y + GRAVITY * delta, MAX_FALL)
		_move(n, delta, w)

		# Fase 8/10: trampa de pinchos — daña a los NPCs terrestres que la
		# pisan; los excavadores ("digs": taladro/topo/jefe_topo) son
		# inmunes y la destruyen al pasar en vez de recibir daño.
		if not bool(k.get("fly", false)):
			n.spike_cd = maxf(0.0, n.get("spike_cd", 0.0) - delta)
			if n.spike_cd <= 0.0:
				var under := Vector2i(floori(n.pos.x / w.TILE), floori((n.pos.y + SIZE.y * 0.5 - 1.0) / w.TILE))
				if w.tiles.get(under, 0) == w.T_SPIKES:
					n.spike_cd = SPIKE_CD
					if bool(k.get("digs", false)):
						w.damage_tile(under, int(k.get("block_dmg", k.dmg)))
						block_hit_fx.rpc(n.pos)
						_block_hit_fx(n.pos)
					else:
						spike_fx.rpc(n.pos)
						_spike_fx(n.pos)
						damage_npc(id, SPIKE_DAMAGE)
						if not npcs.has(id):
							continue

			# Fase 10: "rompedor vertical" — excava periódicamente el
			# bloque de abajo (taladro/topo/jefe_topo), abriendo pozos.
			if bool(k.get("digs", false)):
				n.dig_cd = maxf(0.0, n.get("dig_cd", 0.0) - delta)
				if n.dig_cd <= 0.0:
					var below := Vector2i(floori(n.pos.x / w.TILE), floori((n.pos.y + SIZE.y * 0.5 + 2.0) / w.TILE))
					var bt: int = w.tiles.get(below, 0)
					if bt != w.T_BEDROCK and w.is_solid(below) and w.HP.has(bt):
						n.dig_cd = DIG_CD
						w.damage_tile(below, int(k.get("block_dmg", k.dmg)))
						block_hit_fx.rpc(n.pos)
						_block_hit_fx(n.pos)

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
					w.damage_tile(bc, int(k.get("block_dmg", k.dmg)))
					block_hit_fx.rpc(n.pos)
					_block_hit_fx(n.pos)

		# Daño por contacto (la embestida usa "charge_dmg" mientras embiste)
		if n.cool <= 0.0:
			for pid: int in main.players:
				var p: Node2D = main.players[pid]
				var prect := Rect2(p.position - p.SIZE * 0.5, p.SIZE)
				if prect.intersects(Rect2(n.pos - SIZE * 0.5, SIZE)):
					n.cool = CONTACT_COOLDOWN
					var dmg_amt := int(k.dmg)
					if n.get("charge_state", "") == "charging":
						dmg_amt = int(k.get("charge_dmg", k.dmg))
					main.damage_player(pid, dmg_amt)
					break

	_process_fusions(delta)


## Embistedor / jefe_corredor (Fase 10): se detiene "cargando" durante
## CHARGE_WINDUP segundos si el jugador está cerca y a su altura, luego
## embiste en horizontal a CHARGE_SPEED unos CHARGE_TILES cuadros (o
## hasta chocar con un bloque). Fuera de eso se mueve como un slime normal.
func _update_charge(n: Dictionary, k: Dictionary, target: Node2D, best: float, delta: float, w: Node2D, enraged: bool) -> void:
	var spd := float(k.speed) * (BOSS_ENRAGE_SPEED if enraged else 1.0)
	var state: String = n.get("charge_state", "idle")
	match state:
		"winding":
			n.vel.x = 0.0
			n.charge_t = n.get("charge_t", CHARGE_WINDUP) - delta
			if n.charge_t <= 0.0:
				n.charge_state = "charging"
				n.charge_t = (CHARGE_TILES * w.TILE) / CHARGE_SPEED
				n.vel.x = float(n.charge_dir) * CHARGE_SPEED
				charge_fx.rpc(n.pos, n.charge_dir)
				_charge_fx(n.pos, n.charge_dir)
		"charging":
			if n.vel.x == 0.0:   # _resolve lo frenó: chocó contra un bloque
				n.charge_state = "cooldown"
				n.charge_cd = CHARGE_COOLDOWN
			else:
				n.charge_t = n.get("charge_t", 0.0) - delta
				n.vel.x = float(n.charge_dir) * CHARGE_SPEED
				if n.charge_t <= 0.0:
					n.charge_state = "cooldown"
					n.charge_cd = CHARGE_COOLDOWN
					n.vel.x = 0.0
		_:
			# "idle"/"cooldown": deambula o persigue como un slime normal,
			# y si el jugador está cerca y a su altura, inicia la carga.
			n.charge_cd = maxf(0.0, n.get("charge_cd", 0.0) - delta)
			if state == "cooldown" and n.charge_cd <= 0.0:
				n.charge_state = "idle"
				state = "idle"
			if _on_floor(n, w) and n.jump_t <= 0.0:
				n.jump_t = randf_range(0.8, 1.6)
				n.vel.y = -430.0
				if target != null and best < CHASE_RANGE:
					n.vel.x = signf(target.position.x - n.pos.x) * spd
				else:
					n.vel.x = [-1.0, 0.0, 1.0].pick_random() * 70.0
			if state == "idle" and target != null and best < CHASE_RANGE \
					and absf(target.position.y - n.pos.y) < SIZE.y \
					and n.charge_cd <= 0.0 and _on_floor(n, w):
				n.charge_state = "winding"
				n.charge_t = CHARGE_WINDUP
				n.charge_dir = -1.0 if target.position.x < n.pos.x else 1.0
	n.vel.y = minf(n.vel.y + GRAVITY * delta, MAX_FALL)


## Fase 10: dos slimes "fusionables" del mismo tipo que permanecen a
## menos de MERGE_RADIUS por MERGE_TIME segundos se combinan en uno
## más grande (FUSION_CHAIN). `a`/`b` son referencias directas a las
## entradas de `npcs` (Dictionary es por referencia): mutarlas mutas
## `npcs` directamente.
func _process_fusions(delta: float) -> void:
	var ids := npcs.keys()
	for i in ids.size():
		var ida: int = ids[i]
		if not npcs.has(ida):
			continue
		var a: Dictionary = npcs[ida]
		if not FUSION_CHAIN.has(a.kind):
			continue
		var partner := -1
		for j in range(i + 1, ids.size()):
			var idb: int = ids[j]
			if not npcs.has(idb):
				continue
			var b: Dictionary = npcs[idb]
			if b.kind == a.kind and a.pos.distance_to(b.pos) <= MERGE_RADIUS:
				partner = idb
				break
		if partner == -1:
			a.near_t = 0.0
			continue
		a.near_t = a.get("near_t", 0.0) + delta
		npcs[partner].near_t = a.near_t
		if a.near_t >= MERGE_TIME:
			_fuse(ida, partner)


func _fuse(ida: int, idb: int) -> void:
	var a: Dictionary = npcs[ida]
	var b: Dictionary = npcs[idb]
	var new_kind: String = FUSION_CHAIN[a.kind]
	a.pos = (a.pos + b.pos) * 0.5
	a.kind = new_kind
	a.hp = int(KINDS[new_kind].hp)
	a.near_t = 0.0
	npcs.erase(idb)
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(a.pos, KINDS[new_kind].color, 22, 170.0)
		main.world.fx.ring(a.pos, 70.0, KINDS[new_kind].color)


# -------------------------------------------------------------
# NIDOS (Fase 10): cuadros T_NEST que, si no se destruyen, escupen un
# enemigo cada NEST_SPAWN_EVERY segundos. main.gd los siembra con
# w.spawn_nest() en las oleadas nocturnas; aquí solo se rastrean
# (re-escaneo periódico de world.tiles) y alimentan.
# -------------------------------------------------------------
func _update_nests(delta: float, w: Node2D) -> void:
	_nest_scan_t -= delta
	if _nest_scan_t <= 0.0:
		_nest_scan_t = NEST_SCAN_EVERY
		for c: Vector2i in w.tiles:
			if w.tiles[c] == w.T_NEST and not _nests.has(c):
				_nests[c] = 0.0
		for c: Vector2i in _nests.keys():
			if w.tiles.get(c, 0) != w.T_NEST:
				_nests.erase(c)

	for c: Vector2i in _nests.keys():
		_nests[c] += delta
		if _nests[c] >= NEST_SPAWN_EVERY:
			_nests[c] = 0.0
			if npcs.size() < WAVE_CAP:
				_spawn_from_nest(c, w)


func _spawn_from_nest(c: Vector2i, w: Node2D) -> void:
	for d: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		var ac: Vector2i = c + d
		if w.SOLID.has(w.tiles.get(ac, 0)):
			continue
		var pos := Vector2(ac.x * w.TILE + w.TILE * 0.5, ac.y * w.TILE + w.TILE * 0.5)
		var kind := "topo" if randf() < 0.5 else "normal"
		npcs[_next_id] = {"pos": pos, "vel": Vector2.ZERO, "hp": int(KINDS[kind].hp),
			"kind": kind, "cool": 0.0, "jump_t": randf_range(0.0, 1.0), "block_cd": 0.0}
		_next_id += 1
		nest_spawn_fx.rpc(pos)
		_nest_spawn_fx(pos)
		return


## Quita un nido del rastreo (llamado desde main.gd al destruirlo con pico).
func forget_nest(coord: Vector2i) -> void:
	_nests.erase(coord)


func _try_spawn() -> void:
	if npcs.size() >= MAX_NPCS or main.players.is_empty() or main.world == null:
		return
	var kind := _roll_kind_night(main.night_number) if main.is_night else _roll_kind()
	_spawn_one(kind, main.players.values().pick_random())


## Fase 10: "topo" puede salir de día desde las cuevas.
func _roll_kind() -> String:
	var r := randf()
	if r < 0.05:
		return "dorado"
	if r < 0.12:
		return "topo"
	if r < 0.28:
		return "grande"
	return "normal"


## De noche entran los murciélagos y las variantes duras escalan con el
## número de noche (Fase 6). Fase 10: desde la oleada 3 puede aparecer
## el "taladro" (rompedor vertical); "topo" y "embistedor" desde la 1.
func _roll_kind_night(night: int) -> String:
	var r := randf()
	var p := 0.0
	if night >= 3:
		p += 0.10
		if r < p:
			return "taladro"
	p += 0.08
	if r < p:
		return "topo"
	p += 0.10
	if r < p:
		return "embistedor"
	p += 0.30
	if r < p:
		return "murcielago"
	p += 0.04 * night
	if r < p:
		return "grande"
	p += 0.06
	if r < p:
		return "dorado"
	return "normal"


func _spawn_one(kind: String, near: Node2D) -> void:
	var w: Node2D = main.world
	var x := clampi(floori(near.position.x / w.TILE) + randi_range(-12, 12), 2, w.W - 3)
	var pos: Vector2
	if bool(KINDS[kind].get("cave", false)):
		pos = _spawn_underground(x, w)
	else:
		pos = w.surface_spawn(x)
		pos.y -= 4.0
		if bool(KINDS[kind].get("fly", false)):
			pos.y -= randf_range(80.0, 160.0)   # los voladores aparecen en el aire
	npcs[_next_id] = {"pos": pos, "vel": Vector2.ZERO, "hp": int(KINDS[kind].hp),
		"kind": kind, "cool": 0.0, "jump_t": randf_range(0.0, 1.0), "block_cd": 0.0}
	_next_id += 1


## Topo (Fase 10): busca una bolsa de aire subterránea cerca de x para
## nacer dentro de una cueva; si no encuentra ninguna en 12 intentos,
## sale a la superficie como cualquier otro enemigo.
func _spawn_underground(x: int, w: Node2D) -> Vector2:
	for _attempt in 12:
		var cx := clampi(x + randi_range(-10, 10), 2, w.W - 3)
		var cy := randi_range(w.SKY_ROWS + 6, w.H - 3)
		var c := Vector2i(cx, cy)
		if w.tiles.get(c, 0) == 0 and w.is_solid(c + Vector2i.DOWN):
			return Vector2(c.x * w.TILE + w.TILE * 0.5, c.y * w.TILE + w.TILE * 0.5)
	return w.surface_spawn(x)


## Oleada nocturna (Fase 6): la dispara _set_phase (main.gd) al caer
## la noche. Crece con el número de noche: 3 + noche enemigos.
## Fase 9: cada BOSS_EVERY noches se suma el jefe de la run
## (main.run_boss_kind), fuera del WAVE_CAP (evento especial —
## main.gd anuncia su llegada con un toast). Fase 10: las oleadas
## impares siembran además un nido (w.spawn_nest) en una cueva.
func night_wave(night: int) -> bool:
	if not multiplayer.is_server() or main.players.is_empty() or main.world == null:
		return false
	var count := mini(3 + night, WAVE_CAP - npcs.size())
	for i in maxi(count, 0):
		_spawn_one(_roll_kind_night(night), main.players.values().pick_random())
	if night % BOSS_EVERY == 0:
		_spawn_one(main.run_boss_kind, main.players.values().pick_random())
	if night % 2 == 1:
		var px := floori(main.players.values().pick_random().position.x / main.world.TILE)
		main.world.spawn_nest(px)
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
		var kind := str(npcs[id].kind)
		_death_fx(npcs[id].pos, k, kind)
		npcs.erase(id)
		main.count_kill(kind)                 # estadística de la run (Fase 9)
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
		var kind := str(npcs[id].kind)
		var pos: Vector2 = npcs[id].pos
		_death_fx(pos, k, kind)
		npcs.erase(id)
		main.count_kill(kind)                 # estadística de la run (Fase 9)
		var nearest := _nearest_player(pos)
		if nearest != -1:
			for i in int(k.ore):
				main.add_item(nearest, "ore")
			main.add_coins(nearest, int(k.coins))
	elif main.world != null and main.world.fx != null:
		main.world.fx.burst(npcs[id].pos, Color(1, 1, 1), 5, 120.0)


## Estallido al morir; cualquier "boss" además deja un anillo expansivo (Fase 9/10).
func _death_fx(pos: Vector2, k: Dictionary, kind: String) -> void:
	if main.world == null or main.world.fx == null:
		return
	main.world.fx.burst(pos, k.color, 16)
	if bool(k.get("boss", false)):
		main.world.fx.burst(pos, Color("ffd9a0"), 24, 240.0)
		main.world.fx.ring(pos, 180.0, Color("ff6040"))


# FX cosmético del golpe a un bloque (Fase 9, pulido): "thud" audible
# si el jugador local está cerca — oír que atacan tu muralla importa.
@rpc("authority", "call_remote", "unreliable")
func block_hit_fx(pos: Vector2) -> void:
	_block_hit_fx(pos)


func _block_hit_fx(pos: Vector2) -> void:
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 900.0:
		Sfx.play("golpe")


# FX cosmético de la trampa de pinchos (Fase 8, pulido): salpicadura
# + chasquido metálico cerca del jugador local.
@rpc("authority", "call_remote", "unreliable")
func spike_fx(pos: Vector2) -> void:
	_spike_fx(pos)


func _spike_fx(pos: Vector2) -> void:
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(pos, Color(0.85, 0.2, 0.2), 6, 100.0)
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 900.0:
		Sfx.play("pinchos")


# FX cosmético del embistedor / jefe_corredor al lanzar la carga (Fase 10):
# polvo en la dirección de la embestida + sonido grave cerca del jugador.
@rpc("authority", "call_remote", "unreliable")
func charge_fx(pos: Vector2, dir: float) -> void:
	_charge_fx(pos, dir)


func _charge_fx(pos: Vector2, dir: float) -> void:
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(pos + Vector2(-dir * 16.0, 6.0), Color(0.7, 0.6, 0.5), 10, 140.0)
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 900.0:
		Sfx.play("embestida")


# FX cosmético al salir un enemigo de un nido (Fase 10): destello +
# partículas en el tile, sin afectar el estado real (eso va por sync_npcs).
@rpc("authority", "call_remote", "unreliable")
func nest_spawn_fx(pos: Vector2) -> void:
	_nest_spawn_fx(pos)


func _nest_spawn_fx(pos: Vector2) -> void:
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(pos, Color("9a6ad0"), 14, 160.0)
		main.world.fx.ring(pos, 60.0, Color("c08af0"))
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 900.0:
		Sfx.play("invasion")


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
			_death_fx(npcs[id].pos, _kind_of(npcs[id]), str(npcs[id].get("kind", "")))
		elif float(fresh[id].ratio) < float(npcs[id].get("ratio", 1.0)) - 0.01:
			main.world.fx.burst(npcs[id].pos, Color(1, 1, 1), 5, 120.0)   # flash de golpe
	npcs = fresh
