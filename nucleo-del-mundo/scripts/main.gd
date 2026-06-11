# =============================================================
# main.gd — Orquestador — FASES 3-4 + FASE 5 (monetización)
# Novedades Fase 5:
#  - NÚCLEOS: moneda del juego, server-authoritative. La sueltan
#    los slimes y el mineral. Base de la monetización (ver
#    MONETIZACION.md): los paquetes de Núcleos serán el producto
#    de compra real (Google Play Billing) cuando exista backend.
#  - TIENDA DE SKINS: catálogo cosmético; comprar y equipar lo
#    valida el SERVIDOR (§16). Las skins son visibles para todos.
#  - PERFILES POR NOMBRE: monedas y skins persisten en el save
#    keyed por nombre de jugador (cuentas reales = backend Fase 5;
#    limitación conocida: en LAN cualquiera puede usar tu nombre).
# Fases 3-4:
#  - SERVIDOR DEDICADO: `godot --headless --path . -- --server`
#    corre este mismo proyecto como servidor puro (GDD §1.2).
#  - Crafting de picos validado por el servidor (GDD §8).
#  - Vida + respawn (los slimes hacen daño por contacto).
#  - Persistencia: guardado JSON comprimido con gzip (GDD §14),
#    autosave cada 60 s y al cerrar la ventana del host.
#  - Scheduler del servidor (GDD §9): dispara el evento meteoro.
# =============================================================
extends Node2D

const PlayerScript := preload("res://scripts/player.gd")
const WorldScript := preload("res://scripts/world.gd")
const JoystickScript := preload("res://scripts/virtual_joystick.gd")
const NpcScript := preload("res://scripts/npc_manager.gd")

const SAVE_PATH := "user://nucleo_save.json.gz"

const ITEM_NAMES := {"dirt": "Tierra", "stone": "Piedra", "wood": "Madera", "ore": "Mineral",
	"muralla": "Muralla", "fogata": "Fogata"}

# GDD §8.1 — recetas: picos (minan), espadas (combate) y armaduras
# (reducen daño). Los diccionarios *_DAMAGE/_REDUCTION van del mejor
# al peor: el servidor usa el primero que el jugador tenga.
const RECIPES := {
	"pico_madera": {"nombre": "Pico de madera", "costo": {"wood": 8}},
	"pico_piedra": {"nombre": "Pico de piedra", "costo": {"wood": 4, "stone": 12}},
	"pico_dorado": {"nombre": "Pico dorado", "costo": {"wood": 4, "ore": 8}},
	"espada_madera": {"nombre": "Espada de madera", "costo": {"wood": 10}},
	"espada_piedra": {"nombre": "Espada de piedra", "costo": {"wood": 4, "stone": 16}},
	"espada_dorada": {"nombre": "Espada dorada", "costo": {"wood": 4, "ore": 10}},
	"armadura_madera": {"nombre": "Armadura de madera", "costo": {"wood": 20}},
	"armadura_piedra": {"nombre": "Armadura de piedra", "costo": {"stone": 30}},
	"armadura_dorada": {"nombre": "Armadura dorada", "costo": {"stone": 10, "ore": 15}},
	"muralla": {"nombre": "Muralla", "costo": {"stone": 6}},
	"fogata": {"nombre": "Fogata", "costo": {"wood": 8, "stone": 4}},
}
const TOOL_DAMAGE := {"pico_dorado": 100, "pico_piedra": 60, "pico_madera": 35}
const WEAPON_DAMAGE := {"espada_dorada": 60, "espada_piedra": 38, "espada_madera": 24}
const ARMOR_REDUCTION := {"armadura_dorada": 6, "armadura_piedra": 4, "armadura_madera": 2}
const HAND_DAMAGE := 20
const PLAYER_MAX_HP := 100
const REGEN_EVERY := 4.0     # segundos entre ticks de regeneración de vida
const REGEN_AMOUNT := 3      # vida recuperada por tick (solo servidor)
const METEOR_WARN := 3.0     # segundos de aviso antes del impacto del meteoro
const TOAST_LIFE := 4.5      # segundos visibles del toast antes de desvanecerse
const FOGATA_RANGE := 256.0  # radio del aura de la fogata (8 tiles) — Fase 7

# Fase 6 — ciclo día/noche JUGABLE (ROADMAP.md): el servidor es el reloj
const DAY_SECONDS := 180.0   # duración del día
const NIGHT_SECONDS := 90.0  # duración de la noche
const DUSK_WARN := 30.0      # aviso de atardecer
const SURVIVAL_NIGHTS := 7   # objetivo del modo supervivencia

# MONETIZACIÓN — catálogo de skins (solo cosmético, nunca pay-to-win).
# El SERVIDOR valida compra/equipamiento (§16); el cliente solo pide.
# "default" usa el color por jugador de siempre. "anim" = color animado.
const SKINS := {
	"default": {"nombre": "Clásica", "precio": 0,
		"cuerpo": Color.WHITE, "borde": Color.BLACK, "anim": false},
	"esmeralda": {"nombre": "Esmeralda", "precio": 25,
		"cuerpo": Color(0.13, 0.68, 0.35), "borde": Color(0.04, 0.28, 0.13), "anim": false},
	"rubi": {"nombre": "Rubí", "precio": 25,
		"cuerpo": Color(0.85, 0.18, 0.24), "borde": Color(0.35, 0.04, 0.07), "anim": false},
	"zafiro": {"nombre": "Zafiro", "precio": 25,
		"cuerpo": Color(0.20, 0.40, 0.90), "borde": Color(0.06, 0.12, 0.38), "anim": false},
	"dorado": {"nombre": "Dorado", "precio": 60,
		"cuerpo": Color(0.95, 0.78, 0.20), "borde": Color(0.55, 0.42, 0.05), "anim": false},
	"sombra": {"nombre": "Sombra", "precio": 80,
		"cuerpo": Color(0.13, 0.11, 0.18), "borde": Color(0.55, 0.25, 0.85), "anim": false},
	"neon": {"nombre": "Neón", "precio": 80,
		"cuerpo": Color(0.05, 0.93, 0.85), "borde": Color.WHITE, "anim": false},
	"arcoiris": {"nombre": "Arcoíris", "precio": 150,
		"cuerpo": Color.WHITE, "borde": Color.WHITE, "anim": true},
}
# Núcleos por matar slimes: ver npc_manager.KINDS (varía por variante)
const COIN_ORE := 2          # Núcleos por minar un tile de mineral

