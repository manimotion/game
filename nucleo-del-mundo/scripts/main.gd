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
const NpcScript := preload("res://scripts/npc_manager.gd")
const TowerScript := preload("res://scripts/tower_manager.gd")
const GameModesScript := preload("res://scripts/game_modes.gd")  # CAPA DE REGLAS
const UiBuilderScript := preload("res://scripts/ui_builder.gd")  # CAPA DE PRESENTACIÓN

const SAVE_PATH := "user://nucleo_save.json.gz"
# Ajustes LOCALES por dispositivo (NO viajan por red, NO son del save de
# partida): por ahora solo el modo de control móvil/PC.
const SETTINGS_PATH := "user://nucleo_settings.cfg"
const CONTROL_MODES := ["auto", "movil", "pc"]

const ITEM_NAMES := {"dirt": "Tierra", "stone": "Piedra", "wood": "Madera", "ore": "Mineral",
	"cristal": "Cristal", "muralla": "Muralla", "fogata": "Fogata", "trampa": "Trampa", "torre": "Torre",
	"pluma": "Pluma", "esencia": "Esencia", "diamante": "Diamante", "ascua": "Ascua",
	"torre_mega": "Torre mega"}

# Contador de minerales del HUD (petición del jugador: faltaba ver
# diamantes/cristal/etc.). Orden e icono de cada material precioso.
const MINERAL_ICONS := {"ore": "⛏️", "cristal": "🔷", "diamante": "💎",
	"pluma": "🪶", "esencia": "🌀", "ascua": "🔥"}

# GDD §8.1 — recetas: picos (minan), espadas (combate) y armaduras
# (reducen daño). Los diccionarios *_DAMAGE/_REDUCTION van del mejor
# al peor: el servidor usa el primero que el jugador tenga.
const RECIPES := {
	"pico_madera": {"nombre": "Pico de madera", "costo": {"wood": 8}},
	"pico_piedra": {"nombre": "Pico de piedra", "costo": {"wood": 4, "stone": 12}},
	"pico_dorado": {"nombre": "Pico dorado", "costo": {"wood": 4, "ore": 8}},
	"pico_cristal": {"nombre": "Pico de cristal", "costo": {"wood": 4, "cristal": 6}},
	"espada_madera": {"nombre": "Espada de madera", "costo": {"wood": 10}},
	"espada_piedra": {"nombre": "Espada de piedra", "costo": {"wood": 4, "stone": 16}},
	"espada_dorada": {"nombre": "Espada dorada", "costo": {"wood": 4, "ore": 10}},
	"espada_diamante": {"nombre": "Espada de diamante", "costo": {"wood": 4, "diamante": 6, "ascua": 4}},
	"armadura_madera": {"nombre": "Armadura de madera", "costo": {"wood": 20}},
	"armadura_piedra": {"nombre": "Armadura de piedra", "costo": {"stone": 30}},
	"armadura_dorada": {"nombre": "Armadura dorada", "costo": {"stone": 10, "ore": 15}},
	"armadura_diamante": {"nombre": "Armadura de diamante", "costo": {"stone": 10, "diamante": 8, "esencia": 4, "pluma": 4}},
	"muralla": {"nombre": "Muralla", "costo": {"stone": 6}},
	"fogata": {"nombre": "Fogata", "costo": {"wood": 8, "stone": 4}},
	"trampa": {"nombre": "Trampa de pinchos", "costo": {"stone": 10, "ore": 4}},
	"torre": {"nombre": "Torre de flechas", "costo": {"stone": 20, "wood": 10, "ore": 15}},
	"torre_mega": {"nombre": "Torre mega", "costo": {"stone": 20, "diamante": 6, "ascua": 4, "cristal": 4}},
}
# Cadenas de mejora de equipo único: el panel de Fabricar muestra UNA
# fila por familia con la SIGUIENTE mejora disponible — para craftear
# el tier N+1 hace falta tener ya el tier N (ver _do_craft/_next_tier).
# Bloque 2 "Progresión elemental": espada/armadura suman un tier final que
# consume los minerales de los Bloques 1 — torre_mega NO entra aquí (es un
# bloque apilable más, sin cadena, ver tower_manager.MEGA_*).
const TIER_CHAINS := {
	"pico": ["pico_madera", "pico_piedra", "pico_dorado", "pico_cristal"],
	"espada": ["espada_madera", "espada_piedra", "espada_dorada", "espada_diamante"],
	"armadura": ["armadura_madera", "armadura_piedra", "armadura_dorada", "armadura_diamante"],
}
const TOOL_DAMAGE := {"pico_cristal": 150, "pico_dorado": 100, "pico_piedra": 60, "pico_madera": 35}
const WEAPON_DAMAGE := {"espada_diamante": 90, "espada_dorada": 60, "espada_piedra": 38, "espada_madera": 24}
const ARMOR_REDUCTION := {"armadura_diamante": 10, "armadura_dorada": 6, "armadura_piedra": 4, "armadura_madera": 2}
const HAND_DAMAGE := 20
const PLAYER_MAX_HP := 100
const REGEN_EVERY := 4.0     # segundos entre ticks de regeneración de vida
const REGEN_AMOUNT := 3      # vida recuperada por tick (solo servidor)
const METEOR_WARN := 3.0     # segundos de aviso antes del impacto del meteoro
const TOAST_LIFE := 4.5      # segundos visibles del toast antes de desvanecerse
const FOGATA_RANGE := 256.0  # radio del aura de la fogata (8 tiles) — Fase 7

# Ciclo día/noche y estructura de run: los NÚMEROS por modo viven en
# game_modes.gd (capa de reglas, ver ARQUITECTURA.md) — aquí quedan
# como espejo de los modos clásicos (sandbox/survival) para los tests.
const DAY_SECONDS := 180.0   # duración del día (modos clásicos)
const NIGHT_SECONDS := 90.0  # duración de la noche (modos clásicos)
const DUSK_WARN := 30.0      # aviso de atardecer (UI, igual en todos los modos)
const SURVIVAL_NIGHTS := 7   # objetivo del modo supervivencia clásico
const NIGHT_REWARD_BASE := 10  # Núcleos al amanecer por sobrevivir una noche
const NIGHT_REWARD_STEP := 5   # + esto por cada número de noche (escala el riesgo)
const VICTORY_BONUS := 100     # Núcleos extra al completar el modo supervivencia
const COIN_NEST := 8           # Núcleos extra al destruir un nido (Fase 10)

# Fase 10 — roster de jefes: cada BOSS_EVERY noches aparece uno de estos,
# elegido al azar al iniciar la partida y anunciado de inmediato (toast +
# rugido) para que el jugador planee su defensa contra ese jefe en concreto.
const BOSS_KINDS := ["jefe", "jefe_murcielago", "jefe_topo", "jefe_corredor"]
const BOSS_HINTS := {
	"jefe": "rompe muros y se enfurece con poca vida — refuerza tus murallas",
	"jefe_murcielago": "vuela y embiste en línea recta — las torres de flechas son clave",
	"jefe_topo": "excava bajo tus pies y ataca tus muros desde el subsuelo",
	"jefe_corredor": "carga en horizontal a gran velocidad — no te quedes en su camino",
}

