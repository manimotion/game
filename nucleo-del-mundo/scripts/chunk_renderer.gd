# =============================================================
# chunk_renderer.gd — Renderizado por chunk (GDD §2, §15) — Fase 5B
# Cada chunk dibuja SOLO sus 16x16 tiles. Cuando un tile cambia,
# se redibuja únicamente el chunk afectado (no el mundo entero).
# Fase 5B: texturas de pixel art del Atlas (variantes por coord,
# césped si hay aire encima), grietas por daño y oscurecimiento
# progresivo con la profundidad (atmósfera de subsuelo).
# =============================================================
extends Node2D

const DEPTH_ROWS := 40.0       # filas hasta la oscuridad máxima
const DEPTH_MAX := 0.55        # cuánto se oscurece como máximo
const FIRE_REDRAW := 0.12      # cadencia de parpadeo de la fogata (Fase 7, pulido)
const EMBER_EVERY := 0.5       # cadencia media de brasas por fogata

var chunk := Vector2i.ZERO
var world: Node2D
var _fires: Array = []         # posiciones LOCALES de fogatas en este chunk
var _fire_t := 0.0
var _ember_t := 0.0


## Solo los chunks con fogata se redibujan periódicamente: el aura
## parpadea y suelta brasas (fx.ember). El resto sigue estático.
func _process(delta: float) -> void:
	if _fires.is_empty():
		return
	_fire_t += delta
	if _fire_t >= FIRE_REDRAW:
		_fire_t = 0.0
		queue_redraw()
	_ember_t -= delta
	if _ember_t <= 0.0 and world != null and world.fx != null:
		_ember_t = EMBER_EVERY * randf_range(0.6, 1.4)
		var f: Vector2 = _fires.pick_random()
		world.fx.ember(position + f + Vector2(0, -6.0))


func _draw() -> void:
	_fires.clear()
	if world == null:
		return
	var t: int = world.TILE
	for lx in world.CHUNK:
		for ly in world.CHUNK:
			var coord := Vector2i(chunk.x * world.CHUNK + lx, chunk.y * world.CHUNK + ly)
			var tt: int = world.tiles.get(coord, 0)
			if tt == 0:
				continue
			var rect := Rect2(lx * t, ly * t, t, t)
			var air_above: bool = world.tiles.get(coord + Vector2i.UP, 0) == 0
			var dark := clampf(float(coord.y - world.SKY_ROWS) / DEPTH_ROWS, 0.0, DEPTH_MAX)
			var mod := Color(1.0 - dark, 1.0 - dark, 1.0 - dark)
			draw_texture_rect(Atlas.tile_tex(tt, coord, air_above), rect, false, mod)
			# Fogata: aura cálida que PARPADEA (solo visual, Fase 7 pulida).
			# El radio y la intensidad oscilan con el tiempo; de noche el
			# resplandor se nota más (la fogata es el refugio).
			if tt == world.T_CAMPFIRE:
				var center := Vector2(lx * t + t * 0.5, ly * t + t * 0.5)
				_fires.append(center)
				var ms := float(Time.get_ticks_msec())
				var flick := 1.0 + 0.12 * sin(ms / 110.0 + center.x) + 0.06 * sin(ms / 47.0)
				var night_boost: float = 1.0 + (1.0 - world.daylight()) * 0.8
				draw_circle(center, 56.0 * flick, Color(1.0, 0.7, 0.3, 0.05 * night_boost))
				draw_circle(center, 38.0 * flick, Color(1.0, 0.65, 0.28, 0.08 * night_boost))
				draw_circle(center, 22.0 * flick, Color(1.0, 0.6, 0.25, 0.12 * night_boost))
			# Decoración sobre el césped: hierba alta y flores (solo adorno)
			if tt == world.T_DIRT and air_above and Atlas._h(coord.x, coord.y, 13) < 0.35:
				var di := int(Atlas._h(coord.x, coord.y, 14) * Atlas.deco.size()) % Atlas.deco.size()
				draw_texture_rect(Atlas.deco[di], Rect2(lx * t, (ly - 1) * t, t, t), false, mod)
			# Grietas según el daño acumulado (GDD §6)
			var ratio: float = world.damage_ratio.get(coord, 1.0)
			if ratio < 1.0:
				var lvl := 0
				if ratio < 0.4:
					lvl = 2
				elif ratio < 0.72:
					lvl = 1
				draw_texture_rect(Atlas.cracks[lvl], rect, false)
