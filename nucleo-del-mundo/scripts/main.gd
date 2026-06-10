# =============================================================
# main.gd — Orquestador — FASES 3-4
# Novedades:
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

const ITEM_NAMES := {"dirt": "Tierra", "stone": "Piedra", "wood": "Madera", "ore": "Mineral"}

# GDD §8.1 — recetas. El orden de TOOL_DAMAGE es del mejor al peor.
const RECIPES := {
	"pico_madera": {"nombre": "Pico de madera", "costo": {"wood": 8}},
	"pico_piedra": {"nombre": "Pico de piedra", "costo": {"wood": 4, "stone": 12}},
	"pico_dorado": {"nombre": "Pico dorado", "costo": {"wood": 4, "ore": 8}},
}
const TOOL_DAMAGE := {"pico_dorado": 100, "pico_piedra": 60, "pico_madera": 35}
const TOOL_NAMES := {"pico_dorado": "Dorado", "pico_piedra": "Piedra", "pico_madera": "Madera"}
const HAND_DAMAGE := 20

var world: Node2D = null
var players: Dictionary = {}        # peer_id -> Player (todos los peers)
var inventories: Dictionary = {}    # peer_id -> {item: qty}   (SOLO servidor)
var player_hp: Dictionary = {}      # peer_id -> hp            (SOLO servidor)
var selected_item := "dirt"
var dedicated := false

var _my_inv: Dictionary = {}
var _my_hp := 100
var _stream_t := 0.0
var _save_t := 0.0
var _meteor_t := 90.0

var _ui: CanvasLayer
var _menu: PanelContainer
var _status: Label
var _ip_input: LineEdit
var _slot_buttons: Dictionary = {}
var _info: Label
var _hud_box: Control = null
var _craft_btn: Control = null
var _craft_panel: Control = null


func _ready() -> void:
	_build_ui()
	Net.player_connected.connect(_on_player_connected)
	Net.player_disconnected.connect(_on_player_disconnected)
	Net.connection_succeeded.connect(_on_connected_to_host)
	Net.connection_failed.connect(func(): _status.text = "❌ No se pudo conectar al host")
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
	if world == null:
		return

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
		_meteor_t -= delta
		if _meteor_t <= 0.0:
			_meteor_t = randf_range(70.0, 120.0)
			var where: Vector2i = world.meteor_strike()
			var msg := "☄️ ¡Meteoro! Cayó cerca de x=%d — dejó mineral" % where.x
			show_toast.rpc(msg)
			_show_toast(msg)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if multiplayer.multiplayer_peer != null and multiplayer.is_server() and world != null:
			save_game()


# -------------------------------------------------------------
# LOBBY
# -------------------------------------------------------------
func _host(load_save: bool) -> void:
	if Net.host_game() != OK:
		_status.text = "❌ Error al crear la partida (¿puerto ocupado?)"
		return
	_start_game()
	if not (load_save and load_game()):
		world.generate()
	inventories[1] = inventories.get(1, {})
	player_hp[1] = 100
	_spawn_player(1, world.surface_spawn(randi_range(4, world.W - 5)))
	_apply_inventory(inventories[1])
	_status.text = "🟢 Partida creada — comparte tu IP: %s" % Net.local_ip()


func _on_join_pressed() -> void:
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		_status.text = "Escribe la IP del host"
		return
	if Net.join_game(ip) != OK:
		_status.text = "❌ Dirección inválida"
		return
	_status.text = "Conectando a %s..." % ip


func _on_connected_to_host() -> void:
	_start_game()
	request_join.rpc_id(1)
	_status.text = "🟢 Conectado"


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
func request_join() -> void:
	if not multiplayer.is_server():
		return
	var new_id := multiplayer.get_remote_sender_id()
	inventories[new_id] = {}
	player_hp[new_id] = 100

	for pid: int in players:
		spawn_player_remote.rpc_id(new_id, pid, players[pid].position)

	var spawn: Vector2 = world.surface_spawn(randi_range(4, world.W - 5))
	spawn_player_remote.rpc(new_id, spawn)
	_spawn_player(new_id, spawn)


@rpc("authority", "call_remote", "reliable")
func spawn_player_remote(id: int, pos: Vector2) -> void:
	_spawn_player(id, pos)


