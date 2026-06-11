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

## Fase 9 — Estructura de run completa

1. **Win/lose**: sobrevivir X noches = pantalla de victoria con resumen
   (noches, recursos, Núcleos); morir en supervivencia = fin de run.
2. **Escalado por noche**: más slimes, variantes nuevas; jefe cada 5 noches.
3. **Recompensa**: Núcleos al perfil por noche sobrevivida → engancha con la
   monetización existente (los Núcleos/skins persisten entre runs).

## Fase 10+ — Evolución futura (del doc de visión, NO empezar aún)

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
