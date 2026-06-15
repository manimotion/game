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
const BOSS_TUNNEL_CD := 0.55   # cooldown del jefe al romper un obstáculo hacia el jugador
const CHARGE_WINDUP := 0.9     # segundos "cargando" antes de embestir ("charges", Fase 10)
const CHARGE_SPEED := 420.0    # velocidad horizontal durante la embestida
const CHARGE_TILES := 5.0      # cuadros recorridos por la embestida
const CHARGE_COOLDOWN := 3.0   # cooldown tras embestir (o tras chocar)
const MERGE_RADIUS := 46.0     # distancia para que dos slimes empiecen a fusionarse
const MERGE_TIME := 8.0        # segundos juntos antes de fusionarse (Fase 10)
const NEST_SCAN_EVERY := 4.0   # re-escaneo de world.tiles buscando nidos (Fase 10)
const NEST_SPAWN_EVERY := 22.0 # cada cuánto un nido vivo escupe un enemigo
const WATER_SLOW := 0.55       # ralentización en T_WATER, igual que el jugador (Bloque 2)
# Bloque 4 "Bestiario vivo": curación de apoyo del "sanador"
const HEAL_CD := 3.0           # cada cuánto pulsa la cura
const HEAL_AMOUNT := 14        # vida que devuelve a cada enemigo cercano
const HEAL_RADIUS := 150.0     # alcance del pulso de cura

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
		"w": 32.0, "h": 28.0, "color": Color("8a8f9b"), "block_dmg": 50, "digs": true, "walks": true},
	"topo": {"hp": 55, "dmg": 6, "speed": 90.0, "coins": 5, "ore": 1,
		"w": 32.0, "h": 24.0, "color": Color("6b4a3a"), "block_dmg": 10,
		"digs": true, "cave": true, "walks": true},
	"embistedor": {"hp": 110, "dmg": 14, "speed": 90.0, "coins": 9, "ore": 2,
		"w": 44.0, "h": 32.0, "color": Color("c46a3a"), "charges": true, "charge_dmg": 24},
	# Bloque 4 "Bestiario vivo": 3 enemigos con comportamiento propio.
	# "ghost" = vuela Y atraviesa los muros (anti-turtling); "armor" = resta
	# daño recibido (tanque); "heals" = cura a los enemigos cercanos (apoyo).
	# "drop" = material de bioma que sueltan al morir (además de ore/Núcleos).
	"espectro": {"hp": 60, "dmg": 9, "speed": 130.0, "coins": 6, "ore": 0,
		"w": 34.0, "h": 26.0, "color": Color("aeb8e8"), "fly": true, "ghost": true,
		"drop": "esencia"},
	"coracero": {"hp": 210, "dmg": 12, "speed": 68.0, "coins": 12, "ore": 2,
		"w": 48.0, "h": 38.0, "color": Color("8a909c"), "armor": 7, "block_dmg": 30,
		"drop": "ascua", "walks": true},
	"sanador": {"hp": 80, "dmg": 4, "speed": 105.0, "coins": 10, "ore": 1,
		"w": 36.0, "h": 28.0, "color": Color("46c98e"), "heals": true,
		"drop": "pluma", "walks": true},
	"jefe": {"hp": 500, "dmg": 18, "speed": 65.0, "coins": 50, "ore": 6,
		"w": 64.0, "h": 50.0, "color": Color("d6453f"), "block_dmg": 60,
		"boss": true, "nombre": "Jefe Demonio", "walks": true},
	"jefe_murcielago": {"hp": 620, "dmg": 20, "speed": 110.0, "coins": 60, "ore": 7,
		"w": 90.0, "h": 60.0, "color": Color("6b5b8e"), "fly": true,
		"boss": true, "nombre": "Murciélago Gigante"},
	"jefe_topo": {"hp": 600, "dmg": 20, "speed": 70.0, "coins": 60, "ore": 7,
		"w": 80.0, "h": 56.0, "color": Color("6b4a3a"), "block_dmg": 70,
		"digs": true, "boss": true, "nombre": "Mega Topo", "walks": true},
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
var _had_npcs := false        # para redibujar una última vez al morir el último NPC

