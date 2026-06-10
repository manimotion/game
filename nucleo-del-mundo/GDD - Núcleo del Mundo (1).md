# 🧰 Especificación Técnica

## Proyecto: Núcleo del Mundo

# 🏗️ 1. ARQUITECTURA GENERAL

## 1.1 Modelo

- Arquitectura: Cliente–Servidor
- Autoridad: Server authoritative
- Sincronización: Estado + eventos (delta updates)

## 1.2 Componentes

- Cliente (Unity / motor 2D)
- Servidor de juego (instancias por mundo)
- Backend (usuarios, matchmaking, persistencia)

# 🌍 2. MODELO DE MUNDO (CHUNKS)

## 2.1 División

- Mundo dividido en chunks (ej: 32x32 tiles)
- Capas: cielo, superficie, subsuelo

## 2.2 Datos de chunk

1 {

2   "chunkId": "x_y_layer",

3   "tiles": \[\],

4   "entities": \[\],

5   "resources": \[\],

6   "modified": true

7 }

## 2.3 Streaming

- Carga dinámica según posición del jugador
- Caché local de chunks cercanos

# 🧱 3. SISTEMA DE TILES

## 3.1 Tipos

- Sólido
- Fluido
- Decorativo
- Interactivo

## 3.2 Estructura

1 {

2   "id": "stone",

3   "hp": 100,

4   "drop": "stone_item",

5   "collision": true

6 }

# 👤 4. ENTIDADES

## 4.1 Tipos

- Jugadores
- NPCs
- Enemigos
- Objetos

## 4.2 Base Entity

1 Entity {

2   id: string

3   position: Vector2

4   velocity: Vector2

5   health: number

6   state: string

7 }

## 4.3 Sistema ECS (recomendado)

- Components: Transform, Render, Physics, AI
- Systems: Movement, Combat, AI, Networking

# ⚙️ 5. SISTEMA DE FÍSICA

- Motor 2D (Box2D o equivalente)
- Colisiones AABB
- Movimiento basado en fuerzas

# ⛏️ 6. MECÁNICA DE MINADO

Proceso:

1.  Input jugador
2.  Raycast al tile
3.  Reducir HP
4.  Drop item
5.  Sincronizar evento

# 📦 7. INVENTARIO

## 7.1 Estructura

1 {

2   "slots": \[

3     {"item": "stone", "qty": 32}

4   \]

5 }

## 7.2 Reglas

- Stack limit
- Consumo
- Equipamiento

# 🛠️ 8. CRAFTING

## 8.1 Recetas

1 {

2   "recipeId": "pickaxe_1",

3   "ingredients": \[

4     {"item": "wood", "qty": 10}

5   \],

6   "output": "pickaxe"

7 }

## 8.2 Tipos

- Manual
- Estaciones

# 🌩️ 9. EVENTOS DEL MUNDO

## 9.1 Sistema

- Scheduler en servidor
- Eventos globales sincronizados

## 9.2 Ejemplo

1 {

2   "event": "island_fall",

3   "targetChunk": "12_8_sky"

4 }

# 🧑‍🤝‍🧑 10. MULTIJUGADOR

## 10.1 Networking

- Protocolo: UDP (realtime)
- Fallback: TCP

## 10.2 Sincronización

- Snapshot parcial
- Interpolación cliente
- Reconciliación

## 10.3 Gestión de salas

- Matchmaking
- Instancias por sesión

# 🔋 11. SISTEMA DE ENERGÍA

- Red de nodos conectados
- Flujo desde subsuelo
- Buff en cielo

# 🤖 12. IA NPC

- FSM (Finite State Machine)
- Estados: idle, work, attack, flee

# 📱 13. INPUT MOBILE

- Joystick virtual
- Botones contextuales
- Auto-target

# 💾 14. PERSISTENCIA

## 14.1 Datos guardados

- Estado del mundo
- Inventarios
- Progreso

## 14.2 Formato

- JSON comprimido
- Base de datos (NoSQL recomendado)

# 🚀 15. OPTIMIZACIÓN

- Pooling de objetos
- Culling
- Limitación de entidades activas

# 🔐 16. SEGURIDAD

- Validación en servidor
- Anti-cheat básico
- Autoridad total servidor

# 🧪 17. TESTING

- Unit tests
- Simulación de carga
- Pruebas multiplayer

# 📦 18. ESTRUCTURA DE PROYECTO

1 /Client

2 /Server

3 /Shared

4 /Assets

5 /Networking

# ✅ CONCLUSIÓN

Documento técnico listo para implementación en Fable 5 o motor similar, cubriendo arquitectura, sistemas base y estructura para desarrollo escalable.