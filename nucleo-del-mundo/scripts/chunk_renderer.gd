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

var chunk := Vector2i.ZERO
var world: Node2D


func _draw() -> void:
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
			# Fogata: aura cálida (solo visual, Fase 7)
			if tt == world.T_CAMPFIRE:
				var center := Vector2(lx * t + t * 0.5, ly * t + t * 0.5)
				draw_circle(center, 48.0, Color(1.0, 0.7, 0.3, 0.06))
				draw_circle(center, 28.0, Color(1.0, 0.6, 0.25, 0.10))
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
