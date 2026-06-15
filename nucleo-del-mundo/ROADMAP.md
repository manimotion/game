# 🗺️ ROADMAP — Núcleo del Mundo

Plan de ruta derivado de `Evolución de la Visión del Proyecto.md` (2026-06-10).
La identidad del juego ahora es:

> **"Un sandbox donde el jugador debe sobrevivir una serie de noches mientras
> construye, progresa y diseña un sistema de defensa vivo contra el mundo."**

Principios (del doc de visión, aplican a TODA implementación):
1. Core simple y modular. 2. Gameplay > cantidad de features. 3. Sin complejidad
innecesaria. 4. Todo sistema nuevo se conecta al loop día/noche. 5. Diseñar para
runs, no solo sandbox eterno.

---

## Qué ya existe y en qué se convierte

| Hoy (sandbox) | Mañana (supervivencia por noches) |
|---|---|
| Día/noche **solo visual** (`daylight()` con hora del sistema) | **Reloj de partida server-authoritative** que gobierna el gameplay |
| Invasiones de slimes con timer aleatorio (`spawn_wave`) | **Oleadas nocturnas** programadas y escaladas por número de noche |
| Muerte = respawn gratis | Muerte de noche = **fin de run** (en modo supervivencia) |
| Colocar bloques sin función | **Murallas con HP** que los enemigos atacan |
| Regeneración global pasiva | Regeneración **en la base** (fogata) → construir tiene propósito |
| Equipo (picos/espadas/armaduras) | Igual, + **infraestructura** como segunda vía de progresión |

---

## Fase 6 — Ciclo día/noche JUGABLE ✅ HECHA (2026-06-10)

1. ✅ Reloj de partida server-authoritative en `main.gd` (`is_night`,
   `night_number`, `_phase_t`; día 180 s, noche 90 s). Los clientes reciben
   `apply_phase` por RPC y solo cuentan hacia atrás para el HUD.
   `world.daylight()`/`day_phase()` delegan en el reloj (ya no hora del sistema).
2. ✅ La noche dispara `night_wave(noche)`: 3+noche enemigos, variantes duras
   escalan con la noche. La invasión aleatoria desapareció; meteoro = diurno.
3. ✅ HUD "☀️ Día 1 — 2:45" / "🌙 Noche 3 de 7 — 0:58" + aviso de atardecer.
4. ✅ Lobby: "🌙 Supervivencia — 7 noches" y "🏖️ Sandbox libre". Las runs de
   supervivencia NO tocan el save del sandbox; al sobrevivir las 7 noches hay
   toast de victoria (la pantalla de resumen completa es Fase 9).
5. ✅ Primer enemigo nuevo: **murciélago** (volador, nocturno, sin gravedad,
   persigue en línea recta; `fly: true` en `KINDS`).

## Fase 7 — La base importa: defensa pasiva ✅ HECHA (2026-06-11)

1. ✅ **Muralla** (`T_WALL`): tile craftable (6 piedra), 400 HP, sólida. Los
   slimes terrestres **golpean bloques** que les cierran el paso hacia el
   jugador (`damage_tile`, cooldown `BLOCK_CD=1s`). Los murciélagos NO atacan
   bloques (vuelan por encima). Mismo pipeline de HP/grietas que el minado.
2. ✅ **Fogata** (`T_CAMPFIRE`): tile craftable (8 madera + 4 piedra), 200 HP,
   no sólida. De noche: regeneración SOLO cerca de fogata (radio 8 tiles).
   De día: regeneración global como antes. Respawn del jugador en la fogata
   más cercana (si existe) en vez de en la superficie.
3. ✅ Crafting apilable: muralla y fogata se fabrican en múltiples unidades
   (los equipos siguen siendo únicos). Panel "Fabricar" muestra `(N)` en vez
   de `✓`.
4. ✅ Texturas pixel-art en atlas.gd (ladrillos para muralla, leños+llama
   para fogata), aura cálida visual en chunk_renderer.
5. ✅ Test headless: muralla absorbe 8 dmg del slime (392/400), regen nocturna
   solo cerca de fogata, regen diurna global, respawn en fogata.