var world: Node2D = null
var players: Dictionary = {}        # peer_id -> Player (todos los peers)
var inventories: Dictionary = {}    # peer_id -> {item: qty}   (SOLO servidor)
var player_hp: Dictionary = {}      # peer_id -> hp            (SOLO servidor)
var selected_item := "dirt"
var dedicated := false

# MONETIZACIÓN — perfiles por nombre (SOLO servidor, salvo _my_*)
var profiles: Dictionary = {}       # nombre -> {coins, skins: [], skin}
var peer_names: Dictionary = {}     # peer_id -> nombre        (SOLO servidor)
var my_name := "Jugador"

var _my_inv: Dictionary = {}
var _inv_init := false              # evita textos flotantes en la primera sincronización
var _my_hp := PLAYER_MAX_HP
var _my_coins := 0
var _my_skins: Array = ["default"]
var _my_skin := "default"
var _profile_init := false          # evita sonidos en la primera sincronización
var _stream_t := 0.0
var _save_t := 0.0
var _meteor_t := 90.0
var _meteor_x := -1                 # x anunciada del meteoro (-1 = ninguno pendiente)
var _meteor_warn_t := 0.0
var _regen_t := 0.0
var _toast_life := 0.0

# Ciclo día/noche (Fase 6) — el SERVIDOR lleva el reloj; los clientes
# reciben cada cambio de fase y solo cuentan hacia atrás para el HUD.
var game_mode := "sandbox"          # "sandbox" | "survival" (lo fija el host)
var is_night := false
var night_number := 0               # noches iniciadas (0 = aún no anochece)
var _phase_t := DAY_SECONDS         # tiempo restante de la fase actual
var _dusk_warned := false

var _ui: CanvasLayer
var _menu: PanelContainer
var _status: Label
var _toast_panel: PanelContainer = null
var _hp_panel: Control = null
var _low_hp: Panel = null           # borde rojo pulsante con vida baja
var _phase_label: Label = null      # "☀️ Día 1 — 2:45" / "🌙 Noche 3 — 0:58"
var _ip_input: LineEdit
var _name_input: LineEdit
var _slot_buttons: Dictionary = {}
var _info: Label
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _tool_label: Label = null
var _armor_label: Label = null
var _hud_box: Control = null
var _craft_btn: Control = null
var _craft_panel: Control = null
var _craft_rows: Dictionary = {}    # recipe_id -> {label, button}
var _shop_btn: Control = null
var _shop_panel: Control = null
var _shop_title: Label = null
var _shop_rows: Dictionary = {}     # skin_id -> Button


func _ready() -> void:
	_build_ui()
	Net.player_connected.connect(_on_player_connected)
	Net.player_disconnected.connect(_on_player_disconnected)
	Net.connection_succeeded.connect(_on_connected_to_host)
	Net.connection_failed.connect(func(): _show_toast("❌ No se pudo conectar al host"))
	Net.server_disconnected.connect(_on_host_lost)

	# ---- MODO SERVIDOR DEDICADO (GDD §1.2) ----
	if "--server" in OS.get_cmdline_user_args():
		dedicated = true
		if Net.host_game() != OK:
			print("[SERVIDOR] No se pudo abrir el puerto %d" % Net.PORT)
			get_tree().quit(1)
			return
		_start_game()
		if load_game():
			print("[SERVIDOR] Partida guardada cargada")
		else:
			world.generate()
			print("[SERVIDOR] Mundo nuevo generado")
		print("[SERVIDOR] Escuchando en puerto %d (IP local: %s)" % [Net.PORT, Net.local_ip()])


# -------------------------------------------------------------
# SCHEDULER (GDD §9): streaming, autosave y eventos del mundo
# -------------------------------------------------------------
func _process(delta: float) -> void:
	# Desvanecido del toast (solo visual, corre también en el lobby)
	if _toast_life > 0.0 and not _menu.visible:
		_toast_life -= delta
		if _toast_life <= 0.0:
			_toast_panel.hide()
		elif _toast_life < 0.8:
			_toast_panel.modulate.a = _toast_life / 0.8

	if world == null:
		return

	# Borde rojo pulsante con vida baja (solo visual)
	if _low_hp != null:
		if _my_hp < 30:
			_low_hp.visible = true
			_low_hp.modulate.a = 0.45 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
		else:
			_low_hp.visible = false

	_stream_t += delta
	if _stream_t >= 0.4:
		_stream_t = 0.0
		var me: Node2D = players.get(multiplayer.get_unique_id())
		if me != null:
			world.update_streaming(me.position)

	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_save_t += delta
		if _save_t >= 60.0:
			_save_t = 0.0
			save_game()

		# Regeneración de vida lenta (solo servidor)
		_regen_t += delta
		if _regen_t >= REGEN_EVERY:
			_regen_t = 0.0
			_regen_tick()

		# Reloj de partida (Fase 6): el día/noche gobierna el gameplay.
		# Al anochecer _set_phase dispara la oleada (ya no hay invasiones
		# con timer aleatorio: las oleadas SON la noche).
		_phase_t -= delta
		if not is_night and not _dusk_warned and _phase_t <= DUSK_WARN:
			_dusk_warned = true
			_broadcast_toast("🌆 Anochece en %d s — prepárate" % int(DUSK_WARN))
		if _phase_t <= 0.0:
			_set_phase(not is_night)

		# Meteoro (GDD §9): evento DIURNO con aviso previo
		if not is_night:
			_meteor_t -= delta
			if _meteor_t <= 0.0 and _meteor_x < 0:
				_meteor_t = randf_range(70.0, 120.0)
				_meteor_x = randi_range(6, world.W - 7)
				_meteor_warn_t = METEOR_WARN
				_broadcast_toast("☄️ ¡Meteoro inminente cerca de x=%d! Aléjate" % _meteor_x)
		if _meteor_x >= 0:
			_meteor_warn_t -= delta
			if _meteor_warn_t <= 0.0:
				var where: Vector2i = world.meteor_strike(_meteor_x)
				_meteor_x = -1
				_broadcast_toast("☄️ ¡Impacto! El meteoro dejó mineral en x=%d" % where.x)
	elif multiplayer.multiplayer_peer != null:
		# Cliente: solo cuenta hacia atrás para el HUD (el servidor manda)
		_phase_t = maxf(0.0, _phase_t - delta)
	_update_phase_label()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if multiplayer.multiplayer_peer != null and multiplayer.is_server() and world != null:
			save_game()


