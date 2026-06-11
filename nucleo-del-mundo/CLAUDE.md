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
El plan de negocio y el camino a cobrar dinero real está en `MONETIZACION.md`.

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

**Excepción consciente:** el movimiento del jugador es client-authoritative (cada peer tiene
`set_multiplayer_authority` sobre su nodo Player y transmite posición a 20 Hz). La migración
a movimiento server-side + predicción/reconciliación es Fase 5; no implementarla parcialmente.

**El mundo es datos puros:** `world.tiles: Dictionary[Vector2i → int]`. Sin TileMap, sin nodos
de colisión. La física es AABB manual contra ese diccionario, resuelta por eje (X, luego Y).
Esto es deliberado (red, persistencia, chunks, testeo) — no migrar a física del motor.

**Chunks (GDD §2):** 16×16 tiles. El cliente pide chunks cercanos (`update_streaming`) y
descarga lejanos. Chunk no cargado = sólido + física del jugador congelada (`area_ready`).
Render: un `chunk_renderer.gd` por chunk; al cambiar un tile se redibuja solo su chunk.

**NPCs (GDD §12):** simulación 100% en servidor (`npc_manager.gd`), snapshot de posiciones
a 10 Hz por rpc unreliable. Los clientes solo dibujan. Nuevos enemigos siguen este patrón.

## Archivos

- `scripts/network_manager.gd` — autoload `Net`. Host/join ENet, señales de conexión.
- `scripts/sfx.gd` — autoload `Sfx`. SFX y música de fondo procedurales (WAV sintetizado
  al arrancar; la música es un loop suave Am–F–C–G, omitida en headless). 100% local y
  cosmético: nunca viaja por red ni toca estado del juego. Incluye jingles
  (`_make_jingle`) de victoria/derrota y sonidos de torre/pinchos/jefe/amanecer/noche;
  `main._show_toast` dispara sonido por PREFIJO de emoji del toast (☄️🛠️👾👹🌙☀️) —
  así el aviso y su sonido llegan juntos a todos los peers. Fase 10: sonido
  "embestida" (embistedor/jefe_corredor) y de eclosión de nido.
- `scripts/main.gd` — lobby (modos Supervivencia/Sandbox), HUD (fase del ciclo, barra de
  vida, equipo, toast central con desvanecido), spawn, inventarios (servidor), crafting
  (equipo único + bloques apilables: muralla/fogata/trampa/torre), vida/respawn en fogata
  más cercana + regeneración nocturna solo cerca de fogata (Fase 7), RELOJ DE PARTIDA
  día/noche (Fase 6: `is_night`, `night_number`, `_set_phase` dispara `night_wave`; solo
  el servidor cambia de fase), persistencia (gzip JSON en `user://nucleo_save.json.gz`;
  las runs de supervivencia NO guardan), scheduler (autosave, meteoro diurno con aviso),
  modo `--server`.
  ESTRUCTURA DE RUN (Fase 9): al amanecer (`_set_phase(false)`) reparte Núcleos por noche
  sobrevivida (`NIGHT_REWARD_BASE`/`NIGHT_REWARD_STEP`); `_end_run(victory)` (guardado por
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
- `scripts/world.gd` — tiles (incluye T_WALL 400 HP, T_CAMPFIRE 200 HP — Fase 7,
  T_SPIKES 120 HP no sólida y T_TOWER 250 HP sólida — Fase 8, T_NEST 150 HP
  sólida — Fase 10: `spawn_nest(near_x)` busca una cara de aire en una cueva
  cercana y coloca un nido; destruirlo (`_do_hit`) llama a
  `main.on_nest_destroyed`), chunks/streaming,
  HP por tile, minado/colocación, `damage_tile()` para daño de NPCs,
  `nearest_campfire_pos()`, generación con cuevas (ruido 2D) e islas flotantes, luz
  día/noche (`daylight()` delega en el reloj de partida de main.gd), meteoro (FX de
  impacto + sacudida de cámara), validaciones de alcance.
- `scripts/fx.gd` — partículas, textos flotantes ("+N item"), anillos de impacto y ambiente
  (luciérnagas/polen/polvo). 100% visual y local, nunca toca estado.
- `scripts/player.gd` — física AABB, cámara (con `shake()`), input (joystick táctil +
  teclado), combate.
- `scripts/npc_manager.gd` — enemigos FSM con variantes en `KINDS` (slimes
  normal/grande/dorado + murciélago volador `fly: true`, nocturno + "jefe" Fase 9);
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
  unreliable cosméticos `charge_fx`/`nest_spawn_fx`.
- `scripts/tower_manager.gd` — torre de flechas (Fase 8), mismo patrón que
  `npc_manager`: el servidor re-escanea `world.tiles` cada `SCAN_EVERY` segundos
  buscando `T_TOWER`, dispara con cooldown al enemigo más cercano en rango
  (`_nearest_enemy`) y simula las flechas (`arrows`) hasta impactar
  (`npc_mgr.damage_npc`) o agotar su vida útil; snapshot `(pos, dir)` a 10 Hz vía
  `sync_arrows`, los clientes solo dibujan con `Atlas.arrow_tex` (+ estela que se
  desvanece). PULIDO: rpc unreliable cosmético `fired_fx` (fogonazo + sonido "flecha"
  con gate de distancia) al disparar.
- `scripts/virtual_joystick.gd` — joystick multi-touch; consume sus toques con
  `set_input_as_handled()` para no interferir con minar.
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
- Items son strings: materiales (`dirt`, `stone`, `wood`, `ore`), equipo craftable
  (`pico_*`, `espada_*`, `armadura_*` — únicos, max 1) y bloques craftables apilables
  (`muralla`, `fogata`, `trampa`, `torre` — se colocan con ITEM_TILE).
  Picos minan (`TOOL_DAMAGE`), espadas pegan a NPCs (`WEAPON_DAMAGE`), armaduras
  reducen daño recibido (`ARMOR_REDUCTION`); el servidor consulta el inventario real.
- Skins son strings (claves de `SKINS` en main.gd). Los Núcleos NO son item de inventario:
  viven en el perfil (`profiles`) y solo el servidor los modifica (`add_coins`).
- Las skins son SOLO cosméticas — nunca vender ventaja de juego (ver MONETIZACION.md).
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

## Roadmap

El plan por fases vive en **`ROADMAP.md`** (derivado de la visión de supervivencia
por noches). Resumen: Fase 6 ciclo día/noche jugable → Fase 7 defensa pasiva
(murallas, fogata) → Fase 8 defensa activa (torres, trampas) → Fase 9 estructura
de run (win/lose, escalado, recompensas) → Fase 10 bestiario expandido (taladro/
topo que excavan, embistedor, fusión de slimes, nidos, roster de 4 jefes
anunciado al iniciar) → Fase 11+ campañas y mundos temáticos.
Fases 1-10 completas; la Fase 11+ está bloqueada hasta validar diversión con
jugadores reales.

Vía paralela de negocio (independiente del gameplay, ver MONETIZACION.md):
backend de cuentas (los `profiles` por nombre migran tal cual, la clave pasa de
nombre a uid) → validación de recibos de Google Play → export AAB firmado.

Deuda técnica pendiente (sin fase asignada): movimiento server-authoritative +
predicción (GDD §10.2), tests GUT formales, animaciones pulidas.