## Fase 8 — Defensa activa (torres y trampas) ✅ HECHA (2026-06-11)

1. ✅ **Torre de flechas** (`T_TOWER`, 250 HP, sólida): entidad simulada en
   servidor (`tower_manager.gd`, mismo patrón que `npc_manager`). Re-escanea
   `world.tiles` cada segundo, dispara al enemigo más cercano en rango
   (320px) con cooldown de 1.2s; flechas server-side a 480px/s, snapshot
   `(pos, dir)` a 10 Hz, los clientes solo dibujan con `Atlas.arrow_tex`.
2. ✅ **Trampa de pinchos** (`T_SPIKES`, 120 HP, NO sólida): los NPCs
   terrestres que la pisan reciben 25 de daño con cooldown de 0.5s
   (`npc_manager._simulate`).
3. ✅ Daño ambiental sin atacante jugador: `npc_manager.damage_npc()` (usado
   por trampas y flechas) entrega el botín al jugador más cercano
   (`_nearest_player`).
4. ✅ Costos altos en mineral: trampa = 10 piedra + 4 mineral; torre = 20
   piedra + 10 madera + 15 mineral → sumidero de recursos que da propósito
   al minado profundo (cuevas) y a las islas.
5. ✅ Texturas pixel-art en atlas.gd (pinchos metálicos, torre de vigía con
   tronera, proyectil de flecha).
6. ✅ Test headless: recetas/costos, tiles (HP, sólido/no sólido), trampa
   daña NPC por contacto, torre detecta, dispara y daña al enemigo más
   cercano.

## Fase 9 — Estructura de run completa ✅ HECHA (2026-06-11)

1. ✅ **Win/lose**: `_end_run(victory)` en `main.gd` (solo servidor, guardado
   por `_run_over` para no disparar dos veces). Sobrevivir `SURVIVAL_NIGHTS`
   (7) = victoria; morir en modo supervivencia (`damage_player` con `hp<=0`)
   = derrota, sin respawn. Ambos casos muestran `_run_panel` (panel
   "🏆 ¡VICTORIA!" / "💀 FIN DE LA RUN" con resumen: noches, recursos,
   Núcleos) vía RPC `run_ended` y luego `_reset_run()` vuelve todo a modo
   sandbox (reloj a día 1, NPCs/flechas limpios, jugadores con vida llena).
2. ✅ **Escalado por noche**: `night_wave(noche)` sigue dando 3+noche enemigos;
   cada `BOSS_EVERY=5` noches se suma además un **"jefe"** (`KINDS["jefe"]`:
   500 HP, 18 dmg, 65 vel, 50 Núcleos/6 mineral de botín, sprite 64×50
   reutilizando `_make_slime` con paleta roja). `main.gd` anuncia su llegada
   con un toast "👹 ¡Un jefe ha llegado!".
3. ✅ **Recompensa**: al amanecer (`_set_phase(false)`), si `night_number > 0`,
   todos los jugadores reciben `NIGHT_REWARD_BASE(10) + NIGHT_REWARD_STEP(5)
   * noche` Núcleos vía `add_coins`. Victoria suma además `VICTORY_BONUS=100`.
   Los Núcleos persisten en `profiles` (enganchado con la monetización).
4. ✅ Test headless: `KINDS`/Atlas incluyen "jefe", la oleada de la noche 5
   incluye un jefe, recompensa de Núcleos al amanecer (+25 en noche 3),
   victoria al sobrevivir 7 noches (panel + bono + reset a sandbox), derrota
   en supervivencia (panel + vida llena + reset a sandbox).