@onready var main: Node2D = get_parent()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_simulate(delta)
		_sync_t += delta
		if _sync_t >= 0.1:
			_sync_t = 0.0
			var snap := {}
			for id: int in npcs:
				snap[id] = [npcs[id].pos, npcs[id].kind, _ratio_of(npcs[id]), _state_flag(npcs[id])]
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
	# Redibuja mientras haya NPCs, y UNA VEZ MÁS cuando el último muere
	# (si no, su sprite queda "pegado" en pantalla con el último _draw()
	# hasta que vuelva a haber NPCs y se dispare un redraw de nuevo).
	var has_npcs := not npcs.is_empty()
	if has_npcs or _had_npcs:
		queue_redraw()
	_had_npcs = has_npcs


func _kind_of(n: Dictionary) -> Dictionary:
	return KINDS.get(n.get("kind", "normal"), KINDS["normal"])


## Vida 0..1: el servidor la calcula de hp; los clientes la reciben en el snapshot.
func _ratio_of(n: Dictionary) -> float:
	if n.has("hp"):
		return clampf(float(n.hp) / float(_kind_of(n).hp), 0.0, 1.0)
	return float(n.get("ratio", 1.0))


## NPCs vivos que NO son "boss". Los jefes quedan "fuera del WAVE_CAP" de
## forma PERSISTENTE (no solo al spawnear): si no, un jefe sin matar ocupa
## un cupo para siempre y frena las oleadas/spawns siguientes — grave en
## una run sin fin como sandbox (boss_every sigue sumando jefes).
func _non_boss_count() -> int:
	var n := 0
	for id: int in npcs:
		if not bool(_kind_of(npcs[id]).get("boss", false)):
			n += 1
	return n


## Estado VISUAL del NPC para el snapshot (0 nada, 1 cargando la
## embestida, 2 embistiendo, 3 jefe enfurecido): permite a los
## clientes dibujar telegraphs sin conocer la FSM real — el flag
## es puramente cosmético, el estado de verdad nunca sale del server.
func _state_flag(n: Dictionary) -> int:
	if n.has("hp"):
		var k := _kind_of(n)
		if bool(k.get("boss", false)) and _ratio_of(n) < BOSS_ENRAGE_HP:
			return 3
		match str(n.get("charge_state", "")):
			"winding": return 1
			"charging": return 2
		return 0
	return int(n.get("st", 0))


