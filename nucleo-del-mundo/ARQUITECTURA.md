# 🏛️ ARQUITECTURA — Núcleo del Mundo

El juego está separado en **3 capas** con dependencias en una sola dirección
(presentación → reglas → núcleo). El objetivo: poder crear **modos de juego,
campañas y mundos temáticos (Fase 11+)** tocando SOLO la capa de reglas,
sin reescribir el motor ni la interfaz.

```
┌─────────────────────────────────────────────────────────────┐
│  CAPA 3 — PRESENTACIÓN (cosmética, 100% local)              │
│  ui_builder.gd · atlas.gd · sfx.gd · fx.gd ·                │
│  virtual_joystick.gd · chunk_renderer.gd (dibujo)           │
│  Nunca toca estado del juego. Lee la capa de reglas para     │
│  pintarse (el lobby recorre GameModes.LOBBY_ORDER).          │
├─────────────────────────────────────────────────────────────┤
│  CAPA 2 — REGLAS DE JUEGO (data-driven)                     │
│  game_modes.gd (modos: duraciones, noches, jefes, oleadas,  │
│  recompensas) · main.gd como ORQUESTADOR (aplica las reglas │
│  del modo activo en el servidor: reloj, run, recompensas)   │
├─────────────────────────────────────────────────────────────┤
│  CAPA 1 — NÚCLEO / MOTOR (server-authoritative, GDD §16)    │
│  world.gd (tiles, chunks, física del mundo) · player.gd     │
│  (AABB, input) · npc_manager.gd (simulación de enemigos) ·  │
│  tower_manager.gd (defensas simuladas) · network_manager.gd │
│  No sabe qué modo se juega: recibe números (mode_cfg).      │
└─────────────────────────────────────────────────────────────┘
```

## Capa 1 — Núcleo / Motor

Los sistemas mecánicos: mundo como datos puros (`tiles: Dictionary`),
física AABB manual, chunks/streaming, red ENet y simulación de NPCs y
torres 100% en el servidor con snapshots a 10 Hz. **No conoce los modos
de juego**: cuando necesita un número de reglas (tamaño de oleada,
cadencia del jefe) lo lee de `main.mode_cfg` con un default seguro.

## Capa 2 — Reglas de juego

- **`game_modes.gd`** — la única fuente de verdad de QUÉ se juega:
  cada modo es un diccionario (duración día/noche, `nights_to_win`,
  `death_ends_run`, `save_allowed`, `boss_every`, `wave_base/step`,
  recompensas, `victory_bonus`, `meteors`). Solo datos y helpers puros:
  nada de nodos, red ni UI.
- **`main.gd`** — el orquestador: ejecuta esas reglas en el servidor
  (reloj de fase, oleadas, win/lose, recompensas, persistencia) y es
  dueño del estado (inventarios, vida, perfiles). `set_mode(id)` es el
  ÚNICO punto donde cambia el modo activo (`game_mode` + `mode_cfg`);
  se llama al hostear, en `apply_phase` (clientes) y en `_reset_run`.

### Cómo añadir un modo de juego

1. Añade una entrada a `GameModes.MODES` (y a `LOBBY_ORDER` si va en el menú).
2. No hay paso 2. El lobby lo muestra, el reloj/oleadas/recompensas lo
   obedecen y el smoke test 33 valida la mecánica genérica.

### Cómo encajarán las campañas (Fase 11+)

Una campaña es una SECUENCIA de modos: cada "misión" es un diccionario
con la misma forma que `MODES` (+ texto narrativo / condiciones extra).
Un `campaign_runner` en la capa de reglas iría llamando `set_mode()` con
la config de cada misión al completarse la anterior. Ni el motor ni la
UI necesitan cambios estructurales.

## Capa 3 — Presentación

Arte (`atlas.gd`, sprites procedurales), sonido (`sfx.gd`), partículas
(`fx.gd`), interfaz (`ui_builder.gd` construye lobby y HUD por código y
asigna las referencias a `main`, que sigue siendo dueño del estado) y
dibujo de chunks. **Regla dura: esta capa nunca modifica estado del
juego** — los efectos en red viajan como rpcs `unreliable` puramente
cosméticos con gate de distancia (`block_hit_fx`, `charge_fx`,
`fusion_fx`, `nest_spawn_fx`, `fired_fx`); el estado real solo viaja
por los canales de siempre (`sync_npcs`, `damage_tile`, `apply_*`).

Telegraphs del bestiario: el snapshot de NPCs lleva un 4º campo `st`
(0 nada, 1 cargando, 2 embistiendo, 3 jefe enfurecido) para que los
clientes dibujen avisos (sacudida + "!", líneas de velocidad, tinte
rojo, aura del jefe) sin conocer la FSM real del servidor.

## Reglas transversales (no cambian)

- **Autoridad del servidor (GDD §16)**: patrón `try_X → request_X →
  _do_X → apply_X` para todo cambio de estado.
- El movimiento del jugador es server-authoritative con predicción/
  reconciliación (GDD §10.2): el servidor simula a TODOS los jugadores
  y difunde `players[pid].position` real vía `sync_players`; cada
  cliente predice su nodo y `_reconcile()` corrige contra el snapshot.
- Skins SOLO cosméticas; los Núcleos viven en `profiles` (servidor).
- Cada cambio se valida con el smoke test headless
  (`tests/smoke_craft.tscn`, exit 0 = OK).