5. ✅ PULIDO F7-F9 (2026-06-11) — pasada de "game feel" sobre todo lo anterior:
   - Jefe con sprite propio (cuernos, corona, colmillos), rompe-murallas
     (`block_dmg` 60; el grande también, 24), ENRAGE bajo 50% de vida
     (más velocidad y salto), barra de vida del jefe en el HUD y anillo
     expansivo + aviso global al derrotarlo.
   - Run con estadísticas: contador de bajas (`run_kills`/`count_kill`),
     panel de fin rediseñado (borde/título dorado o rojo según resultado,
     noches/bajas/recursos/Núcleos), jingle de victoria/derrota y fuegos
     artificiales al ganar.
   - Defensa con feedback: flechas con estela + fogonazo y sonido al
     disparar; trampa de pinchos con salpicadura y chasquido; "thud"
     audible cuando un enemigo golpea tu muralla (rpcs cosméticos
     unreliable con gate de distancia — el estado no cambia de canal).
   - Mundo más vivo: fogata con aura parpadeante (más intensa de noche)
     y brasas que flotan; chispas verdes al curar; sonidos de amanecer,
     anochecer y rugido del jefe enganchados al prefijo del toast.
   - Test headless: bajas por run, jefe rompe-murallas, panel con bajas,
     sonidos nuevos presentes, barra del jefe y sprite propio del jefe.

## Fase 10 — Bestiario expandido y jefes variados ✅ HECHA (2026-06-11)

Más complejidad táctica para las oleadas nocturnas: nuevos tipos de enemigo,
una mecánica de "los slimes se organizan" y un roster de jefes anunciado al
arrancar la run para que el jugador planee su defensa desde el minuto cero.

1. ✅ **Taladro** (rompedor vertical, `KINDS["taladro"]`): desde la noche 3
   puede aparecer en las oleadas. Excava periódicamente (`DIG_CD=1.2s`) el
   bloque de debajo (`damage_tile` con `block_dmg=50`), abriendo pozos hacia
   la base. Es inmune a `T_SPIKES`: en vez de recibir daño, las destruye al
   pasar (flag `digs: true`, compartido con "topo" y "jefe_topo").
2. ✅ **Fusión de slimes** (`_process_fusions`, `FUSION_CHAIN`): dos slimes
   "normal" que permanecen a menos de `MERGE_RADIUS=46px` por `MERGE_TIME=8s`
   se combinan en un "grande"; dos "grande" igual se combinan en
   "slime_mega" (320 HP, rompe-murallas `block_dmg=40`). FX de fusión
   (ráfaga + anillo) en el punto medio.
3. ✅ **Embistedor** (`KINDS["embistedor"]`, flag `charges: true`): FSM propia
   (`_update_charge`) — si el jugador está cerca y a su altura, se detiene
   "cargando" (`winding`, `CHARGE_WINDUP=0.9s`) y luego embiste en horizontal
   (`charging`) a `CHARGE_SPEED=420px/s` durante `CHARGE_TILES=5` cuadros (o
   hasta chocar contra un bloque), haciendo `charge_dmg` (mayor que su `dmg`
   normal) por contacto. Tras embestir entra en `CHARGE_COOLDOWN=3s`.
4. ✅ **Topo** (`KINDS["topo"]`, flags `digs: true, cave: true`): puede nacer
   directamente en bolsas de aire subterráneas (`_spawn_underground`) y
   también de día con baja probabilidad (`_roll_kind`). Excava como el
   taladro pero con `block_dmg` menor.
5. ✅ **Nidos** (`T_NEST`, mundo): `world.spawn_nest(near_x)` coloca un tile
   sólido de 150 HP junto a una cara de aire en una cueva. `night_wave`
   siembra uno en las oleadas impares. `npc_manager` los rastrea
   (`_nests`, re-escaneo cada `NEST_SCAN_EVERY=4s`) y cada
   `NEST_SPAWN_EVERY=22s` escupen un enemigo ("topo" o "normal") por su cara
   de aire (`_spawn_from_nest`, FX `nest_spawn_fx`). Destruirlo a tiempo
   (`world._do_hit` → `main.on_nest_destroyed` → `forget_nest`) lo detiene y
   da `COIN_NEST=8` Núcleos extra.
6. ✅ **Roster de jefes** (`main.BOSS_KINDS`): además del "Jefe Demonio"
   clásico, ahora `night % BOSS_EVERY == 0` puede traer al "Murciélago
   Gigante" (`jefe_murcielago`, vuela y embiste en línea recta), "Mega Topo"
   (`jefe_topo`, excava y rompe muros desde el subsuelo) o "Mega Corredor"
   (`jefe_corredor`, embiste con `charges`). `_host()` elige
   `run_boss_kind` al azar al crear la partida y lo anuncia de inmediato con
   un toast (`_boss_announcement()`, nombre + pista táctica de
   `BOSS_HINTS`); los que se unen después reciben el mismo aviso de forma
   privada. La barra de vida del jefe en el HUD (`_boss_panel`/`_boss_label`)
   ahora es genérica: se activa con CUALQUIER `boss: true` vivo y muestra su
   nombre propio. Derrotar a cualquier jefe del roster anuncia su nombre via
   `count_kill`.
