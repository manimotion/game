# =============================================================
# ui_builder.gd — CAPA DE PRESENTACIÓN (ver ARQUITECTURA.md)
# Construye TODA la interfaz por código (decisión de prototipo:
# sin .tscn complejos) y asigna las referencias en main.gd, que
# sigue siendo el dueño del estado. Aquí no hay reglas de juego:
# el lobby se genera recorriendo GameModes.LOBBY_ORDER — añadir
# un modo en la capa de reglas lo hace aparecer aquí solo.
# 100% local y cosmético: nunca toca estado del juego (GDD §16).
# =============================================================
extends RefCounted

const GameModesScript := preload("res://scripts/game_modes.gd")
const JoystickScript := preload("res://scripts/virtual_joystick.gd")

# Paleta de la interfaz: una sola fuente de verdad para el look.
const COL_BG := Color(0.07, 0.08, 0.12, 0.92)
const COL_BG_SOFT := Color(0.05, 0.06, 0.1, 0.8)
const COL_ACCENT := Color(0.95, 0.78, 0.2)      # dorado (Núcleos)
const COL_DANGER := Color("d6453f")
const COL_TEXT_DIM := Color(1, 1, 1, 0.55)


## Estilo común de paneles: fondo oscuro translúcido, bordes redondeados
## y márgenes internos — legible sobre cualquier fondo del mundo.
static func style_panel(p: PanelContainer, bg := COL_BG) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)


## Botón destacado (modos de juego): borde dorado sutil y altura cómoda.
static func _accent_button(text: String, height := 56.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = height
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.2, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.35)
	sb.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", sb)
	return b


# -------------------------------------------------------------
# LOBBY (menú principal): título, perfil, modos (data-driven
# desde la capa de reglas) y sección de unirse por IP.
# -------------------------------------------------------------
static func build_lobby(m: Node2D) -> void:
	m._ui = CanvasLayer.new()
	m.add_child(m._ui)

	# Toast de avisos: arriba al CENTRO (no choca con la barra de vida)
	m._toast_panel = PanelContainer.new()
	m._toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	m._toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	m._toast_panel.grow_vertical = Control.GROW_DIRECTION_END
	m._toast_panel.position += Vector2(0, 8)
	style_panel(m._toast_panel, Color(0.05, 0.06, 0.1, 0.85))
	m._toast_panel.hide()
	m._ui.add_child(m._toast_panel)

	m._status = Label.new()
	m._status.add_theme_font_size_override("font_size", 17)
	m._toast_panel.add_child(m._status)

	m._menu = PanelContainer.new()
	m._menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	m._menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	m._menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	style_panel(m._menu)
	m._ui.add_child(m._menu)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 10)
	m._menu.add_child(box)

	var title := Label.new()
	title.text = "⛏️ NÚCLEO DEL MUNDO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_ACCENT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = m.L("subtitle", "De día construye. De noche sobrevive.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	# Nombre de jugador: clave del perfil (Núcleos y skins persisten por nombre)
	m._name_input = LineEdit.new()
	m._name_input.text = "Jugador"
	m._name_input.placeholder_text = m.L("name_ph", "Tu nombre (guarda tus Núcleos y skins)")
	m._name_input.max_length = 16
	m._name_input.custom_minimum_size.y = 48
	box.add_child(m._name_input)

	# Modos de juego DATA-DRIVEN: la capa de reglas decide qué existe.
	for mode_id: String in GameModesScript.LOBBY_ORDER:
		var cfg: Dictionary = GameModesScript.MODES[mode_id]
		var nm: String = m.L("mode_%s_name" % mode_id, str(cfg.nombre))
		var goal: String = (m.L("nights_fmt", "%d noches") % int(cfg.nights_to_win)) if int(cfg.nights_to_win) > 0 else m.L("endless", "sin fin")
		var btn := _accent_button("%s %s — %s (%s)" % [cfg.icono, nm, goal, m.L("host_suffix", "host")])
		btn.pressed.connect(func(): m._host(false, mode_id))
		box.add_child(btn)
		var dl := Label.new()
		dl.text = m.L("mode_%s_desc" % mode_id, str(cfg.desc))
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_size_override("font_size", 13)
		dl.modulate = COL_TEXT_DIM
		box.add_child(dl)

	if FileAccess.file_exists(m.SAVE_PATH):
		var cont_btn := Button.new()
		cont_btn.text = m.L("continue_save", "💾 Continuar partida guardada")
		cont_btn.custom_minimum_size.y = 52
		cont_btn.pressed.connect(func(): m._host(true))
		box.add_child(cont_btn)

	# Unirse por IP: solo en escritorio/móvil (ENet). En WEB (itch.io) no hay
	# ENet, así que el lobby se queda con los modos en SOLO y se oculta esto.
	m._ip_input = LineEdit.new()
	if not Net.is_web():
		box.add_child(HSeparator.new())

		m._ip_input.text = "127.0.0.1"
		m._ip_input.placeholder_text = m.L("ip_ph", "IP del host (ej: 192.168.1.50)")
		m._ip_input.custom_minimum_size.y = 48
		box.add_child(m._ip_input)

		var join_btn := Button.new()
		join_btn.text = m.L("join", "🔗 Unirse a partida")
		join_btn.custom_minimum_size.y = 52
		join_btn.pressed.connect(m._on_join_pressed)
		box.add_child(join_btn)

	box.add_child(HSeparator.new())

	var settings_btn := Button.new()
	settings_btn.text = m.L("settings_btn_lobby", "⚙️ Ajustes (controles / idioma)")
	settings_btn.custom_minimum_size.y = 48
	settings_btn.pressed.connect(m._on_settings_pressed)
	box.add_child(settings_btn)

	# Panel de ajustes (compartido con el HUD: se añade a _ui, persiste).
	_build_settings_panel(m)
	m._refresh_settings()


