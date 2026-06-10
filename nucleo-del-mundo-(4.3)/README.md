# ⛏️ Núcleo del Mundo — Fases 3-4: Chunks, Crafting, NPCs y Servidor Dedicado

Tercera iteración en **Godot 4.3+ / GDScript**. El mundo ahora es 4× más grande y se transmite por chunks, minar toma varios golpes según tu pico, hay slimes que te persiguen, meteoros que caen del cielo, guardado de partida, y el mismo proyecto puede correr como **servidor dedicado headless**.

## 🆕 Qué agregan las Fases 3-4

| Sistema | GDD | Detalle |
|---|---|---|
| Chunks 16×16 con streaming | §2.3 | El cliente pide chunks cercanos al moverse y descarga los lejanos. Ya no se envía el mundo completo al unirse |
| Renderizado por chunk | §15 | Cambiar un tile redibuja solo su chunk |
| HP por tile + grietas | §3.2, §6 | Tierra 40, madera 60, piedra 100, mineral 140. El tile se oscurece con el daño |
| Picos (herramientas) | §7.2 | Mano 20 dmg → madera 35 → piedra 60 → dorado 100. El **servidor** decide el daño consultando tu inventario real |
| Árboles | — | Fuente de madera para crafting. Tronco y hojas son decorativos (no colisionan, §3.1) |
| Crafting | §8 | 3 recetas de picos. El servidor valida y consume ingredientes |
| NPCs slime con FSM | §12 | idle → wander → chase. Simulados 100% en el servidor, sincronizados a 10 Hz. Contacto = daño; tap = atacarlos; al morir sueltan mineral |
| Vida + respawn | — | 100 HP autoritativos en el servidor. Al morir reapareces en la superficie |
| Evento meteoro | §9 | El scheduler del servidor lo dispara cada 70-120 s: cráter + mineral, anunciado a todos |
| Persistencia | §14 | JSON comprimido gzip en `user://`. Autosave cada 60 s y al cerrar. Botón "Continuar partida" |
| Servidor dedicado | §1.2 | El mismo proyecto corre headless como servidor puro |

## 🎮 Cómo se juega ahora

- **Minar:** mantén el dedo (o clic) sobre un tile — golpea cada 0.3 s. Toque corto = un golpe. Los tiles se agrietan antes de romperse.
- **Progresión:** tala árboles → fabrica el pico de madera (🛠️ arriba a la derecha) → mina piedra más rápido → pico de piedra → busca mineral (o mata slimes / espera meteoros) → pico dorado.
- **Slimes:** verdes, saltan hacia ti. Tócalos para atacar. Te quitan 8 HP por contacto.
- **Construir:** selecciona tierra/piedra/madera en el HUD y toca un espacio vacío.

## 🚀 Ejecutar

Igual que antes: Godot 4.3+ → Importar → F5. Multijugador local con **Depurar → Ejecutar múltiples instancias**.

### Servidor dedicado (Fase 4)

```bash
# Desde la carpeta del proyecto (requiere el ejecutable de Godot en el PATH):
godot --headless --path . -- --server
```

El servidor genera o carga el mundo, escucha en el puerto 7777 e imprime su IP local. Los clientes se unen normalmente con esa IP. Para producción, Godot permite exportar un build "dedicated server" para Linux que puedes subir a cualquier VPS.

## 🧪 Checklist de QA — Fases 3-4

**Chunks/streaming:**
- [ ] Únete como cliente y camina lejos del spawn: el terreno aparece antes de llegar (radio de 2 chunks)
- [ ] Vuelve sobre tus pasos: los chunks descargados se vuelven a pedir y llegan con los cambios (tiles minados siguen minados)
- [ ] Al unirte, el jugador queda "congelado" milisegundos hasta que llega su chunk — nunca cae a través del mundo

**Herramientas/crafting:**
- [ ] Minar piedra a mano (5 golpes) vs con pico de piedra (2 golpes)
- [ ] Intentar fabricar sin materiales → toast de error, nada se consume
- [ ] Cliente y host fabrican a la vez → ambos inventarios correctos

**NPCs/combate:**
- [ ] Un slime te persigue si te acercas a menos de ~10 tiles y deambula si te alejas
- [ ] Morir por slimes → respawn en superficie con 100 HP
- [ ] Matar un slime desde el cliente → el mineral llega a TU inventario
- [ ] Máximo 5 slimes vivos a la vez

**Persistencia/servidor:**
- [ ] Mina algo, cierra el host, "Continuar partida" → el mundo conserva los cambios
- [ ] Corre el servidor dedicado, conecta 2 clientes, ciérralos y reconéctalos
- [ ] El autosave del dedicado imprime "[SERVIDOR] Partida guardada" cada 60 s

## 📐 Decisiones de arquitectura de estas fases

**Streaming en vez de snapshot completo.** Antes el servidor enviaba todo el mundo al unirse; con 9600 tiles eso ya no escala. Ahora el cliente pide chunks bajo demanda y los descarta al alejarse — exactamente el modelo del GDD §2.3, y la base para mundos mucho más grandes.

**El servidor decide el daño del pico.** El cliente nunca dice "tengo pico dorado": solo dice "golpeé este tile". El servidor consulta el inventario real y aplica el daño correcto. Mismo patrón para el crafting y el combate contra NPCs.

**NPCs 100% del lado del servidor.** Los clientes ni siquiera tienen la lógica de FSM: reciben posiciones y dibujan. Imposible de hackear y trivial de extender con más tipos de enemigos.

**Qué quedó fuera (deliberadamente) para Fase 5:** matchmaking y cuentas de usuario (requieren backend externo — los inventarios por jugador persistentes dependen de esto, porque los peer-ids cambian entre sesiones), y predicción/reconciliación de movimiento (solo necesaria si movemos la simulación del jugador al servidor, el paso final de anti-cheat).

## 📦 Estructura

```
/project.godot
/scenes/main.tscn
/scripts/
  network_manager.gd     Autoload "Net" — conexiones ENet
  main.gd                Lobby, HUD, crafting, vida, persistencia, scheduler, modo dedicado
  world.gd               Chunks, streaming, HP de tiles, meteoros, validaciones
  chunk_renderer.gd      Dibujo por chunk con grietas
  npc_manager.gd         Slimes: FSM + física + combate (servidor)
  player.gd              Física AABB, gate de streaming, input, combate
  virtual_joystick.gd    Joystick dinámico multi-touch
```
