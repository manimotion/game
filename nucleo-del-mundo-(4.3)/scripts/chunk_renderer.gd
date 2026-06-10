# =============================================================
# chunk_renderer.gd — Renderizado por chunk (GDD §2, §15)
# Cada chunk dibuja SOLO sus 16x16 tiles. Cuando un tile cambia,
# se redibuja únicamente el chunk afectado (no el mundo entero).
# =============================================================
extends Node2D

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
			var rect := Rect2(lx * t, ly * t, t - 1, t - 1)
			draw_rect(rect, world.COLORS[tt])
			# Grietas: oscurece según el daño acumulado (GDD §6)
			var ratio: float = world.damage_ratio.get(coord, 1.0)
			if ratio < 1.0:
				draw_rect(rect, Color(0, 0, 0, (1.0 - ratio) * 0.55))