# -------------------------------------------------------------
# AJUSTES: selector de modo de control móvil/PC (local, per-device).
# main es dueño del estado (control_mode) y de la lógica (set_control_mode
# / effective_control_mode); aquí solo se construye el panel y se cablean
# los botones. Compartido por lobby y HUD — se añade a _ui una sola vez.
# -------------------------------------------------------------
static func _build_settings_panel(m: Node2D) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.z_index = 6
	style_panel(panel)
	panel.hide()
	m._ui.add_child(panel)
	m._settings_panel = panel

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = m.L("settings_title", "⚙️ Ajustes")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(40, 40)
	close.pressed.connect(func(): panel.hide())
	top.add_child(close)

	var sub := Label.new()
	sub.text = m.L("ctrl_sub", "Cómo se controla el juego en este dispositivo:")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.modulate = COL_TEXT_DIM
	box.add_child(sub)

	# Las 3 opciones de control, en un ButtonGroup (selección única).
	var group := ButtonGroup.new()
	var opciones := {
		"auto": m.L("ctrl_auto", "🔍 Automático (según el dispositivo)"),
		"movil": m.L("ctrl_movil", "📱 Móvil — joystick táctil"),
		"pc": m.L("ctrl_pc", "🖥️ PC — teclado (WASD/flechas) + ratón"),
	}
	for mode: String in opciones:
		var b := _accent_button(opciones[mode], 48.0)
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func(): m.set_control_mode(mode))
		box.add_child(b)
		m._control_buttons[mode] = b

	box.add_child(HSeparator.new())

	m._settings_hint = Label.new()
	m._settings_hint.add_theme_font_size_override("font_size", 13)
	m._settings_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._settings_hint.modulate = COL_TEXT_DIM
	box.add_child(m._settings_hint)

	# --- IDIOMA / LANGUAGE (ES/EN) ---
	box.add_child(HSeparator.new())
	var lang_lbl := Label.new()
	lang_lbl.text = m.L("lang_label", "🌐 Idioma / Language:")
	box.add_child(lang_lbl)
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	box.add_child(lang_row)
	var lgroup := ButtonGroup.new()
	var langs := {"auto": m.L("lang_auto", "Auto"), "es": m.L("lang_es", "Español"), "en": m.L("lang_en", "English")}
	for lg: String in langs:
		var lb := _accent_button(langs[lg], 44.0)
		lb.toggle_mode = true
		lb.button_group = lgroup
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.pressed.connect(func(): m.set_language(lg))
		lang_row.add_child(lb)
		m._lang_buttons[lg] = lb

	# --- MENÚ DE SALIDA / PAUSA (publicación) ---
	box.add_child(HSeparator.new())
	var menu_btn := Button.new()
	menu_btn.text = m.L("main_menu", "🏠 Menú principal")
	menu_btn.custom_minimum_size.y = 46
	menu_btn.pressed.connect(m._on_main_menu_pressed)
	box.add_child(menu_btn)
	var quit_btn := Button.new()
	quit_btn.text = m.L("quit", "🚪 Salir del juego")
	quit_btn.custom_minimum_size.y = 46
	quit_btn.pressed.connect(m._on_quit_pressed)
	box.add_child(quit_btn)