func _draw() -> void:
	# Slime gelatinoso: se estira al saltar/caer y se aplasta al tocar suelo.
	# Tamaño y textura según la variante; barra de vida si está dañado.
	# Telegraphs (st del snapshot): sacudida + "!" cargando la embestida,
	# líneas de velocidad embistiendo, aura pulsante en jefes y tinte
	# rojo si el jefe está enfurecido — TODO legible a primera vista.
	var ms := float(Time.get_ticks_msec())
	for id: int in npcs:
		var n: Dictionary = npcs[id]
		var k := _kind_of(n)
		var p: Vector2 = n.pos
		var st := _state_flag(n)
		var tex: Texture2D = Atlas.slimes.get(n.get("kind", "normal"), Atlas.slimes["normal"])
		# Aura del jefe: anillo cálido que respira (más rápido enfurecido)
		if bool(k.get("boss", false)):
			var pulse := 0.5 + 0.5 * sin(ms / (90.0 if st == 3 else 220.0) + id)
			var ac := Color(0.95, 0.35, 0.2, 0.10 + 0.08 * pulse) if st == 3 \
				else Color(k.color.r, k.color.g, k.color.b, 0.07 + 0.05 * pulse)
			draw_circle(p, float(k.w) * (0.75 + 0.1 * pulse), ac)
		var rect: Rect2
		if bool(k.get("fly", false)):
			# Volador: anclado al centro, con aleteo y vaivén
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
		var tint := Color.WHITE
		# Bloque 4: el espectro se dibuja translúcido y palpitante (etéreo).
		if bool(k.get("ghost", false)):
			tint = Color(1, 1, 1, 0.5 + 0.18 * sin(ms / 200.0 + id))
		if st == 1:
			# Cargando: tiembla y avisa con "!" — el jugador puede apartarse
			rect.position.x += 2.0 * sin(ms / 28.0 + id)
			draw_string(ThemeDB.fallback_font, Vector2(p.x - 5.0, rect.position.y - 12.0),
				"!", HORIZONTAL_ALIGNMENT_CENTER, 12, 18, Color(1.0, 0.85, 0.2))
		elif st == 2:
			# Embistiendo: estela de líneas de velocidad detrás (la dirección
			# sale de la posición previa — funciona igual en server y clientes)
			var prev: Vector2 = _vis.get(id, {}).get("prev", p)
			var dx := -signf(p.x - prev.x)
			if dx == 0.0:
				dx = 1.0
			for i in 3:
				var off := dx * (14.0 + i * 12.0)
				draw_line(p + Vector2(off, -6.0 + i * 6.0), p + Vector2(off + dx * 10.0, -6.0 + i * 6.0),
					Color(1, 1, 1, 0.35 - i * 0.1), 2.0)
		elif st == 3:
			tint = Color(1.0, 0.65, 0.6)   # jefe enfurecido: se enciende en rojo
		draw_texture_rect(tex, rect, false, tint)
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
		elif bool(k.get("walks", false)):
			# CAMINAR (rediseño: no todos saltan): avanza en horizontal hacia el
			# jugador, con auto-step para escalones — topo, taladro, coracero,
			# sanador y los jefes terrestres (demonio/topo). Sin el rebote del slime.
			var wspd := float(k.speed) * (BOSS_ENRAGE_SPEED if enraged else 1.0)
			_walk_step(n, target, best, wspd, w)
			n.vel.y = minf(n.vel.y + GRAVITY * delta, MAX_FALL)
		else:
			# Saltar (SLIMES): rebote hacia el jugador. Más FORMAS DE ALCANZARLO
			# (petición del jugador): el "dorado" es un saltarín ágil (salta más
			# alto y lejos); y CUALQUIER slime que tope con un muro hacia el
			# jugador salta MÁS ALTO para treparlo — así te alcanzan aunque te
			# subas a bloques, sin depender solo de romper la pared.
			var spd := float(k.speed)
			var jump := -545.0 if str(n.kind) == "dorado" else -430.0
			if enraged:
				spd *= BOSS_ENRAGE_SPEED
				jump = -520.0
			if _on_floor(n, w) and n.jump_t <= 0.0:
				n.jump_t = randf_range(0.8, 1.6)
				var jv := jump
				if target != null and best < CHASE_RANGE:
					var d := signf(target.position.x - n.pos.x)
					n.vel.x = d * spd
					# ¿muro al frente a la altura del cuerpo? salta alto para treparlo
					if d != 0.0 and w.is_solid(Vector2i(floori(n.pos.x / w.TILE) + int(d), floori(n.pos.y / w.TILE))):
						jv = jump * 1.45
				else:
					n.vel.x = [-1.0, 0.0, 1.0].pick_random() * 70.0
				n.vel.y = jv
			n.vel.y = minf(n.vel.y + GRAVITY * delta, MAX_FALL)
		_move(n, delta, w)

		# Petición del jugador: CUALQUIER jefe excava roca/murallas en
		# TODA dirección hacia el jugador para llegar hasta él (carva un
		# túnel diagonal; cada bloque aguanta los golpes que su HP exija).
		# Aplica también a jefes voladores (si los amurallan).
		if bool(k.get("boss", false)) and target != null:
			_boss_tunnel(n, k, target, w, delta)

		# Bloque 4 "Bestiario vivo": el "sanador" pulsa cura a los enemigos
		# cercanos (no a los jefes) cada HEAL_CD — vuelve resistentes a las
		# hordas, así que conviene matarlo primero. Solo cura a heridos.
		if bool(k.get("heals", false)):
			n.heal_cd = maxf(0.0, n.get("heal_cd", 0.0) - delta)
			if n.heal_cd <= 0.0:
				n.heal_cd = HEAL_CD
				var healed := false
				for oid: int in npcs:
					var o: Dictionary = npcs[oid]
					var ok := _kind_of(o)
					if bool(ok.get("boss", false)):
						continue
					if o.pos.distance_to(n.pos) <= HEAL_RADIUS and int(o.hp) < int(ok.hp):
						o.hp = mini(int(o.hp) + HEAL_AMOUNT, int(ok.hp))
						healed = true
				if healed:
					heal_fx.rpc(n.pos)
					_heal_fx(n.pos)

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
			# bloque de abajo (taladro/topo). Los JEFES usan _boss_tunnel
			# (rompe en toda dirección), así que aquí se excluyen.
			if bool(k.get("digs", false)) and not bool(k.get("boss", false)):
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
		# esquivan por arriba. Los JEFES usan _boss_tunnel (toda dirección).
		if not bool(k.get("fly", false)) and not bool(k.get("boss", false)) and target != null \
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


