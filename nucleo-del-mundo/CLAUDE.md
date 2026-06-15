# CLAUDE.md — Núcleo del Mundo

Juego sandbox 2D multijugador para Android, en **Godot 4.3+ / GDScript**.
**Identidad actual** (ver `Evolución de la Visión del Proyecto.md`): sandbox de
supervivencia por noches — de día recolectas y construyes, de noche defiendes;
el objetivo es sobrevivir X noches. La base (murallas, torres, trampas) es una
vía de progresión tan importante como el equipo. El plan por fases está en
`ROADMAP.md`; el GDD original sigue siendo la referencia técnica de los sistemas
base. Estado: Fases 1-10 completadas (core sandbox + monetización + arte/SFX
procedurales + ciclo día/noche jugable + defensa pasiva con murallas y fogatas
+ defensa activa con trampas de pinchos y torres de flechas + estructura de
run: jefe cada 5 noches, recompensa de Núcleos por noche, victoria/derrota con
panel de resumen + bestiario expandido: taladro/topo que excavan, fusión de
slimes, embistedor con embestida, nidos que escupen enemigos, y un roster de
4 jefes anunciado al iniciar la run). La Fase 11+ (campañas/mundos temáticos)
está bloqueada hasta validar diversión con jugadores reales (ver ROADMAP.md).
Fuera de esa numeración (igual que el refactor de 3 capas): el mundo se
amplió a 200×90 con cielo y subsuelo profundo más grandes, ambos biomas
comparten un recurso nuevo (`T_CRYSTAL`/`cristal` → `pico_cristal`, el mejor
pico) y los árboles vuelven a crecer cada amanecer (`world.grow_trees()`).
**Bloque 1 "Mundo vivo"** (2026-06-12, primero de 4 bloques acordados con el
jugador): cada bioma tiene ahora minerales y tinte de color propios (aéreo:
`T_FEATHER`/`T_AETHER`; profundo: `T_DIAMOND`/`T_EMBER` + "ríos" de
`T_WATER` que ralentizan al pisarlos), un sistema de "presión ambiental"
castiga vivir en cielo/cueva/profundo sin un fuerte propio cerca (aviso ⚠️
previo y enemigos junto al jugador, escalando si reincide — resuelve las
islas sin amenazas) y el jefe de la run se anuncia en un banner dedicado de
8s.
**Bloque 2 "Progresión elemental y jefes adaptativos"** (2026-06-13): el agua
ahora forma lagos GRANDES y CONTENIDOS (`world._spawn_lakes`, blobs de 18-40
tiles dentro de la banda profunda) que ralentizan tanto al jugador como a los
NPC terrestres (`npc_manager._move`, mismo `WATER_SLOW`). Los 4 minerales del
Bloque 1 ya tienen uso: recetas "mega" de diamante (`espada_diamante`,
`armadura_diamante`, cierran sus `TIER_CHAINS` tras la dorada) y una
`torre_mega` (`T_TOWER_MEGA`, más alcance/daño/cadencia que la torre normal).
El jefe de la run ahora es ADAPTATIVO: si el jugador más cercano lleva
`BOSS_EVOLVE_TIME=60s` en una zona que el jefe activo no puede amenazar
(`main.ZONE_BOSS_KIND`: cielo→murciélago, cueva/profundo→topo,
superficie→corredor), el jefe MUTA a esa variante conservando vida
proporcional (`npc_mgr.evolve_boss`) y lo anuncia con el banner dedicado.
**Bloque 3 "Mundo vivo II — exploración y eventos"** (2026-06-13): 3 tiles
nuevos de exploración — `T_RAIL` (vía de tren abandonada en galerías
excavadas del subsuelo, da madera x2 al minarla), `T_CHEST` (cofre con
botín por bioma vía `main.open_chest`) y `T_SKULL` (calavera estilo Halo:
5 variantes ocultas, todas iguales hasta excavarlas; `main.excavate_skull`
elige al azar un efecto bueno —cura/Núcleos/botín— o malo —horda/bestia—).
Además los árboles ahora crecen también en las islas aéreas (`_spawn_islands`).
**Bloque 4 "Bestiario vivo"** (2026-06-13): 3 enemigos con comportamiento
propio en `npc_manager.KINDS` — `espectro` (`ghost`: vuela y ATRAVIESA los
muros, anti-turtling), `coracero` (`armor`: resta daño recibido, tanque) y
`sanador` (`heals`: cura a los enemigos cercanos cada `HEAL_CD`) — cada uno
con un material de bioma como botín (`drop`: esencia/ascua/pluma). Entran en
las oleadas nocturnas escalando con la noche.
**Bloque 5 "Identidad visual y sonora"** (2026-06-13, último bloque): pulido
audiovisual del contenido nuevo — SFX procedurales de `cofre`/`cura`/
`maldicion` cableados por prefijo de emoji del toast (📦💎💚😡), sonido del
pulso del `sanador`, y un FX de evento difundido a todos los peers
(`main.event_fx`: estallido dorado al abrir un cofre, verde/rojo al excavar
una calavera buena/mala). Con esto los **Bloques 1-5 están completos** (ver
ROADMAP.md); el siguiente hito ya solo es validar diversión con jugadores
reales antes de la Fase 11+.
El plan de negocio y el camino a cobrar dinero real está en `MONETIZACION.md`.
**El código está separado en 3 CAPAS (ver `ARQUITECTURA.md`):** núcleo/motor
(world, player, npc_manager, tower_manager, red) → reglas de juego
(`game_modes.gd` data-driven + main.gd como orquestador; modos: survival,
asedio, sandbox) → presentación (`ui_builder.gd`, atlas, sfx, fx). Añadir un
modo = añadir una entrada a `GameModes.MODES`; las campañas (Fase 11+) serán
secuencias de esas configs.

## Comandos

