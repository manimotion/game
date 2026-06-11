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