# -------------------------------------------------------------
# LOBBY
# -------------------------------------------------------------
func _host(load_save: bool, mode: String = "sandbox") -> void:
	my_name = _read_name()
	game_mode = mode
	if Net.host_game() != OK:
		_show_toast("❌ Error al crear la partida (¿puerto ocupado?)")
		return
	_start_game()
	if not (load_save and load_game()):
		world.generate()
	inventories[1] = inventories.get(1, {})
	player_hp[1] = PLAYER_MAX_HP
	peer_names[1] = my_name
	var prof := _profile_for(my_name)
	_spawn_player(1, world.surface_spawn(randi_range(4, world.W - 5)), str(prof.skin), my_name)
	_apply_inventory(inventories[1])
	_apply_profile(prof)
	_show_toast("🟢 Partida creada — comparte tu IP: %s" % Net.local_ip())


func _on_join_pressed() -> void:
	my_name = _read_name()
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		_show_toast("Escribe la IP del host")
		return
	if Net.join_game(ip) != OK:
		_show_toast("❌ Dirección inválida")
		return
	_show_toast("Conectando a %s..." % ip)


func _on_connected_to_host() -> void:
	_start_game()
	request_join.rpc_id(1, my_name)
	_show_toast("🟢 Conectado")


func _read_name() -> String:
	var n := _name_input.text.strip_edges().substr(0, 16)
	return n if not n.is_empty() else "Jugador"


func _start_game() -> void:
	_menu.hide()
	world = Node2D.new()
	world.set_script(WorldScript)
	world.name = "World"
	add_child(world)
	move_child(world, 0)

	var npcs := Node2D.new()
	npcs.set_script(NpcScript)
	npcs.name = "NPCs"
	add_child(npcs)

	if not dedicated:
		_show_hud()


# -------------------------------------------------------------
# FLUJO DE UNIÓN (solo servidor)
# Ya NO se envía el mundo completo: el cliente pide chunks según
# se mueve (streaming §2.3).
# -------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func request_join(nombre: String) -> void:
	if not multiplayer.is_server():
		return
	var new_id := multiplayer.get_remote_sender_id()
	nombre = nombre.strip_edges().substr(0, 16)
	if nombre.is_empty():
		nombre = "Jugador%d" % new_id
	peer_names[new_id] = nombre
	var prof := _profile_for(nombre)
	inventories[new_id] = {}
	player_hp[new_id] = PLAYER_MAX_HP

	for pid: int in players:
		spawn_player_remote.rpc_id(new_id, pid, players[pid].position, _skin_of(pid), _name_of(pid))

	var spawn: Vector2 = world.surface_spawn(randi_range(4, world.W - 5))
	spawn_player_remote.rpc(new_id, spawn, str(prof.skin), nombre)
	_spawn_player(new_id, spawn, str(prof.skin), nombre)
	_push_profile(new_id)
	apply_phase.rpc_id(new_id, is_night, night_number, _phase_t, game_mode)


@rpc("authority", "call_remote", "reliable")
func spawn_player_remote(id: int, pos: Vector2, skin: String, nombre: String) -> void:
	_spawn_player(id, pos, skin, nombre)


func _spawn_player(id: int, pos: Vector2, skin: String = "default", nombre: String = "") -> void:
	if players.has(id):
		return
	var p := Node2D.new()
	p.set_script(PlayerScript)
	p.name = "Player_%d" % id
	p.peer_id = id
	p.skin_id = skin
	p.player_name = nombre
	p.position = pos
	p.set_multiplayer_authority(id)
	add_child(p)
	players[id] = p


# -------------------------------------------------------------
# INVENTARIO SERVER-AUTHORITATIVE (GDD §7)
# -------------------------------------------------------------
func add_item(peer_id: int, item: String) -> void:
	if not multiplayer.is_server():
		return
	var inv: Dictionary = inventories.get(peer_id, {})
	inv[item] = int(inv.get(item, 0)) + 1
	inventories[peer_id] = inv
	_push_inventory(peer_id)


func consume_item(peer_id: int, item: String) -> bool:
	if not multiplayer.is_server():
		return false
	var inv: Dictionary = inventories.get(peer_id, {})
	if int(inv.get(item, 0)) <= 0:
		return false
	inv[item] = int(inv[item]) - 1
	_push_inventory(peer_id)
	return true


## El SERVIDOR consulta el inventario real para decidir cuánto daño
## hace cada golpe (un cliente no puede mentir sobre su pico — §16).
func get_tool_damage(peer_id: int) -> int:
	var inv: Dictionary = inventories.get(peer_id, {})
	for tool: String in TOOL_DAMAGE:
		if int(inv.get(tool, 0)) > 0:
			return TOOL_DAMAGE[tool]
	return HAND_DAMAGE