7. ✅ Test headless (TEST 27-32): registro de las nuevas variantes en
   `KINDS`/`Atlas`, excavación del taladro (daño = `block_dmg`, cooldown
   activo), FSM del embistedor (`winding` → `charging` a `CHARGE_SPEED`),
   fusión normal+normal → grande tras `MERGE_TIME`, siembra/escaneo/eclosión
   de un nido y `forget_nest`, roster de jefes (`BOSS_KINDS`,
   `_boss_announcement`, `night_wave` invoca `run_boss_kind`, HUD muestra el
   nombre del jefe vivo).

## Refactor: arquitectura en 3 capas + pulido global ✅ HECHO (2026-06-11)

Preparación estructural para la Fase 11+ (el gate de contenido sigue): el
código quedó separado en núcleo/motor → reglas → presentación (ver
**`ARQUITECTURA.md`**), de modo que crear modos/campañas es añadir datos.

1. ✅ **`game_modes.gd` (capa de reglas)**: modos data-driven (duraciones,
   `nights_to_win`, `death_ends_run`, `save_allowed`, `boss_every`,
   `wave_base/step`, recompensas). `main.set_mode()` carga `mode_cfg` y
   TODO el código (reloj, oleadas, win/lose, save, meteoros) lee de ahí.
2. ✅ **Modo nuevo "Asedio"** (prueba de la capa): 3 noches brutales, días
   cortos, oleadas 6+2·noche, jefe en la noche 3, recompensas dobles.
   Apareció en el lobby sin tocar UI: el menú se genera desde
   `GameModes.LOBBY_ORDER`.
3. ✅ **`ui_builder.gd` (capa de presentación)**: lobby y HUD extraídos de
   main.gd (~470 líneas), menú rediseñado (título dorado, tagline,
   tarjetas de modo con descripción, secciones separadas) y paleta de UI
   centralizada.
4. ✅ **Telegraphs del bestiario** (legibilidad = juego justo): el snapshot
   lleva un flag visual `st` — el embistedor tiembla y muestra "!" al
   cargar, deja líneas de velocidad al embestir; los jefes tienen aura
   pulsante y se encienden en rojo al enfurecer.
5. ✅ **FX/SFX nuevos**: la fusión de slimes ahora se ve y suena en TODOS
   los peers (rpc cosmético `fusion_fx` + sonido "fusion"); sonido "nido"
   y aviso 🕳️ con la x del nido sembrado (demorado 4 s para no pisar el
   toast de la noche).
6. ✅ **4 skins nuevas del bestiario** (solo cosméticas): Topo, Nocturna,
   Acero y Demonio.
7. ✅ Test headless (TEST 33): los 3 modos existen, `set_mode` carga las
   reglas, la oleada obedece `wave_base/step` del modo, skins y sonidos
   nuevos registrados. 33 grupos de prueba en verde.

## Expansión de mundo: biomas aéreo/profundo + cristal + bosques renovables ✅ HECHO (2026-06-12)

Trabajo FUERA de la numeración de fases (igual que el refactor de 3 capas):
NO es contenido de Fase 11+ (campañas/mundos temáticos, que sigue bloqueada)
sino una ampliación del mundo base que da más motivo para excavar hacia
arriba y hacia abajo, y evita que la madera se agote en runs largas.

1. ✅ **Mundo más grande**: `W=200` (antes 160), `H=90` (antes 60), `SKY_ROWS=24`
   (antes 14, cielo ampliado para más islas) y `DEEP_ROWS=12` (franja nueva
   justo antes del bedrock). Sin cambios en `chunk_renderer.gd`, `player.gd`,
   `tower_manager.gd` ni el resto de `main.gd`: todo lee `world.W/H/SKY_ROWS`
   dinámicamente — el "mundo es datos puros + chunks" paga exactamente como
   prometía `ARQUITECTURA.md`.
