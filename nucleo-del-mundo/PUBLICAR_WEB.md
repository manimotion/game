# Publicar en la web (itch.io) — Núcleo del Mundo

Guía para sacar un build jugable **en el navegador** (sin instalar nada),
ideal para compartir un enlace y que la gente pruebe el juego al instante.

## Importante: en web es modo SOLO

El navegador **no tiene ENet** (la red UDP del multijugador). Por eso el build
web detecta la plataforma (`Net.is_web()`) y arranca en **modo solo** con un
`OfflineMultiplayerPeer` (`Net.host_offline()`): toda la lógica
server-authoritative corre local, sin abrir puertos. El lobby web oculta la
sección de "Unirse por IP". El **multijugador LAN sigue intacto en
escritorio/Android** (ahí se usa ENet como siempre).

## Pasos para exportar

1. **Instalar plantillas de exportación** (una vez):
   Editor → *Proyecto* → *Administrar plantillas de exportación* →
   *Descargar y instalar* (la versión debe coincidir con tu Godot: 4.6.3).

2. **El preset "Web" ya está configurado** en `export_presets.cfg`
   (`variant/thread_support=false` para que funcione en itch.io **sin** las
   cabeceras especiales de `SharedArrayBuffer`).

3. **Exportar** (cualquiera de las dos):
   - Editor: *Proyecto* → *Exportar* → preset **Web** → *Exportar proyecto* →
     guardar en `export/web/index.html`.
   - Terminal (con las plantillas ya instaladas):
     ```bash
     godot --headless --path . --export-release "Web" export/web/index.html
     ```
   Genera `index.html`, `.wasm`, `.pck`, `.js`, etc. en `export/web/`
   (esa carpeta está en `.gitignore`: son artefactos, no van a git).

4. **Probar en local** (los navegadores no abren `.wasm` desde `file://`):
   ```bash
   python -m http.server 8000 --directory export/web
   ```
   y abre `http://localhost:8000`.

## Subir a itch.io

1. Crea un proyecto nuevo en itch.io → *Kind of project*: **HTML**.
2. Comprime el **contenido** de `export/web/` (no la carpeta) en un `.zip`
   (debe incluir `index.html` en la raíz del zip) y súbelo.
3. Marca **"This file will be played in the browser"**.
4. *Embed options*: tamaño del viewport ~**1280×704** (el del proyecto),
   activa **fullscreen** y **mobile friendly**.
5. Deja **"SharedArrayBuffer support"** DESACTIVADO (no hace falta, exportamos
   sin hilos).

## Notas

- El juego usa `gl_compatibility` (ya configurado en `project.godot`), que es
  el render correcto para web.
- Primer arranque: el `.wasm` (~30-40 MB) se descarga una vez; luego cachea.
- El control móvil/PC y el idioma ES/EN del menú ⚙️ Ajustes funcionan igual en
  web (el joystick táctil sirve en móvil; teclado+ratón en escritorio).
