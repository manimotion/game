# 💰 MONETIZACION.md — Núcleo del Mundo

Plan de monetización del juego. **Modelo elegido: free-to-play + cosméticos**
(el más adecuado para un sandbox multijugador social: maximiza jugadores,
no rompe el balance, y es el modelo de Terraria-likes móviles exitosos).

**Regla de diseño: nunca pay-to-win.** Solo se vende apariencia (skins) y
conveniencia (monedas que también se ganan jugando). Los picos, bloques y
progresión NUNCA se venden directo.

---

## 1. Lo que YA está implementado (esta fase)

| Pieza | Dónde | Qué hace |
|---|---|---|
| Núcleos 🪙 | `main.gd` (perfiles) | Moneda del juego, server-authoritative. Slimes dan 3, minar mineral da 2. |
| Tienda de skins | `main.gd` (`SKINS`, panel 🛒) | 8 skins de 0 a 150 Núcleos. Comprar/equipar lo valida el servidor (§16). |
| Skins visibles | `player.gd` | Todos los jugadores ven tu skin (presión social = motor de compra). |
| Perfiles por nombre | `main.gd` (`profiles`) | Núcleos y skins persisten en el save del servidor, keyed por nombre. |

Este es el "loop" completo de economía funcionando **sin dinero real**:
ganar Núcleos jugando → desearlos → gastarlos en skins. Cuando se conecte
el cobro real, lo único que cambia es que habrá un segundo camino para
obtener Núcleos: comprarlos.

**Limitación conocida (aceptable en LAN, bloqueante para cobrar):** los
perfiles van por nombre sin contraseña — cualquiera puede usar tu nombre.
Por eso el dinero real exige primero el backend de cuentas (paso 3 abajo).

---

## 2. Productos a vender (cuando haya cobro real)

### Paquetes de Núcleos (IAP consumible) — el producto principal
| Producto | Núcleos | Precio sugerido |
|---|---|---|
| Puñado | 200 | US$ 0.99 |
| Bolsa | 550 (+10%) | US$ 2.49 |
| Cofre | 1.200 (+20%) | US$ 4.99 |
| Núcleo gigante | 2.800 (+40%) | US$ 9.99 |

En el código: tras validar la compra, el servidor llama `add_coins(peer_id, n)`.
Ya existe — no hay que tocar la economía.

### Skins premium exclusivas (IAP no consumible)
Skins que NO se pueden comprar con Núcleos, solo con dinero (US$ 1.99–3.99).
En el código: agregar al catálogo `SKINS` con `"precio": -1` (no comprable
en tienda) y otorgarlas con un `prof.skins.append()` server-side tras la compra.

### Pase de temporada (más adelante, cuando haya más contenido)
30 días de recompensas diarias (Núcleos + 1 skin exclusiva). US$ 4.99.
Requiere el scheduler que ya existe (`main.gd`) + fechas del backend.

### Anuncios recompensados (AdMob) — opcional, ingreso secundario
"Ver un video → +15 Núcleos" (límite 5/día). No molesta porque es voluntario.
Plugin oficial: `godot-admob` (Poing Studios). Decisión: probar primero solo
IAP; agregar ads únicamente si la conversión de compras es baja.

### Lo que NO recomiendo
- **Precio de venta directo (pago por descargar):** mata el multijugador
  (necesitas masa de jugadores) y en Play Store los sandbox de pago no despegan.
- **Anuncios intersticiales forzados:** destruyen retención en juegos de sesión larga.

---

## 3. Camino al primer peso cobrado (en orden, sin saltarse pasos)

1. **Terminar el juego jugable** (roadmap Fase 5): sprites, más contenido.
   Nadie paga en un prototipo de rectángulos — el arte vende las skins.
2. **Export Android firmado (AAB)**: instalar export templates de Godot,
   crear keystore (`keytool`), configurar `export_presets.cfg`.
3. **Backend de cuentas** (roadmap §4): login real (aunque sea anónimo de
   Firebase/Supabase + nickname). Sin esto, las compras no se pueden atar a
   nadie de forma segura. Los `profiles` por nombre actuales migran tal cual:
   misma estructura `{coins, skins, skin}`, solo cambia la clave (uid).
4. **Cuenta de Google Play Console**: pago único de US$ 25. Crear la ficha
   de la app + cuenta de comerciante (necesaria para vender).
5. **Plugin de facturación**: `godot-google-play-billing` (el oficial de
   Godot 4). Definir los productos del punto 2 en Play Console con los
   mismos IDs (ej. `nucleos_200`).
6. **Validación de recibos EN EL SERVIDOR** — crítico (es la regla §16
   aplicada al dinero): el cliente compra → recibe `purchase_token` → lo
   manda al servidor → el servidor lo verifica contra la API de Google Play
   (endpoint `purchases.products.get`) → solo entonces `add_coins()`.
   **Nunca** acreditar Núcleos confiando en lo que dice el cliente.
7. **Prueba cerrada** (testers internos de Play Console, compras de prueba),
   luego producción.

---

## 4. Proyección honesta

Con cosméticos, la referencia de la industria es: 2–5% de jugadores pagan,
ARPU mensual de US$ 0.05–0.30 en este género para un indie. Es decir: la
monetización solo importa si el juego retiene jugadores. **La prioridad
sigue siendo el roadmap de contenido (arte, sonido, más enemigos/eventos)**;
la infraestructura de cobro de este documento ya está lista para enchufarse
cuando llegue el momento.