## Daño de ataque contra NPCs: la mejor espada, o los puños.
func get_attack_damage(peer_id: int) -> int:
	var inv: Dictionary = inventories.get(peer_id, {})
	for wpn: String in WEAPON_DAMAGE:
		if int(inv.get(wpn, 0)) > 0:
			return WEAPON_DAMAGE[wpn]
	return HAND_DAMAGE


## Reducción de daño de la mejor armadura del jugador.
func get_armor_reduction(peer_id: int) -> int:
	var inv: Dictionary = inventories.get(peer_id, {})
	for arm: String in ARMOR_REDUCTION:
		if int(inv.get(arm, 0)) > 0:
			return ARMOR_REDUCTION[arm]
	return 0


func _push_inventory(peer_id: int) -> void:
	if peer_id == 1:
		if not dedicated:
			_apply_inventory(inventories[1])
	else:
		update_inventory.rpc_id(peer_id, inventories[peer_id])


@rpc("authority", "call_remote", "reliable")
func update_inventory(inv: Dictionary) -> void:
	_apply_inventory(inv)


func _apply_inventory(inv: Dictionary) -> void:
	# "+N material" flotando sobre el jugador (solo visual)
	if _inv_init and world != null and world.fx != null:
		var me: Node2D = players.get(multiplayer.get_unique_id())
		if me != null:
			var k := 0
			for item: String in ITEM_NAMES:
				var d := int(inv.get(item, 0)) - int(_my_inv.get(item, 0))
				if d > 0:
					world.fx.float_text(me.position + Vector2(0, -36.0 - k * 16.0),
						"+%d %s" % [d, ITEM_NAMES[item]], Color(1, 1, 1))
					k += 1
	_inv_init = true
	_my_inv = inv
	for item: String in _slot_buttons:
		_slot_buttons[item].text = "%s\n%d" % [ITEM_NAMES[item], int(inv.get(item, 0))]
	_refresh_info()
	_refresh_craft()


# -------------------------------------------------------------
# CRAFTING (GDD §8) — el servidor valida y consume ingredientes
# -------------------------------------------------------------
func craft_local(recipe_id: String) -> void:
	if multiplayer.is_server():
		_do_craft(recipe_id, 1)
	else:
		request_craft.rpc_id(1, recipe_id)


@rpc("any_peer", "call_remote", "reliable")
func request_craft(recipe_id: String) -> void:
	if not multiplayer.is_server():
		return
	_do_craft(recipe_id, multiplayer.get_remote_sender_id())


func _do_craft(recipe_id: String, peer_id: int) -> void:
	if not RECIPES.has(recipe_id):
		return
	var inv: Dictionary = inventories.get(peer_id, {})
	# Equipo (picos/espadas/armaduras) es único; bloques son apilables
	var is_unique := recipe_id.begins_with("pico_") or recipe_id.begins_with("espada_") or recipe_id.begins_with("armadura_")
	if is_unique and int(inv.get(recipe_id, 0)) > 0:
		_toast_to(peer_id, "Ya tienes: %s" % RECIPES[recipe_id].nombre)
		return
	var costo: Dictionary = RECIPES[recipe_id].costo
	for item: String in costo:
		if int(inv.get(item, 0)) < int(costo[item]):
			_toast_to(peer_id, "❌ Te faltan materiales para: %s" % RECIPES[recipe_id].nombre)
			return
	for item: String in costo:
		inv[item] = int(inv[item]) - int(costo[item])
	if is_unique:
		inv[recipe_id] = 1
	else:
		inv[recipe_id] = int(inv.get(recipe_id, 0)) + 1
	inventories[peer_id] = inv
	_push_inventory(peer_id)
	_toast_to(peer_id, "🛠️ Fabricaste: %s" % RECIPES[recipe_id].nombre)


# -------------------------------------------------------------
# MONETIZACIÓN — Núcleos, perfiles y skins (SOLO servidor decide)
# Sigue el patrón try_X → request_X → _do_X → apply_X (§16).
# Las compras con dinero real (Google Play Billing) acreditarán
# Núcleos vía add_coins() cuando exista backend — MONETIZACION.md.
# -------------------------------------------------------------
func _profile_for(nombre: String) -> Dictionary:
	var key := nombre.strip_edges().to_lower()
	if not profiles.has(key):
		profiles[key] = {"coins": 0, "skins": ["default"], "skin": "default"}
	return profiles[key]


func _profile_of(peer_id: int) -> Dictionary:
	return _profile_for(peer_names.get(peer_id, "anon_%d" % peer_id))


func _skin_of(peer_id: int) -> String:
	return str(_profile_of(peer_id).skin)


func _name_of(peer_id: int) -> String:
	return peer_names.get(peer_id, "P%d" % peer_id)


func add_coins(peer_id: int, n: int) -> void:
	if not multiplayer.is_server():
		return
	var prof := _profile_of(peer_id)
	prof.coins = int(prof.coins) + n
	_push_profile(peer_id)


func try_buy_skin(skin_id: String) -> void:
	if multiplayer.is_server():
		_do_buy_skin(skin_id, 1)
	else:
		request_buy_skin.rpc_id(1, skin_id)


func try_equip_skin(skin_id: String) -> void:
	if multiplayer.is_server():
		_do_equip_skin(skin_id, 1)
	else:
		request_equip_skin.rpc_id(1, skin_id)