2. ✅ **Cristal** (`T_CRYSTAL`, 160 HP, sólido, drop `"cristal"`): aparece en
   el núcleo de las vetas del bioma subterráneo profundo (las `DEEP_ROWS`
   filas antes del bedrock, `ore_noise > 0.55`) y en el núcleo de las islas
   flotantes del bioma aéreo (`_spawn_islands`, ahora 7-11 islas, 12% de
   probabilidad de cristal por celda). Un solo recurso nuevo da propósito a
   AMBAS direcciones de excavación.
3. ✅ **Pico de cristal** (`pico_cristal`: 4 madera + 6 cristal): el mejor
   pico (`TOOL_DAMAGE=150`, por delante del dorado).
4. ✅ **Bosques renovables**: `_plant_tree` ahora solo escribe en un
   diccionario `changes` (no toca `tiles` directamente), reutilizable por
   `generate()` (bulk, sin FX) y por `grow_trees()` (runtime, con FX +
   `apply_changes.rpc`, mismo patrón que `meteor_strike`). Cada amanecer
   (`_set_phase(false)`, si `night_number > 0`) el servidor intenta plantar
   hasta 3 árboles nuevos en superficie despejada — `_surface_y` arranca en
   `SKY_ROWS` para no confundir el suelo con las islas flotantes.
5. ✅ Test headless (TEST 36): dimensiones del mundo, `T_CRYSTAL` sólido/HP/
   drop + textura en Atlas, cristal generado en el subsuelo profundo Y en
   las islas aéreas, `grow_trees()` añade troncos nuevos, receta y daño de
   `pico_cristal`.

## Bloque 1: Mundo vivo ✅ HECHO (2026-06-12)

Primero de 4 bloques acordados con el jugador (sesión 2026-06-12) tras el
feedback de que el mundo "ampliado" no se sentía distinto: las islas aéreas
eran zona 100% segura y el subsuelo profundo solo cambiaba la densidad de
mineral, sin ningún elemento visual propio. Ataca las 3 causas con un mismo
hilo: minerales + tinte por bioma, presión ambiental anti-turtling y un
banner de jefe propio.

1. ✅ **5 tiles nuevos** (`world.gd`/`atlas.gd`): `T_WATER` (no sólido,
   ralentiza al pisarlo), `T_FEATHER`/`T_AETHER` (bioma aéreo, drop
   `"pluma"`/`"esencia"`) y `T_DIAMOND`/`T_EMBER` (bioma profundo, drop
   `"diamante"`/`"ascua"`, `T_DIAMOND` más raro que `T_CRYSTAL`). Los 4
   minerales quedan listos para el Bloque 2 sin tocar generación de mundo
   otra vez.
2. ✅ **Generación e identidad de bioma**: `_spawn_islands` reparte
   `T_FEATHER`/`T_AETHER` en el núcleo de las islas junto a `T_CRYSTAL`; el
   subsuelo profundo gana `T_DIAMOND`/`T_EMBER` y "ríos" de `T_WATER` (nuevo
   `FastNoiseLite` `water`). `chunk_renderer` tiñe el cielo (frío/violeta) y
   el subsuelo profundo (cálido) para que ambos biomas se distingan a simple
   vista.
3. ✅ **Agua ralentiza**: `player._simulate_step` aplica `WATER_SLOW=0.55` a
   `velocity.x` sobre `T_WATER`, tanto en predicción local como en
   `_process_remote_authority` (misma física). PULIDO: salpicadura + sonido
   "agua" al entrar (cosmético local, `player._water_fx`).
