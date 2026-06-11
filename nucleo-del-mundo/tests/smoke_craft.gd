# =============================================================
# smoke_craft.gd — prueba headless del panel 🛠️ Fabricar (RECIPES)
# Ejecutar:
#   godot --headless --path . res://tests/smoke_craft.tscn --quit-after 5
# =============================================================
extends Node2D

const MainScript := preload("res://scripts/main.gd")

var _fail := 0


func _ready() -> void:
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

	# ---- TEST 1: craftear pico_madera con materiales exactos ----
	main.inventories[1] = {"wood": 8}
	main._apply_inventory(main.inventories[1])
	print("[1] panel craft (madera lista):", main._craft_rows["pico_madera"].label.text)
	_check("panel craft muestra madera 8/8 antes de craftear", "madera 8/8" in main._craft_rows["pico_madera"].label.text)
	_check("panel craft habilita 'Crear' con materiales completos", not main._craft_rows["pico_madera"].button.disabled)

	main._do_craft("pico_madera", 1)
	var inv1: Dictionary = main.inventories[1]
	print("[1] inventario tras craft pico_madera:", inv1, " status:", main._status.text)
	_check("pico_madera consume 8 madera", int(inv1.get("wood", -1)) == 0)
	_check("pico_madera queda en inventario", int(inv1.get("pico_madera", 0)) == 1)
	_check("get_tool_damage = 35 (madera)", main.get_tool_damage(1) == 35)
	print("[1] panel craft tras craftear:", main._craft_rows["pico_madera"].label.text)
	_check("panel craft marca pico_madera con ✓ tras craftear", "✓" in main._craft_rows["pico_madera"].label.text)
	_check("panel craft deshabilita 'Crear' sin madera restante", main._craft_rows["pico_madera"].button.disabled)

	# ---- TEST 2: craftear pico_piedra SIN materiales ----
	main.inventories[1] = {"wood": 0, "stone": 0}
	main._apply_inventory(main.inventories[1])
	print("[2] panel craft (sin materiales):", main._craft_rows["pico_piedra"].label.text)
	_check("panel craft muestra madera 0/4 y piedra 0/12", "madera 0/4" in main._craft_rows["pico_piedra"].label.text and "piedra 0/12" in main._craft_rows["pico_piedra"].label.text)
	_check("panel craft deshabilita 'Crear' sin materiales", main._craft_rows["pico_piedra"].button.disabled)

	main._do_craft("pico_piedra", 1)
	var inv2: Dictionary = main.inventories[1]
	print("[2] inventario tras craft sin materiales:", inv2, " status:", main._status.text)
	_check("sin materiales no agrega pico_piedra", not inv2.has("pico_piedra"))
	_check("toast de error muestra 'faltan materiales'", "faltan materiales" in main._status.text)

	# ---- TEST 3: craftear pico_dorado con materiales exactos ----
	main.inventories[1] = {"wood": 4, "ore": 8}
	main._apply_inventory(main.inventories[1])
	_check("panel craft habilita pico_dorado con materiales completos", not main._craft_rows["pico_dorado"].button.disabled)

	main._do_craft("pico_dorado", 1)
	var inv3: Dictionary = main.inventories[1]
	print("[3] inventario tras craft pico_dorado:", inv3, " status:", main._status.text)
	_check("pico_dorado consume wood y ore", int(inv3.get("wood", -1)) == 0 and int(inv3.get("ore", -1)) == 0)
	_check("get_tool_damage = 100 (dorado, mejor herramienta)", main.get_tool_damage(1) == 100)
	print("[3] panel craft tras craftear:", main._craft_rows["pico_dorado"].label.text)
	_check("panel craft marca pico_dorado con ✓ tras craftear", "✓" in main._craft_rows["pico_dorado"].label.text)
	_check("panel craft deshabilita pico_dorado sin materiales restantes", main._craft_rows["pico_dorado"].button.disabled)

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