# -------------------------------------------------------------
# HUD de juego: vida/fase, inventario, fabricar, tienda, barra
# del jefe, aviso de vida baja y panel de fin de run.
# -------------------------------------------------------------
static func build_hud(m: Node2D) -> void:
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
	m._ui.add_child(lowhp)
	m._low_hp = lowhp

	var joy := Control.new()
	joy.set_script(JoystickScript)
	m._ui.add_child(joy)
	m._joystick = joy   # main lo activa/desactiva según el modo de control

	# --- Barra de vida del JEFE (Fase 9, pulido) ---
	# Solo informativa: MOUSE_FILTER_IGNORE en todo y fuera de
	# is_point_on_ui — no roba taps (mismo trato que _low_hp).
	var bpanel := PanelContainer.new()
	bpanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bpanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bpanel.grow_vertical = Control.GROW_DIRECTION_END
	bpanel.position += Vector2(0, 64)
	bpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_panel(bpanel, Color(0.12, 0.02, 0.02, 0.8))
	bpanel.hide()
	m._ui.add_child(bpanel)
	m._boss_panel = bpanel

	var bbox := VBoxContainer.new()
	bbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bbox.add_theme_constant_override("separation", 4)
	bpanel.add_child(bbox)

	var blbl := Label.new()
	blbl.text = "👹 JEFE"
	blbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blbl.add_theme_font_size_override("font_size", 15)
	blbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bbox.add_child(blbl)
	m._boss_label = blbl

	m._boss_bar = ProgressBar.new()
	m._boss_bar.custom_minimum_size = Vector2(280, 16)
	m._boss_bar.min_value = 0.0
	m._boss_bar.max_value = 1.0
	m._boss_bar.show_percentage = false
	m._boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = COL_DANGER
	bfill.set_corner_radius_all(3)
	m._boss_bar.add_theme_stylebox_override("fill", bfill)
	bbox.add_child(m._boss_bar)

	# --- Banner dedicado de anuncio de jefe (Bloque 1 "Mundo vivo") ---
	# Centrado y más vistoso que el toast genérico (no compite con
	# "Partida creada" ni avisos posteriores). MOUSE_FILTER_IGNORE y
	# fuera de is_point_on_ui — no roba taps (mismo trato que _low_hp).
	var apanel := PanelContainer.new()
	apanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	apanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	apanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	apanel.position += Vector2(0, -140)
	apanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apanel.z_index = 4
	var asb := StyleBoxFlat.new()
	asb.bg_color = Color(0.12, 0.05, 0.02, 0.9)
	asb.set_corner_radius_all(12)
	asb.set_border_width_all(2)
	asb.border_color = COL_ACCENT
	asb.set_content_margin_all(16)
	apanel.add_theme_stylebox_override("panel", asb)
	apanel.hide()
	m._ui.add_child(apanel)
	m._boss_announce_panel = apanel

	var albl := Label.new()
	albl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	albl.add_theme_font_size_override("font_size", 20)
	albl.add_theme_color_override("font_color", COL_ACCENT)
	albl.autowrap_mode = TextServer.AUTOWRAP_WORD
	albl.custom_minimum_size = Vector2(420, 0)
	albl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apanel.add_child(albl)
	m._boss_announce_label = albl

	# --- Vida + herramienta equipada (arriba a la izquierda) ---
	var hp_panel := PanelContainer.new()
	hp_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hp_panel.position += Vector2(12, 10)
	style_panel(hp_panel, Color(0.05, 0.06, 0.1, 0.75))
	m._ui.add_child(hp_panel)
	m._hp_panel = hp_panel

	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	hp_panel.add_child(status_box)

	m._phase_label = Label.new()
	m._phase_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(m._phase_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	status_box.add_child(hp_row)

	var hp_icon := Label.new()
	hp_icon.text = "❤"
	hp_icon.add_theme_font_size_override("font_size", 20)
	hp_row.add_child(hp_icon)

	m._hp_bar = ProgressBar.new()
	m._hp_bar.custom_minimum_size = Vector2(160, 22)
	m._hp_bar.min_value = 0
	m._hp_bar.max_value = m.PLAYER_MAX_HP
	m._hp_bar.show_percentage = false
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = COL_DANGER
	hp_fill.set_corner_radius_all(4)
	m._hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_row.add_child(m._hp_bar)

	m._hp_label = Label.new()
	m._hp_label.add_theme_font_size_override("font_size", 14)
	hp_row.add_child(m._hp_label)

	m._tool_label = Label.new()
	m._tool_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(m._tool_label)

	m._armor_label = Label.new()
	m._armor_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(m._armor_label)

	# --- Inventario + info (abajo a la derecha) — barra de items PLEGABLE ---
	var hud := VBoxContainer.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.position += Vector2(-16, -16)
	hud.add_theme_constant_override("separation", 8)
	m._ui.add_child(hud)
	m._hud_box = hud

	m._info = Label.new()
	m._info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	m._info.add_theme_font_size_override("font_size", 16)
	hud.add_child(m._info)

	# Fila plegable: [slots ...][botón]. El botón pliega la barra hacia la
	# derecha; al plegarse, los slots se ocultan y la franja inferior queda
	# LIBRE para minar/colocar debajo (la barra acaparaba esos taps — por eso
	# is_point_on_ui mira `_slots_box`, que desaparece al plegar, no el hud).
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 8)
	hud.add_child(bar)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	bar.add_child(slots)
	m._slots_box = slots

	var toggle := Button.new()
	toggle.custom_minimum_size = Vector2(40, 72)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_END
	toggle.pressed.connect(m._toggle_items)
	bar.add_child(toggle)
	m._items_toggle = toggle

	var group := ButtonGroup.new()
	for item: String in ["dirt", "stone", "wood", "muralla", "fogata", "trampa", "torre", "torre_mega"]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(96, 72)
		b.text = "%s\n0" % m.item_name(item)
		b.pressed.connect(func(): m.selected_item = item)
		slots.add_child(b)
		m._slot_buttons[item] = b
	m._slot_buttons[m.selected_item].button_pressed = true
	m._refresh_items_toggle()

	# --- Botón y panel de crafting (arriba a la derecha) ---
	var craft_btn := Button.new()
	craft_btn.text = m.L("craft", "🛠️ Fabricar")
	craft_btn.custom_minimum_size = Vector2(150, 52)
	craft_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	craft_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	craft_btn.position += Vector2(-12, 10)
	craft_btn.z_index = 2
	m._ui.add_child(craft_btn)
	m._craft_btn = craft_btn

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position += Vector2(-12, 0)
	style_panel(panel)
	panel.hide()
	m._ui.add_child(panel)
	m._craft_panel = panel
	craft_btn.pressed.connect(func(): panel.visible = not panel.visible)

	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 10)
	panel.add_child(pbox)

	var ptop := HBoxContainer.new()
	pbox.add_child(ptop)
	var ptitle := Label.new()
	ptitle.text = m.L("craft_title", "🛠️ Fabricar (usa materiales, NO Núcleos)")
	ptitle.add_theme_font_size_override("font_size", 18)
	ptitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ptop.add_child(ptitle)
	var pclose := Button.new()
	pclose.text = "✕"
	pclose.custom_minimum_size = Vector2(40, 40)
	pclose.pressed.connect(func(): panel.hide())
	ptop.add_child(pclose)

	# Equipo: una fila por familia (pico/espada/armadura) con la SIGUIENTE
	# mejora — hasta no fabricar la de madera no se puede fabricar la de
	# piedra, y así (TIER_CHAINS + _next_tier en main.gd).
	for fam: String in m.TIER_CHAINS:
		var chain: Array = m.TIER_CHAINS[fam]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		pbox.add_child(row)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cbtn := Button.new()
		cbtn.text = "Crear"
		cbtn.custom_minimum_size = Vector2(84, 44)
		cbtn.pressed.connect(func(): m.craft_local(m._next_tier(chain, m._my_inv)))
		row.add_child(cbtn)

		m._craft_rows[fam] = {"label": lbl, "button": cbtn, "chain": chain}

	# Bloques apilables (sin cadena de mejora): una fila por receta
	for rid: String in m.RECIPES:
		if not m._tier_chain_of(rid).is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		pbox.add_child(row)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cbtn := Button.new()
		cbtn.text = "Crear"
		cbtn.custom_minimum_size = Vector2(84, 44)
		cbtn.pressed.connect(func(): m.craft_local(rid))
		row.add_child(cbtn)

		m._craft_rows[rid] = {"label": lbl, "button": cbtn}

	# --- Botón y panel de la TIENDA de skins (MONETIZACIÓN) ---
	var shop_btn := Button.new()
	shop_btn.text = m.L("shop", "🛒 Tienda (skins)")
	shop_btn.custom_minimum_size = Vector2(170, 52)
	shop_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	shop_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	shop_btn.position += Vector2(-174, 10)
	shop_btn.z_index = 2
	shop_btn.pressed.connect(m._on_shop_pressed)
	m._ui.add_child(shop_btn)
	m._shop_btn = shop_btn

	var spanel := PanelContainer.new()
	spanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	spanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	spanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	style_panel(spanel)
	spanel.hide()
	m._ui.add_child(spanel)
	m._shop_panel = spanel

	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 10)
	spanel.add_child(sbox)

	var stop := HBoxContainer.new()
	sbox.add_child(stop)
	m._shop_title = Label.new()
	m._shop_title.add_theme_font_size_override("font_size", 18)
	m._shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop.add_child(m._shop_title)
	var sclose := Button.new()
	sclose.text = "✕"
	sclose.custom_minimum_size = Vector2(40, 40)
	sclose.pressed.connect(func(): spanel.hide())
	stop.add_child(sclose)

	for sid: String in m.SKINS:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 12)
		sbox.add_child(srow)

		var swatch := ColorRect.new()
		swatch.color = m.SKINS[sid].camisa
		swatch.custom_minimum_size = Vector2(28, 28)
		srow.add_child(swatch)

		var slbl := Label.new()
		slbl.text = m.SKINS[sid].nombre
		slbl.custom_minimum_size.x = 160
		slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(slbl)

		var sbtn := Button.new()
		sbtn.custom_minimum_size = Vector2(130, 44)
		sbtn.pressed.connect(m._on_skin_pressed.bind(sid))
		srow.add_child(sbtn)
		m._shop_rows[sid] = sbtn

	# --- Panel de fin de run (Fase 9): victoria/derrota en supervivencia ---
	var rpanel := PanelContainer.new()
	rpanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rpanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rpanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	rpanel.z_index = 5
	style_panel(rpanel)
	rpanel.hide()
	m._ui.add_child(rpanel)
	m._run_panel = rpanel

	var rbox := VBoxContainer.new()
	rbox.custom_minimum_size = Vector2(360, 0)
	rbox.add_theme_constant_override("separation", 14)
	rpanel.add_child(rbox)

	m._run_title = Label.new()
	m._run_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._run_title.add_theme_font_size_override("font_size", 26)
	rbox.add_child(m._run_title)

	m._run_body = Label.new()
	m._run_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m._run_body.add_theme_font_size_override("font_size", 16)
	rbox.add_child(m._run_body)

	var run_close := Button.new()
	run_close.text = m.L("run_close", "Continuar en modo libre")
	run_close.custom_minimum_size.y = 52
	run_close.pressed.connect(func(): rpanel.hide())
	rbox.add_child(run_close)

	# --- Botón compacto de AJUSTES (control móvil/PC) en el HUD ---
	# El PANEL se construyó en el lobby (persiste en _ui); aquí solo
	# añadimos el acceso, a la izquierda de los botones Fabricar/Tienda.
	var set_btn := Button.new()
	set_btn.text = "⚙️"
	set_btn.custom_minimum_size = Vector2(52, 52)
	set_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	set_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	set_btn.position += Vector2(-352, 10)
	set_btn.z_index = 2
	set_btn.pressed.connect(m._on_settings_pressed)
	m._ui.add_child(set_btn)
	m._settings_btn = set_btn

	m._refresh_info()
	m._refresh_shop()
	m._refresh_craft()
