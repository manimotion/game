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

## Fase 6 — Ciclo día/noche JUGABLE (la fundación) 🎯 SIGUIENTE

El resto del roadmap cuelga de esto. Sin reloj de partida no hay runs.

1. **Reloj de partida en el servidor**: `game_time` avanza en el scheduler de
   `main.gd`, se sincroniza a los peers (RPC reliable al cambiar de fase basta).
   `world.daylight()` pasa a leer este reloj (la hora del sistema queda solo
   como fallback del menú). Día ≈ 3 min, noche ≈ 1.5 min (constantes arriba).
2. **La noche dispara oleadas**: al anochecer, `spawn_wave()` con tamaño/variantes
   escalados por número de noche. El timer de invasión aleatoria desaparece
   (las invasiones SON la noche). El meteoro queda como evento diurno.
3. **HUD del ciclo**: contador "🌙 Noche 3" / "☀️ Día 4", aviso de atardecer
   ("anochece en 30 s"), todo en el panel superior.
4. **Selector de modo en el lobby**: *Sandbox* (mundo actual, persistente) y
   *Supervivencia* (run de X noches). El save actual es el modo sandbox.

## Fase 7 — La base importa: defensa pasiva

1. **Muralla**: tile craftable (piedra), HP alto (~400). De noche los slimes
   **atacan los bloques** que les cierran el paso (FSM: si está bloqueado hacia
   el jugador, golpea el tile). Mismo pipeline de HP/grietas que el minado.
2. **Fogata/refugio**: tile especial — punto de respawn del equipo y aura de
   regeneración (la regen global de hoy migra aquí). Una por base.
3. Test headless: muralla absorbe daño de slime; regen solo cerca de fogata.

## Fase 8 — Defensa activa (torres y trampas)

1. **Torre de flechas**: entidad simulada en servidor (mismo patrón que
   `npc_manager`: estado en servidor, snapshot 10 Hz, clientes dibujan).
   Dispara al enemigo más cercano en rango; proyectil server-side.
2. **Trampa de pinchos**: tile que daña NPCs por contacto (server).
3. Costos altos en mineral/Núcleos de juego → sumidero de recursos que da
   propósito al minado profundo (cuevas) y a las islas.

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
