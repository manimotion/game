# 🎯 CONTEXTO PARA CLAUDE

## Proyecto: Núcleo del Mundo (Dirección de Producto)

# 🧠 VISIÓN GENERAL

Estamos desarrollando un videojuego 2D sandbox tipo Terraria, pero con una evolución más ambiciosa:

El objetivo no es solo crear un juego, sino construir una base que evolucione hacia una plataforma de mundos y campañas.

# 🎮 CONCEPTO BASE

El juego consiste en:

- Mundo 2D procedural
- Jugador con movimiento, salto y físicas
- Sistema de bloques (minar y construir)
- Exploración vertical en 3 capas:
	- Cielo (islas flotantes)
	- Superficie
	- Subsuelo

El gameplay principal es:

- Minar
- Construir
- Sobrevivir
- Explorar

# 🚀 OBJETIVO A LARGO PLAZO

El proyecto evolucionará hacia algo más similar a:

Una mezcla entre Terraria + Roblox + Wesnoth

Esto significa:

## 🧩 1. Core Engine (Juego base)

El núcleo debe ser genérico y reusable.

NO debe contener:

- Historia fija
- Misiones hardcodeadas
- Temas específicos

Debe contener:

- Movimiento
- Física
- Sistema de tiles
- Minado
- Construcción
- Inventario

## 🌍 2. Sistema de “temas” o mundos

El juego debe permitir cargar distintas configuraciones:

Ejemplo de tema:

- Fantasy
- Sci-fi
- Survival

Cada tema define:

- Enemigos
- Items
- Biomas
- Música
- Assets visuales

## 📖 3. Sistema de campañas (estilo Wesnoth)

Cada mundo puede incluir una campaña narrativa.

Una campaña debe incluir:

- Historia
- NPCs
- Misiones
- Eventos
- Progresión

Ejemplo:

- NPC guía da misiones
- Evento al entrar a zona
- Spawn de enemigos
- Boss final

# ⚙️ PRINCIPIOS DE DESARROLLO

1.  Construir primero el CORE antes que contenido
2.  Evitar sobreingeniería
3.  Mantener sistemas modulares
4.  Separar claramente:
	- Engine
	- Tema
	- Campaña

# 🔥 ESTADO ACTUAL DEL PROYECTO

Actualmente ya existe:

- Generación de terreno procedural
- Sistema de tiles
- Jugador con movimiento
- UI básica

Faltan sistemas clave:

- Minado de bloques
- Colocación de bloques
- Inventario

# 🎯 OBJETIVO INMEDIATO

NO construir campañas todavía.

Prioridad absoluta:

1.  Implementar minado de bloques
2.  Implementar colocación de bloques
3.  Implementar inventario básico

# 🧠 CÓMO RESPONDER COMO CLAUDE

Cuando generes soluciones:

- Divide problemas en pasos pequeños
- Prioriza implementación práctica
- Evita soluciones complejas innecesarias
- Explica decisiones técnicas
- Enfócate en prototipo funcional

# ❌ EVITAR

- Diseños gigantes
- Sistemas completos de RPG desde inicio
- Historia compleja
- Features innecesarias

# ✅ OBJETIVO FINAL

Construir paso a paso:

1.  Juego base jugable
2.  Sistema simple de misión
3.  Primer mundo con historia
4.  Expansión hacia múltiples campañas

# 💬 CONTEXTO FINAL

Este proyecto es desarrollado por una sola persona usando Claude como apoyo principal.

Por lo tanto:

- Las soluciones deben ser claras y aplicables
- El código debe ser simple y mantenible
- Cada paso debe aportar valor inmediato

# 🚀 RESUMEN

Construir primero un sandbox divertido luego soportar campañas luego escalar a múltiples mundos

Este documento define la dirección del proyecto. Todas las decisiones deben alinearse con esta visión.