@rpc("any_peer", "call_remote", "reliable")
func request_buy_skin(skin_id: String) -> void:
	if not multiplayer.is_server():
		return
	_do_buy_skin(skin_id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func request_equip_skin(skin_id: String) -> void:
	if not multiplayer.is_server():
		return
	_do_equip_skin(skin_id, multiplayer.get_remote_sender_id())


func _do_buy_skin(skin_id: String, peer_id: int) -> void:
	if not SKINS.has(skin_id):
		return
	var prof := _profile_of(peer_id)
	if skin_id in prof.skins:
		_do_equip_skin(skin_id, peer_id)     # ya la tiene: solo equipar
		return
	var precio: int = SKINS[skin_id].precio
	if int(prof.coins) < precio:
		_toast_to(peer_id, "❌ Te faltan Núcleos para: %s (cuesta %d)" % [SKINS[skin_id].nombre, precio])
		return
	prof.coins = int(prof.coins) - precio
	prof.skins.append(skin_id)
	_do_equip_skin(skin_id, peer_id)
	_toast_to(peer_id, "🛒 ¡Compraste la skin %s!" % SKINS[skin_id].nombre)


func _do_equip_skin(skin_id: String, peer_id: int) -> void:
	var prof := _profile_of(peer_id)
	if not SKINS.has(skin_id) or skin_id not in prof.skins:
		return
	prof.skin = skin_id
	_push_profile(peer_id)
	apply_skin.rpc(peer_id, skin_id)
	_apply_skin(peer_id, skin_id)


@rpc("authority", "call_remote", "reliable")
func apply_skin(peer_id: int, skin_id: String) -> void:
	_apply_skin(peer_id, skin_id)


func _apply_skin(peer_id: int, skin_id: String) -> void:
	if players.has(peer_id):
		players[peer_id].set_skin(skin_id)


func _push_profile(peer_id: int) -> void:
	var prof := _profile_of(peer_id)
	if peer_id == 1:
		if not dedicated:
			_apply_profile(prof)
	else:
		update_profile.rpc_id(peer_id, prof)


@rpc("authority", "call_remote", "reliable")
func update_profile(prof: Dictionary) -> void:
	_apply_profile(prof)


func _apply_profile(prof: Dictionary) -> void:
	var coins := int(prof.coins)
	if _profile_init:
		if coins > _my_coins:
			Sfx.play("moneda")
			var me: Node2D = players.get(multiplayer.get_unique_id())
			if me != null and world != null and world.fx != null:
				world.fx.burst(me.position + Vector2(0, -30), Color(0.95, 0.78, 0.2), 8, 110.0)
				world.fx.float_text(me.position + Vector2(0, -56),
					"+%d Núcleos" % (coins - _my_coins), Color(0.95, 0.8, 0.25))
		if prof.skins.size() > _my_skins.size():
			Sfx.play("compra")
	_profile_init = true
	_my_coins = coins
	# duplicate(): en el host prof.skins es la MISMA referencia del perfil;
	# sin copia, la comparación de tamaño de arriba nunca detectaría compras.
	_my_skins = prof.skins.duplicate()
	_my_skin = str(prof.skin)
	_refresh_info()
	_refresh_shop()


# -------------------------------------------------------------
# VIDA Y RESPAWN (SOLO servidor decide el daño)
# -------------------------------------------------------------
func damage_player(peer_id: int, dmg: int) -> void:
	if not multiplayer.is_server() or not players.has(peer_id):
		return
	dmg = maxi(1, dmg - get_armor_reduction(peer_id))   # la armadura amortigua
	var hp: int = player_hp.get(peer_id, PLAYER_MAX_HP) - dmg
	if hp <= 0:
		hp = PLAYER_MAX_HP
		# Respawn en la fogata más cercana (Fase 7), o en la superficie
		var camp: Vector2 = world.nearest_campfire_pos(players[peer_id].position)
		var pos: Vector2
		if camp.x < 1e8:
			pos = camp
		else:
			pos = world.surface_spawn(randi_range(4, world.W - 5))
		if peer_id == 1:
			players[1].position = pos
			players[1].velocity = Vector2.ZERO
		else:
			respawn_player.rpc_id(peer_id, pos)
		_toast_to(peer_id, "💀 ¡Caíste! Reapareciendo...")
	player_hp[peer_id] = hp
	if peer_id == 1:
		if not dedicated:
			_set_hp(hp)
	else:
		update_health.rpc_id(peer_id, hp)


@rpc("authority", "call_remote", "reliable")
func update_health(hp: int) -> void:
	_set_hp(hp)


@rpc("authority", "call_remote", "reliable")
func respawn_player(pos: Vector2) -> void:
	var me: Node2D = players.get(multiplayer.get_unique_id())
	if me != null:
		me.position = pos
		me.velocity = Vector2.ZERO


func _set_hp(hp: int) -> void:
	if hp < _my_hp:
		Sfx.play("dano")
		var me: Node2D = players.get(multiplayer.get_unique_id())
		if me != null and world != null and world.fx != null:
			world.fx.burst(me.position, Color(0.9, 0.2, 0.2), 10, 150.0)
	_my_hp = hp
	_refresh_info()


## Tick de regeneración (solo servidor): de noche solo cura cerca
## de una fogata (Fase 7); de día cura en todas partes.
func _regen_tick() -> void:
	for pid: int in player_hp.keys():
		var hp: int = player_hp[pid]
		if hp >= PLAYER_MAX_HP or not players.has(pid):
			continue
		if is_night and not _near_campfire(players[pid].position):
			continue
		player_hp[pid] = mini(hp + REGEN_AMOUNT, PLAYER_MAX_HP)
		if pid == 1:
			if not dedicated:
				_set_hp(player_hp[1])
		else:
			update_health.rpc_id(pid, player_hp[pid])


func _near_campfire(pos: Vector2) -> bool:
	if world == null:
		return false
	var cp: Vector2 = world.nearest_campfire_pos(pos)
	return cp.x < 1e8 and cp.distance_to(pos) <= FOGATA_RANGE


# -------------------------------------------------------------
# CICLO DÍA/NOCHE (Fase 6, ROADMAP.md) — SOLO el servidor cambia
# de fase; los clientes la reciben por RPC. La luz del mundo
# (world.daylight) y las oleadas nocturnas cuelgan de esto.
# -------------------------------------------------------------
func _set_phase(night: bool) -> void:
	is_night = night
	_phase_t = NIGHT_SECONDS if night else DAY_SECONDS
	_dusk_warned = false
	if night:
		night_number += 1
		_broadcast_toast("🌙 ¡Noche %d! Resiste hasta el amanecer" % night_number)
		var npcs_node: Node2D = get_node_or_null("NPCs")
		if npcs_node != null:
			npcs_node.night_wave(night_number)
	else:
		if night_number > 0:
			_broadcast_toast("☀️ Amaneció — sobreviviste la noche %d" % night_number)
		if game_mode == "survival" and night_number == SURVIVAL_NIGHTS:
			_broadcast_toast("🏆 ¡Sobreviviste las %d noches! Sigue jugando en modo libre" % SURVIVAL_NIGHTS)
	apply_phase.rpc(is_night, night_number, _phase_t, game_mode)


@rpc("authority", "call_remote", "reliable")
func apply_phase(night: bool, n: int, t_left: float, mode: String) -> void:
	is_night = night
	night_number = n
	_phase_t = t_left
	game_mode = mode


## 1.0 = pleno día, 0.0 = plena noche; amanecer/atardecer de ~12 s.
## world.daylight() delega aquí (la hora del sistema ya no manda).
func daylight_factor() -> float:
	var total: float = NIGHT_SECONDS if is_night else DAY_SECONDS
	var k := clampf((total - _phase_t) / 12.0, 0.0, 1.0)
	return (1.0 - k) if is_night else k


## Progreso 0..1 de la fase actual (posición del sol/luna en el cielo).
func phase_progress() -> float:
	var total: float = NIGHT_SECONDS if is_night else DAY_SECONDS
	return clampf(1.0 - _phase_t / total, 0.0, 1.0)


func _update_phase_label() -> void:
	if _phase_label == null or world == null:
		return
	var mm := int(_phase_t) / 60
	var ss := int(_phase_t) % 60
	if is_night:
		var meta := (" de %d" % SURVIVAL_NIGHTS) if game_mode == "survival" else ""
		_phase_label.text = "🌙 Noche %d%s — %d:%02d" % [night_number, meta, mm, ss]
	else:
		_phase_label.text = "☀️ Día %d — %d:%02d" % [night_number + 1, mm, ss]


# -------------------------------------------------------------
# PERSISTENCIA (GDD §14): JSON comprimido con gzip
# Nota: se guarda el mundo + el inventario del host. Inventarios
# por jugador requieren cuentas (los peer-ids cambian por sesión)
# y llegarán con el backend (Fase 5).
# -------------------------------------------------------------
func save_game() -> void:
	# Las runs de supervivencia NO se guardan: el save es del sandbox
	if world == null or game_mode == "survival":
		return
	var tiles_s := {}
	for c: Vector2i in world.tiles:
		tiles_s["%d,%d" % [c.x, c.y]] = world.tiles[c]
	var data := {"v": 4, "tiles": tiles_s, "host_inv": inventories.get(1, {}), "profiles": profiles}
	var f := FileAccess.open_compressed(SAVE_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()
		if dedicated:
			print("[SERVIDOR] Partida guardada")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open_compressed(SAVE_PATH, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("tiles"):
		return false
	world.tiles.clear()
	for k: String in data.tiles:
		var p := (k as String).split(",")
		world.tiles[Vector2i(int(p[0]), int(p[1]))] = int(data.tiles[k])
	inventories[1] = data.get("host_inv", {})
	# Perfiles (v4) — normalizar tipos: JSON devuelve floats
	profiles = {}
	for n: String in data.get("profiles", {}):
		var pr: Dictionary = data.profiles[n]
		profiles[n] = {"coins": int(pr.get("coins", 0)),
			"skins": pr.get("skins", ["default"]), "skin": str(pr.get("skin", "default"))}
	return true


# -------------------------------------------------------------
# TOASTS / CONEXIONES
# -------------------------------------------------------------
func _toast_to(peer_id: int, text: String) -> void:
	if peer_id == 1:
		if not dedicated:
			_show_toast(text)
	else:
		show_toast.rpc_id(peer_id, text)


## Aviso de evento del mundo: a todos los peers + al propio servidor.
func _broadcast_toast(text: String) -> void:
	show_toast.rpc(text)
	_show_toast(text)


@rpc("authority", "call_remote", "reliable")
func show_toast(text: String) -> void:
	_show_toast(text)


func _show_toast(text: String) -> void:
	_status.text = text
	_toast_panel.show()
	_toast_panel.modulate.a = 1.0
	_toast_life = TOAST_LIFE
	if text.begins_with("☄️"):   # el aviso de meteoro llega a todos los peers
		Sfx.play("meteoro")
	elif text.begins_with("🛠️"):  # crafteo exitoso
		Sfx.play("fabricar")
	elif text.begins_with("👾"):  # invasión de slimes
		Sfx.play("invasion")


func _on_player_connected(id: int) -> void:
	if multiplayer.is_server():
		if dedicated:
			print("[SERVIDOR] Jugador %d conectado" % id)
		else:
			_show_toast("🟢 Jugador %d conectado — IP del host: %s" % [id, Net.local_ip()])


func _on_player_disconnected(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	inventories.erase(id)
	player_hp.erase(id)
	peer_names.erase(id)   # el perfil queda en profiles (persiste por nombre)
	if dedicated:
		print("[SERVIDOR] Jugador %d desconectado" % id)


func _on_host_lost() -> void:
	Net.disconnect_game()
	get_tree().reload_current_scene()


# -------------------------------------------------------------
# UI
# -------------------------------------------------------------
## El jugador ignora toques que caen sobre la interfaz.
func is_point_on_ui(p: Vector2) -> bool:
	for ctrl: Control in [_hud_box, _craft_btn, _craft_panel, _shop_btn, _shop_panel, _hp_panel, _toast_panel]:
		if ctrl != null and ctrl.visible and ctrl.get_global_rect().has_point(p):
			return true
	return _menu.visible


## Estilo común de paneles: fondo oscuro translúcido, bordes redondeados
## y márgenes internos — legible sobre cualquier fondo del mundo.
func _style_panel(p: PanelContainer, bg := Color(0.07, 0.08, 0.12, 0.92)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	# Toast de avisos: arriba al CENTRO (no choca con la barra de vida)
	_toast_panel = PanelContainer.new()
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.grow_vertical = Control.GROW_DIRECTION_END
	_toast_panel.position += Vector2(0, 8)
	_style_panel(_toast_panel, Color(0.05, 0.06, 0.1, 0.85))
	_toast_panel.hide()
	_ui.add_child(_toast_panel)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 17)
	_toast_panel.add_child(_status)

	_menu = PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_style_panel(_menu)
	_ui.add_child(_menu)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 14)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "⛏️ NÚCLEO DEL MUNDO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Fase 5 — skins, Núcleos y sonido"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	# Nombre de jugador: clave del perfil (Núcleos y skins persisten por nombre)
	_name_input = LineEdit.new()
	_name_input.text = "Jugador"
	_name_input.placeholder_text = "Tu nombre (guarda tus Núcleos y skins)"
	_name_input.max_length = 16
	_name_input.custom_minimum_size.y = 48
	box.add_child(_name_input)

	# Modos de juego (Fase 6): supervivencia por noches o sandbox libre
	var surv_btn := Button.new()
	surv_btn.text = "🌙 Supervivencia — %d noches (host)" % SURVIVAL_NIGHTS
	surv_btn.custom_minimum_size.y = 56
	surv_btn.pressed.connect(func(): _host(false, "survival"))
	box.add_child(surv_btn)

	var new_btn := Button.new()
	new_btn.text = "🏖️ Sandbox libre (host)"
	new_btn.custom_minimum_size.y = 56
	new_btn.pressed.connect(func(): _host(false))
	box.add_child(new_btn)

	if FileAccess.file_exists(SAVE_PATH):
		var cont_btn := Button.new()
		cont_btn.text = "Continuar partida guardada"
		cont_btn.custom_minimum_size.y = 56
		cont_btn.pressed.connect(func(): _host(true))
		box.add_child(cont_btn)

	_ip_input = LineEdit.new()
	_ip_input.text = "127.0.0.1"
	_ip_input.placeholder_text = "IP del host (ej: 192.168.1.50)"
	_ip_input.custom_minimum_size.y = 48
	box.add_child(_ip_input)

	var join_btn := Button.new()
	join_btn.text = "Unirse a partida"
	join_btn.custom_minimum_size.y = 56
	join_btn.pressed.connect(_on_join_pressed)
	box.add_child(join_btn)


func _show_hud() -> void:
	# Aviso de vida baja: borde rojo pulsante en todo el viewport.
	# MOUSE_FILTER_IGNORE y fuera de is_point_on_ui: no bloquea taps.
	var lowhp := Panel.new()
	lowhp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lowhp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lsb := StyleBoxFlat.new()
	lsb.draw_center = false
	lsb.border_color = Color(0.85, 0.1, 0.1, 0.8)
	lsb.set_border_width_all(14)
	lowhp.add_theme_stylebox_override("panel", lsb)
	lowhp.hide()
	_ui.add_child(lowhp)
	_low_hp = lowhp

	var joy := Control.new()
	joy.set_script(JoystickScript)
	_ui.add_child(joy)

	# --- Vida + herramienta equipada (arriba a la izquierda) ---
	var hp_panel := PanelContainer.new()
	hp_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hp_panel.position += Vector2(12, 10)
	_style_panel(hp_panel, Color(0.05, 0.06, 0.1, 0.75))
	_ui.add_child(hp_panel)
	_hp_panel = hp_panel

	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	hp_panel.add_child(status_box)

	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(_phase_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	status_box.add_child(hp_row)

	var hp_icon := Label.new()
	hp_icon.text = "❤"
	hp_icon.add_theme_font_size_override("font_size", 20)
	hp_row.add_child(hp_icon)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(160, 22)
	_hp_bar.min_value = 0
	_hp_bar.max_value = PLAYER_MAX_HP
	_hp_bar.show_percentage = false
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color("d6453f")
	hp_fill.set_corner_radius_all(4)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_row.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 14)
	hp_row.add_child(_hp_label)

	_tool_label = Label.new()
	_tool_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(_tool_label)

	_armor_label = Label.new()
	_armor_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(_armor_label)

	# --- Inventario + info (abajo a la derecha) ---
	var hud := VBoxContainer.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.position += Vector2(-16, -16)
	hud.add_theme_constant_override("separation", 8)
	_ui.add_child(hud)
	_hud_box = hud

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info.add_theme_font_size_override("font_size", 16)
	hud.add_child(_info)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	hud.add_child(slots)

	var group := ButtonGroup.new()
	for item: String in ["dirt", "stone", "wood", "muralla", "fogata"]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(96, 72)
		b.text = "%s\n0" % ITEM_NAMES[item]
		b.pressed.connect(func(): selected_item = item)
		slots.add_child(b)
		_slot_buttons[item] = b
	_slot_buttons[selected_item].button_pressed = true

	# --- Botón y panel de crafting (arriba a la derecha) ---
	var craft_btn := Button.new()
	craft_btn.text = "🛠️ Fabricar"
	craft_btn.custom_minimum_size = Vector2(150, 52)
	craft_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	craft_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	craft_btn.position += Vector2(-12, 10)
	craft_btn.z_index = 2
	_ui.add_child(craft_btn)
	_craft_btn = craft_btn

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position += Vector2(-12, 0)
	_style_panel(panel)
	panel.hide()
	_ui.add_child(panel)
	_craft_panel = panel
	craft_btn.pressed.connect(func(): panel.visible = not panel.visible)

	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 10)
	panel.add_child(pbox)

	var ptop := HBoxContainer.new()
	pbox.add_child(ptop)
	var ptitle := Label.new()
	ptitle.text = "🛠️ Fabricar (usa materiales, NO Núcleos)"
	ptitle.add_theme_font_size_override("font_size", 18)
	ptitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ptop.add_child(ptitle)
	var pclose := Button.new()
	pclose.text = "✕"
	pclose.custom_minimum_size = Vector2(40, 40)
	pclose.pressed.connect(func(): panel.hide())
	ptop.add_child(pclose)

	for rid: String in RECIPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		pbox.add_child(row)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cbtn := Button.new()
		cbtn.text = "Crear"
		cbtn.custom_minimum_size = Vector2(84, 44)
		cbtn.pressed.connect(func(): craft_local(rid))
		row.add_child(cbtn)

		_craft_rows[rid] = {"label": lbl, "button": cbtn}

	# --- Botón y panel de la TIENDA de skins (MONETIZACIÓN) ---
	var shop_btn := Button.new()
	shop_btn.text = "🛒 Tienda (skins)"
	shop_btn.custom_minimum_size = Vector2(170, 52)
	shop_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	shop_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	shop_btn.position += Vector2(-174, 10)
	shop_btn.z_index = 2
	shop_btn.pressed.connect(_on_shop_pressed)
	_ui.add_child(shop_btn)
	_shop_btn = shop_btn

	var spanel := PanelContainer.new()
	spanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	spanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	spanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_style_panel(spanel)
	spanel.hide()
	_ui.add_child(spanel)
	_shop_panel = spanel

	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 10)
	spanel.add_child(sbox)

	var stop := HBoxContainer.new()
	sbox.add_child(stop)
	_shop_title = Label.new()
	_shop_title.add_theme_font_size_override("font_size", 18)
	_shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop.add_child(_shop_title)
	var sclose := Button.new()
	sclose.text = "✕"
	sclose.custom_minimum_size = Vector2(40, 40)
	sclose.pressed.connect(func(): spanel.hide())
	stop.add_child(sclose)

	for sid: String in SKINS:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 12)
		sbox.add_child(srow)

		var swatch := ColorRect.new()
		swatch.color = SKINS[sid].cuerpo
		swatch.custom_minimum_size = Vector2(28, 28)
		srow.add_child(swatch)

		var slbl := Label.new()
		slbl.text = SKINS[sid].nombre
		slbl.custom_minimum_size.x = 160
		slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(slbl)

		var sbtn := Button.new()
		sbtn.custom_minimum_size = Vector2(130, 44)
		sbtn.pressed.connect(_on_skin_pressed.bind(sid))
		srow.add_child(sbtn)
		_shop_rows[sid] = sbtn

	_refresh_info()
	_refresh_shop()
	_refresh_craft()