## Petición del jugador: el JEFE rompe roca/murallas/obstáculos en TODA
## dirección hacia el jugador para alcanzarlo (no solo de frente o hacia
## abajo). Cada BOSS_TUNNEL_CD golpea el bloque inmediato en el eje X y en
## el eje Y hacia el jugador — carva un túnel diagonal y derriba cualquier
## infraestructura por el camino; cada bloque aguanta los golpes que su HP
## exija (una muralla de 400 HP cae en HP/block_dmg golpes). Vale también
## para jefes voladores si los amurallan.
func _boss_tunnel(n: Dictionary, k: Dictionary, target: Node2D, w: Node2D, delta: float) -> void:
	n.tunnel_cd = maxf(0.0, n.get("tunnel_cd", 0.0) - delta)
	if n.tunnel_cd > 0.0:
		return
	var dmg := int(k.get("block_dmg", k.dmg))
	var cx := floori(n.pos.x / w.TILE)
	var cy := floori(n.pos.y / w.TILE)
	var sx := int(signf(target.position.x - n.pos.x))   # tile vecino en X hacia el jugador
	var sy := int(signf(target.position.y - n.pos.y))   # tile vecino en Y hacia el jugador
	var hit := false
	if sx != 0 and _breakable(Vector2i(cx + sx, cy), w):
		w.damage_tile(Vector2i(cx + sx, cy), dmg)
		hit = true
	if sy != 0 and _breakable(Vector2i(cx, cy + sy), w):
		w.damage_tile(Vector2i(cx, cy + sy), dmg)
		hit = true
	if hit:
		n.tunnel_cd = BOSS_TUNNEL_CD
		block_hit_fx.rpc(n.pos)
		_block_hit_fx(n.pos)


## ¿Tile sólido, destructible y no indestructible (bedrock)? — destino válido
## para que el jefe lo derribe al excavar hacia el jugador.
func _breakable(c: Vector2i, w: Node2D) -> bool:
	var t: int = w.tiles.get(c, 0)
	return t != 0 and t != w.T_BEDROCK and w.SOLID.has(t) and w.HP.has(t)


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
			# CAMINA (no salta) entre embestidas — rediseño de movimiento
			_walk_step(n, target, best, spd, w)
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
	fusion_fx.rpc(a.pos, new_kind)
	_fusion_fx(a.pos, new_kind)