4. ✅ **Presión ambiental (anti-turtling)**: `main._update_zone_pressure`
   clasifica a cada jugador con `_zone_at` (cielo/cueva/profundo/superficie).
   Sin un "fuerte" propio cerca (`_has_fort`, `FORT_MIN_BLOCKS=4` en
   `FORT_RADIUS=6`), tras `ZONE_PRESSURE_TIME=80s` sin pasar por superficie
   ni fortificarse, avisa con un toast y llama
   `npc_manager.spawn_near(kind, p)` (murciélago/topo/taladro según la zona)
   — el enemigo aparece JUNTO al jugador, resolviendo las islas aéreas sin
   amenazas. PULIDO: telegraph ⚠️ a los `PRESSURE_WARN_TIME=60s` (se puede
   reaccionar antes del spawn — legibilidad = juego justo), la reincidencia
   ESCALA (cada disparo trae un enemigo más, tope `PRESSURE_MAX_SPAWNS=3`;
   fortificar o subir perdona), los toasts de presión suenan (⚠️ → "noche",
   🌬️🦇🔥 → "invasion") y `UNDERGROUND_BAND=10` (la superficie generada llega
   a `SKY_ROWS+8`: con la banda anterior de 6, un valle profundo contaba
   como cueva y generaba presión injusta — bug arreglado).
5. ✅ **Banner de jefe dedicado**: `_boss_announce_panel`/
   `_boss_announce_label` (centrado, 8s con fade) reemplaza el toast genérico
   para el anuncio del jefe de la run, vía RPC `show_boss_announcement`.
6. ✅ Test headless (TEST 37a-g): tiles nuevos generados en su bioma con
   HP/drop/sólido correctos, ralentización en agua + sonido "agua",
   `_has_fort`, `_zone_at` (incluido que un valle de superficie NO es cueva),
   telegraph ⚠️ antes del disparo, la presión ambiental dispara `spawn_near`
   y escala al reincidir, banner de jefe con nombre.

## Bloque 2: Progresión elemental y jefes adaptativos ✅ HECHO (2026-06-13)

Segundo de los bloques acordados con el jugador (sesión 2026-06-12): da uso a
los 4 minerales del Bloque 1, contiene el agua dispersa en lagos reconocibles
y hace que el jefe de la run reaccione si el jugador se esconde en una zona
que no puede amenazar.

1. ✅ **Lagos contenidos**: `world._spawn_lakes()` (llamado tras
   `_spawn_islands()` en `generate()`) reemplaza los "ríos" dispersos de
   `water_noise` por un BFS flood-fill desde 2-4 puntos aleatorios de la banda
   profunda, generando 2-4 lagos de `T_WATER` de 18-40 tiles — charcos grandes
   y delimitados que sirven de barrera/ralentización cerca de torres y
   pinchos.
2. ✅ **Agua ralentiza también a los NPC terrestres**: `npc_manager._move`
   aplica el mismo `WATER_SLOW=0.55` que `player._simulate_step` sobre
   `T_WATER` (los voladores, `fly: true`, no se ven afectados).
3. ✅ **Recetas mega de diamante**: `espada_diamante`
   (`wood4+diamante6+ascua4`, `WEAPON_DAMAGE=90`) y `armadura_diamante`
   (`stone10+diamante8+esencia4+pluma4`, `ARMOR_REDUCTION=10`) cierran
   `TIER_CHAINS["espada"]`/`["armadura"]` tras la dorada (mismo gating de
   `_do_craft`: hay que tener la dorada antes de poder craftear la de
   diamante) — usan los 4 minerales del Bloque 1.
4. ✅ **Torre mega**: `T_TOWER_MEGA` (18, 400 HP, sólido, drop
   `"torre_mega"`), receta `stone20+diamante6+ascua4+cristal4`, bloque
   apilable SIN cadena (`ITEM_TILE["torre_mega"] = T_TOWER_MEGA`).
   `tower_manager` la dispara con más alcance/daño/cadencia
   (`MEGA_RANGE=480`, `MEGA_COOLDOWN=0.7`, `MEGA_DAMAGE=40` vs `RANGE=320`,
   `COOLDOWN=1.2`, `ARROW_DAMAGE=18`) y tiñe sus flechas celeste/diamante. El
   panel "Fabricar" pasa de 7 a 8 filas (3 familias de equipo + 5 bloques
   apilables: muralla/fogata/trampa/torre/torre_mega).
