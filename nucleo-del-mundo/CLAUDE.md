# CLAUDE.md — Núcleo del Mundo

Juego sandbox 2D multijugador para Android, en **Godot 4.3+ / GDScript**.
**Identidad actual** (ver `Evolución de la Visión del Proyecto.md`): sandbox de
supervivencia por noches — de día recolectas y construyes, de noche defiendes;
el objetivo es sobrevivir X noches. La base (murallas, torres, trampas) es una
vía de progresión tan importante como el equipo. El plan por fases está en
`ROADMAP.md`; el GDD original sigue siendo la referencia técnica de los sistemas
base. Estado: Fases 1-6 completadas (core sandbox + monetización + arte/SFX
procedurales + ciclo día/noche jugable con modos Supervivencia/Sandbox);
la Fase 7 (defensa pasiva: murallas y fogata) es lo siguiente.
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
  cosmético: nunca viaja por red ni toca estado del juego.
- `scripts/main.gd` — lobby (modos Supervivencia/Sandbox), HUD (fase del ciclo, barra de
  vida, equipo, toast central con desvanecido), spawn, inventarios (servidor), crafting,
  vida/respawn + regeneración lenta, RELOJ DE PARTIDA día/noche (Fase 6: `is_night`,
  `night_number`, `_set_phase` dispara `night_wave`; solo el servidor cambia de fase),
  persistencia (gzip JSON en `user://nucleo_save.json.gz`; las runs de supervivencia NO
  guardan), scheduler (autosave, meteoro diurno con aviso), modo `--server`. MONETIZACIÓN:
  catálogo `SKINS`, Núcleos (`add_coins`), tienda 🛒 y perfiles `profiles` persistidos (v4).
- `scripts/world.gd` — tiles, chunks/streaming, HP por tile, minado/colocación, generación
  con cuevas (ruido 2D) e islas flotantes, luz día/noche (`daylight()` delega en el reloj
  de partida de main.gd), meteoro (FX de impacto + sacudida de cámara), validaciones
  de alcance.
- `scripts/fx.gd` — partículas, textos flotantes ("+N item"), anillos de impacto y ambiente
  (luciérnagas/polen/polvo). 100% visual y local, nunca toca estado.
- `scripts/player.gd` — física AABB, cámara (con `shake()`), input (joystick táctil +
  teclado), combate.
- `scripts/npc_manager.gd` — enemigos FSM con variantes en `KINDS` (slimes
  normal/grande/dorado + murciélago volador `fly: true`, nocturno); oleadas nocturnas
  vía `night_wave(noche)` (3+noche enemigos, escala con la noche); de noche el spawn
  regular también se acelera.
- `scripts/virtual_joystick.gd` — joystick multi-touch; consume sus toques con
  `set_input_as_handled()` para no interferir con minar.
- `scripts/chunk_renderer.gd` — dibujo por chunk con grietas de daño y decoración
  de superficie (hierba alta/flores del Atlas, por hash de coordenada).

La UI se construye por código en `main.gd` (sin .tscn complejos, decisión de prototipo).
`scenes/main.tscn` es mínimo a propósito.

## Convenciones

- GDScript tipado (`:=`, tipos en parámetros y retornos). Comentarios en español con
  referencia a la sección del GDD que implementan (ej. `# GDD §6`).
- RPCs: `reliable` para acciones/estado, `unreliable_ordered` solo para posiciones.
- Items son strings: materiales (`dirt`, `stone`, `wood`, `ore`) y equipo craftable
  (`pico_*`, `espada_*`, `armadura_*` en madera/piedra/dorado — claves de `RECIPES`).
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
de run (win/lose, escalado, recompensas) → Fase 10+ campañas y mundos temáticos.

Vía paralela de negocio (independiente del gameplay, ver MONETIZACION.md):
backend de cuentas (los `profiles` por nombre migran tal cual, la clave pasa de
nombre a uid) → validación de recibos de Google Play → export AAB firmado.

Deuda técnica pendiente (sin fase asignada): movimiento server-authoritative +
predicción (GDD §10.2), tests GUT formales, animaciones pulidas.