## Evolución de jefe por zona (Bloque 2 "Progresión elemental"): cuando el
## jugador lleva BOSS_EVOLVE_TIME en una zona que el jefe activo no puede
## amenazar (p.ej. "jefe_topo" no alcanza una isla del cielo), main.gd llama
## esto para mutar el jefe a la variante de esa zona (main.ZONE_BOSS_KIND).
## Conserva posición y vida PROPORCIONAL (igual idea que _fuse: reasigna
## kind/hp sin reiniciar el combate) y limpia el estado transitorio de la
## FSM anterior para que la nueva variante arranque "idle" sin
## comportamientos heredados (p.ej. una embestida a medias).
func evolve_boss(id: int, new_kind: String) -> void:
	if not npcs.has(id):
		return
	var n: Dictionary = npcs[id]
	if n.kind == new_kind:
		return
	var ratio := _ratio_of(n)
	n.kind = new_kind
	n.hp = maxi(1, int(KINDS[new_kind].hp * ratio))
	n.vel = Vector2.ZERO
	n.cool = 0.0
	n.jump_t = 0.0
	n.block_cd = 0.0
	n.spike_cd = 0.0
	n.dig_cd = 0.0
	n.charge_state = "idle"
	n.charge_cd = 0.0
	n.near_t = 0.0
	n.tunnel_cd = 0.0
	boss_evolve_fx.rpc(n.pos, new_kind)
	_boss_evolve_fx(n.pos, new_kind)


# FX cosmético de la evolución de jefe (Bloque 2): ráfaga + anillo grande
# en TODOS los peers — misma idea que _fusion_fx pero a escala de jefe.
@rpc("authority", "call_remote", "unreliable")
func boss_evolve_fx(pos: Vector2, new_kind: String) -> void:
	_boss_evolve_fx(pos, new_kind)


func _boss_evolve_fx(pos: Vector2, new_kind: String) -> void:
	var col: Color = KINDS.get(new_kind, KINDS["jefe"]).color
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(pos, col, 32, 220.0)
		main.world.fx.ring(pos, 110.0, col)
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 1100.0:
		Sfx.play("fusion")


# FX cosmético de la fusión de slimes (Fase 10, pulido): ráfaga + anillo
# + sonido viscoso en TODOS los peers (antes solo lo veía el servidor).
@rpc("authority", "call_remote", "unreliable")
func fusion_fx(pos: Vector2, new_kind: String) -> void:
	_fusion_fx(pos, new_kind)


func _fusion_fx(pos: Vector2, new_kind: String) -> void:
	var col: Color = KINDS.get(new_kind, KINDS["normal"]).color
	if main.world != null and main.world.fx != null:
		main.world.fx.burst(pos, col, 22, 170.0)
		main.world.fx.ring(pos, 70.0, col)
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 900.0:
		Sfx.play("fusion")


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
			if _non_boss_count() < WAVE_CAP:
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
	if _non_boss_count() >= MAX_NPCS or main.players.is_empty() or main.world == null:
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
	# Bloque 4 "Bestiario vivo": el sanador entra pronto (apoyo de horda), el
	# coracero (tanque) y el espectro (atraviesa muros) escalan más tarde.
	if night >= 2:
		p += 0.07
		if r < p:
			return "sanador"
		p += 0.07
		if r < p:
			return "espectro"
	if night >= 4:
		p += 0.07
		if r < p:
			return "coracero"
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


## Inserta un NPC nuevo en `npcs` (helper común de _spawn_one/spawn_near).
func _insert_npc(kind: String, pos: Vector2) -> void:
	npcs[_next_id] = {"pos": pos, "vel": Vector2.ZERO, "hp": int(KINDS[kind].hp),
		"kind": kind, "cool": 0.0, "jump_t": randf_range(0.0, 1.0), "block_cd": 0.0}
	_next_id += 1


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
	_insert_npc(kind, pos)