5. ✅ **Jefes adaptativos**: `main.ZONE_BOSS_KIND` mapea cada zona a la
   variante de jefe que puede amenazarla (cielo→murciélago,
   cueva/profundo→topo, superficie→corredor). Si el jugador más cercano al
   jefe pasa `BOSS_EVOLVE_TIME=60s` en una zona que el jefe activo no puede
   alcanzar, `_update_boss_evolution` llama `npc_manager.evolve_boss(id,
   target)` — el jefe MUTA a esa variante conservando vida proporcional y
   resetea su FSM transitoria (sin embestidas/excavaciones a medias) — y
   `_broadcast_boss_evolution` reutiliza el banner dedicado del Bloque 1 +
   sonido "jefe". Cambiar de zona o ya ser la variante correcta resetea el
   contador (evita mutar "de paso").
6. ✅ Test headless (TEST 38a-h): lagos contenidos dentro de la banda
   profunda, agua ralentiza a jugador y NPC por igual, recetas mega
   craftean tras tener la dorada y no antes, `torre_mega` dispara con su
   rango/daño/cadencia propios, `evolve_boss` conserva vida proporcional y
   resetea la FSM, y la evolución se dispara/cancela según la zona del
   jugador más cercano.

## Bloque 3: Mundo vivo II — exploración y eventos ✅ HECHO (2026-06-13)

Tercero de los bloques acordados con el jugador: da motivos para EXPLORAR el
mundo expandido (cielo, superficie, subsuelo) con botín y eventos sorpresa,
en vez de quedarse fabricando en la base.

1. ✅ **Árboles en las islas aéreas**: `world._spawn_islands` planta un árbol
   (`_plant_tree`) en la cima del ~55% de las islas — antes solo crecían en
   la superficie; ahora el cielo también da madera.
2. ✅ **Vías de tren abandonadas** (`T_RAIL`, 19): `_spawn_rails` EXCAVA 3-5
   galerías mineras en el subsuelo (raíl + piso sólido + 2 de aire de techo).
   `T_RAIL` no es sólido (no estorba); minarlo da **madera x2** (`RAIL_WOOD`,
   rama propia de `world._do_hit`, sin `DROPS`).
3. ✅ **Cofres de recursos** (`T_CHEST`, 20): `_spawn_chests` reparte ~2 por
   banda (cielo/superficie/cueva/profundo). Al romperlo, `main.open_chest`
   suelta botín de `CHEST_LOOT[zona]` (rango por material, `_zone_at` del
   cofre) + Núcleos, con aviso solo al que lo abrió.
4. ✅ **Calaveras estilo Halo** (`T_SKULL`, 21): `_spawn_skulls` entierra 7
   calaveras en piedra/tierra (ocultas hasta excavarlas; todas se ven igual).
   `main.excavate_skull` elige al azar una de las 5 `SKULLS` —3 buenas
   (`monedas`/`cura`/`botin`) y 2 malas (`horda`=3 slimes, `bestia`=1 slime
   grande junto al jugador)— y avisa a TODOS. No se sabe si ayuda al jugador
   o a los enemigos hasta romperla.
5. ✅ Test headless (TEST 40a-e): tiles nuevos con HP/DROPS/SOLID y textura,
   generación siembra vías/cofres/calaveras y árboles en el cielo, vía da
   madera x2, cofre profundo suelta diamante/ascua/cristal + Núcleos, y
   excavar calaveras dispara efectos buenos Y malos.

## Bloque 4: Bestiario vivo ✅ HECHO (2026-06-13)

Cuarto bloque acordado con el jugador: más variedad y COMPORTAMIENTO de
enemigos (no solo variantes de stats), ligados a los biomas y recursos.

1. ✅ **Espectro** (`espectro`, `ghost`+`fly`): vuela y ATRAVIESA los muros
   (`_move` ignora la colisión y solo lo acota al mundo) — un contrajuego a
   amurallarse; se dibuja translúcido y palpitante. Suelta `esencia`.
2. ✅ **Coracero** (`coracero`, `armor`): tanque lento que resta `armor=7`
   a cada golpe recibido (en `_do_hit` y `damage_npc`, mín. 1 de daño) y
   rompe murallas. Suelta `ascua`.