func _on_shop_pressed() -> void:
	_shop_panel.visible = not _shop_panel.visible
	_refresh_shop()


func _on_skin_pressed(sid: String) -> void:
	if sid in _my_skins:
		try_equip_skin(sid)
	else:
		try_buy_skin(sid)


func _refresh_shop() -> void:
	if _shop_panel == null:
		return
	_shop_title.text = "🛒 Tienda de skins — tienes 🪙 %d Núcleos" % _my_coins
	for sid: String in _shop_rows:
		var b: Button = _shop_rows[sid]
		if sid == _my_skin:
			b.text = "✓ Equipada"
			b.disabled = true
		elif sid in _my_skins:
			b.text = "Equipar"
			b.disabled = false
		else:
			b.text = "🪙 %d" % int(SKINS[sid].precio)
			b.disabled = int(SKINS[sid].precio) > _my_coins


func _refresh_craft() -> void:
	for rid: String in _craft_rows:
		var costo: Dictionary = RECIPES[rid].costo
		var partes := []
		var alcanza := true
		for item: String in costo:
			var tengo := int(_my_inv.get(item, 0))
			var necesito := int(costo[item])
			if tengo < necesito:
				alcanza = false
			partes.append("%s %d/%d" % [ITEM_NAMES[item].to_lower(), tengo, necesito])
		var tiene := int(_my_inv.get(rid, 0)) > 0
		var is_unique := rid.begins_with("pico_") or rid.begins_with("espada_") or rid.begins_with("armadura_")
		var row: Dictionary = _craft_rows[rid]
		var lbl: Label = row.label
		var btn: Button = row.button
		if is_unique:
			lbl.text = "%s%s — %s" % ["✓ " if tiene else "", RECIPES[rid].nombre, ", ".join(partes)]
			btn.disabled = tiene or not alcanza
		else:
			var count := int(_my_inv.get(rid, 0))
			var prefix := "(%d) " % count if count > 0 else ""
			lbl.text = "%s%s — %s" % [prefix, RECIPES[rid].nombre, ", ".join(partes)]
			btn.disabled = not alcanza


func _refresh_info() -> void:
	if _info != null:
		_info.text = "🪙 %d   |   Mineral: %d" % [_my_coins, int(_my_inv.get("ore", 0))]
	_refresh_status()


func _refresh_status() -> void:
	if _hp_bar == null:
		return
	_hp_bar.value = _my_hp
	_hp_label.text = "%d/%d" % [_my_hp, PLAYER_MAX_HP]
	var tool_name := "Mano"
	for t: String in TOOL_DAMAGE:
		if int(_my_inv.get(t, 0)) > 0:
			tool_name = RECIPES[t].nombre
			break
	var weapon_name := "Puños"
	for wpn: String in WEAPON_DAMAGE:
		if int(_my_inv.get(wpn, 0)) > 0:
			weapon_name = RECIPES[wpn].nombre
			break
	var armor_name := "Sin armadura"
	for arm: String in ARMOR_REDUCTION:
		if int(_my_inv.get(arm, 0)) > 0:
			armor_name = RECIPES[arm].nombre
			break
	_tool_label.text = "⛏ %s   ⚔ %s" % [tool_name, weapon_name]
	_armor_label.text = "🛡 %s" % armor_name