## Bloque 1 "Mundo vivo": coloca un enemigo CERCA de la posición de `near`
## (no en la superficie) — lo usa la presión ambiental cuando un jugador se
## queda en una isla aérea o en el subsuelo profundo sin fortificar (las
## zonas donde _spawn_one/surface_spawn nunca colocan enemigos).
func spawn_near(kind: String, near: Node2D) -> void:
	var w: Node2D = main.world
	var pos := Vector2(near.position.x, near.position.y - 48.0)   # fallback
	if bool(KINDS[kind].get("fly", false)):
		pos = near.position + Vector2(randf_range(-80.0, 80.0), -randf_range(60.0, 140.0))
	else:
		var cx := floori(near.position.x / w.TILE)
		var cy := floori(near.position.y / w.TILE)
		for _attempt in 10:
			var c := Vector2i(cx + randi_range(-6, 6), cy + randi_range(-6, 6))
			if w.tiles.get(c, 0) == 0 and w.is_solid(c + Vector2i.DOWN):
				pos = Vector2(c.x * w.TILE + w.TILE * 0.5, c.y * w.TILE + w.TILE * 0.5)
				break
	_insert_npc(kind, pos)


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
	# Tamaño de la oleada y cadencia del jefe: del MODO activo (capa de
	# reglas, game_modes.gd) — "asedio" manda más enemigos que "survival".
	var base := int(main.mode_cfg.get("wave_base", 3))
	var step := int(main.mode_cfg.get("wave_step", 1))
	var boss_every := int(main.mode_cfg.get("boss_every", BOSS_EVERY))
	var count := mini(base + step * night, WAVE_CAP - _non_boss_count())
	for i in maxi(count, 0):
		_spawn_one(_roll_kind_night(night), main.players.values().pick_random())
	if night % boss_every == 0:
		_spawn_one(main.run_boss_kind, main.players.values().pick_random())
	if night % 2 == 1:
		var px := floori(main.players.values().pick_random().position.x / main.world.TILE)
		var nc: Vector2i = main.world.spawn_nest(px)
		if nc.x >= 0:
			# Avisar dónde palpita el nido (dar contrajuego es la regla),
			# DEMORADO unos segundos para no pisar el toast de "¡Noche N!"
			get_tree().create_timer(4.0).timeout.connect(func():
				main._broadcast_toast("🕳️ Un nido palpita bajo tierra cerca de x=%d — destrúyelo" % nc.x))
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


## Locomoción de CAMINAR (rediseño "no todos saltan"): avanza en horizontal
## hacia el jugador a velocidad constante — SIN el rebote del slime. Da un
## brinco CORTO solo si un escalón de terreno le cierra el paso, para no
## quedarse trabado. La gravedad la aplica el llamador (igual que la rama de
## salto). `jump_t` se reusa como temporizador del deambular.
func _walk_step(n: Dictionary, target: Node2D, best: float, spd: float, w: Node2D) -> void:
	if target != null and best < CHASE_RANGE * 1.4:
		n.vel.x = signf(target.position.x - n.pos.x) * spd
	elif n.jump_t <= 0.0:
		n.jump_t = randf_range(1.2, 2.6)
		n.vel.x = [-1.0, 1.0].pick_random() * spd * 0.5
	if _on_floor(n, w) and _step_blocked(n, w):
		n.vel.y = -300.0


## ¿Hay un escalón sólido en la columna vecina, a la altura de los pies? (para
## el auto-step de los que caminan — un brinco corto, no el rebote del slime).
func _step_blocked(n: Dictionary, w: Node2D) -> bool:
	if absf(n.vel.x) < 1.0:
		return false
	var ahead := floori(n.pos.x / w.TILE) + int(signf(n.vel.x))
	var foot := floori((n.pos.y + SIZE.y * 0.5 - 3.0) / w.TILE)
	return w.is_solid(Vector2i(ahead, foot))