3. ✅ **Sanador** (`sanador`, `heals`): apoyo que cada `HEAL_CD` cura
   `HEAL_AMOUNT` a los enemigos NO jefe heridos en `HEAL_RADIUS` (pulso en
   `_simulate` + `heal_fx` anillo verde) — vuelve resistentes a las hordas,
   conviene matarlo primero. Suelta `pluma`.
4. ✅ **Drops de bioma**: cada uno suelta su material (`drop`) además de
   ore/Núcleos, así que cazarlos es otra vía de farmeo de los recursos del
   Bloque 1. Entran por `_roll_kind_night` escalando con la noche
   (sanador/espectro desde la 2, coracero desde la 4).
5. ✅ Robustez: `world.spawn_nest` gana un barrido determinista de respaldo
   (siembra el nido siempre que exista hueco) — cambiar tablas de spawn ya no
   rompe el TEST 31 por desplazar el RNG.
6. ✅ Test headless (TEST 41a-e): KINDS y sprites nuevos, el espectro
   atraviesa la roca en `_move`, el coracero amortigua el daño, el sanador
   cura a un aliado herido cercano y matar un enemigo de bioma suelta su
   material propio.

## Bloque 5: Identidad visual y sonora ✅ HECHO (2026-06-13)

Último bloque acordado con el jugador: pulido audiovisual sobre todo el
contenido nuevo (cofres, calaveras, sanador), que hasta ahora no tenía
audio ni feedback visual propio.

1. ✅ **SFX procedurales nuevos** (`sfx.gd`): `cofre` (arpegio ascendente),
   `cura` (brillo suave) y `maldicion` (presagio grave), sintetizados al
   arrancar como el resto (sin archivos de audio).
2. ✅ **Cableado por prefijo de emoji** (`main._show_toast`, mismo patrón
   que el resto): 📦→`cofre` (cofre abierto / calavera del botín),
   💎→`moneda` (calavera del tesoro), 💚→`cura` (calavera vital),
   😡→`maldicion` (calavera de la furia); la 👹 Calavera Maldita reusa el
   rugido `jefe`. Aviso y sonido llegan juntos a todos los peers.
3. ✅ **Sonido del sanador**: `npc_mgr._heal_fx` añade el brillo `cura`
   cerca del jugador local — oír que sanan a la horda avisa de que conviene
   matar al sanador primero.
4. ✅ **FX de evento difundido** (`main.event_fx`, rpc cosmético): estallido
   dorado al abrir un cofre y verde/rojo al excavar una calavera buena/mala,
   visible en TODOS los peers (usa `world.fx`, no toca estado — GDD §16).
5. ✅ Test headless (TEST 43): los streams nuevos existen, los toasts de
   cofre/calavera se muestran y enrutan sonido por prefijo, y `event_fx`
   corre sin romper.

Con esto los **Bloques 1-5 (todos los acordados con el jugador) están
completos**. El siguiente hito es VALIDAR DIVERSIÓN con jugadores reales —
puerta de entrada a la Fase 11+ (campañas/mundos temáticos), que sigue
bloqueada hasta entonces.

## Fase 11+ — Evolución futura (del doc de visión, NO empezar aún)

- **Modo Campañas** (historia, NPCs, eventos — estilo Wesnoth).
- **Mundos temáticos** (reglas/enemigos distintos).
- ⛔ Gate: no arrancar hasta que el modo supervivencia sea demostrablemente
  divertido (probado con jugadores reales).

## Vía paralela — negocio (sin cambios, ver MONETIZACION.md)

Backend de cuentas → validación de recibos Google Play → export AAB firmado.
Prerrequisito para cobrar dinero real; independiente de las fases de gameplay.

---

## Reglas que NO cambian con la nueva visión

- Autoridad del servidor (GDD §16): el reloj de partida, las oleadas, el daño a
  murallas y las torres viven en el servidor. Los clientes dibujan.
- El mundo sigue siendo datos puros (`tiles: Dictionary`); las estructuras
  nuevas son tiles o entidades server-sim, nunca nodos de física.
- Cada fase entrega con su validación headless (`tests/smoke_*.tscn`).
- Skins solo cosméticas; la infraestructura se paga con recursos DEL juego,
  nunca con dinero real (no pay-to-win).
