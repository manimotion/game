# =============================================================
# virtual_joystick.gd — Joystick virtual dinámico (GDD §13)
# Aparece donde el jugador apoya el dedo (zona inferior-izquierda)
# y rastrea SU índice de toque, dejando los demás dedos libres
# para minar/colocar al mismo tiempo (multi-touch real).
# Empujar hacia ARRIBA (> 55%) cuenta como saltar.
# =============================================================
extends Control

const RADIUS := 90.0
const KNOB := 34.0
const DEADZONE := 0.22

## Vector de salida normalizado (-1..1 en cada eje).
var output := Vector2.ZERO

var _touch_index := -1
var _origin := Vector2.ZERO
var _knob_pos := Vector2.ZERO


func _ready() -> void:
	add_to_group("joystick")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # no bloquear botones de la UI


## Zona de activación: 45% izquierdo y 65% inferior de la pantalla.
func _in_zone(p: Vector2) -> bool:
	var vs := get_viewport_rect().size
	return p.x < vs.x * 0.45 and p.y > vs.y * 0.35


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and _in_zone(event.position):
			_touch_index = event.index
			_origin = event.position
			_knob_pos = event.position
			output = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()  # este toque es del joystick
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			output = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var v: Vector2 = (event.position - _origin).limit_length(RADIUS)
		_knob_pos = _origin + v
		output = v / RADIUS
		if output.length() < DEADZONE:
			output = Vector2.ZERO
		queue_redraw()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _touch_index == -1:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(_origin, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(_knob_pos, KNOB, Color(1, 1, 1, 0.30))