func _move(n: Dictionary, delta: float, w: Node2D) -> void:
	# Bloque 4 "Bestiario vivo": el "espectro" (ghost) ATRAVIESA los muros —
	# flota hacia el jugador sin colisionar (anti-turtling: las murallas no
	# lo frenan). Solo se le acota a los límites del mundo.
	if bool(_kind_of(n).get("ghost", false)):
		n.pos += n.vel * delta
		n.pos.x = clampf(n.pos.x, 16.0, w.W * w.TILE - 16.0)
		n.pos.y = clampf(n.pos.y, 16.0, w.H * w.TILE - 16.0)
		return
	var dx: float = n.vel.x * delta
	# Bloque 2 "Progresión elemental": los lagos del subsuelo profundo
	# también ralentizan a los NPCs terrestres, igual que al jugador. Se
	# escala el desplazamiento del frame (dx), no vel.x: vel.x persiste
	# entre frames (se fija al saltar/perseguir) y mutarlo decaería sin fin.
	var feet_tile := Vector2i(floori(n.pos.x / w.TILE), floori(n.pos.y / w.TILE))
	if w.tiles.get(feet_tile, 0) == w.T_WATER:
		dx *= WATER_SLOW
	n.pos.x += dx
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
	# Bloque 4: el "coracero" (armor) amortigua cada golpe (mínimo 1 de daño)
	var dmg := maxi(1, main.get_attack_damage(attacker) - int(_kind_of(npcs[id]).get("armor", 0)))
	npcs[id].hp -= dmg                        # espada, no pico
	if npcs[id].hp <= 0:
		var k := _kind_of(npcs[id])
		var kind := str(npcs[id].kind)
		_death_fx(npcs[id].pos, k, kind)
		npcs.erase(id)
		main.count_kill(kind)                 # estadística de la run (Fase 9)
		for i in int(k.ore):                  # botín según la variante (KINDS)
			main.add_item(attacker, "ore")
		var drop := str(k.get("drop", ""))    # Bloque 4: material de bioma
		if drop != "":
			main.add_item(attacker, drop)
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
	# Bloque 4: el blindaje del "coracero" también amortigua el daño ambiental
	npcs[id].hp -= maxi(1, dmg - int(_kind_of(npcs[id]).get("armor", 0)))
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
			var drop := str(k.get("drop", ""))   # Bloque 4: material de bioma
			if drop != "":
				main.add_item(nearest, drop)
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


# FX cosmético del pulso de cura del "sanador" (Bloque 4): anillo verde
# expansivo + chispas en su posición. El estado real (hp curado) viaja por
# sync_npcs; esto es solo el telegraph para que se LEA quién cura a la horda.
@rpc("authority", "call_remote", "unreliable")
func heal_fx(pos: Vector2) -> void:
	_heal_fx(pos)


func _heal_fx(pos: Vector2) -> void:
	if main.world != null and main.world.fx != null:
		main.world.fx.ring(pos, HEAL_RADIUS, Color(0.3, 0.9, 0.55, 0.8))
		main.world.fx.burst(pos, Color("8af0b0"), 10, 120.0)
	# Bloque 5: brillo audible cerca del jugador local — oír que sanan a la
	# horda avisa de que conviene matar al sanador primero (cosmético).
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me != null and me.position.distance_to(pos) < 700.0:
		Sfx.play("cura")


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
		fresh[id] = {"pos": s[0], "kind": s[1], "ratio": s[2],
			"st": (s[3] if s.size() > 3 else 0)}
	for id: int in npcs:
		if main.world == null or main.world.fx == null:
			break
		if not fresh.has(id):
			_death_fx(npcs[id].pos, _kind_of(npcs[id]), str(npcs[id].get("kind", "")))
		elif float(fresh[id].ratio) < float(npcs[id].get("ratio", 1.0)) - 0.01:
			main.world.fx.burst(npcs[id].pos, Color(1, 1, 1), 5, 120.0)   # flash de golpe
	npcs = fresh
