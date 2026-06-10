# CLAUDE.md — Núcleo del Mundo

Juego sandbox 2D multijugador (estilo Terraria) para Android, en **Godot 4.3+ / GDScript**.
Basado en el GDD "Núcleo del Mundo". Estado actual: Fases 1-4 completadas + base de
monetización de Fase 5 (Núcleos, tienda de skins, perfiles por nombre, SFX procedurales).
El plan de negocio y el camino a cobrar dinero real está en `MONETIZACION.md`.

## Comandos

```bash
# Validar que el proyecto parsea sin errores (correr SIEMPRE tras editar .gd)
godot --headless --path . --quit-after 2

# Servidor dedicado
godot --headless --path . -- --server

# Tests unitarios (cuando GUT esté instalado en addons/gut)
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

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
- `scripts/sfx.gd` — autoload `Sfx`. SFX procedurales (WAV sintetizado al arrancar).
  100% local y cosmético: nunca viaja por red ni toca estado del juego.
- `scripts/main.gd` — lobby, HUD, spawn, inventarios (servidor), crafting, vida/respawn,
  persistencia (gzip JSON en `user://nucleo_save.json.gz`), scheduler (autosave, meteoros),
  modo `--server`. MONETIZACIÓN: catálogo `SKINS`, Núcleos (`add_coins`), tienda 🛒 y
  perfiles `profiles` (nombre → {coins, skins, skin}) persistidos en el save (v4).
- `scripts/world.gd` — tiles, chunks/streaming, HP por tile, minado/colocación, meteoro,
  validaciones de alcance.
- `scripts/player.gd` — física AABB, cámara, input (joystick táctil + teclado), combate.
- `scripts/npc_manager.gd` — slimes FSM (idle/wander/chase).
- `scripts/virtual_joystick.gd` — joystick multi-touch; consume sus toques con
  `set_input_as_handled()` para no interferir con minar.
- `scripts/chunk_renderer.gd` — dibujo por chunk con grietas de daño.

La UI se construye por código en `main.gd` (sin .tscn complejos, decisión de prototipo).
`scenes/main.tscn` es mínimo a propósito.

## Convenciones

- GDScript tipado (`:=`, tipos en parámetros y retornos). Comentarios en español con
  referencia a la sección del GDD que implementan (ej. `# GDD §6`).
- RPCs: `reliable` para acciones/estado, `unreliable_ordered` solo para posiciones.
- Items son strings: `dirt`, `stone`, `wood`, `ore`, `pico_madera`, `pico_piedra`, `pico_dorado`.
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

## Roadmap pendiente (Fase 5+)

1. Arte: sprites (atlas) en chunk_renderer y player en vez de rectángulos; animaciones.
2. Música (los SFX básicos ya están en `sfx.gd`).
3. Tests GUT para `world.gd` (generación, minado, alcance) y física del jugador.
4. Backend: cuentas + matchmaking. Los `profiles` por nombre migran tal cual (misma
   estructura, la clave pasa de nombre a uid). Prerrequisito para cobrar dinero real.
5. Validación de recibos de Google Play en el servidor + paquetes de Núcleos (MONETIZACION.md §3).
6. Movimiento server-authoritative + predicción/reconciliación (GDD §10.2).
7. Sistema de energía (§11), más NPCs, eventos adicionales (§9).
8. Export Android firmado (AAB) para Play Store.