# MONETIZACIÓN — catálogo de skins (solo cosmético, nunca pay-to-win).
# El SERVIDOR valida compra/equipamiento (§16); el cliente solo pide.
# "default" usa el color por jugador de siempre. "anim" = color animado.
# Rediseño 2026-06-13: cada skin es un ATUENDO completo (camisa + pantalón +
# pelo + borde) y un ACCESORIO de identidad (corona/cuernos/capucha/...), no
# solo un color de camisa. `camisa` es el color del swatch en la tienda; en la
# skin "default" el jugador usa su color por-peer para la camisa. `accent`
# tiñe el accesorio. Sigue siendo 100% cosmético (nunca pay-to-win).
const SKINS := {
	"default": {"nombre": "Clásica", "precio": 0, "anim": false,
		"camisa": Color.WHITE, "pantalon": Color("3a4a6b"), "pelo": Color("4a3220"),
		"borde": Color.BLACK, "accesorio": "", "accent": Color.WHITE},
	"esmeralda": {"nombre": "Esmeralda", "precio": 25, "anim": false,
		"camisa": Color("20ad58"), "pantalon": Color("155f33"), "pelo": Color("3a2a18"),
		"borde": Color("04280d"), "accesorio": "diadema", "accent": Color("8af0b0")},
	"rubi": {"nombre": "Rubí", "precio": 25, "anim": false,
		"camisa": Color("d92e3d"), "pantalon": Color("7a1520"), "pelo": Color("3a2218"),
		"borde": Color("350407"), "accesorio": "diadema", "accent": Color("ffb0b8")},
	"zafiro": {"nombre": "Zafiro", "precio": 25, "anim": false,
		"camisa": Color("3366e6"), "pantalon": Color("1c2f7a"), "pelo": Color("2a2a3a"),
		"borde": Color("0a1f6a"), "accesorio": "diadema", "accent": Color("a8c8ff")},
	"dorado": {"nombre": "Dorado", "precio": 60, "anim": false,
		"camisa": Color("f2c733"), "pantalon": Color("8a6a12"), "pelo": Color("5a4a10"),
		"borde": Color("5a4205"), "accesorio": "corona", "accent": Color("ffe070")},
	"sombra": {"nombre": "Sombra", "precio": 80, "anim": false,
		"camisa": Color("221d2e"), "pantalon": Color("15111f"), "pelo": Color("15111f"),
		"borde": Color("8c40d9"), "accesorio": "capucha", "accent": Color("1a1626")},
	"neon": {"nombre": "Neón", "precio": 80, "anim": false,
		"camisa": Color("0cedd9"), "pantalon": Color("086e7a"), "pelo": Color("0a3a3a"),
		"borde": Color.WHITE, "accesorio": "visor", "accent": Color("eafcff")},
	"arcoiris": {"nombre": "Arcoíris", "precio": 150, "anim": true,
		"camisa": Color.WHITE, "pantalon": Color("888a90"), "pelo": Color("aa90c0"),
		"borde": Color.WHITE, "accesorio": "halo", "accent": Color.WHITE},
	# Skins temáticas del bestiario (solo cosméticas)
	"topo": {"nombre": "Topo", "precio": 40, "anim": false,
		"camisa": Color("6b4a3a"), "pantalon": Color("4a3226"), "pelo": Color("2a1c14"),
		"borde": Color("e8e0d0"), "accesorio": "casco", "accent": Color("f0c84a")},
	"nocturna": {"nombre": "Nocturna", "precio": 40, "anim": false,
		"camisa": Color("6b5c8e"), "pantalon": Color("2c2440"), "pelo": Color("2c2440"),
		"borde": Color("15111f"), "accesorio": "orejas", "accent": Color("4a3d66")},
	"acero": {"nombre": "Acero", "precio": 40, "anim": false,
		"camisa": Color("8a909c"), "pantalon": Color("5a606c"), "pelo": Color("3a3a45"),
		"borde": Color("f0c84a"), "accesorio": "casco", "accent": Color("c0c6d2")},
	"demonio": {"nombre": "Demonio", "precio": 120, "anim": false,
		"camisa": Color("d6453f"), "pantalon": Color("7a1f1c"), "pelo": Color("2a0f0c"),
		"borde": Color("15040c"), "accesorio": "cuernos", "accent": Color("2a1a1a")},
}
# Núcleos por matar slimes: ver npc_manager.KINDS (varía por variante)
const COIN_ORE := 2          # Núcleos por minar un tile de mineral

# Bloque 3 "Mundo vivo II" — EXPLORACIÓN: cofres de recursos. El botín
# depende del bioma del cofre (_zone_at de su posición): cada material
# tiene un rango [min, max] de cuántos suelta. Además unos Núcleos.
const CHEST_LOOT := {
	"cielo": {"pluma": [2, 5], "esencia": [1, 3], "wood": [3, 6]},
	"superficie": {"wood": [4, 8], "stone": [4, 8], "ore": [2, 4]},
	"cueva": {"stone": [4, 8], "ore": [3, 6], "cristal": [1, 3]},
	"profundo": {"diamante": [1, 3], "ascua": [2, 4], "cristal": [2, 4]},
}
const CHEST_COINS := [3, 8]

# Bloque 3 — CALAVERAS estilo Halo: 5 variantes ocultas (todas se ven
# igual hasta excavarlas). Unas ayudan al jugador, otras a los enemigos;
# el efecto se elige al azar al romperla. `efecto` lo aplica excavate_skull.
const SKULL_HEAL := 60         # curación de la calavera vital
const SKULLS := [
	{"nombre": "💎 Calavera del Tesoro", "buena": true, "efecto": "monedas",
		"aviso": "💎 ¡Calavera del Tesoro! Una lluvia de Núcleos."},
	{"nombre": "💚 Calavera Vital", "buena": true, "efecto": "cura",
		"aviso": "💚 ¡Calavera Vital! Tus heridas se cierran."},
	{"nombre": "📦 Calavera del Botín", "buena": true, "efecto": "botin",
		"aviso": "📦 ¡Calavera del Botín! Materiales caen en tus manos."},
	{"nombre": "😡 Calavera de la Furia", "buena": false, "efecto": "horda",
		"aviso": "😡 ¡Calavera de la Furia! Algo se acerca corriendo..."},
	{"nombre": "👹 Calavera Maldita", "buena": false, "efecto": "bestia",
		"aviso": "👹 ¡Calavera Maldita! Una bestia despierta a tu lado."},
]

# Bloque 1 "Mundo vivo" — PRESIÓN AMBIENTAL (anti-turtling): vivir en cielo/
# cueva/profundo sin una fortificación propia cerca acaba atrayendo enemigos.
# "superficie" no genera presión (ya cubierta por las oleadas nocturnas).
# La superficie generada llega hasta SKY_ROWS+8 (generate(): (noise+1)*4),
# así que la banda debe superar esa amplitud o un valle contaría como cueva.
const UNDERGROUND_BAND := 10    # filas bajo SKY_ROWS que aún cuentan como "superficie"
const FORT_TILES := {WorldScript.T_WALL: true, WorldScript.T_CAMPFIRE: true,
	WorldScript.T_SPIKES: true, WorldScript.T_TOWER: true, WorldScript.T_TOWER_MEGA: true}