func _spawn_player(id: int, pos: Vector2) -> void:
	if players.has(id):
		return
	var p := Node2D.new()
	p.set_script(PlayerScript)
	p.name = "Player_%d" % id
	p.peer_id = id
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
	_my_inv = inv
	for item: String in _slot_buttons:
		_slot_buttons[item].text = "%s\n%d" % [ITEM_NAMES[item], int(inv.get(item, 0))]
	_refresh_info()


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
	var costo: Dictionary = RECIPES[recipe_id].costo
	for item: String in costo:
		if int(inv.get(item, 0)) < int(costo[item]):
			_toast_to(peer_id, "❌ Te faltan materiales para: %s" % RECIPES[recipe_id].nombre)
			return
	for item: String in costo:
		inv[item] = int(inv[item]) - int(costo[item])
	inv[recipe_id] = 1
	inventories[peer_id] = inv
	_push_inventory(peer_id)
	_toast_to(peer_id, "🛠️ Fabricaste: %s" % RECIPES[recipe_id].nombre)


# -------------------------------------------------------------
# VIDA Y RESPAWN (SOLO servidor decide el daño)
# -------------------------------------------------------------
func damage_player(peer_id: int, dmg: int) -> void:
	if not multiplayer.is_server() or not players.has(peer_id):
		return
	var hp: int = player_hp.get(peer_id, 100) - dmg
	if hp <= 0:
		hp = 100
		var pos: Vector2 = world.surface_spawn(randi_range(4, world.W - 5))
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
	_my_hp = hp
	_refresh_info()


# -------------------------------------------------------------
# PERSISTENCIA (GDD §14): JSON comprimido con gzip
# Nota: se guarda el mundo + el inventario del host. Inventarios
# por jugador requieren cuentas (los peer-ids cambian por sesión)
# y llegarán con el backend (Fase 5).
# -------------------------------------------------------------
func save_game() -> void:
	if world == null:
		return
	var tiles_s := {}
	for c: Vector2i in world.tiles:
		tiles_s["%d,%d" % [c.x, c.y]] = world.tiles[c]
	var data := {"v": 3, "tiles": tiles_s, "host_inv": inventories.get(1, {})}
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


@rpc("authority", "call_remote", "reliable")
func show_toast(text: String) -> void:
	_show_toast(text)


func _show_toast(text: String) -> void:
	_status.text = text


func _on_player_connected(id: int) -> void:
	if multiplayer.is_server():
		if dedicated:
			print("[SERVIDOR] Jugador %d conectado" % id)
		else:
			_status.text = "🟢 Jugador %d conectado — IP del host: %s" % [id, Net.local_ip()]


func _on_player_disconnected(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	inventories.erase(id)
	player_hp.erase(id)
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
	for ctrl: Control in [_hud_box, _craft_btn, _craft_panel]:
		if ctrl != null and ctrl.visible and ctrl.get_global_rect().has_point(p):
			return true
	return _menu.visible


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	_status = Label.new()
	_status.position = Vector2(12, 8)
	_status.add_theme_font_size_override("font_size", 16)
	_ui.add_child(_status)

	_menu = PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
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
	subtitle.text = "Fases 3-4 — chunks, crafting, NPCs y persistencia"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	var new_btn := Button.new()
	new_btn.text = "Nueva partida (host)"
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
	var joy := Control.new()
	joy.set_script(JoystickScript)
	_ui.add_child(joy)

	# --- Inventario + info (abajo a la derecha) ---
	var hud := VBoxContainer.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
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
	for item: String in ["dirt", "stone", "wood"]:
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
	craft_btn.custom_minimum_size = Vector2(140, 52)
	craft_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	craft_btn.position += Vector2(-12, 10)
	_ui.add_child(craft_btn)
	_craft_btn = craft_btn

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.position += Vector2(-12, 0)
	panel.hide()
	_ui.add_child(panel)
	_craft_panel = panel
	craft_btn.pressed.connect(func(): panel.visible = not panel.visible)

	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 10)
	panel.add_child(pbox)

	var ptitle := Label.new()
	ptitle.text = "Recetas (GDD §8)"
	ptitle.add_theme_font_size_override("font_size", 18)
	pbox.add_child(ptitle)

	for rid: String in RECIPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		pbox.add_child(row)

		var costs := []
		for item: String in RECIPES[rid].costo:
			costs.append("%d %s" % [RECIPES[rid].costo[item], ITEM_NAMES[item].to_lower()])
		var lbl := Label.new()
		lbl.text = "%s — %s" % [RECIPES[rid].nombre, ", ".join(costs)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cbtn := Button.new()
		cbtn.text = "Crear"
		cbtn.custom_minimum_size = Vector2(84, 44)
		cbtn.pressed.connect(func(): craft_local(rid))
		row.add_child(cbtn)

	_refresh_info()


func _refresh_info() -> void:
	if _info == null:
		return
	var tool_name := "Mano"
	for t: String in TOOL_DAMAGE:
		if int(_my_inv.get(t, 0)) > 0:
			tool_name = TOOL_NAMES[t]
			break
	_info.text = "❤ %d   |   ⛏ Pico: %s   |   Mineral: %d" % [_my_hp, tool_name, int(_my_inv.get("ore", 0))]
