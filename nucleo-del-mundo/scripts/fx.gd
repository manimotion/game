# =============================================================
# fx.gd — Partículas y "juice" (Fase 5B: arte)
# Fragmentos al picar/romper/colocar, textos flotantes ("+1 …"),
# anillos de onda expansiva (meteoro) y ambiente vivo: luciérnagas
# de noche, polen de día y motas de polvo en cuevas.
# Puramente visual y local: cada peer lo dispara desde sus apply_*
# — no viaja nada por red ni toca estado del juego (GDD §16).
# =============================================================
extends Node2D

const GRAV := 700.0
const AMB_MAX := 36            # tope de partículas ambientales vivas

var _parts: Array = []
var _texts: Array = []
var _rings: Array = []
var _amb: Array = []
var _amb_t := 0.0


func burst(pos: Vector2, color: Color, n: int, speed: float = 130.0) -> void:
	for i in n:
		_parts.append({
			"pos": pos + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
			"vel": Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * speed + Vector2(0, -50),
			"life": randf_range(0.25, 0.55),
			"t": 0.0,
			"color": color,
			"size": randf_range(2.0, 4.5),
		})


## Brasa de fogata: chispa cálida que flota hacia arriba (Fase 7, pulido).
func ember(pos: Vector2) -> void:
	_parts.append({
		"pos": pos + Vector2(randf_range(-5, 5), randf_range(-3, 0)),
		"vel": Vector2(randf_range(-9, 9), randf_range(-46, -26)),
		"life": randf_range(0.7, 1.3),
		"t": 0.0,
		"color": Color(1.0, randf_range(0.55, 0.8), 0.25),
		"size": randf_range(1.5, 2.8),
		"g": -0.12,   # gravedad negativa: el aire caliente la empuja
	})


## Texto que sube y se desvanece ("+2 Madera", "+3 Núcleos").
func float_text(pos: Vector2, text: String, color: Color) -> void:
	_texts.append({"pos": pos, "t": 0.0, "life": 1.1, "text": text, "color": color})


## Anillo de onda expansiva (impacto de meteoro).
func ring(pos: Vector2, r_max: float, color: Color) -> void:
	_rings.append({"pos": pos, "t": 0.0, "life": 0.5, "r": r_max, "color": color})


func _process(delta: float) -> void:
	_amb_t -= delta
	if _amb_t <= 0.0:
		_amb_t = 0.22
		_spawn_ambient()
	if _parts.is_empty() and _texts.is_empty() and _rings.is_empty() and _amb.is_empty():
		return
	for p: Dictionary in _parts:
		p.t += delta
		p.vel.y += GRAV * float(p.get("g", 1.0)) * delta
		p.pos += p.vel * delta
	_parts = _parts.filter(func(p: Dictionary) -> bool: return p.t < p.life)
	for tx: Dictionary in _texts:
		tx.t += delta
		tx.pos.y -= 26.0 * delta
	_texts = _texts.filter(func(tx: Dictionary) -> bool: return tx.t < tx.life)
	for rg: Dictionary in _rings:
		rg.t += delta
	_rings = _rings.filter(func(rg: Dictionary) -> bool: return rg.t < rg.life)
	for a: Dictionary in _amb:
		a.t += delta
		a.pos += a.vel * delta
	_amb = _amb.filter(func(a: Dictionary) -> bool: return a.t < a.life)
	queue_redraw()


## Ambiente alrededor del jugador local: luciérnagas (noche),
## polen (día) o motas de polvo (bajo tierra).
func _spawn_ambient() -> void:
	var w := get_parent()
	var main := w.get_parent()
	if _amb.size() >= AMB_MAX or main.players.is_empty():
		return
	var me: Node2D = main.players.get(multiplayer.get_unique_id())
	if me == null:
		return
	var pos: Vector2 = me.position + Vector2(randf_range(-420.0, 420.0), randf_range(-240.0, 180.0))
	if pos.y > float((w.SKY_ROWS + 8) * w.TILE):
		_amb.append({"pos": pos, "vel": Vector2(randf_range(-7, 7), randf_range(-4, 4)),
			"t": 0.0, "life": randf_range(3.0, 6.0), "size": 1.6,
			"color": Color(0.8, 0.75, 0.62), "blink": 0.0, "seed": randf() * TAU})
	elif w.daylight() < 0.45:
		_amb.append({"pos": pos, "vel": Vector2(randf_range(-14, 14), randf_range(-10, 10)),
			"t": 0.0, "life": randf_range(3.0, 6.0), "size": 2.2,
			"color": Color(0.75, 1.0, 0.45), "blink": 4.0, "seed": randf() * TAU})
	else:
		_amb.append({"pos": pos, "vel": Vector2(randf_range(4, 18), randf_range(-6, 6)),
			"t": 0.0, "life": randf_range(4.0, 7.0), "size": 1.5,
			"color": Color(1.0, 1.0, 0.85), "blink": 1.3, "seed": randf() * TAU})


func _draw() -> void:
	for p: Dictionary in _parts:
		var a: float = 1.0 - p.t / p.life
		var c: Color = p.color
		draw_rect(Rect2(p.pos - Vector2.ONE * p.size * 0.5, Vector2.ONE * p.size),
			Color(c.r, c.g, c.b, a))
	for am: Dictionary in _amb:
		var tw := 1.0
		if am.blink > 0.0:
			tw = 0.55 + 0.45 * sin(am.t * am.blink + am.seed)
		var fade: float = minf(am.t / 0.5, 1.0) * clampf((am.life - am.t) / 0.5, 0.0, 1.0)
		var ca: Color = am.color
		if am.blink >= 3.0:   # halo de luciérnaga
			draw_circle(am.pos, am.size * 2.6, Color(ca.r, ca.g, ca.b, 0.10 * tw * fade))
		draw_circle(am.pos, am.size, Color(ca.r, ca.g, ca.b, 0.55 * tw * fade))
	for rg: Dictionary in _rings:
		var k: float = rg.t / rg.life
		var cr: Color = rg.color
		draw_arc(rg.pos, maxf(2.0, rg.r * k), 0.0, TAU, 40,
			Color(cr.r, cr.g, cr.b, 1.0 - k), 3.0 + 4.0 * (1.0 - k))
	for tx: Dictionary in _texts:
		var at: float = 1.0 - tx.t / tx.life
		var ct: Color = tx.color
		draw_string(ThemeDB.fallback_font, tx.pos + Vector2(-79, 1), tx.text,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(0, 0, 0, at * 0.6))
		draw_string(ThemeDB.fallback_font, tx.pos + Vector2(-80, 0), tx.text,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(ct.r, ct.g, ct.b, at))