const FORT_RADIUS := 6          # tiles de radio donde se cuentan bloques de fuerte
const FORT_MIN_BLOCKS := 4      # bloques de fuerte mínimos para no generar presión
const PRESSURE_CHECK_EVERY := 2.0   # segundos entre comprobaciones de presión
const ZONE_PRESSURE_TIME := 80.0    # segundos sin fuerte antes de la primera presión
const PRESSURE_WARN_TIME := 60.0    # aviso ⚠️ previo (telegraph: legibilidad = juego justo)
const PRESSURE_MAX_SPAWNS := 3      # tope de enemigos por presión aunque siga reincidiendo
const BOSS_ANNOUNCE_LIFE := 8.0     # segundos visibles del banner de jefe

# Bloque 2 "Progresión elemental" — JEFES ADAPTATIVOS: si el jefe activo no
# puede amenazar bien la zona donde se queda el jugador (p.ej. "jefe_topo"
# no alcanza una isla del cielo, "jefe_murcielago" no sigue bajo tierra, o
# cualquier jefe lento deja que el jugador campee en superficie), tras
# BOSS_EVOLVE_TIME el jefe MUTA a la variante de esa zona (npc_mgr.evolve_boss
# conserva posición/vida proporcional). "cueva" y "profundo" comparten
# destino (jefe_topo: excava en ambos); "superficie" evoluciona a
# jefe_corredor (amenaza rápida en terreno abierto).
const ZONE_BOSS_KIND := {
	"cielo": "jefe_murcielago",
	"cueva": "jefe_topo",
	"profundo": "jefe_topo",
	"superficie": "jefe_corredor",
}
const BOSS_EVOLVE_TIME := 30.0      # segundos en zona "equivocada" antes de mutar al jefe

var world: Node2D = null
var npc_mgr: Node2D = null           # NPCs (npc_manager.gd) — Fase 8: lo usa tower_manager
var tower_mgr: Node2D = null         # Towers (tower_manager.gd) — Fase 8
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
var _player_sync_accum := 0.0       # SOLO servidor: cadencia de sync_players (GDD §10.2, 20 Hz)
var _meteor_t := 90.0
var _meteor_x := -1                 # x anunciada del meteoro (-1 = ninguno pendiente)
var _meteor_warn_t := 0.0
var _regen_t := 0.0
var _toast_life := 0.0
var _pressure_t := 0.0               # Bloque 1 "Mundo vivo": cadencia de _update_zone_pressure
var _zone_pressure: Dictionary = {}  # peer_id -> {"zone": String, "t": float} (SOLO servidor)
var _boss_announce_life := 0.0       # banner dedicado de anuncio de jefe
var _boss_evolve: Dictionary = {}    # npc_id -> segundos acumulados en zona "equivocada" (SOLO servidor)

# Ciclo día/noche (Fase 6) — el SERVIDOR lleva el reloj; los clientes
# reciben cada cambio de fase y solo cuentan hacia atrás para el HUD.
var game_mode := "sandbox"          # id del modo activo (claves de GameModes.MODES)
var mode_cfg: Dictionary = GameModesScript.get_mode("sandbox")  # reglas del modo activo
var is_night := false
var night_number := 0               # noches iniciadas (0 = aún no anochece)
var _phase_t := DAY_SECONDS         # tiempo restante de la fase actual
var _dusk_warned := false
var _run_over := false              # evita que _end_run() se dispare dos veces (Fase 9)
var run_kills := 0                  # bajas de la run actual (SOLO servidor, Fase 9)
var run_boss_kind := "jefe"         # jefe de esta run (Fase 10), elegido por el host

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
var _slots_box: Control = null      # barra de items plegable (fila de slots)
var _items_toggle: Button = null    # botón ▶/◀ que pliega la barra
var _craft_btn: Control = null
var _craft_panel: Control = null
var _craft_rows: Dictionary = {}    # recipe_id -> {label, button}
var _shop_btn: Control = null
var _shop_panel: Control = null
var _shop_title: Label = null
var _shop_rows: Dictionary = {}     # skin_id -> Button
var _run_panel: Control = null      # pantalla de fin de run (Fase 9)
var _run_title: Label = null
var _run_body: Label = null
var _boss_panel: Control = null     # barra de vida del jefe en el HUD (Fase 9)
var _boss_bar: ProgressBar = null
var _boss_label: Label = null       # nombre del jefe vivo (Fase 10: roster variable)
var _boss_announce_panel: Control = null   # banner dedicado del jefe de la run (Bloque 1)
var _boss_announce_label: Label = null

# --- Ajustes de control móvil/PC (local, per-device) ---
var control_mode := "auto"          # "auto"/"movil"/"pc" (ver SETTINGS_PATH)
var _joystick: Control = null       # joystick virtual (ui_builder lo crea en el HUD)
var _settings_btn: Control = null
var _settings_panel: Control = null
var _settings_hint: Label = null
var _control_buttons: Dictionary = {}   # "auto"/"movil"/"pc" -> Button


