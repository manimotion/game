# =============================================================
# smoke_craft.gd — prueba headless del panel 🛠️ Fabricar (RECIPES)
# Ejecutar:
#   godot --headless --path . res://tests/smoke_craft.tscn --quit-after 5
# =============================================================
extends Node2D

const MainScript := preload("res://scripts/main.gd")

var _fail := 0


func _ready() -> void:
	# RNG determinista: varios checks dependen de generación aleatoria
	# (mundo, spawn_nest hace 20 intentos al azar). Sin seed fija, TEST 31
	# fallaba ~1 de cada 5 corridas por pura mala suerte del RNG.
	seed(20260612)

	var main := Node2D.new()
	main.set_script(MainScript)
	add_child(main)

	if Net.host_game() != OK:
		print("ERROR: no se pudo abrir el servidor (host_game)")
		get_tree().quit(1)
		return

	main._start_game()
	main.world.generate()
	main.inventories[1] = {}
	main.player_hp[1] = 100
	main._spawn_player(1, main.world.surface_spawn(20), "default", "Tester")
	main._apply_inventory(main.inventories[1])

	_check("RECIPES tiene pico_madera/piedra/dorado",
		main.RECIPES.has("pico_madera") and main.RECIPES.has("pico_piedra") and main.RECIPES.has("pico_dorado"))

	# ---- TEST 0: HUD arranca con vida llena y "Mano" equipada ----
	print("[0] HUD inicial:", main._hp_label.text, "|", main._tool_label.text)
	_check("HUD barra de vida arranca en %d/%d" % [main.PLAYER_MAX_HP, main.PLAYER_MAX_HP],
		int(main._hp_bar.value) == main.PLAYER_MAX_HP and main._hp_label.text == "%d/%d" % [main.PLAYER_MAX_HP, main.PLAYER_MAX_HP])
	_check("HUD muestra 'Mano' y 'Puños' sin equipo",
		"Mano" in main._tool_label.text and "Puños" in main._tool_label.text)
	_check("HUD muestra 'Sin armadura' al inicio", "Sin armadura" in main._armor_label.text)

	# ---- TEST 1: panel de Fabricar — una fila por familia de equipo,
	# con progresión por niveles (TIER_CHAINS): no se salta de tier ----
	_check("TIER_CHAINS define pico/espada/armadura",
		main.TIER_CHAINS.has("pico") and main.TIER_CHAINS.has("espada") and main.TIER_CHAINS.has("armadura"))
	_check("panel Fabricar tiene 8 filas (3 familias de equipo + 5 bloques)",
		main._craft_rows.size() == 8)

	main.inventories[1] = {"wood": 8}
	main._apply_inventory(main.inventories[1])
	print("[1] panel craft (pico, madera lista):", main._craft_rows["pico"].label.text)
	_check("panel craft muestra Pico de madera con madera 8/8 antes de craftear",
		"Pico de madera" in main._craft_rows["pico"].label.text and "madera 8/8" in main._craft_rows["pico"].label.text)
	_check("panel craft habilita 'Crear' con materiales completos", not main._craft_rows["pico"].button.disabled)

	main._do_craft("pico_madera", 1)
	var inv1: Dictionary = main.inventories[1]
	print("[1] inventario tras craft pico_madera:", inv1, " status:", main._status.text)
	_check("pico_madera consume 8 madera", int(inv1.get("wood", -1)) == 0)
	_check("pico_madera queda en inventario", int(inv1.get("pico_madera", 0)) == 1)
	_check("get_tool_damage = 35 (madera)", main.get_tool_damage(1) == 35)
	print("[1] panel craft tras craftear:", main._craft_rows["pico"].label.text)
	_check("panel craft avanza a la siguiente mejora (Pico de piedra)", "Pico de piedra" in main._craft_rows["pico"].label.text)
	_check("panel craft deshabilita 'Crear' sin materiales para la siguiente mejora", main._craft_rows["pico"].button.disabled)

	# ---- TEST 1b: no se puede saltar de madera a dorado sin pasar por piedra ----
	main.inventories[1] = {"wood": 4, "ore": 8, "pico_madera": 1}
	main._apply_inventory(main.inventories[1])
	main._do_craft("pico_dorado", 1)
	var inv1b: Dictionary = main.inventories[1]
	print("[1b] intento de saltar a pico_dorado sin pico_piedra:", inv1b, " status:", main._status.text)
	_check("no se puede saltar de madera a dorado sin pasar por piedra", not inv1b.has("pico_dorado"))
	_check("el toast pide fabricar la mejora intermedia (piedra)", "Pico de piedra" in main._status.text)

	# ---- TEST 2: craftear pico_piedra SIN materiales (con pico_madera ya en inventario) ----
	main.inventories[1] = {"wood": 0, "stone": 0, "pico_madera": 1}
	main._apply_inventory(main.inventories[1])
	print("[2] panel craft (sin materiales):", main._craft_rows["pico"].label.text)
	_check("panel craft muestra madera 0/4 y piedra 0/12", "madera 0/4" in main._craft_rows["pico"].label.text and "piedra 0/12" in main._craft_rows["pico"].label.text)
	_check("panel craft deshabilita 'Crear' sin materiales", main._craft_rows["pico"].button.disabled)

	main._do_craft("pico_piedra", 1)
	var inv2: Dictionary = main.inventories[1]
	print("[2] inventario tras craft sin materiales:", inv2, " status:", main._status.text)
	_check("sin materiales no agrega pico_piedra", not inv2.has("pico_piedra"))
	_check("toast de error muestra 'faltan materiales'", "faltan materiales" in main._status.text)

	# ---- TEST 3: craftear pico_dorado con materiales exactos (ya con pico_piedra) ----
	main.inventories[1] = {"wood": 4, "ore": 8, "pico_piedra": 1}
	main._apply_inventory(main.inventories[1])
	_check("panel craft habilita pico_dorado con materiales completos", not main._craft_rows["pico"].button.disabled)

	main._do_craft("pico_dorado", 1)
	var inv3: Dictionary = main.inventories[1]
	print("[3] inventario tras craft pico_dorado:", inv3, " status:", main._status.text)
	_check("pico_dorado consume wood y ore", int(inv3.get("wood", -1)) == 0 and int(inv3.get("ore", -1)) == 0)
	_check("get_tool_damage = 100 (dorado, mejor herramienta)", main.get_tool_damage(1) == 100)
	print("[3] panel craft tras craftear:", main._craft_rows["pico"].label.text)
	_check("panel craft avanza a la siguiente mejora (Pico de cristal)", "Pico de cristal" in main._craft_rows["pico"].label.text)
	_check("panel craft deshabilita pico de cristal sin cristal", main._craft_rows["pico"].button.disabled)

	# ---- TEST 3b: HUD muestra el pico dorado como herramienta equipada ----
	print("[3b] HUD tras craftear dorado:", main._tool_label.text)
	_check("HUD muestra pico dorado equipado", "Pico dorado" in main._tool_label.text)

	# ---- TEST 3c: barra de vida reacciona al daño ----
	main.damage_player(1, 30)
	print("[3c] HUD tras 30 de daño:", main._hp_label.text)
	_check("HUD actualiza barra de vida tras daño", int(main._hp_bar.value) == main.PLAYER_MAX_HP - 30 and main._hp_label.text == "%d/%d" % [main.PLAYER_MAX_HP - 30, main.PLAYER_MAX_HP])

	# ---- TEST 4: minar un árbol da madera (pipeline completo) ----
	main.inventories[1] = {}
	var w: Node2D = main.world
	var wood_coord: Variant = null
	for c: Vector2i in w.tiles.keys():
		if w.tiles[c] == w.T_WOOD:
			wood_coord = c
			break
	if wood_coord == null:
		print("[4] no se generó ningún árbol en este mundo (probabilidad 10% por columna) — se omite")
	else:
		var p: Node2D = main.players[1]
		p.position = w._tile_center(wood_coord)
		print("[4] tile de madera en", wood_coord, "HP=", w.HP[w.T_WOOD], "jugador en", p.position)
		for i in range(5):
			w._do_hit(wood_coord, 1)
			if not w.tiles.has(wood_coord):
				break
		print("[4] inventario tras minar árbol:", main.inventories[1])
		_check("minar madera agrega 'wood' al inventario", int(main.inventories[1].get("wood", 0)) >= 1)

	# ---- TEST 5: regeneración de vida (tick del servidor) ----
	main.player_hp[1] = 50
	main._regen_tick()
	print("[5] vida tras un tick de regen:", main.player_hp[1])
	_check("regen cura %d puntos por tick" % main.REGEN_AMOUNT,
		int(main.player_hp[1]) == 50 + main.REGEN_AMOUNT)
	_check("HUD refleja la regeneración", int(main._hp_bar.value) == 50 + main.REGEN_AMOUNT)
	main.player_hp[1] = main.PLAYER_MAX_HP - 1
	main._regen_tick()
	_check("regen no pasa del máximo", int(main.player_hp[1]) == main.PLAYER_MAX_HP)

	# ---- TEST 6: ciclo día/noche (Fase 6) + oleada nocturna ----
	var npcs_node: Node2D = main.get_node("NPCs")
	_check("la partida arranca de día", not main.is_night and main.night_number == 0)
	main._phase_t = main.DAY_SECONDS - 20.0
	_check("daylight_factor = 1 en pleno día", main.daylight_factor() == 1.0)
	main._set_phase(true)
	_check("_set_phase(true) inicia la noche 1", main.is_night and main.night_number == 1)
	_check("toast anuncia la noche", "Noche 1" in main._status.text)
	print("[6] enemigos tras anochecer:", npcs_node.npcs.size())
	_check("el anochecer invoca la oleada (3+noche)", npcs_node.npcs.size() >= 4)
	var kinds_ok := true
	for nid: int in npcs_node.npcs:
		if not npcs_node.KINDS.has(npcs_node.npcs[nid].kind):
			kinds_ok = false
	_check("todos los enemigos tienen variante válida", kinds_ok)
	main._phase_t = main.NIGHT_SECONDS - 20.0
	_check("daylight_factor = 0 en plena noche", main.daylight_factor() == 0.0)
	main._set_phase(false)
	_check("amanece tras la noche", not main.is_night and "Amaneció" in main._status.text)

	# ---- TEST 6b: murciélago (enemigo volador nocturno) ----
	_check("KINDS incluye murciélago volador",
		npcs_node.KINDS.has("murcielago") and bool(npcs_node.KINDS["murcielago"].get("fly", false)))
	_check("Atlas tiene textura del murciélago", Atlas.slimes.has("murcielago"))
	npcs_node.npcs.clear()
	npcs_node._spawn_one("murcielago", main.players[1])
	var bid: int = npcs_node.npcs.keys()[0]
	var b0: Vector2 = npcs_node.npcs[bid].pos
	for i in 30:
		npcs_node._simulate(1.0 / 30.0)
	var bat: Dictionary = npcs_node.npcs.get(bid, {})
	print("[6b] murciélago:", b0, "->", bat.get("pos"))
	_check("el murciélago vuela (se mueve sin caer en picada)",
		bat.has("pos") and bat.pos != b0 and absf(bat.vel.y) < 250.0)

	# ---- TEST 7: matar un slime da Núcleos según su variante ----
	var sid: int = npcs_node.npcs.keys()[0]
	var skind: String = npcs_node.npcs[sid].kind
	npcs_node.npcs[sid].hp = 1
	npcs_node.npcs[sid].pos = main.players[1].position
	var coins_antes: int = int(main._profile_of(1).coins)
	npcs_node._do_hit(sid, 1)
	print("[7] slime '%s' muerto, Núcleos: %d -> %d" % [skind, coins_antes, int(main._profile_of(1).coins)])
	_check("el slime muerto desaparece", not npcs_node.npcs.has(sid))
	_check("Núcleos por slime según su variante",
		int(main._profile_of(1).coins) == coins_antes + int(npcs_node.KINDS[skind].coins))

	# ---- TEST 8: meteoro con x anunciada deja mineral donde avisó ----
	var donde: Vector2i = main.world.meteor_strike(40)
	print("[8] meteoro impactó en", donde)
	_check("el meteoro respeta la x anunciada", donde.x == 40)

	# ---- TEST 9: armas — la espada sube el ataque pero no el minado ----
	main.inventories[1] = {}
	_check("sin espada se ataca a mano (%d)" % main.HAND_DAMAGE,
		main.get_attack_damage(1) == main.HAND_DAMAGE)
	main.inventories[1] = {"wood": 10}
	main._do_craft("espada_madera", 1)
	print("[9] inventario tras craft espada:", main.inventories[1])
	_check("craftear espada_madera consume la madera", int(main.inventories[1].get("wood", -1)) == 0)
	_check("ataque con espada de madera = %d" % main.WEAPON_DAMAGE["espada_madera"],
		main.get_attack_damage(1) == main.WEAPON_DAMAGE["espada_madera"])
	_check("la espada NO cambia el daño de minado", main.get_tool_damage(1) == main.HAND_DAMAGE)
	main._do_craft("espada_madera", 1)
	_check("no se puede fabricar un duplicado", "Ya tienes" in main._status.text)

	# ---- TEST 10: armadura — reduce el daño recibido ----
	main.inventories[1]["armadura_piedra"] = 1
	main._apply_inventory(main.inventories[1])
	main.player_hp[1] = 100
	main.damage_player(1, 14)
	print("[10] vida tras 14 de daño con armadura de piedra:", main.player_hp[1])
	_check("la armadura de piedra absorbe %d de daño" % main.ARMOR_REDUCTION["armadura_piedra"],
		int(main.player_hp[1]) == 100 - (14 - main.ARMOR_REDUCTION["armadura_piedra"]))
	_check("HUD muestra espada y armadura equipadas",
		"Espada de madera" in main._tool_label.text and "Armadura de piedra" in main._armor_label.text)

	# ---- TEST 11: generación — cuevas e islas flotantes ----
	var w2: Node2D = main.world
	w2.tiles.clear()
	w2.generate()
	var huecos := 0
	for y in range(w2.SKY_ROWS + 8, w2.H - 2):
		for x in w2.W:
			if not w2.tiles.has(Vector2i(x, y)):
				huecos += 1
	var isla := 0
	for c: Vector2i in w2.tiles:
		if c.y < w2.SKY_ROWS - 2:
			isla += 1
	print("[11] aire subterráneo (cuevas):", huecos, " | tiles de isla:", isla)
	_check("la generación talla cuevas", huecos > 80)
	_check("hay islas flotantes en el cielo", isla > 20)
	var sp: Vector2 = w2.surface_spawn(40)
	_check("surface_spawn aterriza en el suelo, no en una isla",
		sp.y >= float(w2.SKY_ROWS * w2.TILE) - 48.0)

	# ---- TEST 12: la música procedural se genera y loopea ----
	var m: AudioStreamWAV = Sfx._make_music()
	print("[12] música generada:", m.data.size() / 2, "muestras")
	_check("la música se genera con datos", m != null and m.data.size() > 100000)
	_check("la música está en loop", m.loop_mode == AudioStreamWAV.LOOP_FORWARD and m.loop_end > 0)

	# ---- TEST 14: FASE 7 — muralla (craftable, apilable, 400 HP) ----
	main.inventories[1] = {"stone": 20}
	main._apply_inventory(main.inventories[1])
	_check("RECIPES tiene muralla y fogata",
		main.RECIPES.has("muralla") and main.RECIPES.has("fogata"))
	main._do_craft("muralla", 1)
	_check("muralla se craftea (consume 6 piedra)",
		int(main.inventories[1].get("muralla", 0)) == 1 and int(main.inventories[1].get("stone", 0)) == 14)
	main._do_craft("muralla", 1)
	_check("muralla es apilable (se pueden fabricar varias)",
		int(main.inventories[1].get("muralla", 0)) == 2 and int(main.inventories[1].get("stone", 0)) == 8)
	_check("muralla es tile sólido con 400 HP",
		w2.SOLID.has(w2.T_WALL) and w2.HP[w2.T_WALL] == 400)
	_check("fogata NO es sólida y tiene 200 HP",
		not w2.SOLID.has(w2.T_CAMPFIRE) and w2.HP[w2.T_CAMPFIRE] == 200)
	_check("Atlas genera texturas de muralla y fogata",
		Atlas.tiles.has(Atlas.T_WALL) and Atlas.tiles.has(Atlas.T_CAMPFIRE))

	# ---- TEST 15: NPC ataca bloque que le cierra el paso ----
	# Preparar zona de prueba limpia: vaciar área, poner suelo y muralla
	var test_y := 40
	for tx in range(16, 28):
		for ty in range(test_y - 2, test_y + 3):
			w2.tiles.erase(Vector2i(tx, ty))
			w2.damage.erase(Vector2i(tx, ty))
	for tx in range(16, 28):
		w2.tiles[Vector2i(tx, test_y + 1)] = w2.T_STONE
	var wall_c := Vector2i(21, test_y)
	w2.tiles[wall_c] = w2.T_WALL
	npcs_node.npcs.clear()
	var wall_p: Node2D = main.players[1]
	wall_p.position = Vector2(24 * w2.TILE, float(test_y * w2.TILE + 12))
	npcs_node._spawn_one("normal", wall_p)
	var nid_w: int = npcs_node.npcs.keys()[0]
	# NPC a la izquierda de la muralla, sobre el suelo, SIN saltar
	npcs_node.npcs[nid_w].pos = Vector2(658.0, float((test_y + 1) * w2.TILE - 10))
	npcs_node.npcs[nid_w].block_cd = 0.0
	npcs_node.npcs[nid_w].jump_t = 10.0
	npcs_node._simulate(0.033)
	var wall_dmg_exists: bool = w2.damage.has(wall_c)
	var wall_hp_now: int = w2.damage.get(wall_c, w2.HP[w2.T_WALL])
	print("[15] muralla dañada:", wall_dmg_exists, " HP:", wall_hp_now, "/", w2.HP[w2.T_WALL])
	_check("NPC daña el bloque que le cierra el paso",
		wall_dmg_exists and wall_hp_now < w2.HP[w2.T_WALL])
	# Limpiar zona
	for tx in range(16, 28):
		for ty in range(test_y - 2, test_y + 3):
			w2.tiles.erase(Vector2i(tx, ty))

	# ---- TEST 16: fogata — regen nocturna solo en su aura ----
	var camp_c := Vector2i(25, 17)
	w2.tiles[camp_c] = w2.T_CAMPFIRE
	main.is_night = true
	main.player_hp[1] = 50
	wall_p.position = Vector2(25 * w2.TILE + 16, 17 * w2.TILE)
	main._regen_tick()
	_check("regen nocturna funciona CERCA de la fogata",
		int(main.player_hp[1]) == 50 + main.REGEN_AMOUNT)
	main.player_hp[1] = 50
	wall_p.position = Vector2(1 * w2.TILE, 1 * w2.TILE)
	main._regen_tick()
	_check("regen nocturna NO funciona LEJOS de la fogata",
		int(main.player_hp[1]) == 50)
	main.is_night = false
	main._regen_tick()
	_check("regen diurna funciona en todas partes",
		int(main.player_hp[1]) == 50 + main.REGEN_AMOUNT)

	# ---- TEST 17: respawn en fogata más cercana ----
	wall_p.position = Vector2(25 * w2.TILE, 17 * w2.TILE)
	main.player_hp[1] = 1
	main.damage_player(1, 10)
	var spawn_d: float = wall_p.position.distance_to(Vector2(camp_c.x * w2.TILE + 16, camp_c.y * w2.TILE - 20))
	print("[17] respawn cerca de fogata, distancia:", spawn_d)
	_check("el jugador respawnea cerca de la fogata",
		spawn_d < main.FOGATA_RANGE)
	w2.tiles.erase(camp_c)
	w2.tiles.erase(wall_c)

	# ---- TEST 18: FASE 8 — recetas, tiles y texturas de trampa/torre ----
	_check("RECIPES tiene trampa y torre",
		main.RECIPES.has("trampa") and main.RECIPES.has("torre"))
	_check("trampa NO es sólida y tiene 120 HP",
		not w2.SOLID.has(w2.T_SPIKES) and w2.HP[w2.T_SPIKES] == 120)
	_check("torre es sólida con 250 HP",
		w2.SOLID.has(w2.T_TOWER) and w2.HP[w2.T_TOWER] == 250)
	_check("Atlas genera texturas de trampa, torre y flecha",
		Atlas.tiles.has(Atlas.T_SPIKES) and Atlas.tiles.has(Atlas.T_TOWER) and Atlas.arrow_tex != null)

	main.inventories[1] = {"stone": 30, "ore": 19, "wood": 10}
	main._apply_inventory(main.inventories[1])
	main._do_craft("trampa", 1)
	_check("trampa se craftea (consume 10 piedra + 4 mineral)",
		int(main.inventories[1].get("trampa", 0)) == 1
		and int(main.inventories[1].get("stone", 0)) == 20
		and int(main.inventories[1].get("ore", 0)) == 15)
	main._do_craft("torre", 1)
	_check("torre se craftea (consume 20 piedra + 10 madera + 15 mineral)",
		int(main.inventories[1].get("torre", 0)) == 1
		and int(main.inventories[1].get("stone", 0)) == 0
		and int(main.inventories[1].get("wood", 0)) == 0
		and int(main.inventories[1].get("ore", 0)) == 0)

	# ---- TEST 19: FASE 8 — trampa de pinchos daña por contacto ----
	var spike_y := 45
	for tx in range(50, 56):
		for ty in range(spike_y - 2, spike_y + 3):
			w2.tiles.erase(Vector2i(tx, ty))
			w2.damage.erase(Vector2i(tx, ty))
	for tx in range(50, 56):
		w2.tiles[Vector2i(tx, spike_y + 1)] = w2.T_STONE
	var spike_c := Vector2i(53, spike_y)
	w2.tiles[spike_c] = w2.T_SPIKES
	npcs_node.npcs.clear()
	npcs_node._spawn_one("normal", wall_p)
	var sid_spike: int = npcs_node.npcs.keys()[0]
	npcs_node.npcs[sid_spike].pos = Vector2(float(spike_c.x * w2.TILE + 16), float(spike_c.y * w2.TILE + 22))
	npcs_node.npcs[sid_spike].vel = Vector2.ZERO
	npcs_node.npcs[sid_spike].jump_t = 10.0
	var spike_hp_before: int = int(npcs_node.npcs[sid_spike].hp)
	npcs_node._simulate(0.033)
	var spike_hp_after: int = int(npcs_node.npcs.get(sid_spike, {}).get("hp", spike_hp_before))
	print("[19] HP del NPC sobre la trampa:", spike_hp_before, "->", spike_hp_after)
	_check("la trampa de pinchos daña al NPC por contacto",
		spike_hp_after == spike_hp_before - npcs_node.SPIKE_DAMAGE)
	for tx in range(50, 56):
		for ty in range(spike_y - 2, spike_y + 3):
			w2.tiles.erase(Vector2i(tx, ty))

	# ---- TEST 20: FASE 8 — torre de flechas dispara y daña al enemigo ----
	var tower_c := Vector2i(60, 45)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			w2.tiles.erase(Vector2i(tower_c.x + dx, tower_c.y + dy))
	w2.tiles[tower_c] = w2.T_TOWER
	npcs_node.npcs.clear()
	npcs_node._spawn_one("normal", wall_p)
	var tid: int = npcs_node.npcs.keys()[0]
	var torigin := Vector2(tower_c.x * w2.TILE + w2.TILE * 0.5, tower_c.y * w2.TILE + w2.TILE * 0.25)
	npcs_node.npcs[tid].pos = torigin + Vector2(96.0, 0.0)
	npcs_node.npcs[tid].vel = Vector2.ZERO
	var tower_hp_before: int = int(npcs_node.npcs[tid].hp)
	main.tower_mgr.towers.clear()
	main.tower_mgr.arrows.clear()
	main.tower_mgr._scan_t = 0.0
	for i in 20:
		main.tower_mgr._simulate(1.0 / 30.0)
	var tower_hp_after: int = int(npcs_node.npcs.get(tid, {}).get("hp", tower_hp_before))
	print("[20] torres detectadas:", main.tower_mgr.towers.size(), " | HP del NPC:", tower_hp_before, "->", tower_hp_after)
	_check("la torre detecta el tile T_TOWER", main.tower_mgr.towers.has(tower_c))
	_check("la torre dispara y daña al enemigo más cercano",
		tower_hp_after == tower_hp_before - main.tower_mgr.ARROW_DAMAGE)
	w2.tiles.erase(tower_c)
	npcs_node.npcs.clear()

	# ---- TEST 21: FASE 9 — el jefe aparece cada BOSS_EVERY noches ----
	_check("KINDS incluye al jefe", npcs_node.KINDS.has("jefe"))
	_check("Atlas tiene textura del jefe", Atlas.slimes.has("jefe"))
	npcs_node.npcs.clear()
	npcs_node.night_wave(npcs_node.BOSS_EVERY)
	var has_boss := false
	for nid: int in npcs_node.npcs:
		if npcs_node.npcs[nid].kind == "jefe":
			has_boss = true
	print("[21] enemigos en la oleada de la noche %d:" % npcs_node.BOSS_EVERY, npcs_node.npcs.size(), "| jefe:", has_boss)
	_check("la oleada de la noche %d incluye un jefe" % npcs_node.BOSS_EVERY, has_boss)
	npcs_node.npcs.clear()

	# ---- TEST 22: FASE 9 — recompensa de Núcleos al amanecer ----
	main.set_mode("sandbox")
	main.night_number = 3
	var coins_before22: int = int(main._profile_of(1).coins)
	main._set_phase(false)
	var reward22: int = main.NIGHT_REWARD_BASE + main.NIGHT_REWARD_STEP * 3
	print("[22] Núcleos antes/después del amanecer:", coins_before22, "->", int(main._profile_of(1).coins))
	_check("amanecer recompensa Núcleos por noche sobrevivida (+%d)" % reward22,
		int(main._profile_of(1).coins) == coins_before22 + reward22)

	# ---- TEST 23: FASE 9 — victoria al completar SURVIVAL_NIGHTS ----
	main.set_mode("survival")
	main.night_number = main.SURVIVAL_NIGHTS
	main._run_over = false
	main._run_panel.hide()
	var coins_before23: int = int(main._profile_of(1).coins)
	main._set_phase(false)
	var reward23: int = main.NIGHT_REWARD_BASE + main.NIGHT_REWARD_STEP * main.SURVIVAL_NIGHTS
	print("[23] panel:", main._run_title.text, "|", main._run_body.text)
	_check("victoria al sobrevivir %d noches muestra el panel de fin de run" % main.SURVIVAL_NIGHTS,
		main._run_panel.visible and "VICTORIA" in main._run_title.text)
	_check("victoria otorga la recompensa de la noche + bono de %d Núcleos" % main.VICTORY_BONUS,
		int(main._profile_of(1).coins) == coins_before23 + reward23 + main.VICTORY_BONUS)
	_check("la run vuelve a modo sandbox tras la victoria",
		main.game_mode == "sandbox" and main.night_number == 0 and not main.is_night)

	# ---- TEST 24: FASE 9 — morir en supervivencia termina la run ----
	main.set_mode("survival")
	main.night_number = 4
	main._run_over = false
	main._run_panel.hide()
	main.player_hp[1] = 30
	main.damage_player(1, 999)
	print("[24] HP tras golpe letal:", main.player_hp[1], "| panel:", main._run_title.text)
	_check("morir en supervivencia muestra el panel 'FIN DE LA RUN'",
		main._run_panel.visible and "FIN DE LA RUN" in main._run_title.text)
	_check("la run reaparece al jugador con vida llena",
		int(main.player_hp[1]) == main.PLAYER_MAX_HP)
	_check("la run vuelve a modo sandbox tras la derrota",
		main.game_mode == "sandbox" and main.night_number == 0)

	# ---- TEST 25: PULIDO F9 — bajas de la run y jefe rompe-murallas ----
	npcs_node.npcs.clear()
	main.run_kills = 0
	npcs_node._spawn_one("normal", wall_p)
	var kid: int = npcs_node.npcs.keys()[0]
	npcs_node.damage_npc(kid, 9999)
	print("[25] bajas tras matar 1 NPC:", main.run_kills)
	_check("count_kill registra las bajas de la run", main.run_kills == 1)
	_check("el jefe es rompe-murallas (block_dmg propio > dmg)",
		int(npcs_node.KINDS["jefe"].get("block_dmg", 0)) > int(npcs_node.KINDS["jefe"].dmg))
	main._apply_run_ended(true, 7, 12)
	_check("el panel de fin de run muestra los enemigos abatidos",
		"12" in main._run_body.text and "abatidos" in main._run_body.text)
	main._run_panel.hide()
	npcs_node.npcs.clear()

	# ---- TEST 26: PULIDO F7-F9 — sonidos nuevos y barra del jefe ----
	var nuevos := ["flecha", "pinchos", "jefe", "noche", "amanecer", "victoria", "derrota"]
	var faltan := []
	for s: String in nuevos:
		if not Sfx._streams.has(s):
			faltan.append(s)
	print("[26] sfx nuevos faltantes:", faltan)
	_check("Sfx tiene los sonidos de torre/pinchos/jefe/fases/victoria/derrota", faltan.is_empty())
	_check("existe la barra de vida del jefe en el HUD",
		main._boss_panel != null and main._boss_bar != null)
	_check("el jefe tiene sprite propio en el Atlas (no slime reteñido)",
		Atlas.slimes["jefe"].get_width() == 24 and Atlas.slimes["jefe"].get_height() == 18)

	# ---- TEST 13: arte y efectos nuevos ----
	_check("Atlas genera 4 decoraciones de superficie", Atlas.deco.size() == 4)
	var dl: float = main.world.daylight()
	print("[13] fase del día:", main.world.day_phase(), " luz:", dl)
	_check("daylight() está en 0..1", dl >= 0.0 and dl <= 1.0)
	main.world.fx.float_text(Vector2.ZERO, "+1 Prueba", Color.WHITE)
	main.world.fx.ring(Vector2.ZERO, 100.0, Color.WHITE)
	main.world.fx.burst(Vector2.ZERO, Color.WHITE, 4)
	_check("fx acepta textos flotantes, anillos y ráfagas", true)
	_check("existe el aviso de vida baja en el HUD", main._low_hp != null)

	# ---- TEST 27: FASE 10 — nuevas variantes registradas (KINDS + Atlas) ----
	var nuevas_kinds := ["taladro", "topo", "embistedor", "slime_mega",
		"jefe_murcielago", "jefe_topo", "jefe_corredor"]
	var faltan_kinds := []
	for k: String in nuevas_kinds:
		if not npcs_node.KINDS.has(k) or not Atlas.slimes.has(k):
			faltan_kinds.append(k)
	print("[27] variantes Fase 10 sin registrar:", faltan_kinds)
	_check("KINDS y Atlas registran las variantes nuevas de Fase 10", faltan_kinds.is_empty())
	_check("'taladro' y 'topo' excavan (digs); 'topo' nace en cuevas (cave)",
		bool(npcs_node.KINDS["taladro"].get("digs", false))
		and bool(npcs_node.KINDS["topo"].get("digs", false))
		and bool(npcs_node.KINDS["topo"].get("cave", false)))
	_check("'embistedor' y 'jefe_corredor' embisten (charges) con charge_dmg > dmg",
		bool(npcs_node.KINDS["embistedor"].get("charges", false))
		and int(npcs_node.KINDS["embistedor"].charge_dmg) > int(npcs_node.KINDS["embistedor"].dmg)
		and bool(npcs_node.KINDS["jefe_corredor"].get("charges", false))
		and int(npcs_node.KINDS["jefe_corredor"].charge_dmg) > int(npcs_node.KINDS["jefe_corredor"].dmg))
	_check("FUSION_CHAIN encadena normal -> grande -> slime_mega",
		npcs_node.FUSION_CHAIN.get("normal", "") == "grande"
		and npcs_node.FUSION_CHAIN.get("grande", "") == "slime_mega")

	# ---- TEST 28: FASE 10 — "taladro" excava el bloque de abajo (rompedor vertical) ----
	var dig_y := 42
	for tx in range(70, 76):
		for ty in range(dig_y - 2, dig_y + 2):
			w2.tiles.erase(Vector2i(tx, ty))
			w2.damage.erase(Vector2i(tx, ty))
	w2.tiles[Vector2i(73, dig_y + 1)] = w2.T_STONE
	npcs_node.npcs.clear()
	npcs_node._spawn_one("taladro", wall_p)
	var did: int = npcs_node.npcs.keys()[0]
	var dig_below := Vector2i(73, dig_y + 1)
	npcs_node.npcs[did].pos = Vector2(73.0 * w2.TILE + w2.TILE * 0.5, float((dig_y + 1) * w2.TILE - 10))
	npcs_node.npcs[did].vel = Vector2.ZERO
	npcs_node.npcs[did].jump_t = 5.0
	npcs_node.npcs[did].dig_cd = 0.0
	npcs_node._simulate(0.05)
	var dig_hp_left: int = int(w2.damage.get(dig_below, w2.HP[w2.T_STONE]))
	print("[28] HP restante del bloque tras excavar:", dig_hp_left, "| dig_cd:", npcs_node.npcs[did].get("dig_cd", 0.0))
	_check("el taladro excava el bloque de abajo (dmg = block_dmg) y entra en cooldown",
		dig_hp_left == w2.HP[w2.T_STONE] - int(npcs_node.KINDS["taladro"].block_dmg)
		and float(npcs_node.npcs[did].get("dig_cd", 0.0)) > 0.0)
	for tx in range(70, 76):
		for ty in range(dig_y - 2, dig_y + 2):
			w2.tiles.erase(Vector2i(tx, ty))
			w2.damage.erase(Vector2i(tx, ty))
	npcs_node.npcs.clear()

	# ---- TEST 29: FASE 10 — "embistedor" carga (winding) y embiste (charging) ----
	var ch_y := 50
	for tx in range(98, 104):
		for ty in range(ch_y - 2, ch_y + 2):
			w2.tiles.erase(Vector2i(tx, ty))
			w2.damage.erase(Vector2i(tx, ty))
	w2.tiles[Vector2i(100, ch_y + 1)] = w2.T_STONE
	npcs_node.npcs.clear()
	npcs_node._spawn_one("embistedor", wall_p)
	var cid: int = npcs_node.npcs.keys()[0]
	var k29: Dictionary = npcs_node.KINDS["embistedor"]
	var n29: Dictionary = npcs_node.npcs[cid]
	n29.pos = Vector2(100.0 * w2.TILE + w2.TILE * 0.5, float((ch_y + 1) * w2.TILE - 10))
	n29.vel = Vector2.ZERO
	var target29 := Node2D.new()
	add_child(target29)
	target29.position = n29.pos + Vector2(80.0, 0.0)
	npcs_node._update_charge(n29, k29, target29, 80.0, 0.05, w2, false)
	print("[29] estado tras detectar al jugador cerca:", n29.get("charge_state", ""))
	_check("el embistedor empieza a 'cargar' (winding) cerca y a la altura del jugador",
		n29.get("charge_state", "") == "winding")
	var ticks29 := 0
	while n29.get("charge_state", "") != "charging" and ticks29 < 20:
		npcs_node._update_charge(n29, k29, target29, 80.0, 0.1, w2, false)
		ticks29 += 1
	print("[29] estado tras", ticks29, "ticks de carga:", n29.get("charge_state", ""), "| vel.x:", n29.vel.x)
	_check("tras CHARGE_WINDUP, el embistedor embiste (charging) hacia el jugador a CHARGE_SPEED",
		n29.get("charge_state", "") == "charging"
		and signf(n29.vel.x) == signf(target29.position.x - n29.pos.x)
		and absf(n29.vel.x) == npcs_node.CHARGE_SPEED)
	target29.free()
	npcs_node.npcs.clear()
	for tx in range(98, 104):
		for ty in range(ch_y - 2, ch_y + 2):
			w2.tiles.erase(Vector2i(tx, ty))
			w2.damage.erase(Vector2i(tx, ty))

	# ---- TEST 30: FASE 10 — fusión de slimes (normal + normal -> grande) ----
	npcs_node.npcs.clear()
	npcs_node._spawn_one("normal", wall_p)
	npcs_node._spawn_one("normal", wall_p)
	var ids30: Array = npcs_node.npcs.keys()
	npcs_node.npcs[ids30[0]].pos = Vector2(2000.0, 500.0)
	npcs_node.npcs[ids30[1]].pos = Vector2(2020.0, 500.0)
	for i in 8:
		npcs_node._process_fusions(1.0)
	print("[30] NPCs tras fusión:", npcs_node.npcs.size(), "| kind:", str(npcs_node.npcs.values()[0].get("kind", "")))
	_check("dos slimes 'normal' juntos por MERGE_TIME se fusionan en 'grande'",
		npcs_node.npcs.size() == 1 and npcs_node.npcs.values()[0].get("kind", "") == "grande")
	npcs_node.npcs.clear()

	# ---- TEST 31: FASE 10 — nidos (T_NEST): siembra, escaneo y eclosión ----
	var nest_c: Vector2i = w2.spawn_nest(80)
	print("[31] nido sembrado en:", nest_c, "| tile:", w2.tiles.get(nest_c, -1))
	_check("spawn_nest coloca un T_NEST junto a una cara de aire",
		nest_c.x >= 0 and w2.tiles.get(nest_c, -1) == w2.T_NEST)
	npcs_node.npcs.clear()
	npcs_node._nests.clear()
	npcs_node._nest_scan_t = 0.0
	npcs_node._update_nests(0.0, w2)
	_check("el escaneo periódico detecta el nido sembrado", npcs_node._nests.has(nest_c))
	npcs_node._nests[nest_c] = npcs_node.NEST_SPAWN_EVERY
	npcs_node._update_nests(0.001, w2)
	print("[31] NPCs tras madurar el nido:", npcs_node.npcs.size())
	_check("un nido maduro escupe un enemigo en una cara de aire vecina", npcs_node.npcs.size() == 1)
	main.on_nest_destroyed(nest_c)
	_check("on_nest_destroyed olvida el nido (deja de escupir)", not npcs_node._nests.has(nest_c))
	for c: Vector2i in w2.tiles.keys():
		if w2.tiles[c] == w2.T_NEST:
			w2.tiles.erase(c)
	npcs_node._nests.clear()
	npcs_node.npcs.clear()

	# ---- TEST 32: FASE 10 — roster de jefes + anuncio al iniciar la run ----
	_check("BOSS_KINDS incluye 4 jefes (clásico, murciélago, topo, corredor), todos boss=true",
		main.BOSS_KINDS.size() == 4
		and "jefe_murcielago" in main.BOSS_KINDS and "jefe_topo" in main.BOSS_KINDS
		and "jefe_corredor" in main.BOSS_KINDS
		and bool(npcs_node.KINDS["jefe_murcielago"].get("boss", false))
		and bool(npcs_node.KINDS["jefe_topo"].get("boss", false))
		and bool(npcs_node.KINDS["jefe_corredor"].get("boss", false)))
	main.run_boss_kind = "jefe_topo"
	var anuncio32: String = main._boss_announcement()
	print("[32] anuncio del jefe:", anuncio32)
	_check("el anuncio del jefe incluye su nombre y una pista de estrategia",
		"Mega Topo" in anuncio32 and "excava" in anuncio32)
	npcs_node.npcs.clear()
	npcs_node.night_wave(npcs_node.BOSS_EVERY)
	var has_alt_boss := false
	for nid: int in npcs_node.npcs:
		if npcs_node.npcs[nid].kind == "jefe_topo":
			has_alt_boss = true
	print("[32] oleada con jefe de la run:", npcs_node.npcs.size(), "| jefe_topo:", has_alt_boss)
	_check("night_wave invoca el jefe elegido para la run (run_boss_kind)", has_alt_boss)
	main._process(0.0)
	print("[32] HUD jefe:", main._boss_label.text if main._boss_label != null else "?", "| visible:", main._boss_panel.visible)
	_check("la barra del HUD muestra el nombre del jefe vivo (roster variable)",
		main._boss_panel.visible and main._boss_label != null and "MEGA TOPO" in main._boss_label.text)
	npcs_node.npcs.clear()
	main.run_boss_kind = "jefe"
	main._boss_panel.hide()

	# ---- TEST 33: ARQUITECTURA — capa de reglas (game_modes.gd) ----
	var gm := preload("res://scripts/game_modes.gd")
	_check("la capa de reglas define los modos sandbox, survival y asedio",
		gm.MODES.has("sandbox") and gm.MODES.has("survival") and gm.MODES.has("asedio"))
	main.set_mode("asedio")
	print("[33] modo asedio:", main.mode_cfg.nombre, "| noches:", main.mode_cfg.nights_to_win,
		"| oleada base:", main.mode_cfg.wave_base)
	_check("set_mode carga las reglas del modo (asedio: 3 noches, muerte termina run)",
		int(main.mode_cfg.nights_to_win) == 3 and bool(main.mode_cfg.death_ends_run)
		and not bool(main.mode_cfg.save_allowed))
	npcs_node.npcs.clear()
	npcs_node.night_wave(2)   # noche par: sin nido; asedio manda 6+2*2=10 enemigos
	print("[33] enemigos de la oleada 2 en asedio:", npcs_node.npcs.size())
	_check("la oleada nocturna obedece wave_base/wave_step del modo (asedio escala más)",
		npcs_node.npcs.size() == mini(6 + 2 * 2, npcs_node.WAVE_CAP))
	npcs_node.npcs.clear()
	main.set_mode("sandbox")
	_check("el catálogo de skins incluye las temáticas del bestiario (Fase 10)",
		main.SKINS.has("topo") and main.SKINS.has("nocturna")
		and main.SKINS.has("acero") and main.SKINS.has("demonio"))
	_check("los sonidos nuevos (fusión, nido) están sintetizados",
		Sfx._streams.has("fusion") and Sfx._streams.has("nido"))

	# ---- TEST 34: PULIDO — sprite fantasma al morir el último NPC,
	# y jefes sin matar no frenan las oleadas siguientes ----
	npcs_node.npcs.clear()
	npcs_node._had_npcs = false
	npcs_node._spawn_one("normal", wall_p)
	npcs_node._process(0.016)
	print("[34] _had_npcs con NPCs en pantalla:", npcs_node._had_npcs)
	_check("_had_npcs se activa mientras haya NPCs", npcs_node._had_npcs)
	npcs_node.npcs.clear()
	npcs_node._process(0.016)
	print("[34] _had_npcs tras matar al último NPC:", npcs_node._had_npcs)
	_check("tras vaciarse npcs, _process aún dispara un redraw final (limpia el sprite fantasma)",
		not npcs_node._had_npcs)

	npcs_node.npcs.clear()
	npcs_node._spawn_one("jefe", wall_p)   # jefe sin matar de una noche anterior
	_check("_non_boss_count() no cuenta al jefe vivo (queda fuera del WAVE_CAP)",
		npcs_node._non_boss_count() == 0)
	npcs_node.night_wave(1)   # sandbox: wave_base=3, wave_step=1 -> 3+1=4
	var non_boss34 := 0
	for nid: int in npcs_node.npcs:
		if not bool(npcs_node.KINDS[npcs_node.npcs[nid].kind].get("boss", false)):
			non_boss34 += 1
	print("[34] no-jefes tras night_wave con un jefe vivo:", non_boss34, "| total:", npcs_node.npcs.size())
	_check("night_wave manda la oleada completa aunque haya un jefe sin matar de antes",
		non_boss34 == 4)
	npcs_node.npcs.clear()

	# ---- TEST 35: movimiento server-authoritative — _simulate_step,
	# _process_remote_authority y _reconcile (GDD §10.2). El flujo
	# end-to-end con 2+ peers reales (sin rubber-banding, respawn limpio)
	# se prueba a mano: Depurar -> Ejecutar múltiples instancias. ----
	var p35: Node2D = main.players[1]

	# 35a: error pequeño (entre RECONCILE_MIN_ERROR y RECONCILE_SNAP_DIST)
	# corrige PARCIALMENTE (lerp), sin saltar de golpe al valor del servidor.
	var base35 := Vector2(500.0, 500.0)
	p35.position = base35
	var server_pos_a := base35 + Vector2(10.0, 0.0)
	p35._reconcile(server_pos_a, Vector2.ZERO, true)
	print("[35a] reconcile error pequeño:", base35, "->", p35.position, "(servidor:", server_pos_a, ")")
	_check("_reconcile con error pequeño corrige parcialmente (sin snap total)",
		p35.position.distance_to(base35) > 0.0 and p35.position.distance_to(server_pos_a) > 0.0)

	# 35b: error grande (> RECONCILE_SNAP_DIST) hace SNAP total
	# (posición, velocidad y on_floor igualan al servidor).
	p35.position = base35
	p35.velocity = Vector2(40.0, -10.0)
	p35.on_floor = false
	var server_pos_b := base35 + Vector2(200.0, 0.0)
	var server_vel_b := Vector2(123.0, -45.0)
	p35._reconcile(server_pos_b, server_vel_b, true)
	print("[35b] reconcile error grande:", p35.position, p35.velocity, p35.on_floor)
	_check("_reconcile con error grande hace snap total (posición/velocidad/on_floor)",
		p35.position == server_pos_b and p35.velocity == server_vel_b and p35.on_floor)

	# 35c: error por debajo de RECONCILE_MIN_ERROR no corrige nada (evita jitter).
	p35.position = base35
	var server_pos_c := base35 + Vector2(1.0, 0.0)
	p35._reconcile(server_pos_c, Vector2.ZERO, true)
	_check("_reconcile con error mínimo no corrige (evita jitter)",
		p35.position == base35)

	# 35f: compensación de latencia — corriendo a velocidad constante la
	# predicción va exactamente un snapshot por delante del servidor; la
	# extrapolación (pos + vel * RECONCILE_EXTRAPOLATION) lo reconoce como
	# error CERO y no corrige (sin rubber-banding al correr en línea recta).
	var run_vel := Vector2(p35.SPEED, 0.0)
	var predicted: Vector2 = base35 + run_vel * float(p35.RECONCILE_EXTRAPOLATION)
	p35.position = predicted
	p35._reconcile(base35, run_vel, true)
	print("[35f] predicción adelantada ", base35.distance_to(predicted), "px -> corrección: ",
		p35.position.distance_to(predicted), "px")
	_check("_reconcile extrapola por velocidad (correr no produce rubber-banding)",
		p35.position == predicted)

	# 35d: _simulate_step sigue aplicando gravedad e input horizontal tras
	# la extracción (no rompió la física). Zona despejada en el cielo.
	for tx in range(23, 28):
		for ty in range(0, 5):
			w2.tiles.erase(Vector2i(tx, ty))
	var sky_pos := Vector2(25 * w2.TILE + 16, 2 * w2.TILE + 16)
	p35.position = sky_pos
	p35.velocity = Vector2.ZERO
	p35.on_floor = false
	var fall_v: float = p35._simulate_step(0.0, false, 0.1)
	print("[35d] _simulate_step sin input: velocity.y=", p35.velocity.y, "fall_v=", fall_v)
	_check("_simulate_step aplica gravedad (velocity.y == GRAVITY * delta)",
		is_equal_approx(p35.velocity.y, p35.GRAVITY * 0.1) and is_equal_approx(fall_v, p35.velocity.y))

	p35.position = sky_pos
	p35.velocity = Vector2.ZERO
	p35.on_floor = false
	p35._simulate_step(1.0, false, 0.001)
	print("[35d] _simulate_step con dir_x=1: velocity.x=", p35.velocity.x)
	_check("_simulate_step mueve según dir_x (velocity.x == SPEED)",
		is_equal_approx(p35.velocity.x, p35.SPEED))

	# 35e: _process_remote_authority usa el último input recibido del peer
	# remoto (simula al servidor moviendo el nodo de otro jugador).
	p35.position = sky_pos
	p35.velocity = Vector2.ZERO
	p35.on_floor = false
	p35._last_input_dir_x = 1.0
	p35._last_input_jump = false
	p35._process_remote_authority(0.05)
	print("[35e] _process_remote_authority:", sky_pos, "->", p35.position, "velocity:", p35.velocity)
	_check("_process_remote_authority mueve al jugador con el input del peer remoto",
		p35.position.x > sky_pos.x and is_equal_approx(p35.velocity.x, p35.SPEED))

	p35._last_input_dir_x = 0.0
	p35._last_input_jump = false

	# ---- TEST 36: mundo ampliado, biomas aéreo/profundo (T_CRYSTAL),
	# crecimiento diario de árboles y pico_cristal. ----
	print("[36a] dimensiones: W=", w2.W, " H=", w2.H, " SKY_ROWS=", w2.SKY_ROWS, " DEEP_ROWS=", w2.DEEP_ROWS)
	_check("mundo ampliado: W=200, H=90, SKY_ROWS=24, DEEP_ROWS=12",
		w2.W == 200 and w2.H == 90 and w2.SKY_ROWS == 24 and w2.DEEP_ROWS == 12)

	_check("T_CRYSTAL es sólido, 160 HP y suelta 'cristal'",
		w2.SOLID.has(w2.T_CRYSTAL) and w2.HP[w2.T_CRYSTAL] == 160 and w2.DROPS[w2.T_CRYSTAL] == "cristal")
	_check("Atlas genera textura de T_CRYSTAL",
		Atlas.tiles.has(Atlas.T_CRYSTAL) and Atlas.tiles[Atlas.T_CRYSTAL].size() == Atlas.VARIANTS)

	# Mundo nuevo (la generación es aleatoria; el seed fijo del inicio
	# hace este conteo determinista, igual que TEST 11).
	w2.tiles.clear()
	w2.generate()
	var n_crystal := 0
	var n_crystal_deep := 0
	var n_crystal_sky := 0
	for c: Vector2i in w2.tiles:
		if w2.tiles[c] == w2.T_CRYSTAL:
			n_crystal += 1
			if c.y >= w2.H - 1 - w2.DEEP_ROWS:
				n_crystal_deep += 1
			elif c.y < w2.SKY_ROWS:
				n_crystal_sky += 1
	print("[36c] tiles T_CRYSTAL: ", n_crystal, " (profundo:", n_crystal_deep, " aéreo:", n_crystal_sky, ")")
	_check("la generación produce cristal en el subsuelo profundo", n_crystal_deep > 0)
	_check("la generación produce cristal en las islas aéreas", n_crystal_sky > 0)

	# ---- TEST 36d: grow_trees() repone troncos al amanecer ----
	var wood_before := 0
	for c: Vector2i in w2.tiles:
		if w2.tiles[c] == w2.T_WOOD:
			wood_before += 1
	w2.grow_trees(40, 3)
	var wood_after := 0
	for c: Vector2i in w2.tiles:
		if w2.tiles[c] == w2.T_WOOD:
			wood_after += 1
	print("[36d] tiles T_WOOD: ", wood_before, " -> ", wood_after)
	_check("grow_trees() añade troncos nuevos en superficie despejada", wood_after > wood_before)

	# ---- TEST 36e: pico_cristal — recurso 'cristal', el mejor pico ----
	_check("RECIPES tiene pico_cristal (cuesta cristal) e ITEM_NAMES lo nombra",
		main.RECIPES.has("pico_cristal") and main.RECIPES["pico_cristal"].costo.has("cristal")
		and main.ITEM_NAMES.has("cristal"))
	main.inventories[1] = {"wood": 4, "cristal": 6, "pico_dorado": 1}
	main._apply_inventory(main.inventories[1])
	print("[36e] panel craft pico:", main._craft_rows["pico"].label.text)
	_check("panel craft muestra Pico de cristal con cristal 6/6 antes de craftear",
		"Pico de cristal" in main._craft_rows["pico"].label.text and "cristal 6/6" in main._craft_rows["pico"].label.text)
	main._do_craft("pico_cristal", 1)
	var inv36: Dictionary = main.inventories[1]
	print("[36e] inventario tras craft pico_cristal:", inv36)
	_check("pico_cristal se craftea (consume cristal/madera)",
		int(inv36.get("pico_cristal", 0)) == 1 and int(inv36.get("cristal", 0)) == 0)
	_check("get_tool_damage = 150 (pico_cristal, el mejor pico)", main.get_tool_damage(1) == 150)
	print("[36e] panel craft pico tras llegar al máximo:", main._craft_rows["pico"].label.text)
	_check("panel craft marca el pico al nivel máximo", "nivel máximo" in main._craft_rows["pico"].label.text and main._craft_rows["pico"].button.disabled)

	# ---- TEST 37: Bloque 1 "Mundo vivo" — biomas distintivos (pluma/
	# esencia/diamante/ascua/agua), ralentización en agua, presión
	# ambiental (anti-turtling) y banner dedicado de anuncio de jefe ----

	# 37a: la generación produce los minerales nuevos en su bioma propio
	# (mismo patrón determinista por seed que TEST 36c)
	var n_feather_sky := 0
	var n_aether_sky := 0
	var n_diamond_deep := 0
	var n_ember_deep := 0
	var n_water_deep := 0
	for c: Vector2i in w2.tiles:
		var tt37: int = w2.tiles[c]
		if c.y < w2.SKY_ROWS:
			if tt37 == w2.T_FEATHER:
				n_feather_sky += 1
			elif tt37 == w2.T_AETHER:
				n_aether_sky += 1
		elif c.y >= w2.H - 1 - w2.DEEP_ROWS:
			if tt37 == w2.T_DIAMOND:
				n_diamond_deep += 1
			elif tt37 == w2.T_EMBER:
				n_ember_deep += 1
			elif tt37 == w2.T_WATER:
				n_water_deep += 1
	print("[37a] aéreo pluma/esencia:", n_feather_sky, "/", n_aether_sky,
		" | profundo diamante/ascua/agua:", n_diamond_deep, "/", n_ember_deep, "/", n_water_deep)
	_check("la generación produce pluma y esencia en las islas aéreas",
		n_feather_sky > 0 and n_aether_sky > 0)
	_check("la generación produce diamante, ascua y agua en el subsuelo profundo",
		n_diamond_deep > 0 and n_ember_deep > 0 and n_water_deep > 0)

	# 37b: HP/DROPS/SOLID de los 4 minerales nuevos; T_WATER no es sólido
	_check("pluma/esencia/diamante/ascua son sólidos con su HP y drop",
		w2.SOLID.has(w2.T_FEATHER) and w2.HP[w2.T_FEATHER] == 120 and w2.DROPS[w2.T_FEATHER] == "pluma"
		and w2.SOLID.has(w2.T_AETHER) and w2.HP[w2.T_AETHER] == 180 and w2.DROPS[w2.T_AETHER] == "esencia"
		and w2.SOLID.has(w2.T_DIAMOND) and w2.HP[w2.T_DIAMOND] == 220 and w2.DROPS[w2.T_DIAMOND] == "diamante"
		and w2.SOLID.has(w2.T_EMBER) and w2.HP[w2.T_EMBER] == 160 and w2.DROPS[w2.T_EMBER] == "ascua")
	_check("T_WATER no es sólido (decorativo, ralentiza)", not w2.SOLID.has(w2.T_WATER))
	_check("ITEM_NAMES nombra pluma/esencia/diamante/ascua",
		main.ITEM_NAMES.has("pluma") and main.ITEM_NAMES.has("esencia")
		and main.ITEM_NAMES.has("diamante") and main.ITEM_NAMES.has("ascua"))

	# 37c: T_WATER ralentiza el desplazamiento horizontal (sin afectar salto/gravedad)
	# Re-despejar la zona: TEST 36 hizo tiles.clear()+generate() después del
	# despeje de TEST 35d, así que sky_pos puede haber caído sobre un tile
	# sólido nuevo (isla aérea regenerada).
	for tx in range(23, 28):
		for ty in range(0, 5):
			w2.tiles.erase(Vector2i(tx, ty))
	var water_c := Vector2i(floori(sky_pos.x / w2.TILE), floori(sky_pos.y / w2.TILE))
	w2.tiles[water_c] = w2.T_WATER
	p35.position = sky_pos
	p35.velocity = Vector2.ZERO
	p35.on_floor = false
	p35._simulate_step(1.0, false, 0.001)
	print("[37c] velocity.x sobre T_WATER:", p35.velocity.x, " (SPEED=", p35.SPEED, ")")
	_check("T_WATER ralentiza el desplazamiento horizontal (velocity.x == SPEED * WATER_SLOW)",
		is_equal_approx(p35.velocity.x, p35.SPEED * p35.WATER_SLOW))
	_check("el sonido 'agua' (chapoteo al entrar al agua) está sintetizado",
		Sfx._streams.has("agua"))
	w2.tiles.erase(water_c)

	# 37d: _has_fort detecta fortificaciones propias (T_WALL/CAMPFIRE/
	# SPIKES/TOWER) en FORT_RADIUS, con al menos FORT_MIN_BLOCKS
	var fort_pos := sky_pos
	var fort_c := water_c
	_check("_has_fort es false sin bloques de fuerte cerca", not main._has_fort(fort_pos))
	for i in main.FORT_MIN_BLOCKS:
		w2.tiles[fort_c + Vector2i(i, 0)] = w2.T_WALL
	_check("_has_fort es true con >= FORT_MIN_BLOCKS bloques de fuerte en FORT_RADIUS",
		main._has_fort(fort_pos))
	for i in main.FORT_MIN_BLOCKS:
		w2.tiles.erase(fort_c + Vector2i(i, 0))
	_check("_has_fort vuelve a false tras quitar los bloques de fuerte", not main._has_fort(fort_pos))

	# 37e: _zone_at clasifica cielo/cueva/profundo/superficie
	var y_cielo := Vector2(0.0, 0.0)
	var y_cueva := Vector2(0.0, float((w2.SKY_ROWS + main.UNDERGROUND_BAND + 2) * w2.TILE))
	var y_profundo := Vector2(0.0, float((w2.H - 2) * w2.TILE))
	var y_superficie := Vector2(0.0, float((w2.SKY_ROWS + 1) * w2.TILE))
	print("[37e] zonas:", main._zone_at(y_cielo), main._zone_at(y_cueva),
		main._zone_at(y_profundo), main._zone_at(y_superficie))
	_check("_zone_at clasifica cielo/cueva/profundo/superficie correctamente",
		main._zone_at(y_cielo) == "cielo" and main._zone_at(y_cueva) == "cueva"
		and main._zone_at(y_profundo) == "profundo" and main._zone_at(y_superficie) == "superficie")
	# La superficie generada llega hasta SKY_ROWS+8 (generate()): un valle
	# profundo NO debe contar como cueva (UNDERGROUND_BAND lo cubre)
	_check("un valle profundo de superficie (SKY_ROWS+8) NO cuenta como cueva",
		main._zone_at(Vector2(0.0, float((w2.SKY_ROWS + 8) * w2.TILE))) == "superficie")

	# 37f: _update_zone_pressure dispara spawn_near tras ZONE_PRESSURE_TIME
	# sin fuerte (resuelve el bug de islas/profundo sin enemigos); con
	# fuerte cerca, no se dispara nada.
	npcs_node.npcs.clear()
	main._zone_pressure.clear()
	var cueva_p: Node2D = main.players[1]
	cueva_p.position = y_cueva
	_check("posición de prueba en 'cueva' sin fuerte cerca",
		main._zone_at(cueva_p.position) == "cueva" and not main._has_fort(cueva_p.position))
	var n_checks37 := int(main.ZONE_PRESSURE_TIME / main.PRESSURE_CHECK_EVERY)
	for i in range(n_checks37 - 1):
		main._update_zone_pressure(1)
	print("[37f] npcs antes de cumplir ZONE_PRESSURE_TIME:", npcs_node.npcs.size())
	_check("antes de cumplir ZONE_PRESSURE_TIME no se dispara presión", npcs_node.npcs.is_empty())
	_check("el aviso ⚠️ (telegraph) llega antes del primer disparo de presión",
		main._status.text.begins_with("⚠️"))
	main._update_zone_pressure(1)
	var has_topo37 := false
	for nid: int in npcs_node.npcs:
		if npcs_node.npcs[nid].kind == "topo":
			has_topo37 = true
	print("[37f] tras ZONE_PRESSURE_TIME en cueva sin fuerte, npcs:", npcs_node.npcs.size(), "| topo:", has_topo37)
	_check("la presión ambiental en cueva sin fuerte invoca spawn_near('topo')", has_topo37)

	# 37f-escalada: reincidir en la misma zona sin fortificar trae MÁS
	# enemigos (level 2 → 2 spawns; total 1 + 2 = 3)
	for i in n_checks37:
		main._update_zone_pressure(1)
	print("[37f] tras reincidir (2º ciclo de presión), npcs:", npcs_node.npcs.size())
	_check("la presión escala al reincidir (el 2º disparo trae 2 enemigos, total 3)",
		npcs_node.npcs.size() == 3)

	npcs_node.npcs.clear()
	main._zone_pressure.clear()
	var fort_cueva := Vector2i(floori(cueva_p.position.x / w2.TILE), floori(cueva_p.position.y / w2.TILE))
	for i in main.FORT_MIN_BLOCKS:
		w2.tiles[fort_cueva + Vector2i(i, 0)] = w2.T_WALL
	for i in n_checks37:
		main._update_zone_pressure(1)
	print("[37f] con fuerte cerca, npcs tras ZONE_PRESSURE_TIME:", npcs_node.npcs.size())
	_check("con un fuerte propio cerca, la presión ambiental NO se dispara", npcs_node.npcs.is_empty())
	for i in main.FORT_MIN_BLOCKS:
		w2.tiles.erase(fort_cueva + Vector2i(i, 0))
	npcs_node.npcs.clear()

	# 37g: banner dedicado de anuncio de jefe (Bloque 1)
	main._boss_announce_panel.hide()
	main._broadcast_boss_announcement("jefe_topo")
	print("[37g] banner de jefe:", main._boss_announce_label.text, "| visible:", main._boss_announce_panel.visible)
	_check("_broadcast_boss_announcement muestra el banner dedicado con el nombre del jefe",
		main._boss_announce_panel.visible and "Mega Topo" in main._boss_announce_label.text
		and is_equal_approx(main._boss_announce_life, main.BOSS_ANNOUNCE_LIFE))

	# ---- TEST 38: Bloque 2 "Progresión elemental" — lagos contenidos,
	# T_TOWER_MEGA, ralentización de NPCs en agua, recetas de diamante
	# (espada/armadura/torre mega) y jefes adaptativos por zona ----

	# 38a: los lagos del subsuelo profundo son ahora "contenidos"
	# (flood-fill dentro de la banda profunda) y grandes (2-4 lagos de
	# 18-40 tiles), en vez del ruido disperso anterior
	var n_water_total := 0
	var n_water_outside := 0
	for c: Vector2i in w2.tiles:
		if w2.tiles[c] == w2.T_WATER:
			n_water_total += 1
			if c.y < w2.H - 1 - w2.DEEP_ROWS or c.y > w2.H - 2:
				n_water_outside += 1
	print("[38a] agua total:", n_water_total, " | fuera de la banda profunda:", n_water_outside)
	_check("los lagos de T_WATER quedan contenidos en la banda profunda",
		n_water_total > 0 and n_water_outside == 0)
	_check("los lagos son grandes (>= 20 tiles de agua en total)", n_water_total >= 20)

	# 38b: T_TOWER_MEGA (receta de diamante) — sólido, 400 HP, suelta su
	# propio item y tiene textura en el atlas
	_check("T_TOWER_MEGA es sólido, 400 HP y suelta 'torre_mega'",
		w2.SOLID.has(w2.T_TOWER_MEGA) and w2.HP[w2.T_TOWER_MEGA] == 400 and w2.DROPS[w2.T_TOWER_MEGA] == "torre_mega"
		and w2.ITEM_TILE.get("torre_mega", -1) == w2.T_TOWER_MEGA)
	_check("Atlas genera textura de T_TOWER_MEGA",
		Atlas.tiles.has(Atlas.T_TOWER_MEGA) and Atlas.tiles[Atlas.T_TOWER_MEGA].size() == Atlas.VARIANTS)

	# 38c: T_WATER también ralentiza a los NPC terrestres (npc_manager._move),
	# igual que al jugador (37c). Despejar la zona: TEST 28 limpió esta área
	# antes del tiles.clear()+generate() de TEST 36, así que puede haber
	# vuelto a quedar sólida tras la regeneración.
	var water_npc_c := Vector2i(72, 42)
	for tx in range(70, 76):
		for ty in range(40, 44):
			w2.tiles.erase(Vector2i(tx, ty))
	w2.tiles[water_npc_c] = w2.T_WATER
	npcs_node.npcs.clear()
	npcs_node._spawn_one("normal", wall_p)
	var wnid: int = npcs_node.npcs.keys()[0]
	var n38c: Dictionary = npcs_node.npcs[wnid]
	n38c.pos = Vector2(float(water_npc_c.x * w2.TILE + 16), float(water_npc_c.y * w2.TILE + 16))
	n38c.vel = Vector2(npcs_node.KINDS["normal"].speed, 0.0)
	var x_before38c: float = n38c.pos.x
	npcs_node._move(n38c, 0.1, w2)
	var moved38c: float = n38c.pos.x - x_before38c
	var expected38c: float = npcs_node.KINDS["normal"].speed * 0.1 * npcs_node.WATER_SLOW
	print("[38c] NPC sobre T_WATER se movió:", moved38c, " (esperado ~", expected38c, ")")
	_check("T_WATER ralentiza a los NPC terrestres (dx *= WATER_SLOW)",
		is_equal_approx(moved38c, expected38c))
	w2.tiles.erase(water_npc_c)
	npcs_node.npcs.clear()

	# 38d: recetas mega de diamante (espada/armadura) cierran las
	# TIER_CHAINS tras la dorada; torre_mega es un bloque apilable sin cadena
	_check("RECIPES tiene las 3 recetas mega de diamante",
		main.RECIPES.has("espada_diamante") and main.RECIPES.has("armadura_diamante")
		and main.RECIPES.has("torre_mega"))
	_check("espada_diamante/armadura_diamante cierran sus TIER_CHAINS tras la dorada",
		main.TIER_CHAINS["espada"][-1] == "espada_diamante"
		and main.TIER_CHAINS["armadura"][-1] == "armadura_diamante")
	_check("torre_mega NO pertenece a ninguna TIER_CHAINS (bloque apilable)",
		main._tier_chain_of("torre_mega").is_empty())
	_check("WEAPON_DAMAGE/ARMOR_REDUCTION mejoran con la mejora de diamante",
		main.WEAPON_DAMAGE["espada_diamante"] == 90 and main.WEAPON_DAMAGE["espada_diamante"] > main.WEAPON_DAMAGE["espada_dorada"]
		and main.ARMOR_REDUCTION["armadura_diamante"] == 10 and main.ARMOR_REDUCTION["armadura_diamante"] > main.ARMOR_REDUCTION["armadura_dorada"])

	# Gating: sin la dorada correspondiente, la mega de diamante no se craftea
	main.inventories[1] = {"wood": 10, "stone": 10, "diamante": 20, "ascua": 10, "esencia": 10, "pluma": 10}
	main._do_craft("espada_diamante", 1)
	main._do_craft("armadura_diamante", 1)
	print("[38d] inventario sin dorada previa:", main.inventories[1])
	_check("espada_diamante/armadura_diamante exigen la dorada previa (gating de TIER_CHAINS)",
		int(main.inventories[1].get("espada_diamante", 0)) == 0
		and int(main.inventories[1].get("armadura_diamante", 0)) == 0)

	# Con la dorada ya craftada, ambas mega se craftean y consumen sus minerales
	main.inventories[1]["espada_dorada"] = 1
	main.inventories[1]["armadura_dorada"] = 1
	main._do_craft("espada_diamante", 1)
	main._do_craft("armadura_diamante", 1)
	var inv38d: Dictionary = main.inventories[1]
	print("[38d] inventario tras craftear ambas mega de diamante:", inv38d)
	_check("con la dorada previa, espada_diamante/armadura_diamante se craftean y consumen sus minerales",
		int(inv38d.get("espada_diamante", 0)) == 1 and int(inv38d.get("armadura_diamante", 0)) == 1
		and int(inv38d.get("diamante", 0)) == 6 and int(inv38d.get("ascua", 0)) == 6
		and int(inv38d.get("esencia", 0)) == 6 and int(inv38d.get("pluma", 0)) == 6 and int(inv38d.get("stone", 0)) == 0)
	_check("get_attack_damage/get_armor_reduction usan las mega de diamante",
		main.get_attack_damage(1) == 90 and main.get_armor_reduction(1) == 10)
	main.inventories[1] = {}

	# 38e: T_TOWER_MEGA dispara más fuerte que la torre normal (mismo
	# patrón que TEST 20, con MEGA_DAMAGE)
	var mega_tower_c := Vector2i(64, 45)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			w2.tiles.erase(Vector2i(mega_tower_c.x + dx, mega_tower_c.y + dy))
	w2.tiles[mega_tower_c] = w2.T_TOWER_MEGA
	npcs_node.npcs.clear()
	npcs_node._spawn_one("normal", wall_p)
	var mtid: int = npcs_node.npcs.keys()[0]
	var mtorigin := Vector2(mega_tower_c.x * w2.TILE + w2.TILE * 0.5, mega_tower_c.y * w2.TILE + w2.TILE * 0.25)
	npcs_node.npcs[mtid].pos = mtorigin + Vector2(96.0, 0.0)
	npcs_node.npcs[mtid].vel = Vector2.ZERO
	var mtower_hp_before: int = int(npcs_node.npcs[mtid].hp)
	main.tower_mgr.towers.clear()
	main.tower_mgr.arrows.clear()
	main.tower_mgr._scan_t = 0.0
	for i in 20:
		main.tower_mgr._simulate(1.0 / 30.0)
	var mtower_hp_after: int = int(npcs_node.npcs.get(mtid, {}).get("hp", mtower_hp_before))
	print("[38e] torre_mega:", main.tower_mgr.towers.get(mega_tower_c, {}), " | HP del NPC:", mtower_hp_before, "->", mtower_hp_after)
	_check("la torre_mega se escanea con kind = T_TOWER_MEGA",
		int(main.tower_mgr.towers.get(mega_tower_c, {}).get("kind", -1)) == w2.T_TOWER_MEGA)
	_check("la torre_mega dispara más fuerte que la normal (MEGA_DAMAGE > ARROW_DAMAGE)",
		mtower_hp_after == mtower_hp_before - main.tower_mgr.MEGA_DAMAGE
		and main.tower_mgr.MEGA_DAMAGE > main.tower_mgr.ARROW_DAMAGE)
	w2.tiles.erase(mega_tower_c)
	npcs_node.npcs.clear()

	# 38f-h: JEFES ADAPTATIVOS (_update_boss_evolution/evolve_boss) — un
	# jefe que no amenaza bien la zona donde se queda el jugador muta tras
	# BOSS_EVOLVE_TIME; la variante correcta o un cambio de zona resetean
	# el contador (mismo "perdón a la reincidencia" que la presión ambiental)
	var n_checks38 := int(main.BOSS_EVOLVE_TIME / main.PRESSURE_CHECK_EVERY)

	# 38f: jefe_topo junto a un jugador en 'cielo' evoluciona INTELIGENTEMENTE a
	# la variante que SÍ alcanza esa zona (ZONE_BOSS_KIND["cielo"] =
	# jefe_murcielago volador), conservando vida proporcional
	npcs_node.npcs.clear()
	main._boss_evolve.clear()
	npcs_node._insert_npc("jefe_topo", Vector2(500.0, 500.0))
	var bid38f: int = npcs_node.npcs.keys()[0]
	npcs_node.npcs[bid38f].hp = int(npcs_node.KINDS["jefe_topo"].hp / 2)
	wall_p.position = y_cielo
	_check("posición de prueba en 'cielo' junto al jefe_topo",
		main._zone_at(wall_p.position) == "cielo")
	for i in range(n_checks38 - 1):
		main._update_boss_evolution()
	print("[38f] kind tras", n_checks38 - 1, "ciclos en cielo:", npcs_node.npcs[bid38f].kind,
		"| _boss_evolve:", main._boss_evolve.get(bid38f, 0.0))
	_check("antes de BOSS_EVOLVE_TIME, el jefe_topo no muta pero acumula tiempo",
		npcs_node.npcs[bid38f].kind == "jefe_topo" and float(main._boss_evolve.get(bid38f, 0.0)) > 0.0)
	main._boss_announce_panel.hide()
	main._update_boss_evolution()
	print("[38f] kind tras BOSS_EVOLVE_TIME:", npcs_node.npcs[bid38f].kind, "| hp:", npcs_node.npcs[bid38f].hp,
		"| banner:", main._boss_announce_label.text, "| visible:", main._boss_announce_panel.visible)
	_check("en 'cielo' el jefe muta INTELIGENTEMENTE a jefe_murcielago (la variante que lo alcanza) con vida proporcional",
		npcs_node.npcs[bid38f].kind == "jefe_murcielago"
		and npcs_node.npcs[bid38f].hp == int(npcs_node.KINDS["jefe_murcielago"].hp / 2)
		and not main._boss_evolve.has(bid38f))
	_check("la evolución muestra el banner dedicado con el nombre del nuevo jefe",
		main._boss_announce_panel.visible and "Murciélago Gigante" in main._boss_announce_label.text)

	# 38g: si el jefe activo YA es la variante correcta para la zona, no
	# evoluciona ni acumula tiempo
	npcs_node.npcs.clear()
	main._boss_evolve.clear()
	npcs_node._insert_npc("jefe_corredor", Vector2(500.0, 500.0))
	var bid38g: int = npcs_node.npcs.keys()[0]
	wall_p.position = y_superficie
	_check("posición de prueba en 'superficie' junto al jefe_corredor",
		main._zone_at(wall_p.position) == "superficie")
	for i in n_checks38:
		main._update_boss_evolution()
	print("[38g] kind tras", n_checks38, "ciclos en superficie:", npcs_node.npcs[bid38g].kind)
	_check("jefe_corredor en 'superficie' (ya es la variante correcta) no evoluciona ni acumula",
		npcs_node.npcs[bid38g].kind == "jefe_corredor" and not main._boss_evolve.has(bid38g))

	# 38h: si el jugador cambia a una zona donde el kind actual ya es
	# correcto antes de cumplir BOSS_EVOLVE_TIME, el contador se resetea
	npcs_node.npcs.clear()
	main._boss_evolve.clear()
	npcs_node._insert_npc("jefe_topo", Vector2(500.0, 500.0))
	var bid38h: int = npcs_node.npcs.keys()[0]
	wall_p.position = y_cielo
	for i in range(n_checks38 - 1):
		main._update_boss_evolution()
	print("[38h] _boss_evolve tras", n_checks38 - 1, "ciclos en cielo:", main._boss_evolve.get(bid38h, 0.0))
	_check("el jefe_topo acumula tiempo de evolución mientras el jugador está en 'cielo'",
		float(main._boss_evolve.get(bid38h, 0.0)) > 0.0)
	wall_p.position = y_cueva
	main._update_boss_evolution()
	print("[38h] tras cambiar a 'cueva' (kind correcto): _boss_evolve =", main._boss_evolve.get(bid38h, 0.0),
		"| kind:", npcs_node.npcs[bid38h].kind)
	_check("al cambiar a una zona donde el kind actual ya es correcto, el contador se resetea sin evolucionar",
		not main._boss_evolve.has(bid38h) and npcs_node.npcs[bid38h].kind == "jefe_topo")

	npcs_node.npcs.clear()
	main._boss_evolve.clear()

	# ---- TEST 40: BLOQUE 3 "MUNDO VIVO II" — exploración y eventos ----
	# Vías de tren (madera x2), cofres de recursos por bioma, calaveras
	# estilo Halo (efecto aleatorio bueno/malo) y árboles en islas aéreas.

	# 40a: los 3 tiles nuevos con HP/DROPS/SOLID y textura correctos
	_check("T_RAIL no es sólido, da madera x2 (RAIL_WOOD=2) y tiene textura",
		not w2.SOLID.has(w2.T_RAIL) and w2.HP[w2.T_RAIL] == 50 and w2.RAIL_WOOD == 2
		and Atlas.tiles.has(Atlas.T_RAIL))
	_check("T_CHEST y T_SKULL son sólidos, minables y con textura",
		w2.SOLID.has(w2.T_CHEST) and w2.SOLID.has(w2.T_SKULL)
		and w2.HP.has(w2.T_CHEST) and w2.HP.has(w2.T_SKULL)
		and Atlas.tiles.has(Atlas.T_CHEST) and Atlas.tiles.has(Atlas.T_SKULL))

	# 40b: la generación sembró vías, cofres, calaveras y árboles en islas
	var n_rail := 0
	var n_chest := 0
	var n_skull := 0
	var n_sky_wood := 0
	for c: Vector2i in w2.tiles:
		var tt: int = w2.tiles[c]
		if tt == w2.T_RAIL:
			n_rail += 1
		elif tt == w2.T_CHEST:
			n_chest += 1
		elif tt == w2.T_SKULL:
			n_skull += 1
		if tt == w2.T_WOOD and c.y < w2.SKY_ROWS:
			n_sky_wood += 1
	print("[40b] rail:", n_rail, " chest:", n_chest, " skull:", n_skull, " | madera en cielo:", n_sky_wood)
	_check("generate() siembra vías, cofres y calaveras", n_rail > 0 and n_chest > 0 and n_skull > 0)
	_check("hay árboles en las islas aéreas (madera con y < SKY_ROWS)", n_sky_wood > 0)

	# 40c: minar una vía de tren da madera x2 (rama T_RAIL de world._do_hit)
	var rail_c := Vector2i(40, 50)
	w2.tiles[rail_c + Vector2i(0, 1)] = w2.T_STONE   # piso para que parezca vía
	w2.tiles[rail_c] = w2.T_RAIL
	main.players[1].position = Vector2(rail_c.x * w2.TILE + 16, rail_c.y * w2.TILE + 16)
	main.inventories[1] = {"pico_cristal": 1}        # daño alto: rompe la vía rápido
	main._apply_inventory(main.inventories[1])
	for i in 10:
		if w2.tiles.get(rail_c, 0) != w2.T_RAIL:
			break
		w2._do_hit(rail_c, 1)
	print("[40c] madera tras minar la vía:", int(main.inventories[1].get("wood", 0)))
	_check("minar una vía de tren da madera x2 y desaparece",
		int(main.inventories[1].get("wood", 0)) == w2.RAIL_WOOD and w2.tiles.get(rail_c, 0) == 0)

	# 40d: cofre — botín por bioma (open_chest) + Núcleos
	var deep_chest := Vector2i(10, w2.H - 2)
	_check("la posición de un cofre profundo clasifica como 'profundo'",
		main._zone_at(Vector2(deep_chest.x * w2.TILE, deep_chest.y * w2.TILE)) == "profundo")
	main.inventories[1] = {}
	main._apply_inventory(main.inventories[1])
	var coins_before := int(main._profile_of(1).coins)
	main.open_chest(1, deep_chest)
	var invc: Dictionary = main.inventories[1]
	print("[40d] botín del cofre profundo:", invc, " | Núcleos +", int(main._profile_of(1).coins) - coins_before)
	_check("el cofre profundo suelta diamante/ascua/cristal y Núcleos",
		int(invc.get("diamante", 0)) >= 1 and int(invc.get("ascua", 0)) >= 1 and int(invc.get("cristal", 0)) >= 1
		and int(main._profile_of(1).coins) >= coins_before + main.CHEST_COINS[0])

	# 40e: calaveras estilo Halo — 5 variantes (3 buenas / 2 malas) y
	# excavate_skull dispara efectos a favor del jugador Y de los enemigos
	var buenas := 0
	for s: Dictionary in main.SKULLS:
		if bool(s.buena):
			buenas += 1
	_check("hay 5 calaveras: 3 buenas y 2 malas", main.SKULLS.size() == 5 and buenas == 3)

	main.players[1].position = Vector2(2000.0, 1500.0)
	main.player_hp[1] = 40
	main.inventories[1] = {}
	main._apply_inventory(main.inventories[1])
	npcs_node.npcs.clear()
	var coins0 := int(main._profile_of(1).coins)
	for i in 20:
		main.excavate_skull(1, Vector2i(60, 60))
	var good_fired: bool = int(main.player_hp[1]) != 40 or int(main._profile_of(1).coins) > coins0 or not main.inventories[1].is_empty()
	var bad_fired: bool = npcs_node.npcs.size() > 0
	print("[40e] tras 20 excavaciones -> hp:", main.player_hp[1], " coins+:", int(main._profile_of(1).coins) - coins0,
		" loot:", main.inventories[1].size(), " npcs:", npcs_node.npcs.size())
	_check("excavar calaveras dispara efectos buenos (cura/monedas/botín) y malos (enemigos)",
		good_fired and bad_fired)
	npcs_node.npcs.clear()
	main.inventories[1] = {}
	main._apply_inventory(main.inventories[1])

	# ---- TEST 39: AJUSTES — modo de control móvil/PC ----
	# Selector local (no viaja por red): "auto"/"movil"/"pc" controla si el
	# joystick virtual está activo. En "auto" sigue al dispositivo detectado.
	_check("CONTROL_MODES son auto/movil/pc",
		main.CONTROL_MODES == ["auto", "movil", "pc"])
	_check("_detect_platform devuelve un modo válido (movil/pc)",
		main._detect_platform() in ["movil", "pc"])
	_check("el HUD construyó el joystick y el panel de ajustes con 3 opciones",
		main._joystick != null and main._settings_panel != null and main._control_buttons.size() == 3)

	# Modo explícito PC: el joystick se desactiva (el clic del ratón mina en
	# cualquier zona, incl. la esquina del joystick).
	main.set_control_mode("pc")
	print("[39] modo pc -> joystick.enabled:", main._joystick.enabled, " | efectivo:", main.effective_control_mode())
	_check("modo 'pc' desactiva el joystick virtual",
		main.control_mode == "pc" and main.effective_control_mode() == "pc" and not main._joystick.enabled)

	# Modo explícito móvil: el joystick se reactiva.
	main.set_control_mode("movil")
	print("[39] modo movil -> joystick.enabled:", main._joystick.enabled, " | efectivo:", main.effective_control_mode())
	_check("modo 'movil' activa el joystick virtual",
		main.control_mode == "movil" and main.effective_control_mode() == "movil" and main._joystick.enabled)

	# "auto" delega en la detección del dispositivo.
	main.set_control_mode("auto")
	_check("modo 'auto' usa el dispositivo detectado",
		main.control_mode == "auto" and main.effective_control_mode() == main._detect_platform())

	# El botón ⚙️ abre/cierra el panel y, abierto, cuenta como UI (no mina).
	main._settings_panel.hide()
	main._on_settings_pressed()
	_check("el botón de Ajustes muestra el panel", main._settings_panel.visible)
	_check("el botón activo refleja el modo guardado",
		(main._control_buttons["auto"] as Button).button_pressed)
	main._on_settings_pressed()
	_check("el botón de Ajustes oculta el panel", not main._settings_panel.visible)

	# ---- TEST 41: BLOQUE 4 "BESTIARIO VIVO" — 3 enemigos con comportamiento ----
	# espectro (atraviesa muros), coracero (blindado) y sanador (cura a la horda),
	# cada uno con un material de bioma como botín.
	_check("KINDS define espectro (ghost+fly), coracero (armor) y sanador (heals) con drop",
		npcs_node.KINDS.has("espectro") and bool(npcs_node.KINDS["espectro"].get("ghost", false))
		and bool(npcs_node.KINDS["espectro"].get("fly", false)) and npcs_node.KINDS["espectro"].drop == "esencia"
		and int(npcs_node.KINDS["coracero"].get("armor", 0)) > 0 and npcs_node.KINDS["coracero"].drop == "ascua"
		and bool(npcs_node.KINDS["sanador"].get("heals", false)) and npcs_node.KINDS["sanador"].drop == "pluma")
	_check("Atlas tiene sprite de los 3 enemigos nuevos",
		Atlas.slimes.has("espectro") and Atlas.slimes.has("coracero") and Atlas.slimes.has("sanador"))

	# 41b: el espectro (ghost) atraviesa los muros — _move ignora la colisión
	npcs_node.npcs.clear()
	var b4_gx := 50
	var b4_gy := 50
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			w2.tiles[Vector2i(b4_gx + dx, b4_gy + dy)] = w2.T_STONE
	npcs_node._insert_npc("espectro", Vector2(b4_gx * w2.TILE + 16.0, b4_gy * w2.TILE + 16.0))
	var b4_gid: int = npcs_node.npcs.keys()[0]
	npcs_node.npcs[b4_gid].vel = Vector2(200.0, 0.0)
	var b4_gx0: float = npcs_node.npcs[b4_gid].pos.x
	npcs_node._move(npcs_node.npcs[b4_gid], 0.1, w2)
	var b4_gmoved: float = npcs_node.npcs[b4_gid].pos.x - b4_gx0
	print("[41b] el espectro se movió a través de la roca:", b4_gmoved, " (esperado 20.0)")
	_check("el espectro (ghost) atraviesa los muros en _move", is_equal_approx(b4_gmoved, 20.0))
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			w2.tiles.erase(Vector2i(b4_gx + dx, b4_gy + dy))
	npcs_node.npcs.clear()

	# 41c: el coracero (armor) amortigua el daño recibido (mín. 1)
	npcs_node._insert_npc("coracero", Vector2(2000.0, 1500.0))
	var b4_cid: int = npcs_node.npcs.keys()[0]
	var b4_chp0: int = int(npcs_node.npcs[b4_cid].hp)
	npcs_node.damage_npc(b4_cid, 30)
	var b4_cdealt: int = b4_chp0 - int(npcs_node.npcs.get(b4_cid, {}).get("hp", b4_chp0))
	print("[41c] daño aplicado al coracero:", b4_cdealt, " (30 -", int(npcs_node.KINDS["coracero"].armor), "de armadura)")
	_check("el coracero (armor) amortigua el daño recibido",
		b4_cdealt == 30 - int(npcs_node.KINDS["coracero"].armor))
	npcs_node.npcs.clear()

	# 41d: el sanador cura a los enemigos heridos cercanos (pulso en _simulate)
	npcs_node._insert_npc("sanador", Vector2(2000.0, 1500.0))
	npcs_node._insert_npc("normal", Vector2(2030.0, 1500.0))
	var b4_hid: int = npcs_node.npcs.keys()[1]
	npcs_node.npcs[b4_hid].hp = 10
	npcs_node._simulate(0.1)
	var b4_healed: int = int(npcs_node.npcs.get(b4_hid, {}).get("hp", 10))
	print("[41d] vida del aliado herido tras el pulso del sanador:", b4_healed)
	_check("el sanador cura a los enemigos heridos cercanos", b4_healed > 10)
	npcs_node.npcs.clear()

	# 41e: matar un enemigo de bioma suelta su material propio
	main.players[1].position = Vector2(2000.0, 1500.0)
	main.inventories[1] = {}
	main._apply_inventory(main.inventories[1])
	npcs_node._insert_npc("coracero", Vector2(2010.0, 1500.0))
	var b4_did: int = npcs_node.npcs.keys()[0]
	npcs_node.damage_npc(b4_did, 99999)
	print("[41e] inventario tras matar al coracero:", main.inventories[1])
	_check("matar un enemigo de bioma suelta su material (coracero→ascua)",
		int(main.inventories[1].get("ascua", 0)) >= 1)
	npcs_node.npcs.clear()
	main.inventories[1] = {}
	main._apply_inventory(main.inventories[1])

	# ---- TEST 42: el JEFE excava en TODA dirección hacia el jugador ----
	# (_boss_tunnel) — derriba la roca/muralla a su derecha Y abajo cuando el
	# jugador está abajo-derecha, tardando los golpes que el HP del muro exija.
	npcs_node.npcs.clear()
	var b4_jc := Vector2i(100, 50)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			w2.tiles.erase(Vector2i(b4_jc.x + dx, b4_jc.y + dy))
			w2.damage.erase(Vector2i(b4_jc.x + dx, b4_jc.y + dy))
	var b4_bx := b4_jc + Vector2i(1, 0)   # muralla a la derecha
	var b4_by := b4_jc + Vector2i(0, 1)   # muralla abajo
	w2.tiles[b4_bx] = w2.T_WALL
	w2.tiles[b4_by] = w2.T_WALL
	npcs_node._insert_npc("jefe", Vector2(b4_jc.x * w2.TILE + 16.0, b4_jc.y * w2.TILE + 16.0))
	var b4_jid: int = npcs_node.npcs.keys()[0]
	main.players[1].position = Vector2((b4_jc.x + 5) * w2.TILE, (b4_jc.y + 5) * w2.TILE)
	var b4_pulsos := 0
	for i in 30:
		npcs_node._boss_tunnel(npcs_node.npcs[b4_jid], npcs_node.KINDS["jefe"], main.players[1], w2, 1.0)
		if w2.tiles.get(b4_bx, 0) == 0 and w2.tiles.get(b4_by, 0) == 0:
			b4_pulsos = i + 1
			break
	print("[42] muros derribados en", b4_pulsos, "pulsos (jefe block_dmg=", int(npcs_node.KINDS["jefe"].block_dmg),
		", muro=", w2.HP[w2.T_WALL], "HP) | derecha:", w2.tiles.get(b4_bx, 0), " abajo:", w2.tiles.get(b4_by, 0))
	_check("el jefe rompe el obstáculo HORIZONTAL hacia el jugador", w2.tiles.get(b4_bx, 0) != w2.T_WALL)
	_check("el jefe rompe el obstáculo VERTICAL hacia el jugador", w2.tiles.get(b4_by, 0) != w2.T_WALL)
	_check("derribar la muralla cuesta varios golpes (HP/block_dmg, no instantáneo)", b4_pulsos > 1)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			w2.tiles.erase(Vector2i(b4_jc.x + dx, b4_jc.y + dy))
			w2.damage.erase(Vector2i(b4_jc.x + dx, b4_jc.y + dy))
	npcs_node.npcs.clear()

	# ---- TEST 43: BLOQUE 5 "IDENTIDAD VISUAL Y SONORA" — pulido AV ----
	# Sonidos del contenido nuevo (cofre/calavera/sanación) + FX de evento.
	_check("Sfx tiene los sonidos nuevos (cofre/cura/maldicion)",
		Sfx._streams.has("cofre") and Sfx._streams.has("cura") and Sfx._streams.has("maldicion"))

	# Los toasts de cofre y de cada calavera disparan sonido por su prefijo de
	# emoji (no debe romper aunque en headless no suene). Verificamos que el
	# toast se muestra con su texto.
	main._show_toast("📦 Cofre: 3 Diamante")
	_check("toast de cofre (📦) se muestra y enruta sonido", main._status.text.begins_with("📦"))
	for aviso: Dictionary in main.SKULLS:
		main._show_toast(str(aviso.aviso))
		_check("toast de calavera '%s' se muestra" % str(aviso.nombre),
			main._status.text == str(aviso.aviso))

	# El FX de evento (estallido dorado/verde/rojo) se difunde sin romper y, en
	# el host, dibuja en world.fx localmente (cosmético, no toca estado).
	var b5_before: int = main.world.fx.get_child_count() if main.world.fx != null else -1
	main._broadcast_event_fx(main._cell_center(Vector2i(60, 40)), Color("f0c84a"), true)
	print("[43] event_fx OK | partículas fx tras el estallido:", main.world.fx.get_child_count() if main.world.fx != null else -1)
	_check("_broadcast_event_fx corre sin romper y añade partículas al fx",
		main.world.fx != null and main.world.fx.get_child_count() >= b5_before)

	# ---- TEST 44: REDISEÑO VISUAL — jefes con identidad + skins de atuendo ----
	# Cada jefe tiene su propia silueta (no el demonio recoloreado) y las skins
	# son un atuendo completo (camisa/pantalón/pelo/borde) + accesorio.
	var rv_demon := Vector2i(Atlas.slimes["jefe"].get_width(), Atlas.slimes["jefe"].get_height())
	var rv_bat := Vector2i(Atlas.slimes["jefe_murcielago"].get_width(), Atlas.slimes["jefe_murcielago"].get_height())
	var rv_mole := Vector2i(Atlas.slimes["jefe_topo"].get_width(), Atlas.slimes["jefe_topo"].get_height())
	var rv_run := Vector2i(Atlas.slimes["jefe_corredor"].get_width(), Atlas.slimes["jefe_corredor"].get_height())
	print("[44] siluetas de jefe -> demonio:", rv_demon, " murcielago:", rv_bat, " topo:", rv_mole, " corredor:", rv_run)
	_check("cada jefe tiene su propia silueta (distinta del demonio recoloreado)",
		rv_bat != rv_demon and rv_mole != rv_demon and rv_run != rv_demon)
	_check("las 3 siluetas de jefe nuevas son distintas entre sí",
		rv_bat != rv_mole and rv_bat != rv_run and rv_mole != rv_run)
	_check("el demonio (jefe) conserva su sprite 24x18", rv_demon == Vector2i(24, 18))

	var rv_fr: Dictionary = Atlas.player_frames.idle[0]
	_check("el frame del jugador tiene las capas tintables nuevas (skin/hair/shirt/pants/boot/outline)",
		rv_fr.has("skin") and rv_fr.has("hair") and rv_fr.has("shirt")
		and rv_fr.has("pants") and rv_fr.has("boot") and rv_fr.has("outline"))
	_check("Atlas tiene los accesorios de skin (corona/cuernos/capucha/... >= 8)",
		Atlas.player_acc.has("corona") and Atlas.player_acc.has("cuernos")
		and Atlas.player_acc.has("capucha") and Atlas.player_acc.size() >= 8)

	var rv_ok := true
	var rv_con_acc := 0
	for rv_sid: String in main.SKINS:
		var sk: Dictionary = main.SKINS[rv_sid]
		if not (sk.has("camisa") and sk.has("pantalon") and sk.has("pelo")
				and sk.has("borde") and sk.has("accesorio") and sk.has("accent")):
			rv_ok = false
		var acc := str(sk.accesorio)
		if acc != "":
			rv_con_acc += 1
			if not Atlas.player_acc.has(acc):
				rv_ok = false
	print("[44] skins con accesorio:", rv_con_acc, "/", main.SKINS.size())
	_check("todas las skins tienen atuendo completo (camisa/pantalón/pelo/borde) + accesorio válido", rv_ok)
	_check("casi todas las skins tienen un accesorio de identidad (>= 10)", rv_con_acc >= 10)

	# ---- TEST 45: LOCOMOCIÓN VARIADA — no todos saltan (rediseño) ----
	# Los SLIMES saltan; topo/taladro/coracero/sanador y los jefes terrestres
	# CAMINAN (avanzan en horizontal sin rebote, con auto-step en escalones).
	_check("los slimes NO tienen 'walks' (siguen saltando)",
		not bool(npcs_node.KINDS["normal"].get("walks", false))
		and not bool(npcs_node.KINDS["grande"].get("walks", false)))
	_check("topo/taladro/coracero/sanador y jefe/jefe_topo CAMINAN ('walks')",
		bool(npcs_node.KINDS["topo"].get("walks", false))
		and bool(npcs_node.KINDS["taladro"].get("walks", false))
		and bool(npcs_node.KINDS["coracero"].get("walks", false))
		and bool(npcs_node.KINDS["sanador"].get("walks", false))
		and bool(npcs_node.KINDS["jefe"].get("walks", false))
		and bool(npcs_node.KINDS["jefe_topo"].get("walks", false)))

	npcs_node.npcs.clear()
	var wk := Vector2i(60, 50)
	for dx in range(-3, 6):
		for dy in range(-3, 3):
			w2.tiles.erase(Vector2i(wk.x + dx, wk.y + dy))
	npcs_node._insert_npc("coracero", Vector2(wk.x * w2.TILE + 16.0, wk.y * w2.TILE + 16.0))
	var wid: int = npcs_node.npcs.keys()[0]
	var wn: Dictionary = npcs_node.npcs[wid]
	main.players[1].position = Vector2((wk.x + 6) * w2.TILE, wk.y * w2.TILE + 16.0)   # a la derecha, misma altura
	wn.vel = Vector2.ZERO
	wn.jump_t = 0.0
	var wbest: float = main.players[1].position.distance_to(wn.pos)
	npcs_node._walk_step(wn, main.players[1], wbest, float(npcs_node.KINDS["coracero"].speed), w2)
	print("[45] coracero en suelo plano tras _walk_step -> vel:", wn.vel)
	_check("un enemigo 'walks' avanza HACIA el jugador sin saltar en suelo plano",
		wn.vel.x > 0.0 and is_equal_approx(wn.vel.y, 0.0))

	# Con un escalón sólido delante, _step_blocked lo detecta (auto-step corto)
	var wfoot := floori((wn.pos.y + npcs_node.SIZE.y * 0.5 - 3.0) / w2.TILE)
	w2.tiles[Vector2i(wk.x + 1, wfoot)] = w2.T_STONE
	wn.vel = Vector2(float(npcs_node.KINDS["coracero"].speed), 0.0)
	_check("el auto-step detecta un escalón sólido en la columna vecina", npcs_node._step_blocked(wn, w2))
	w2.tiles.erase(Vector2i(wk.x + 1, wfoot))
	npcs_node.npcs.clear()

	# ---- TEST 46: bestiario con sprite propio + spawn del espectro + HUD plegable ----
	# 46a: el espectro (y coracero/sanador) SÍ entran en las oleadas nocturnas
	var rk := {"espectro": 0, "coracero": 0, "sanador": 0}
	for i in 600:
		var rkk: String = npcs_node._roll_kind_night(4)
		if rk.has(rkk):
			rk[rkk] += 1
	print("[46] tiradas de oleada (noche 4) -> espectro:", rk.espectro, " coracero:", rk.coracero, " sanador:", rk.sanador)
	_check("el espectro SÍ se spawnea en las oleadas (_roll_kind_night, noche >= 2)", rk.espectro > 0)
	_check("coracero y sanador también aparecen en las oleadas", rk.coracero > 0 and rk.sanador > 0)

	# 46b: tienen sprite PROPIO (no el molde de slime 16x12)
	var slime_dim := Vector2i(Atlas.slimes["normal"].get_width(), Atlas.slimes["normal"].get_height())
	_check("espectro/coracero/sanador tienen sprite PROPIO (no el molde slime reteñido)",
		Vector2i(Atlas.slimes["espectro"].get_width(), Atlas.slimes["espectro"].get_height()) != slime_dim
		and Vector2i(Atlas.slimes["coracero"].get_width(), Atlas.slimes["coracero"].get_height()) != slime_dim
		and Vector2i(Atlas.slimes["sanador"].get_width(), Atlas.slimes["sanador"].get_height()) != slime_dim)

	# 46c: barra de items PLEGABLE — al plegar, los slots se ocultan (la franja
	# inferior deja de bloquear taps porque is_point_on_ui mira _slots_box)
	_check("el HUD tiene barra de items plegable (_slots_box + _items_toggle)",
		main._slots_box != null and main._items_toggle != null)
	main._slots_box.visible = true
	main._refresh_items_toggle()
	_check("desplegado: los slots se ven y el botón ofrece plegar (◀)",
		main._slots_box.visible and main._items_toggle.text == "◀")
	main._toggle_items()
	print("[46] tras plegar -> slots visibles:", main._slots_box.visible, " | botón:", main._items_toggle.text)
	_check("plegado: los slots se ocultan (dejan de bloquear taps) y el botón ofrece abrir",
		not main._slots_box.visible and "▶" in main._items_toggle.text)
	main._toggle_items()
	_check("se vuelve a desplegar al pulsar de nuevo", main._slots_box.visible)

	# ---- TEST 47: contador de minerales en el HUD + carácter de los slimes ----
	main.inventories[1] = {"diamante": 5, "cristal": 3, "ascua": 2, "pluma": 1, "esencia": 4, "ore": 9}
	main._apply_inventory(main.inventories[1])
	print("[47] info del HUD:", main._info.text.replace("\n", " | "))
	_check("el HUD muestra el contador de minerales (diamante, cristal, ascua, mineral...)",
		"💎 5" in main._info.text and "🔷 3" in main._info.text
		and "🔥 2" in main._info.text and "⛏️ 9" in main._info.text)
	_check("MINERAL_ICONS cubre los 6 minerales preciosos (incl. diamante)",
		main.MINERAL_ICONS.size() == 6 and main.MINERAL_ICONS.has("diamante"))
	main.inventories[1] = {}
	main._apply_inventory(main.inventories[1])

	# Carácter de los slimes: el dorado tiene corona propia que el normal no
	var dorado_img: Image = Atlas.slimes["dorado"].get_image()
	var normal_img: Image = Atlas.slimes["normal"].get_image()
	_check("los slimes tienen carácter por variante (el dorado luce corona, el normal no)",
		dorado_img.get_pixel(7, 0).a > 0.5 and normal_img.get_pixel(7, 0).a < 0.1)

	print("")
	if _fail == 0:
		print("=== TODO OK: la lógica de crafteo (_do_craft) funciona correctamente ===")
	else:
		print("=== %d CHEQUEO(S) FALLARON ===" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  OK  - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)
