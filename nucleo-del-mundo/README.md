# 🌙 Núcleo del Mundo

Sandbox de supervivencia 2D multijugador para Android, en **Godot 4.3+ / GDScript**.

> "Un sandbox donde el jugador debe sobrevivir una serie de noches mientras
> construye, progresa y diseña un sistema de defensa vivo contra el mundo."

De día exploras, minas, talas y construyes; al caer la noche, oleadas de
enemigos atacan tu base. La infraestructura (murallas, fogatas, trampas,
torres) es una vía de progresión tan importante como el equipo.

**Estado: Fases 1-10 completadas.** El plan por fases vive en
[`ROADMAP.md`](ROADMAP.md), la arquitectura y convenciones en
[`CLAUDE.md`](CLAUDE.md), y el diseño técnico de referencia en el GDD original.

## ✅ Qué incluye el juego hoy

- **Core sandbox multijugador** (Fases 1-4): mundo en chunks 16×16 con
  streaming, minado/colocación con HP por tile y grietas, árboles, picos
  progresivos (madera → piedra → dorado), crafting validado por el servidor,
  meteoros, persistencia (gzip JSON) y servidor dedicado headless.
- **Monetización cosmética** (Fase 5): Núcleos, tienda 🛒, skins (solo
  cosméticas, nunca ventaja de juego) y perfiles persistentes.
- **Arte y sonido procedurales**: sprites/texturas y SFX/música generados en
  código (sin assets externos), incluyendo jingles, fogata viva y FX de
  partículas.
- **Ciclo día/noche jugable** (Fase 6): reloj de partida server-authoritative,
  modos Supervivencia (7 noches) y Sandbox libre, oleadas nocturnas
  escaladas por noche, primer enemigo volador (murciélago).
- **Defensa pasiva** (Fase 7): muralla (bloquea y absorbe daño) y fogata
  (respawn + regeneración nocturna cerca de ella).
- **Defensa activa** (Fase 8): trampa de pinchos (daño por contacto) y torre
  de flechas (dispara sola al enemigo más cercano).
- **Estructura de run** (Fase 9): jefe cada 5 noches, recompensa de Núcleos
  por noche sobrevivida, panel de victoria/derrota con resumen de la run
  (noches, bajas, recursos, bono).
- **Bestiario expandido y jefes variados** (Fase 10): "taladro" y "topo"
  excavan bloques (y destruyen pinchos al pasar), "topo" nace en cuevas,
  "embistedor" carga y embiste en horizontal, los slimes se fusionan en
  variantes más grandes y poderosas, los "nidos" escupen enemigos si no se
  destruyen a tiempo, y un roster de 4 jefes (clásico, murciélago gigante,
  mega topo, mega corredor) se elige al azar y se **anuncia al iniciar la
  run** con una pista táctica.

La Fase 11+ (campañas / mundos temáticos) está **bloqueada** hasta validar
diversión con jugadores reales.

## 🎮 Cómo se juega

- **Lobby**: elige "🌙 Supervivencia — 7 noches" (sin guardado, con
  victoria/derrota) o "🏖️ Sandbox libre" (con guardado y sin oleadas
  nocturnas exigentes).
- **De día**: mina, recolecta madera/piedra/mineral y fabrica equipo y
  bloques de defensa (panel "🛠️ Fabricar").
- **Al anochecer**: un toast avisa y llega una oleada que escala con el
  número de noche; cada 5 noches aparece además el jefe de la run.
- **Defiéndete**: coloca murallas para bloquear el paso, fogatas para curarte
  de noche, trampas de pinchos y torres de flechas para daño automático.
- **Cuidado con**: taladros/topos que excavan bajo tu base, embistedores que
  cargan y golpean fuerte en línea recta, slimes que se fusionan si los dejas
  agruparse, y nidos que hay que destruir antes de que empiecen a escupir
  enemigos.
- **Sobrevive 7 noches** para ganar (bono de Núcleos); morir de noche en
  supervivencia termina la run con un panel de resumen.

## 🚀 Ejecutar

Godot 4.3+ → Importar → F5. Multijugador local: **Depurar → Ejecutar
múltiples instancias**.

### Servidor dedicado

```bash
# Desde la carpeta del proyecto (requiere el ejecutable de Godot en el PATH):
godot --headless --path . -- --server
```

El servidor genera o carga el mundo, escucha en el puerto 7777 e imprime su
IP local. Los clientes se unen normalmente con esa IP.

### Validación tras editar `.gd`

```bash
# Comprobar que el proyecto parsea sin errores
godot --headless --path . --quit-after 2

# Smoke test headless (crafting, HUD, defensa, run, bestiario) — exit 0 = OK
godot --headless --path . res://tests/smoke_craft.tscn --quit-after 10
```

## 📦 Estructura

```
/project.godot
/scenes/main.tscn
/tests/
  smoke_craft.tscn + smoke_craft.gd   Smoke test headless (32 grupos de prueba)
/scripts/
  network_manager.gd   Autoload "Net" — host/join ENet, señales de conexión
  sfx.gd               Autoload "Sfx" — SFX y música procedurales (cosmético, local)
  atlas.gd             Autoload "Atlas" — sprites/texturas generados por código
  fx.gd                Partículas, textos flotantes, anillos de impacto, ambiente
  main.gd              Lobby, HUD, crafting, ciclo día/noche, estructura de run,
                        persistencia, monetización, scheduler, modo --server
  world.gd             Tiles, chunks/streaming, generación (cuevas + islas),
                        HP por tile, minado/colocación, meteoro, nidos (T_NEST)
  npc_manager.gd       Enemigos: FSM, oleadas nocturnas, roster de jefes,
                        excavación, embestida, fusión de slimes, nidos
  tower_manager.gd     Torre de flechas (simulación 100% en servidor)
  player.gd            Física AABB, cámara, input (joystick táctil + teclado), combate
  chunk_renderer.gd    Dibujo por chunk: grietas, decoración, fogata viva
  virtual_joystick.gd  Joystick dinámico multi-touch
```

## 📚 Documentación

- [`CLAUDE.md`](CLAUDE.md) — arquitectura (autoridad del servidor, patrón de
  RPCs, mundo como datos puros, chunks, NPCs), convenciones y trampas conocidas.
- [`ROADMAP.md`](ROADMAP.md) — plan por fases, qué se hizo en cada una y qué
  falta (Fase 11+, deuda técnica).
- [`MONETIZACION.md`](MONETIZACION.md) — plan de negocio y camino a cobrar
  dinero real.
- [`GDD - Núcleo del Mundo (1).md`](<GDD - Núcleo del Mundo (1).md>) — diseño
  técnico de referencia de los sistemas base.
- [`Evolución de la Visión del Proyecto.md`](<Evolución de la Visión del Proyecto.md>)
  — historia de cómo cambió la visión del proyecto hasta la identidad actual.