func _ready() -> void:
	_load_settings()
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

	# Desvanecido del banner de jefe (Bloque 1 "Mundo vivo")
	if _boss_announce_life > 0.0 and not _menu.visible:
		_boss_announce_life -= delta
		if _boss_announce_life <= 0.0:
			_boss_announce_panel.hide()
		elif _boss_announce_life < 1.2:
			_boss_announce_panel.modulate.a = _boss_announce_life / 1.2

	if world == null:
		return

	# Borde rojo pulsante con vida baja (solo visual)
	if _low_hp != null:
		if _my_hp < 30:
			_low_hp.visible = true
			_low_hp.modulate.a = 0.45 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
		else:
			_low_hp.visible = false

	# Barra del JEFE (Fase 9/10, pulido): visible mientras haya CUALQUIER
	# enemigo "boss" vivo (roster variable). Funciona en todos los peers:
	# el ratio de vida y el kind viajan en el snapshot.
	if _boss_panel != null and npc_mgr != null:
		var bratio := -1.0
		var bkind := ""
		for id: int in npc_mgr.npcs:
			var nk := str(npc_mgr.npcs[id].get("kind", ""))
			if bool(npc_mgr.KINDS.get(nk, {}).get("boss", false)):
				bratio = npc_mgr._ratio_of(npc_mgr.npcs[id])
				bkind = nk
				break
		if bratio >= 0.0:
			_boss_panel.show()
			_boss_bar.value = bratio
			if _boss_label != null:
				_boss_label.text = "👹 " + str(npc_mgr.KINDS.get(bkind, {}).get("nombre", "JEFE")).to_upper()
		elif _boss_panel.visible:
			_boss_panel.hide()

	_stream_t += delta
	if _stream_t >= 0.4:
		_stream_t = 0.0
		var me: Node2D = players.get(multiplayer.get_unique_id())
		if me != null:
			world.update_streaming(me.position)

	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		# Movimiento server-authoritative (GDD §10.2): difunde la posición
		# real de todos los jugadores a 20 Hz (mismo patrón que sync_npcs).
		_player_sync_accum += delta
		if _player_sync_accum >= 0.05:
			_player_sync_accum = 0.0
			_broadcast_player_snapshot()

		_save_t += delta
		if _save_t >= 60.0:
			_save_t = 0.0
			save_game()

		# Regeneración de vida lenta (solo servidor)
		_regen_t += delta
		if _regen_t >= REGEN_EVERY:
			_regen_t = 0.0
			_regen_tick()

		# Presión ambiental (Bloque 1 "Mundo vivo"): castiga quedarse en
		# cielo/cueva/profundo sin una fortificación propia cerca.
		_pressure_t += delta
		if _pressure_t >= PRESSURE_CHECK_EVERY:
			_pressure_t = 0.0
			for pid: int in players:
				_update_zone_pressure(pid)
			_update_boss_evolution()

		# Reloj de partida (Fase 6): el día/noche gobierna el gameplay.
		# Al anochecer _set_phase dispara la oleada (ya no hay invasiones
		# con timer aleatorio: las oleadas SON la noche).
		_phase_t -= delta
		if not is_night and not _dusk_warned and _phase_t <= DUSK_WARN:
			_dusk_warned = true
			_broadcast_toast("🌆 Anochece en %d s — prepárate" % int(DUSK_WARN))
		if _phase_t <= 0.0:
			_set_phase(not is_night)

		# Meteoro (GDD §9): evento DIURNO con aviso previo (si el modo lo permite)
		if not is_night and bool(mode_cfg.get("meteors", true)):
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
## Fija el modo activo y carga sus reglas (capa de reglas, game_modes.gd).
## Único punto donde game_mode/mode_cfg cambian: host, apply_phase y reset.
func set_mode(id: String) -> void:
	game_mode = id
	mode_cfg = GameModesScript.get_mode(id)


func _host(load_save: bool, mode: String = "sandbox") -> void:
	my_name = _read_name()
	set_mode(mode)
	_run_over = false
	run_kills = 0
	run_boss_kind = BOSS_KINDS.pick_random()
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
	_broadcast_boss_announcement(run_boss_kind)


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
	npc_mgr = npcs

	var towers := Node2D.new()
	towers.set_script(TowerScript)
	towers.name = "Towers"
	add_child(towers)
	tower_mgr = towers

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
	apply_phase.rpc_id(new_id, is_night, night_number, _phase_t, game_mode, run_boss_kind)
	show_boss_announcement.rpc_id(new_id, run_boss_kind)


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
# MOVIMIENTO SERVER-AUTHORITATIVE (GDD §10.2)
# El servidor simula la física de TODOS los jugadores (cada Player._process
# corre _process_remote_authority para los nodos que no son su autoridad) y
# difunde aquí la posición real. Los clientes reconcilian su propio nodo
# (player._reconcile) y actualizan _target_pos/_target_vel de los remotos.
# -------------------------------------------------------------
## Snapshot autoritativo de posiciones, 20 Hz — mismo patrón que
## npc_manager.sync_npcs. peer_id -> [pos, vel, on_floor]. El servidor
## NO se lo aplica a sí mismo: sus nodos son la autoridad (Casos A y B
## de player._process) y nunca leen _target_pos.
func _broadcast_player_snapshot() -> void:
	if multiplayer.get_peers().is_empty():
		return   # en solitario no hay a quién difundir
	var snap := {}
	for pid: int in players:
		var p: Node2D = players[pid]
		snap[pid] = [p.position, p.velocity, p.on_floor]
	sync_players.rpc(snap)


@rpc("authority", "call_remote", "unreliable_ordered")
func sync_players(snap: Dictionary) -> void:
	_apply_player_snapshot(snap)