```bash
# Validar que el proyecto parsea sin errores (correr SIEMPRE tras editar .gd)
godot --headless --path . --quit-after 2

# Servidor dedicado
godot --headless --path . -- --server

# Smoke test headless (crafting, HUD, regen, invasión, meteoro) — exit code 0 = OK
godot --headless --path . res://tests/smoke_craft.tscn --quit-after 10

# Tests unitarios (cuando GUT esté instalado en addons/gut)
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Los tests headless van como escena (`tests/*.tscn` + script `extends Node2D` con la lógica
en `_ready()`): un `--script` pelado con `extends SceneTree` NO carga los autoloads
(`Net`/`Sfx`/`Atlas`) y falla con "Identifier not found".

El binario `godot` debe estar en el PATH. No hay paso de build: Godot interpreta los .gd.
Las pruebas multijugador manuales se hacen desde el editor: Depurar → Ejecutar múltiples instancias.

## Arquitectura (NO romper estas reglas)

**Regla de oro — autoridad del servidor (GDD §16):** el cliente NUNCA modifica estado del
juego (mundo, inventario, vida, NPCs) por su cuenta. Todo cambio sigue el patrón:

```
cliente: try_X() → request_X.rpc_id(1, ...)        # petición
servidor: request_X() → valida → _do_X()           # única fuente de verdad
servidor: apply_X.rpc(...) + efecto local           # confirmación a todos
```

Si el que actúa es el host (peer 1), `try_X()` llama `_do_X()` directo. Todo `request_*`
empieza con `if not multiplayer.is_server(): return` y usa `multiplayer.get_remote_sender_id()`
para atribuir la acción — jamás confiar en ids enviados por el cliente.

**Movimiento server-authoritative + predicción/reconciliación (GDD §10.2):** el servidor
simula la física de TODOS los jugadores (incluidos los remotos) y es la ÚNICA fuente de
verdad de `players[pid].position` — cierra la última excepción a la regla de oro. Cada
cliente no-host predice localmente (sin cambios de game feel) y envía su input
(`dir_x`, `jump`) a 20 Hz vía `send_input.rpc_id(1, ...)`; el servidor aplica ese input
al nodo del peer remoto (`_process_remote_authority`) con la MISMA física
(`_simulate_step`, compartida con la predicción local) y difunde un snapshot
`{peer_id: [pos, vel, on_floor]}` a 20 Hz (`main.sync_players`, mismo patrón que
`npc_manager.sync_npcs`). `player.gd._process` tiene 3 casos: A) mi nodo → predicción
(`_process_local`); B) nodo remoto pero yo soy el servidor → `_process_remote_authority`;
C) nodo remoto en mi pantalla → lerp visual de siempre. El cliente reconcilia su propio
nodo con `_reconcile()`: error pequeño → corrección suave (lerp), error grande
(`RECONCILE_SNAP_DIST`) → snap total (teleport/respawn real), error mínimo
(`RECONCILE_MIN_ERROR`) → no corrige (evita jitter). El error se mide contra la posición
EXTRAPOLADA del snapshot (`pos + vel * RECONCILE_EXTRAPOLATION`): la predicción siempre
va ~un intervalo por delante del servidor y comparar contra la posición cruda frenaría
al que corre a tirones (rubber-banding). Detalles del input: el salto se retiene entre
envíos (`_jump_latch`, un tap < 50 ms no se pierde), congelado por streaming se envía
input NEUTRO (el servidor no sigue corriendo con input viejo), y `send_input` descarta
`dir_x` no finito (NaN envenenaría la física). El host (peer 1 == servidor) es el
caso degenerado: predicción == autoridad, sin reconciliación.

**El mundo es datos puros:** `world.tiles: Dictionary[Vector2i → int]`. Sin TileMap, sin nodos
de colisión. La física es AABB manual contra ese diccionario, resuelta por eje (X, luego Y).
Esto es deliberado (red, persistencia, chunks, testeo) — no migrar a física del motor.

**Chunks (GDD §2):** 16×16 tiles. El cliente pide chunks cercanos (`update_streaming`) y
descarga lejanos. Chunk no cargado = sólido + física del jugador congelada (`area_ready`).
Render: un `chunk_renderer.gd` por chunk; al cambiar un tile se redibuja solo su chunk.

**NPCs (GDD §12):** simulación 100% en servidor (`npc_manager.gd`), snapshot de posiciones
a 10 Hz por rpc unreliable. Los clientes solo dibujan. Nuevos enemigos siguen este patrón.

## Archivos

- `scripts/game_modes.gd` — CAPA DE REGLAS: modos de juego data-driven
  (`MODES`: duraciones día/noche, `nights_to_win`, `death_ends_run`,
  `save_allowed`, `boss_every`, `wave_base/step`, recompensas, `victory_bonus`).
  Solo datos + helpers puros. `main.set_mode(id)` carga `mode_cfg` (único
  punto de cambio: host, `apply_phase`, `_reset_run`); el resto del código lee
  `main.mode_cfg` en vez de constantes. El lobby se genera desde `LOBBY_ORDER`.
- `scripts/ui_builder.gd` — CAPA DE PRESENTACIÓN: construye lobby y HUD por
  código (`build_lobby(m)` / `build_hud(m)`, funcs estáticas que asignan las
  referencias `_menu`, `_hp_bar`, ... en main, que sigue siendo dueño del
  estado). Paleta de UI centralizada (COL_*). El menú de modos es data-driven.
  BLOQUE 1 "MUNDO VIVO": `build_hud` añade `_boss_announce_panel`/
  `_boss_announce_label` (banner centrado del anuncio de jefe,
  `MOUSE_FILTER_IGNORE`, fuera de `is_point_on_ui` como `_low_hp`/
  `_boss_panel`).
  BLOQUE 2 "PROGRESIÓN ELEMENTAL": la barra de items suma el slot
  `torre_mega`; el panel "Fabricar" pasa de 7 a 8 filas (3 familias de
  equipo + 5 bloques apilables: muralla/fogata/trampa/torre/torre_mega) —
  sigue siendo data-driven (`TIER_CHAINS` + `RECIPES` sin cadena), sin
  cambios estructurales en `build_hud`.
  BARRA DE ITEMS PLEGABLE (petición del jugador): los slots van dentro de
  una fila `bar` con un botón `m._items_toggle` (cableado a
  `m._toggle_items`) que oculta/muestra `m._slots_box`. Plegada, la franja
  inferior-derecha queda LIBRE para minar/colocar: `main.is_point_on_ui`
  mira `_info`/`_slots_box`/`_items_toggle` (NO el `_hud_box` entero), así
  que al ocultarse `_slots_box` esa zona deja de robar taps.
  CONTADOR DE MINERALES (petición del jugador): `main._refresh_info` arma el
  `_info` con Núcleos (línea 1) + todos los minerales preciosos con icono y
  conteo (línea 2, desde `main.MINERAL_ICONS`: ⛏️ore 🔷cristal 💎diamante
  🪶pluma 🌀esencia 🔥ascua) — antes solo se veía el mineral común.
  AJUSTES (control móvil/PC): `_build_settings_panel(m)` (llamado al final
  de `build_lobby`) crea un panel centrado compartido con el selector
  móvil/PC/auto (3 botones en un `ButtonGroup` que llaman
  `m.set_control_mode`) + `_settings_hint`; se añade a `_ui` una sola vez y
  PERSISTE en el HUD. El acceso son DOS botones "⚙️" cableados a
  `m._on_settings_pressed`: uno en el menú del lobby y uno compacto en el
  HUD (top-right, a la izquierda de Fabricar/Tienda). `build_hud` también
  guarda `m._joystick` (el joystick virtual) para que main lo active/
  desactive según el modo.
- `scripts/network_manager.gd` — autoload `Net`. Host/join ENet, señales de conexión.
- `scripts/sfx.gd` — autoload `Sfx`. SFX y música de fondo procedurales (WAV sintetizado
  al arrancar; la música es un loop suave Am–F–C–G, omitida en headless). 100% local y
  cosmético: nunca viaja por red ni toca estado del juego. Incluye jingles
  (`_make_jingle`) de victoria/derrota y sonidos de torre/pinchos/jefe/amanecer/noche;
  `main._show_toast` dispara sonido por PREFIJO de emoji del toast (☄️🛠️👾👹🌙☀️) —
  así el aviso y su sonido llegan juntos a todos los peers. Fase 10: sonidos
  "embestida" (embistedor/jefe_corredor), "fusion" (slimes fusionándose) y
  "nido" (toast 🕳️ al sembrarse un nido). Bloque 1 "Mundo vivo": "agua"
  (chapoteo al entrar al agua) y los prefijos ⚠️ (aviso de presión → "noche")
  y 🌬️🦇🔥 (presión disparada → "invasion"). Bloque 5 "Identidad visual y
  sonora": sonidos "cofre" (arpegio ascendente), "cura" (brillo suave, lo usa
  también el pulso del sanador en `npc_mgr._heal_fx`) y "maldicion"
  (presagio grave); prefijos 📦→"cofre", 💎→"moneda", 💚→"cura",
  😡→"maldicion" (la 👹 Calavera Maldita reusa el rugido "jefe").
- `scripts/main.gd` — ORQUESTADOR (capa de reglas): aplica el modo activo
  (`set_mode`/`mode_cfg`, de game_modes.gd) en el servidor. Lobby y HUD los
  CONSTRUYE ui_builder.gd (main delega en `_build_ui`/`_show_hud` y conserva
  las referencias). Spawn, inventarios (servidor), crafting
  (equipo único + bloques apilables: muralla/fogata/trampa/torre), vida/respawn en fogata
  más cercana + regeneración nocturna solo cerca de fogata (Fase 7), RELOJ DE PARTIDA
  día/noche (Fase 6: `is_night`, `night_number`, `_set_phase` dispara `night_wave`; solo
  el servidor cambia de fase), persistencia (gzip JSON en `user://nucleo_save.json.gz`;
  las runs de supervivencia NO guardan), scheduler (autosave, meteoro diurno con aviso),
  modo `--server`.
  ESTRUCTURA DE RUN (Fase 9): al amanecer (`_set_phase(false)`) reparte Núcleos por noche
  sobrevivida (`NIGHT_REWARD_BASE`/`NIGHT_REWARD_STEP`) y llama `world.grow_trees()`
  (repone madera — EXPANSIÓN DE MUNDO); `_end_run(victory)` (guardado por
  `_run_over`) decide victoria (`night_number == SURVIVAL_NIGHTS`, + `VICTORY_BONUS`) o
  derrota (muerte en supervivencia, sin respawn) — manda `run_ended.rpc(victory, noches,
  bajas)`, muestra `_run_panel` con el resumen (borde/título de color por resultado,
  jingle, fuegos artificiales en victoria) y luego `_reset_run()` vuelve todo a sandbox.
  PULIDO F9: `run_kills` (SOLO servidor, lo alimenta `count_kill()` desde npc_manager),
  barra de vida del JEFE en el HUD (`_boss_panel`, top-center, MOUSE_FILTER_IGNORE y
  fuera de `is_point_on_ui` como `_low_hp` — el ratio del jefe viaja en el snapshot),
  chispas verdes al curar en `_set_hp`.
  FASE 10 — ROSTER DE JEFES: `BOSS_KINDS` (jefe, jefe_murcielago, jefe_topo,
  jefe_corredor) + `BOSS_HINTS`; `_host()` elige `run_boss_kind` al azar y lo
  anuncia con un toast (`_boss_announcement()`, nombre + pista táctica) al crear
  la run y a cada peer que se une (`request_join`); `night_wave` invoca ese jefe
  al llegar `BOSS_EVERY`. `_boss_panel`/`_boss_label` ahora son genéricos: se
  activan con CUALQUIER `boss: true` vivo y muestran su nombre propio.
  `on_nest_destroyed(coord)` avisa a `npc_manager.forget_nest` y da `COIN_NEST`.
  MONETIZACIÓN: catálogo `SKINS`, Núcleos (`add_coins`), tienda 🛒 y perfiles `profiles`
  persistidos (v4).
  AJUSTES DE CONTROL (móvil/PC): `control_mode` (`"auto"`/`"movil"`/`"pc"`)
  es un ajuste LOCAL por dispositivo — NO viaja por red ni va en el save de
  partida; se persiste aparte en `SETTINGS_PATH` (`user://nucleo_settings.cfg`,
  ConfigFile) vía `_load_settings`/`_save_settings`. `_detect_platform()`
  (táctil → "movil", si no "pc") resuelve el modo `"auto"`;
  `effective_control_mode()` devuelve el modo en uso. `set_control_mode(m)`
  persiste y llama `_apply_control_mode()`, que activa/desactiva
  `_joystick` (`set_enabled`) según `effective_control_mode() == "movil"`:
  en PC el joystick virtual se APAGA para que el clic del ratón
  (`emulate_touch_from_mouse`) mine en cualquier zona, incluida la esquina
  inferior-izquierda que el joystick acapararía. El teclado se lee siempre
  (`player._process_local`), así que PC funciona con WASD/flechas + ratón.
  `_settings_panel`/`_settings_btn` están en `is_point_on_ui`; `_show_hud`
  reaplica el modo tras reconstruir el HUD.
  PANEL DE FABRICAR POR NIVELES: `TIER_CHAINS` agrupa el equipo único en
  3 familias (`pico`/`espada`/`armadura`, cada una una lista ordenada de
  `recipe_id`); el panel muestra UNA fila por familia (7 filas en total,
  3 familias + 4 bloques apilables) con la SIGUIENTE mejora disponible
  (`_next_tier`, ui_builder.gd). `_do_craft` exige tener el tier anterior
  para craftear el siguiente (no se salta de madera a dorado); los tiers
  previos se quedan en el inventario (no se borran — `get_tool_damage`/
  `get_attack_damage`/armadura ya eligen el mejor que tengas).
  BLOQUE 1 "MUNDO VIVO" — PRESIÓN AMBIENTAL (anti-turtling): cada
  `PRESSURE_CHECK_EVERY=2s` el servidor llama `_update_zone_pressure(pid)`
  por jugador. `_zone_at(pos)` clasifica la posición en "cielo"
  (`y < SKY_ROWS`), "profundo" (`y >= H-1-DEEP_ROWS`), "cueva"
  (`y >= SKY_ROWS + UNDERGROUND_BAND`, `UNDERGROUND_BAND=10` porque la
  superficie generada llega hasta `SKY_ROWS+8` — con menos, un valle
  contaría como cueva) o "superficie" (sin presión nueva — ya cubierta por
  las oleadas nocturnas). `_has_fort(pos)` cuenta tiles de `FORT_TILES`
  (muralla/fogata/pinchos/torre) en `FORT_RADIUS=6`; con
  `FORT_MIN_BLOCKS=4` o más, o en superficie, el timer
  `_zone_pressure[pid].t` se resetea (y perdona la reincidencia). TELEGRAPH:
  a los `PRESSURE_WARN_TIME=60s` llega un aviso ⚠️ (sonido "noche") para
  poder reaccionar. Tras `ZONE_PRESSURE_TIME=80s` acumulados sin fuerte en
  cielo/cueva/profundo, `_trigger_zone_pressure` manda un toast (🌬️🦇🔥 →
  sonido "invasion") y llama `npc_mgr.spawn_near(kind, p)` (murciélago/topo/
  taladro según la zona) — resuelve el bug de islas aéreas sin amenazas.
  ESCALADA: reincidir sin salir de la zona suma `level`; cada disparo trae
  `min(level, PRESSURE_MAX_SPAWNS=3)` enemigos.
  ANUNCIO DE JEFE: banner dedicado (`_boss_announce_panel`/
  `_boss_announce_label`, separado del toast genérico) vía RPC
  `show_boss_announcement(kind)` / `_broadcast_boss_announcement`, visible
  `BOSS_ANNOUNCE_LIFE=8s` con fade (mismo patrón que `_toast_panel`).
  `_boss_announcement(kind := run_boss_kind)` ahora acepta un `kind`
  explícito.
  BLOQUE 2 "PROGRESIÓN ELEMENTAL" — RECETAS MEGA: `RECIPES` añade
  `espada_diamante` (costo `wood4+diamante6+ascua4`, `WEAPON_DAMAGE=90`) y
  `armadura_diamante` (costo `stone10+diamante8+esencia4+pluma4`,
  `ARMOR_REDUCTION=10`), que cierran `TIER_CHAINS["espada"]`/`["armadura"]`
  tras la dorada (mismo gating de `_do_craft`: exige tener la dorada antes de
  poder craftear la de diamante); y `torre_mega` (costo
  `stone20+diamante6+ascua4+cristal4`), un bloque apilable SIN cadena
  (`ITEM_TILE["torre_mega"] = T_TOWER_MEGA`) que `tower_manager.gd` dispara
  con más alcance/daño/cadencia que `T_TOWER`.
  JEFES ADAPTATIVOS — EVOLUCIÓN INTELIGENTE (petición del jugador: NO
  aleatoria): `ZONE_BOSS_KIND := {"cielo":"jefe_murcielago",
  "cueva":"jefe_topo", "profundo":"jefe_topo", "superficie":"jefe_corredor"}`
  y `BOSS_EVOLVE_TIME := 30.0`. Cada `PRESSURE_CHECK_EVERY`,
  `_update_boss_evolution()` recorre los NPCs con `boss: true`, ubica al
  jugador más cercano (`npc_mgr._nearest_player`) y su `_zone_at`; si la
  variante que SÍ alcanza esa zona NO es la actual, acumula `_boss_evolve[id]`
  (solo servidor) hasta `BOSS_EVOLVE_TIME` y entonces muta EXACTAMENTE a esa
  variante (`npc_mgr.evolve_boss(id, ideal)`: el jefe persigue al jugador a
  donde vaya — al cielo→murciélago volador, al subsuelo→topo excavador) +
  `_broadcast_boss_evolution` (reusa el banner de jefe con texto de mutación y
  `Sfx.play("jefe")`). Conserva vida proporcional y resetea la FSM transitoria.
  Si la zona cambia o el jefe ya es la variante ideal, el contador se resetea.
  JEFE EXCAVADOR EN TODA DIRECCIÓN (petición del jugador): CUALQUIER jefe
  rompe roca/murallas/obstáculos hacia el jugador (no solo de frente ni solo
  abajo). Lo implementa `npc_mgr._boss_tunnel` (ver npc_manager.gd): los
  jefes quedan EXCLUIDOS del golpe-de-frente y la excavación-abajo normales y
  usan en su lugar el túnel diagonal. Cada bloque aguanta los golpes que su
  HP exija (una muralla de 400 HP cae en HP/block_dmg ≈ 7 golpes).
  BLOQUE 3 "MUNDO VIVO II" — EXPLORACIÓN (server-authoritative, los
  llaman las ramas `T_CHEST`/`T_SKULL` de `world._do_hit`): `open_chest
  (miner, coord)` reparte botín de `CHEST_LOOT[zona]` (rango por material)
  + `CHEST_COINS` según `_zone_at` del cofre, con toast solo al que lo abre;
  `excavate_skull(miner, coord)` elige una de las 5 `SKULLS` al azar
  (3 buenas: `monedas`/`cura`/`botin`; 2 malas: `horda`=3 slimes y
  `bestia`=1 slime grande junto al jugador vía `npc_mgr.spawn_near`) y
  avisa a TODOS; `heal_player(peer, amount)` sube vida y la sincroniza
  (mismo push que `damage_player`). La vía de tren (madera x2) se resuelve
  en `world._do_hit` sin lógica en main. BLOQUE 5: `_broadcast_event_fx`/
  `event_fx` (rpc cosmético) — estallido dorado al abrir un cofre y
  verde/rojo al excavar una calavera buena/mala, en todos los peers (usa
  `world.fx`, no toca estado).
- `scripts/world.gd` — tiles (incluye T_WALL 400 HP, T_CAMPFIRE 200 HP — Fase 7,
  T_SPIKES 120 HP no sólida y T_TOWER 250 HP sólida — Fase 8, T_NEST 150 HP
  sólida — Fase 10: `spawn_nest(near_x)` busca una cara de aire en una cueva
  cercana y coloca un nido; destruirlo (`_do_hit`) llama a
  `main.on_nest_destroyed`), chunks/streaming,
  HP por tile, minado/colocación, `damage_tile()` para daño de NPCs,
  `nearest_campfire_pos()`, generación con cuevas (ruido 2D) e islas flotantes, luz
  día/noche (`daylight()` delega en el reloj de partida de main.gd), meteoro (FX de
  impacto + sacudida de cámara), validaciones de alcance.
  EXPANSIÓN DE MUNDO: `W=200`, `H=90`, `SKY_ROWS=24` (bioma aéreo) y
  `DEEP_ROWS=12` (bioma subterráneo profundo, justo antes del bedrock).
  `T_CRYSTAL` (160 HP, sólido, drop `"cristal"`) aparece en el núcleo de las
  vetas más ricas del subsuelo profundo (`ore_noise > 0.55`) y en el núcleo
  de las islas flotantes (`_spawn_islands`, 12% de probabilidad) — un solo
  recurso para ambos biomas. `_plant_tree(x, surface, changes)` solo escribe
  en `changes` (no toca `tiles`): `generate()` la usa en bulk y
  `grow_trees()` (llamada por `main._set_phase(false)` cada amanecer) la usa
  en runtime, vía `_set_tile` + `apply_changes.rpc` (mismo patrón que
  `meteor_strike`) para reponer madera. `_surface_y(x)` (arranca en
  `SKY_ROWS`) encuentra el suelo real sin confundirlo con las islas.
  BLOQUE 1 "MUNDO VIVO": 5 tiles nuevos tras `T_CRYSTAL` — `T_WATER` (13, no
  sólido, sin HP/drop, ralentiza al jugador), `T_FEATHER`/`T_AETHER` (14/15,
  120/180 HP, drop `"pluma"`/`"esencia"`, bioma AÉREO) y `T_DIAMOND`/`T_EMBER`
  (16/17, 220/160 HP, drop `"diamante"`/`"ascua"`, bioma PROFUNDO).
  `_spawn_islands` reparte `T_AETHER` (núcleo raro, ~10%) y `T_FEATHER`
  (~25%) junto a `T_CRYSTAL`/`T_STONE`. En `generate()`, la rama
  `y >= H - 1 - DEEP_ROWS` añade `T_DIAMOND` (`ore_noise > 0.60`, más raro que
  `T_CRYSTAL`) y `T_EMBER` (banda `0.40..0.55`, antes caía en `T_STONE`); un
  `FastNoiseLite` nuevo (`water`, frecuencia 0.06) convierte en `T_WATER` el
  aire de cueva profunda con `water_noise > 0.35`, creando "ríos"
  subterráneos. `chunk_renderer` tiñe cielo y subsuelo profundo con colores
  distintos para que ambos biomas se distingan a simple vista.
  BLOQUE 2 "PROGRESIÓN ELEMENTAL": `_spawn_lakes()` (llamado tras
  `_spawn_islands()` en `generate()`) hace un BFS flood-fill desde 2-4
  puntos aleatorios de la banda profunda (`y` entre `H-1-DEEP_ROWS` y
  `H-2`), generando lagos CONTENIDOS de `T_WATER` de 18-40 tiles —
  reemplaza los antiguos "ríos" dispersos de `water_noise` por charcos
  grandes y delimitados que sirven de barrera/ralentización (jugador y
  NPCs) cerca de torres/pinchos. `T_TOWER_MEGA` (18, 400 HP, sólido, drop
  `"torre_mega"`) es la receta de diamante de `T_TOWER`: mismo
  `ITEM_TILE`/`SOLID`/`HP`/`DROPS` que el resto de bloques craftables, sin
  lógica nueva en `world.gd` — toda su diferencia de comportamiento vive en
  `tower_manager.gd` (`MEGA_RANGE`/`MEGA_COOLDOWN`/`MEGA_DAMAGE`).
  BLOQUE 3 "MUNDO VIVO II": 3 tiles de exploración tras `T_TOWER_MEGA` —
  `T_RAIL` (19, 50 HP, NO sólido, `RAIL_WOOD=2` → la rama `T_RAIL` de
  `_do_hit` da 2 madera, sin entrada en `DROPS`), `T_CHEST` (20, 60 HP,
  sólido, `_do_hit`→`main.open_chest`) y `T_SKULL` (21, 140 HP, sólido,
  `_do_hit`→`main.excavate_skull`). Generación: `_spawn_islands` planta un
  árbol (`_plant_tree`) en la cima del ~55% de las islas; `_spawn_rails`
  EXCAVA 3-5 galerías mineras (raíl + piso sólido + 2 de aire de techo) en
  el subsuelo; `_spawn_chests` reparte ~2 cofres por banda
  (cielo/superficie/cueva/profundo), posándolos en el primer suelo de la
  banda; `_spawn_skulls` entierra 7 calaveras en piedra/tierra (ocultas
  hasta excavarlas). Las tres se llaman desde `generate()` tras
  `_spawn_lakes()`.
- `scripts/fx.gd` — partículas, textos flotantes ("+N item"), anillos de impacto y ambiente
  (luciérnagas/polen/polvo). 100% visual y local, nunca toca estado.
- `scripts/player.gd` — física AABB (`_simulate_step`, GDD §10.2), cámara (con `shake()`),
  input (joystick táctil + teclado), combate. `_process` con 3 casos (mi nodo / nodo
  remoto en el servidor / nodo remoto en mi pantalla); `_process_remote_authority` y
  `_reconcile` son la mitad servidor/cliente del movimiento server-authoritative
  (la otra mitad está en `main._broadcast_player_snapshot`/`sync_players`).
  BLOQUE 1 "MUNDO VIVO": `_simulate_step` aplica `WATER_SLOW=0.55` a
  `velocity.x` si el tile bajo los pies es `T_WATER` — misma física en
  predicción local y en `_process_remote_authority`. `_water_fx()` (100%
  cosmético, llamado para los 3 casos de `_process`) suelta una salpicadura
  al ENTRAR al agua y el sonido "agua" solo si el que se moja es mi nodo.
- `scripts/npc_manager.gd` — enemigos FSM con variantes en `KINDS` (slimes
  normal/grande/dorado + murciélago volador `fly: true`, nocturno + "jefe" Fase 9).
  LOCOMOCIÓN VARIADA (petición del jugador: "no todos saltan"): el `_simulate`
  ramifica por estilo — `fly` (vuela), `charges` (`_update_charge`), `walks`
  (`_walk_step`: avanza en horizontal hacia el jugador SIN el rebote del slime,
  con auto-step `_step_blocked` para escalones) o el salto por defecto (SLIMES).
  Llevan `walks: true` topo/taladro/coracero/sanador y los jefes terrestres
  (`jefe`/`jefe_topo`); el embistedor camina entre embestidas (idle de
  `_update_charge` usa `_walk_step`). Los slimes (normal/grande/slime_mega/
  dorado) siguen saltando, pero con MÁS formas de alcanzar al jugador
  (petición del jugador): si un muro les cierra el paso hacia el jugador
  saltan MÁS ALTO (×1.45) para treparlo, y el `dorado` es un saltarín ágil
  (salto base más alto). Carácter visual por variante en `Atlas._make_slime`
  (param `style`): normal amistoso, grande con cejas furiosas, slime_mega
  agrietado/con colmillos, dorado con corona y destello.
  oleadas nocturnas vía `night_wave(noche)` (3+noche enemigos, escala con la noche;
  cada `BOSS_EVERY=5` noches suma además un "jefe" fuera del `WAVE_CAP`); de noche
  el spawn regular también se acelera. Fase 7: los slimes terrestres golpean bloques
  sólidos que les cierran el paso (`damage_tile`, cooldown `BLOCK_CD`; el daño a bloques
  es `block_dmg` de la variante si existe — grande y jefe son rompe-murallas). Fase 8:
  contacto con `T_SPIKES` aplica `SPIKE_DAMAGE`; `damage_npc()`/`_nearest_player()` son
  el daño ambiental genérico (sin atacante jugador) que usan trampas y `tower_manager`.
  PULIDO: el jefe se ENFURECE bajo `BOSS_ENRAGE_HP` (velocidad/salto extra) y muere con
  anillo expansivo (`_death_fx`, también en la ruta de snapshot del cliente); ambas rutas
  de muerte llaman `main.count_kill(kind)`; rpcs unreliable PURAMENTE cosméticos
  `block_hit_fx`/`spike_fx` (sonido/salpicadura con gate de distancia) — el estado real
  sigue viajando solo por `damage_tile`/`sync_npcs`.
  FASE 10 — bestiario expandido: "taladro" y "topo" (`digs: true`) excavan el bloque
  de abajo (`DIG_CD`, `block_dmg`) y son inmunes a `T_SPIKES` (las destruyen al
  pasar); "topo" además nace en cuevas (`cave: true`, `_spawn_underground`).
  "embistedor" y "jefe_corredor" (`charges: true`) usan `_update_charge` — FSM
  idle→winding (`CHARGE_WINDUP`)→charging (`CHARGE_SPEED` por `CHARGE_TILES`,
  daño `charge_dmg`)→cooldown. `_process_fusions`/`_fuse`: dos slimes del mismo
  tipo cerca por `MERGE_TIME` (radio `MERGE_RADIUS`) se fusionan según
  `FUSION_CHAIN` (normal→grande→slime_mega). `_nests`/`_update_nests`/
  `_spawn_from_nest`/`forget_nest`: rastrean los `T_NEST` del mundo y escupen un
  enemigo cada `NEST_SPAWN_EVERY`. `BOSS_KINDS`/`BOSS_HINTS` (en main.gd) añaden
  "jefe_murcielago"/"jefe_topo"/"jefe_corredor" como variantes de jefe; rpcs
  unreliable cosméticos `charge_fx`/`nest_spawn_fx`/`fusion_fx`.
  TELEGRAPHS: el snapshot lleva un 4º campo `st` (`_state_flag`: 0 nada,
  1 winding, 2 charging, 3 jefe enfurecido) SOLO para dibujo — sacudida + "!"
  al cargar, líneas de velocidad al embestir, tinte rojo y aura pulsante del
  jefe. `night_wave` lee `wave_base`/`wave_step`/`boss_every` de
  `main.mode_cfg` (capa de reglas) y el aviso 🕳️ del nido sembrado se demora
  4 s con un timer para no pisar el toast de "¡Noche N!".
  BLOQUE 1 "MUNDO VIVO": `_insert_npc(kind, pos)` extrae el alta final en
  `npcs`/`_next_id` (antes era el cuerpo final de `_spawn_one`);
  `spawn_near(kind, near)` lo reutiliza para hacer aparecer un enemigo JUNTO
  a un jugador concreto — voladores con un offset aéreo cerca de
  `near.position`, terrestres buscando aire con suelo en ±6 tiles (o cayendo
  en `near.position - (0, 48)` si no hay hueco). Lo usa la presión ambiental
  de `main.gd` para amenazar islas/cuevas/profundo sin depender del spawn de
  superficie.
  BLOQUE 2 "PROGRESIÓN ELEMENTAL": `_move(n, delta, w)` aplica el mismo
  `WATER_SLOW=0.55` que `player._simulate_step` — si el tile bajo los pies
  del NPC (`feet_tile`) es `T_WATER`, multiplica `dx` por `WATER_SLOW` antes
  de mover y resolver colisiones; afecta a todos los NPC terrestres por
  igual (los voladores, `fly: true`, no usan `_move`). `evolve_boss(id,
  new_kind)`: muta un jefe vivo a otra entrada de `KINDS` conservando
  posición y vida PROPORCIONAL (`_ratio_of`/`_kind_of`) y reseteando el
  estado transitorio de la FSM (`vel`, `cool`, `jump_t`, `block_cd`,
  `spike_cd`, `dig_cd`, `charge_state`/`charge_cd`, `near_t`) para que la
  nueva variante arranque "idle" sin comportamientos heredados (p.ej. una
  embestida a medias). `main._update_boss_evolution` es quien decide
  CUÁNDO/A QUÉ mutar; `boss_evolve_fx`/`_boss_evolve_fx` (rpc unreliable
  cosmético, reusa el sonido "fusion") hacen una ráfaga + anillo grande en
  TODOS los peers en la posición del jefe.
  JEFE EXCAVADOR (petición del jugador): `_boss_tunnel(n, k, target, w,
  delta)` — para CUALQUIER `boss: true`, cada `BOSS_TUNNEL_CD` golpea el tile
  vecino en el eje X y en el eje Y hacia el jugador (`_breakable`: sólido, con
  HP, no bedrock) con `block_dmg`, carvando un túnel diagonal que derriba
  murallas/torres/roca por el camino (una muralla cae en HP/block_dmg
  golpes). Se llama tras `_move`; los jefes quedan FUERA del golpe-de-frente
  (`block_cd`) y de la excavación-abajo (`digs`) — ambos gateados con
  `not boss` — para no romper a doble velocidad. Vale también para jefes
  voladores si los amurallan; `evolve_boss` resetea `tunnel_cd`.
  BLOQUE 4 "BESTIARIO VIVO": 3 KINDS con comportamiento propio —
  `espectro` (`ghost`+`fly`: `_move` lo deja ATRAVESAR los muros, solo lo
  acota al mundo; anti-turtling; se dibuja translúcido en `_draw`),
  `coracero` (`armor`: `_do_hit`/`damage_npc` restan `armor` al daño, mín. 1)
  y `sanador` (`heals`: en `_simulate` pulsa cada `HEAL_CD` curando
  `HEAL_AMOUNT` a los NPC no-jefe heridos en `HEAL_RADIUS`, con
  `heal_fx`/`_heal_fx` cosmético). Todos llevan `drop` (material de bioma:
  esencia/ascua/pluma) que las dos rutas de muerte sueltan además de
  ore/Núcleos, y entran por `_roll_kind_night` (sanador/espectro desde la
  noche 2, coracero desde la 4).
- `scripts/tower_manager.gd` — torre de flechas (Fase 8), mismo patrón que
  `npc_manager`: el servidor re-escanea `world.tiles` cada `SCAN_EVERY` segundos
  buscando `T_TOWER`, dispara con cooldown al enemigo más cercano en rango
  (`_nearest_enemy`) y simula las flechas (`arrows`) hasta impactar
  (`npc_mgr.damage_npc`) o agotar su vida útil; snapshot `(pos, dir)` a 10 Hz vía
  `sync_arrows`, los clientes solo dibujan con `Atlas.arrow_tex` (+ estela que se
  desvanece). PULIDO: rpc unreliable cosmético `fired_fx` (fogonazo + sonido "flecha"
  con gate de distancia) al disparar.
  BLOQUE 2 "PROGRESIÓN ELEMENTAL": el escaneo de torres ahora busca también
  `T_TOWER_MEGA`, guardando su `kind` por coordenada; al disparar, si
  `kind == T_TOWER_MEGA` usa `MEGA_RANGE=480` (15 tiles), `MEGA_COOLDOWN=0.7`
  y `MEGA_DAMAGE=40` en vez de los valores normales (`RANGE=320`,
  `COOLDOWN=1.2`, `ARROW_DAMAGE=18`). El snapshot de `arrows` lleva un campo
  `mega: bool` extra — solo cambia el tinte/estela celeste-diamante del
  proyectil en `_draw` (cosmético, el daño real ya viajó por
  `npc_mgr.damage_npc`).
- `scripts/virtual_joystick.gd` — joystick multi-touch; consume sus toques con
  `set_input_as_handled()` para no interferir con minar. `set_enabled(b)`:
  en modo PC (ver `main.control_mode`) se desactiva — `_input` ignora los
  toques (deja pasar el clic del ratón a minar) y no se dibuja.
- `scripts/chunk_renderer.gd` — dibujo por chunk con grietas de daño y decoración
  de superficie (hierba alta/flores del Atlas, por hash de coordenada). FOGATA VIVA:
  solo los chunks con fogata se redibujan periódicamente (`FIRE_REDRAW`) para el aura
  parpadeante (más intensa de noche) y sueltan brasas vía `fx.ember` (partícula con
  gravedad negativa); el resto de chunks sigue siendo estático.

La UI se construye por código en `main.gd` (sin .tscn complejos, decisión de prototipo).
`scenes/main.tscn` es mínimo a propósito.

## Convenciones

- GDScript tipado (`:=`, tipos en parámetros y retornos). Comentarios en español con
  referencia a la sección del GDD que implementan (ej. `# GDD §6`).
- RPCs: `reliable` para acciones/estado, `unreliable_ordered` solo para posiciones.
- Items son strings: materiales (`dirt`, `stone`, `wood`, `ore`, `cristal`, `pluma`,
  `esencia`, `diamante`, `ascua`), equipo craftable (`pico_*`, `espada_*`,
  `armadura_*` — únicos, max 1) y bloques craftables apilables (`muralla`,
  `fogata`, `trampa`, `torre`, `torre_mega` — se colocan con ITEM_TILE).
  Bloque 2 "Progresión elemental": `diamante`/`ascua` ya tienen receta
  (`espada_diamante`, `armadura_diamante`, `torre_mega`, cierran
  `TIER_CHAINS["espada"]`/`["armadura"]` tras la dorada); `pluma`/`esencia`
  se consumen como ingredientes secundarios de `armadura_diamante`.
  Picos minan (`TOOL_DAMAGE`), espadas pegan a NPCs (`WEAPON_DAMAGE`), armaduras
  reducen daño recibido (`ARMOR_REDUCTION`); el servidor consulta el inventario real.
- Skins son strings (claves de `SKINS` en main.gd). Los Núcleos NO son item de inventario:
  viven en el perfil (`profiles`) y solo el servidor los modifica (`add_coins`).
- Las skins son SOLO cosméticas — nunca vender ventaja de juego (ver MONETIZACION.md).
  REDISEÑO 2026-06-13: cada skin es un ATUENDO completo (`camisa`/`pantalon`/
  `pelo`/`borde`) + un `accesorio` de identidad (`corona`/`cuernos`/`capucha`/
  `visor`/`casco`/`orejas`/`halo`/`diadema`, en `Atlas.player_acc`) tintado con
  `accent` — no solo un color de camisa. `player.gd._draw` dibuja las capas del
  `Atlas.player_frames` (`outline`/`skin`/`hair`/`shirt`/`pants`/`boot`) tintadas
  por skin + el accesorio encima; la skin "default" usa el color por-peer para
  la camisa, "arcoíris" anima camisa y accent. El swatch de la tienda usa
  `SKINS[id].camisa`. Los 4 jefes tienen sprite PROPIO (no el molde demonio
  recoloreado): `Atlas._make_boss_bat`/`_make_boss_mole`/`_make_boss_runner`
  (siluetas distintas), `jefe` conserva el demonio `_make_boss` 24×18.
  Igual el bestiario del Bloque 4: `espectro`/`coracero`/`sanador` ya NO son
  slimes reteñidos — `Atlas._make_ghost` (espíritu flotante de faldón
  ondulado, dibujado translúcido por el tinte `ghost`), `_make_armor`
  (blindado con visor) y `_make_healer` (cruz de curación). El espectro sí
  entra en las oleadas (`_roll_kind_night`, noche >= 2).
- Constantes de balance (HP, daños, costos) arriba de cada archivo — no hardcodear inline.
- Diccionarios con claves `Vector2i` viajan bien por RPC; para JSON se serializan como `"x,y"`.

## Trampas conocidas

- `rpc_id(1, ...)` desde el propio servidor NO se entrega: por eso el patrón
  `if multiplayer.is_server(): _do_X() else: request_X.rpc_id(1)`.
- JSON devuelve floats: castear con `int()` al leer saves e inventarios.
- No usar `class_name` global a la ligera; los scripts se cargan con `preload` + `set_script`.
- Los toques de UI: `player.gd` ignora taps sobre la interfaz vía `main.is_point_on_ui()`.
  Si agregas controles nuevos a la UI, inclúyelos ahí.
- Tras editar la generación del mundo, borrar el save (`user://nucleo_save.json.gz`) para probar.
- Los perfiles van por NOMBRE sin contraseña: en LAN cualquiera puede usar tu nombre y
  gastar tus Núcleos. Aceptado hasta el backend de cuentas; NO cobrar dinero real antes.
- El movimiento server-authoritative (GDD §10.2) se cubre en smoke test solo en
  aislamiento (host=servidor=único peer, TEST 35). Verificar el flujo end-to-end
  (predicción/reconciliación con 2+ peers reales: sin rubber-banding en movimiento
  normal, respawn limpio, terceros viendo a los demás moverse con normalidad) a mano
  desde el editor: Depurar → Ejecutar múltiples instancias.
- El smoke test siembra el RNG con una seed FIJA al inicio de `_ready()` — no quitarla:
  mantiene la suite determinista. `spawn_nest` ahora hace 20 intentos aleatorios y, si
  fallan, un BARRIDO determinista en espiral desde `near_x` (siembra el nido siempre que
  exista un hueco viable) — antes 20 tiradas con mala suerte lo dejaban sin sembrar, y
  cambiar tablas de spawn (que desplazan el stream de RNG) rompía el TEST 31. Con el
  barrido, el TEST 31 ya no es frágil a esos cambios.

## Roadmap

El plan por fases vive en **`ROADMAP.md`** (derivado de la visión de supervivencia
por noches). Resumen: Fase 6 ciclo día/noche jugable → Fase 7 defensa pasiva
(murallas, fogata) → Fase 8 defensa activa (torres, trampas) → Fase 9 estructura
de run (win/lose, escalado, recompensas) → Fase 10 bestiario expandido (taladro/
topo que excavan, embistedor, fusión de slimes, nidos, roster de 4 jefes
anunciado al iniciar) → Fase 11+ campañas y mundos temáticos.
Fases 1-10 completas; la Fase 11+ está bloqueada hasta validar diversión con
jugadores reales. Fuera de esa numeración: refactor de 3 capas (2026-06-11),
expansión de mundo — biomas aéreo/profundo + cristal + bosques renovables
(2026-06-12), Bloque 1 "Mundo vivo" (2026-06-12: minerales y tinte por bioma,
agua que ralentiza, presión ambiental anti-turtling y banner de jefe dedicado)
y Bloque 2 "Progresión elemental y jefes adaptativos" (2026-06-13: lagos de
agua contenidos, recetas mega de diamante para espada/armadura/torre y jefes
que mutan de variante si el jugador los esquiva 60s en otra zona) y Bloque 3
"Mundo vivo II — exploración y eventos" (2026-06-13: árboles en islas aéreas,
vías de tren abandonadas con madera x2, cofres de recursos por bioma y
5 calaveras estilo Halo con efecto aleatorio bueno/malo al excavarlas) y
Bloque 4 "Bestiario vivo" (2026-06-13: espectro que atraviesa muros, coracero
blindado y sanador que cura a la horda, con drops de bioma) y Bloque 5
"Identidad visual y sonora" (2026-06-13: SFX de cofre/cura/maldición + FX de
evento difundido al abrir cofres y excavar calaveras). Los Bloques 1-5 están
completos; el siguiente hito es validar diversión con jugadores reales.

Vía paralela de negocio (independiente del gameplay, ver MONETIZACION.md):
backend de cuentas (los `profiles` por nombre migran tal cual, la clave pasa de
nombre a uid) → validación de recibos de Google Play → export AAB firmado.

Deuda técnica pendiente (sin fase asignada): tests GUT formales, animaciones pulidas.