## SOLO clientes (les llega por sync_players): reconcilia mi propio nodo
## contra la posición real del servidor y actualiza el objetivo de lerp
## de los nodos remotos.
func _apply_player_snapshot(snap: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	for pid: int in snap:
		if not players.has(pid):
			continue
		var p: Node2D = players[pid]
		var s: Array = snap[pid]
		var pos: Vector2 = s[0]
		var vel: Vector2 = s[1]
		var floor_flag: bool = s[2]
		if pid == my_id:
			if not multiplayer.is_server():
				p._reconcile(pos, vel, floor_flag)
			# si soy servidor, mi propio nodo YA es la autoridad: no-op
		else:
			p._target_pos = pos
			p._target_vel = vel


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


# Devuelve la cadena de mejora (TIER_CHAINS) a la que pertenece recipe_id,
# o [] si es un bloque apilable sin progresión por niveles.
func _tier_chain_of(recipe_id: String) -> Array:
	for fam: String in TIER_CHAINS:
		if recipe_id in TIER_CHAINS[fam]:
			return TIER_CHAINS[fam]
	return []


# Siguiente mejora disponible de una cadena: el primer tier por encima
# del más alto que ya tenga el jugador (o el último, si está al máximo).
func _next_tier(chain: Array, inv: Dictionary) -> String:
	var highest := -1
	for i in chain.size():
		if int(inv.get(chain[i], 0)) > 0:
			highest = i
	return chain[mini(highest + 1, chain.size() - 1)]


func _do_craft(recipe_id: String, peer_id: int) -> void:
	if not RECIPES.has(recipe_id):
		return
	var inv: Dictionary = inventories.get(peer_id, {})
	# Equipo (picos/espadas/armaduras) es único; bloques son apilables
	var is_unique := recipe_id.begins_with("pico_") or recipe_id.begins_with("espada_") or recipe_id.begins_with("armadura_")
	if is_unique and int(inv.get(recipe_id, 0)) > 0:
		_toast_to(peer_id, "Ya tienes: %s" % RECIPES[recipe_id].nombre)
		return
	# Mejora por niveles: para el tier N+1 hace falta tener ya el tier N
	var chain := _tier_chain_of(recipe_id)
	if not chain.is_empty():
		var idx := chain.find(recipe_id)
		if idx > 0 and int(inv.get(chain[idx - 1], 0)) <= 0:
			_toast_to(peer_id, "Primero fabrica: %s" % RECIPES[chain[idx - 1]].nombre)
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


## Un nido (T_NEST) fue destruido por un jugador (Fase 10): deja de
## generar enemigos de inmediato. Lo llama world._do_hit al minarlo.
func on_nest_destroyed(coord: Vector2i) -> void:
	if npc_mgr != null:
		npc_mgr.forget_nest(coord)


# -------------------------------------------------------------
# BLOQUE 3 "MUNDO VIVO II" — EXPLORACIÓN (server-authoritative; lo
# llaman las ramas T_CHEST/T_SKULL de world._do_hit al minar el tile).
# -------------------------------------------------------------
## Cofre de recursos: reparte botín según el bioma de su posición
## (CHEST_LOOT) + unos Núcleos, y avisa solo al jugador que lo abrió.
func open_chest(miner_id: int, coord: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var pos := Vector2(coord.x * world.TILE, coord.y * world.TILE)
	var zone := _zone_at(pos)
	var loot: Dictionary = CHEST_LOOT.get(zone, CHEST_LOOT["superficie"])
	var resumen: Array[String] = []
	for item: String in loot:
		var rango: Array = loot[item]
		var n := randi_range(int(rango[0]), int(rango[1]))
		for _i in n:
			add_item(miner_id, item)
		if n > 0:
			resumen.append("%d %s" % [n, ITEM_NAMES.get(item, item)])
	add_coins(miner_id, randi_range(CHEST_COINS[0], CHEST_COINS[1]))
	_toast_to(miner_id, "📦 Cofre: %s" % ", ".join(resumen))
	# Bloque 5: estallido dorado en TODOS los peers al abrirse el cofre
	_broadcast_event_fx(_cell_center(coord), Color("f0c84a"), true)


## Calavera (estilo Halo): elige una de las 5 variantes al azar y aplica
## su efecto. Unas favorecen al jugador, otras a los enemigos — no se sabe
## hasta excavarla. El aviso va a TODOS (su suerte cambia la partida).
func excavate_skull(miner_id: int, coord: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var skull: Dictionary = SKULLS.pick_random()
	var p: Node2D = players.get(miner_id)
	match str(skull.efecto):
		"monedas":
			add_coins(miner_id, COIN_NEST * 3)
		"cura":
			heal_player(miner_id, SKULL_HEAL)
		"botin":
			for item: String in ["wood", "stone", "ore", "cristal"]:
				for _i in randi_range(2, 5):
					add_item(miner_id, item)
		"horda":
			if p != null and npc_mgr != null:
				for _i in 3:
					npc_mgr.spawn_near("normal", p)
		"bestia":
			if p != null and npc_mgr != null:
				npc_mgr.spawn_near("grande", p)
	_broadcast_toast(str(skull.aviso))
	# Bloque 5: estallido verde (buena) o rojo (mala) en TODOS los peers
	var col := Color("4ae07a") if bool(skull.buena) else Color("e04a3a")
	_broadcast_event_fx(_cell_center(coord), col, true)


## Centro en píxeles de una celda del mundo (para FX).
func _cell_center(coord: Vector2i) -> Vector2:
	return Vector2(coord.x * world.TILE + world.TILE * 0.5, coord.y * world.TILE + world.TILE * 0.5)


# -------------------------------------------------------------
# BLOQUE 5 "IDENTIDAD VISUAL Y SONORA": FX cosmético de evento difundido
# a todos los peers (cofre/calavera). 100% visual y local en cada cliente
# (usa world.fx): nunca toca estado del juego (GDD §16).
# -------------------------------------------------------------
func _broadcast_event_fx(pos: Vector2, color: Color, ring: bool) -> void:
	event_fx.rpc(pos, color, ring)
	_event_fx(pos, color, ring)


@rpc("authority", "call_remote", "unreliable")
func event_fx(pos: Vector2, color: Color, ring: bool) -> void:
	_event_fx(pos, color, ring)


func _event_fx(pos: Vector2, color: Color, ring: bool) -> void:
	if world == null or world.fx == null:
		return
	world.fx.burst(pos, color, 18, 200.0)
	if ring:
		world.fx.ring(pos, 70.0, color)


## Cura a un jugador (Bloque 3): sube su vida hasta PLAYER_MAX_HP y la
## sincroniza (mismo patrón push que damage_player / la regeneración).
func heal_player(peer_id: int, amount: int) -> void:
	if not multiplayer.is_server() or not players.has(peer_id):
		return
	var hp: int = mini(player_hp.get(peer_id, PLAYER_MAX_HP) + amount, PLAYER_MAX_HP)
	player_hp[peer_id] = hp
	if peer_id == 1:
		if not dedicated:
			_set_hp(hp)
	else:
		update_health.rpc_id(peer_id, hp)


## Estadística de bajas de la run (Fase 9, pulido) — la llaman las dos
## rutas de muerte de npc_manager (golpe del jugador y daño ambiental).
## SOLO servidor. Derrotar a CUALQUIER jefe (Fase 10: roster variable)
## se anuncia a todos con su nombre propio.
func count_kill(kind: String) -> void:
	if not multiplayer.is_server():
		return
	run_kills += 1
	if kind in BOSS_KINDS:
		var nombre := str(npc_mgr.KINDS.get(kind, {}).get("nombre", "Jefe"))
		_broadcast_toast("⚔️ ¡%s derrotado!" % nombre)


## Texto del aviso de jefe de la run (Fase 10): nombre + táctica para
## que el jugador empiece a planear su defensa desde el minuto cero.
func _boss_announcement(kind: String = run_boss_kind) -> String:
	var info: Dictionary = npc_mgr.KINDS.get(kind, {})
	var nombre := str(info.get("nombre", "Jefe"))
	var hint := str(BOSS_HINTS.get(kind, ""))
	return "👹 Jefe de esta run: %s — %s" % [nombre, hint]


## Banner dedicado (Bloque 1 "Mundo vivo"): más vistoso y duradero que
## el toast genérico, no compite con "Partida creada" ni avisos posteriores.
@rpc("authority", "call_remote", "reliable")
func show_boss_announcement(kind: String) -> void:
	_show_boss_announcement(kind)


func _show_boss_announcement(kind: String) -> void:
	_boss_announce_label.text = _boss_announcement(kind)
	_boss_announce_panel.show()
	_boss_announce_panel.modulate.a = 1.0
	_boss_announce_life = BOSS_ANNOUNCE_LIFE
	Sfx.play("jefe")


func _broadcast_boss_announcement(kind: String) -> void:
	show_boss_announcement.rpc(kind)
	_show_boss_announcement(kind)


## Texto del banner de evolución de jefe (Bloque 2 "Progresión elemental"):
## reutiliza el mismo banner que el anuncio inicial para que la mutación del
## jefe (npc_mgr.evolve_boss) no pase desapercibida en el ruido de toasts.
func _boss_evolution_text(new_kind: String) -> String:
	var info: Dictionary = npc_mgr.KINDS.get(new_kind, {})
	var nombre := str(info.get("nombre", "Jefe"))
	var hint := str(BOSS_HINTS.get(new_kind, ""))
	return "🔥 ¡El jefe ha evolucionado! Ahora es: %s — %s" % [nombre, hint]


@rpc("authority", "call_remote", "reliable")
func show_boss_evolution(new_kind: String) -> void:
	_show_boss_evolution(new_kind)


func _show_boss_evolution(new_kind: String) -> void:
	_boss_announce_label.text = _boss_evolution_text(new_kind)
	_boss_announce_panel.show()
	_boss_announce_panel.modulate.a = 1.0
	_boss_announce_life = BOSS_ANNOUNCE_LIFE
	Sfx.play("jefe")


func _broadcast_boss_evolution(new_kind: String) -> void:
	show_boss_evolution.rpc(new_kind)
	_show_boss_evolution(new_kind)


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
		if bool(mode_cfg.death_ends_run):
			# Fase 9: morir en un modo con run termina la run (sin respawn).
			hp = 0
			player_hp[peer_id] = hp
			if peer_id == 1:
				if not dedicated:
					_set_hp(hp)
			else:
				update_health.rpc_id(peer_id, hp)
			_end_run(false)
			return
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
			players[peer_id].position = pos
			players[peer_id].velocity = Vector2.ZERO
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
		me._target_pos = pos
		me._target_vel = Vector2.ZERO


func _set_hp(hp: int) -> void:
	if hp < _my_hp:
		Sfx.play("dano")
		var me: Node2D = players.get(multiplayer.get_unique_id())
		if me != null and world != null and world.fx != null:
			world.fx.burst(me.position, Color(0.9, 0.2, 0.2), 10, 150.0)
	elif hp > _my_hp and _my_hp > 0:
		# Curación (regen/fogata): chispas verdes suaves — ver que la
		# fogata te cura hace legible la mecánica (Fase 7, pulido)
		var me2: Node2D = players.get(multiplayer.get_unique_id())
		if me2 != null and world != null and world.fx != null:
			world.fx.burst(me2.position + Vector2(0, -20), Color(0.4, 0.95, 0.5), 4, 60.0)
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
# PRESIÓN AMBIENTAL (Bloque 1 "Mundo vivo", anti-turtling): vivir en
# cielo/cueva/profundo sin un fuerte propio cerca atrae enemigos —
# "superficie" no genera presión (ya cubierta por las oleadas nocturnas).
# -------------------------------------------------------------
func _zone_at(pos: Vector2) -> String:
	var y := floori(pos.y / world.TILE)
	if y < world.SKY_ROWS:
		return "cielo"
	if y >= world.H - 1 - world.DEEP_ROWS:
		return "profundo"
	if y >= world.SKY_ROWS + UNDERGROUND_BAND:
		return "cueva"
	return "superficie"


## Bloques de FORT_TILES propios del jugador en un radio de FORT_RADIUS.
func _has_fort(pos: Vector2) -> bool:
	var cx := floori(pos.x / world.TILE)
	var cy := floori(pos.y / world.TILE)
	var n := 0
	for dx in range(-FORT_RADIUS, FORT_RADIUS + 1):
		for dy in range(-FORT_RADIUS, FORT_RADIUS + 1):
			if FORT_TILES.has(world.tiles.get(Vector2i(cx + dx, cy + dy), 0)):
				n += 1
				if n >= FORT_MIN_BLOCKS:
					return true
	return false


## Cada PRESSURE_CHECK_EVERY segundos: si el jugador lleva ZONE_PRESSURE_TIME
## seguidos en cielo/cueva/profundo sin fuerte cerca, dispara una presión.
## Telegraph: a los PRESSURE_WARN_TIME llega un aviso ⚠️ para poder reaccionar
## (fortificar o subir). Reincidir sin salir de la zona ESCALA la presión:
## cada disparo trae un enemigo más (hasta PRESSURE_MAX_SPAWNS).
func _update_zone_pressure(pid: int) -> void:
	var p: Node2D = players[pid]
	var zone := _zone_at(p.position)
	var st: Dictionary = _zone_pressure.get(pid, {"zone": "", "t": 0.0, "warned": false, "level": 0})
	if zone != st.zone:
		st = {"zone": zone, "t": 0.0, "warned": false, "level": 0}
	if zone == "superficie" or _has_fort(p.position):
		st.t = 0.0
		st.warned = false
		st.level = 0   # hacer lo correcto perdona la reincidencia
	else:
		st.t += PRESSURE_CHECK_EVERY
		if not st.warned and st.t >= PRESSURE_WARN_TIME:
			st.warned = true
			_toast_to(pid, "⚠️ Algo te acecha... fortifica o vuelve a la superficie")
		if st.t >= ZONE_PRESSURE_TIME:
			st.t = 0.0
			st.warned = false
			st.level = int(st.level) + 1
			_trigger_zone_pressure(pid, zone, p, mini(int(st.level), PRESSURE_MAX_SPAWNS))
	_zone_pressure[pid] = st


## Aviso + enemigos cercanos según la zona (resuelve también el bug de
## islas aéreas sin enemigos: spawn_near coloca el volador junto al jugador).
func _trigger_zone_pressure(pid: int, zone: String, p: Node2D, count: int = 1) -> void:
	var kind := ""
	match zone:
		"cielo":
			_toast_to(pid, "🌬️ Algo te ha seguido hasta las alturas...")
			kind = "murcielago"
		"cueva":
			_toast_to(pid, "🦇 No conviene quedarse tanto en la oscuridad...")
			kind = "topo"
		"profundo":
			_toast_to(pid, "🔥 El calor del núcleo despierta algo cerca...")
			kind = "taladro"
	if kind.is_empty():
		return
	for i in count:
		npc_mgr.spawn_near(kind, p)


## Bloque 2 "Progresión elemental" — JEFES ADAPTATIVOS (rediseño: evolución
## INTELIGENTE, no aleatoria): por cada jefe vivo, mira la zona del jugador
## más cercano. Si el jefe activo no es la variante capaz de alcanzar esa zona
## (`ZONE_BOSS_KIND`: cielo→murciélago volador, cueva/profundo→topo excavador,
## superficie→corredor veloz), acumula tiempo y al llegar a BOSS_EVOLVE_TIME
## muta EXACTAMENTE a esa variante — el jefe persigue al jugador a donde vaya.
## Si la zona cambia o ya es la variante ideal, el contador se resetea.
func _update_boss_evolution() -> void:
	for id: int in npc_mgr.npcs:
		var n: Dictionary = npc_mgr.npcs[id]
		var kind := str(n.get("kind", ""))
		if not bool(npc_mgr.KINDS.get(kind, {}).get("boss", false)):
			continue
		var pid: int = npc_mgr._nearest_player(n.pos)
		if pid == -1:
			_boss_evolve.erase(id)
			continue
		var zone := _zone_at(players[pid].position)
		var ideal := str(ZONE_BOSS_KIND.get(zone, ""))
		if ideal.is_empty() or ideal == kind:
			_boss_evolve.erase(id)
			continue
		var t: float = float(_boss_evolve.get(id, 0.0)) + PRESSURE_CHECK_EVERY
		if t >= BOSS_EVOLVE_TIME:
			# Muta a la variante que SÍ puede alcanzar al jugador en su zona
			_boss_evolve.erase(id)
			npc_mgr.evolve_boss(id, ideal)
			_broadcast_boss_evolution(ideal)
		else:
			_boss_evolve[id] = t


# -------------------------------------------------------------
# CICLO DÍA/NOCHE (Fase 6, ROADMAP.md) — SOLO el servidor cambia
# de fase; los clientes la reciben por RPC. La luz del mundo
# (world.daylight) y las oleadas nocturnas cuelgan de esto.
# -------------------------------------------------------------
func _set_phase(night: bool) -> void:
	is_night = night
	_phase_t = float(mode_cfg.night_seconds) if night else float(mode_cfg.day_seconds)
	_dusk_warned = false
	if night:
		night_number += 1
		_broadcast_toast("🌙 ¡Noche %d! Resiste hasta el amanecer" % night_number)
		var npcs_node: Node2D = get_node_or_null("NPCs")
		if npcs_node != null:
			npcs_node.night_wave(night_number)
			if night_number % int(mode_cfg.boss_every) == 0:
				var nombre := str(npcs_node.KINDS.get(run_boss_kind, {}).get("nombre", "Jefe"))
				_broadcast_toast("👹 ¡%s ha llegado! (Noche %d)" % [nombre, night_number])
	else:
		if night_number > 0:
			_broadcast_toast("☀️ Amaneció — sobreviviste la noche %d" % night_number)
			var reward := int(mode_cfg.night_reward_base) + int(mode_cfg.night_reward_step) * night_number
			for pid: int in players:
				add_coins(pid, reward)
			world.grow_trees()
		var goal := int(mode_cfg.nights_to_win)
		if goal > 0 and night_number == goal:
			_end_run(true)
			return
	apply_phase.rpc(is_night, night_number, _phase_t, game_mode, run_boss_kind)


@rpc("authority", "call_remote", "reliable")
func apply_phase(night: bool, n: int, t_left: float, mode: String, boss_kind: String) -> void:
	is_night = night
	night_number = n
	_phase_t = t_left
	set_mode(mode)
	run_boss_kind = boss_kind


## 1.0 = pleno día, 0.0 = plena noche; amanecer/atardecer de ~12 s.
## world.daylight() delega aquí (la hora del sistema ya no manda).
func daylight_factor() -> float:
	var total := float(mode_cfg.night_seconds) if is_night else float(mode_cfg.day_seconds)
	var k := clampf((total - _phase_t) / 12.0, 0.0, 1.0)
	return (1.0 - k) if is_night else k


## Progreso 0..1 de la fase actual (posición del sol/luna en el cielo).
func phase_progress() -> float:
	var total := float(mode_cfg.night_seconds) if is_night else float(mode_cfg.day_seconds)
	return clampf(1.0 - _phase_t / total, 0.0, 1.0)


func _update_phase_label() -> void:
	if _phase_label == null or world == null:
		return
	var mm := int(_phase_t) / 60
	var ss := int(_phase_t) % 60
	var goal := int(mode_cfg.nights_to_win)
	if is_night:
		var meta := (" de %d" % goal) if goal > 0 else ""
		_phase_label.text = "🌙 Noche %d%s — %d:%02d" % [night_number, meta, mm, ss]
	else:
		_phase_label.text = "☀️ Día %d — %d:%02d" % [night_number + 1, mm, ss]


# -------------------------------------------------------------
# ESTRUCTURA DE RUN (Fase 9, ROADMAP.md): victoria al sobrevivir
# SURVIVAL_NIGHTS noches o derrota al morir en supervivencia.
# SOLO el servidor decide; los clientes reciben run_ended por RPC
# y vuelven a sandbox vía apply_phase (lo manda _reset_run).
# -------------------------------------------------------------
func _end_run(victory: bool) -> void:
	if not multiplayer.is_server() or _run_over:
		return
	_run_over = true
	var nights := night_number
	var kills := run_kills
	if victory:
		for pid: int in players:
			add_coins(pid, int(mode_cfg.victory_bonus))
	run_ended.rpc(victory, nights, kills)
	if not dedicated:
		_apply_run_ended(victory, nights, kills)
	_reset_run()


@rpc("authority", "call_remote", "reliable")
func run_ended(victory: bool, nights: int, kills: int) -> void:
	_apply_run_ended(victory, nights, kills)


func _apply_run_ended(victory: bool, nights: int, kills: int) -> void:
	if _run_panel == null:
		return
	var recursos := (int(_my_inv.get("dirt", 0)) + int(_my_inv.get("stone", 0))
		+ int(_my_inv.get("wood", 0)) + int(_my_inv.get("ore", 0)))
	_run_title.text = "🏆 ¡VICTORIA!" if victory else "💀 FIN DE LA RUN"
	_run_title.add_theme_color_override("font_color",
		Color(0.95, 0.8, 0.25) if victory else Color(0.9, 0.35, 0.3))
	# El borde del panel toma el color del resultado (oro / rojo)
	var sb := _run_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = Color(0.95, 0.78, 0.2, 0.8) if victory else Color(0.85, 0.2, 0.2, 0.8)
		sb.set_border_width_all(2)
	var body := "🌙 Noches sobrevividas: %d\n⚔️ Enemigos abatidos: %d\n📦 Recursos reunidos: %d\n🪙 Núcleos: %d" % [
		nights, kills, recursos, _my_coins]
	if victory:
		body += "\n✨ +%d de bono por la victoria" % int(mode_cfg.victory_bonus)
	_run_body.text = body
	_run_panel.show()
	# Celebración o lamento (solo visual y local)
	Sfx.play("victoria" if victory else "derrota")
	if victory:
		var me: Node2D = players.get(multiplayer.get_unique_id())
		if me != null and world != null and world.fx != null:
			for i in 5:
				world.fx.burst(me.position + Vector2(randf_range(-160, 160), randf_range(-200, -40)),
					Color.from_hsv(randf(), 0.7, 1.0), 18, 230.0)
			world.fx.ring(me.position, 220.0, Color(0.95, 0.8, 0.25))


## Reinicia el reloj de partida y reaparece a todos en modo sandbox
## (gameplay libre tras ganar o perder una run de supervivencia).
func _reset_run() -> void:
	is_night = false
	night_number = 0
	set_mode("sandbox")
	_phase_t = float(mode_cfg.day_seconds)
	_dusk_warned = false
	_run_over = false      # lista para una futura run sin reiniciar la app
	run_kills = 0
	_zone_pressure.clear()
	_boss_evolve.clear()
	if npc_mgr != null:
		npc_mgr.npcs.clear()
	if tower_mgr != null:
		tower_mgr.arrows.clear()
	for pid: int in players:
		var pos: Vector2 = world.surface_spawn(randi_range(4, world.W - 5))
		player_hp[pid] = PLAYER_MAX_HP
		players[pid].position = pos
		players[pid].velocity = Vector2.ZERO
		if pid == 1:
			if not dedicated:
				_set_hp(PLAYER_MAX_HP)
		else:
			respawn_player.rpc_id(pid, pos)
			update_health.rpc_id(pid, PLAYER_MAX_HP)
	apply_phase.rpc(is_night, night_number, _phase_t, game_mode, run_boss_kind)


# -------------------------------------------------------------
# PERSISTENCIA (GDD §14): JSON comprimido con gzip
# Nota: se guarda el mundo + el inventario del host. Inventarios
# por jugador requieren cuentas (los peer-ids cambian por sesión)
# y llegarán con el backend (Fase 5).
# -------------------------------------------------------------
func save_game() -> void:
	# Los modos con run (supervivencia/asedio) NO guardan: el save es del sandbox
	if world == null or not bool(mode_cfg.save_allowed):
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
	elif text.begins_with("👹"):  # llega el jefe: rugido (Fase 9)
		Sfx.play("jefe")
	elif text.begins_with("🌙"):  # cae la noche: tono grave (Fase 6, pulido)
		Sfx.play("noche")
	elif text.begins_with("☀️"):  # amanece: campanada suave
		Sfx.play("amanecer")
	elif text.begins_with("🕳️"):  # un nido apareció: pulso subterráneo
		Sfx.play("nido")
	elif text.begins_with("⚠️"):  # aviso de presión ambiental: tono grave (Bloque 1)
		Sfx.play("noche")
	elif text.begins_with("🌬️") or text.begins_with("🦇") or text.begins_with("🔥"):
		Sfx.play("invasion")       # la presión ambiental se dispara (Bloque 1)
	elif text.begins_with("📦"):  # cofre abierto o calavera del botín (Bloque 5)
		Sfx.play("cofre")
	elif text.begins_with("💎"):  # calavera del tesoro: lluvia de Núcleos (Bloque 5)
		Sfx.play("moneda")
	elif text.begins_with("💚"):  # calavera vital: sanación (Bloque 5)
		Sfx.play("cura")
	elif text.begins_with("😡"):  # calavera de la furia: horda (Bloque 5)
		Sfx.play("maldicion")


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
	_zone_pressure.erase(id)
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
	# Barra de items PLEGABLE: se mira `_slots_box` (la fila de slots) y el
	# botón `_items_toggle`, NO el `_hud_box` entero — así, al plegar la barra,
	# `_slots_box` se oculta y la franja inferior queda libre para minar.
	for ctrl: Control in [_info, _slots_box, _items_toggle, _craft_btn, _craft_panel,
			_shop_btn, _shop_panel, _hp_panel, _toast_panel, _run_panel,
			_settings_btn, _settings_panel]:
		if ctrl != null and ctrl.visible and ctrl.get_global_rect().has_point(p):
			return true
	return _menu.visible


## La CONSTRUCCIÓN de la interfaz vive en ui_builder.gd (capa de
## presentación, ver ARQUITECTURA.md): main solo delega y conserva
## las referencias (_menu, _hp_bar, ...) porque es dueño del estado.
func _build_ui() -> void:
	UiBuilderScript.build_lobby(self)


func _show_hud() -> void:
	UiBuilderScript.build_hud(self)
	_apply_control_mode()


# -------------------------------------------------------------
# AJUSTES DE CONTROL — móvil/PC (local, per-device; NO viaja por red
# ni va en el save de partida — ver SETTINGS_PATH). "auto" detecta si
# hay pantalla táctil. En PC se desactiva el joystick virtual para que
# el clic del ratón (emulate_touch_from_mouse) mine en cualquier zona,
# incluida la esquina inferior-izquierda que el joystick acapararía.
# -------------------------------------------------------------
func _detect_platform() -> String:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return "movil"
	return "pc"


## Modo realmente en uso: el detectado si está en "auto", o el elegido.
func effective_control_mode() -> String:
	return _detect_platform() if control_mode == "auto" else control_mode


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var m := str(cfg.get_value("control", "mode", "auto"))
	if m in CONTROL_MODES:
		control_mode = m


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("control", "mode", control_mode)
	cfg.save(SETTINGS_PATH)


func set_control_mode(mode: String) -> void:
	if mode not in CONTROL_MODES:
		return
	control_mode = mode
	_save_settings()
	_apply_control_mode()
	_refresh_settings()


## Configura el joystick virtual según el modo efectivo (si el HUD existe).
func _apply_control_mode() -> void:
	if _joystick != null and _joystick.has_method("set_enabled"):
		_joystick.set_enabled(effective_control_mode() == "movil")


func _on_settings_pressed() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = not _settings_panel.visible
	if _settings_panel.visible:
		_refresh_settings()


# --- Barra de items PLEGABLE (petición del jugador): plegarla deja la franja
# inferior-derecha libre para minar/colocar debajo (antes acaparaba esos taps).
func _toggle_items() -> void:
	if _slots_box == null:
		return
	_slots_box.visible = not _slots_box.visible
	_refresh_items_toggle()


func _refresh_items_toggle() -> void:
	if _items_toggle == null or _slots_box == null:
		return
	# ◀ = desplegado (clic para plegar hacia la derecha); ▶ = plegado (clic para mostrar)
	_items_toggle.text = "◀" if _slots_box.visible else "🎒▶"


func _refresh_settings() -> void:
	if _settings_panel == null:
		return
	for mode: String in _control_buttons:
		(_control_buttons[mode] as Button).button_pressed = (mode == control_mode)
	var eff := effective_control_mode()
	var det_txt := "móvil (pantalla táctil)" if _detect_platform() == "movil" else "PC (teclado/ratón)"
	var eff_txt := "📱 joystick táctil" if eff == "movil" else "🖥️ teclado (WASD/flechas) + ratón"
	_settings_hint.text = "Dispositivo detectado: %s\nControl activo: %s" % [det_txt, eff_txt]


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
	for key: String in _craft_rows:
		var row: Dictionary = _craft_rows[key]
		var lbl: Label = row.label
		var btn: Button = row.button
		# Filas de equipo (pico/espada/armadura): "chain" guarda la cadena
		# de tiers; rid es la SIGUIENTE mejora, no la receta de la fila.
		var has_chain := row.has("chain")
		var rid: String = _next_tier(row.chain, _my_inv) if has_chain else key
		var maxed := has_chain and int(_my_inv.get(row.chain[-1], 0)) > 0
		var costo: Dictionary = RECIPES[rid].costo
		var partes := []
		var alcanza := true
		for item: String in costo:
			var tengo := int(_my_inv.get(item, 0))
			var necesito := int(costo[item])
			if tengo < necesito:
				alcanza = false
			partes.append("%s %d/%d" % [ITEM_NAMES[item].to_lower(), tengo, necesito])
		if maxed:
			lbl.text = "✓ %s — nivel máximo" % RECIPES[rid].nombre
			btn.disabled = true
		elif has_chain:
			lbl.text = "%s — %s" % [RECIPES[rid].nombre, ", ".join(partes)]
			btn.disabled = not alcanza
		else:
			var count := int(_my_inv.get(rid, 0))
			var prefix := "(%d) " % count if count > 0 else ""
			lbl.text = "%s%s — %s" % [prefix, RECIPES[rid].nombre, ", ".join(partes)]
			btn.disabled = not alcanza


func _refresh_info() -> void:
	if _info != null:
		# Línea 1: Núcleos. Línea 2: CONTADOR DE MINERALES (todos, con icono).
		var mins := ""
		for mat: String in MINERAL_ICONS:
			mins += "%s %d   " % [MINERAL_ICONS[mat], int(_my_inv.get(mat, 0))]
		_info.text = "🪙 %d\n%s" % [_my_coins, mins.strip_edges()]
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
