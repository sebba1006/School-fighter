extends Control
## On-screen joystick for touch screens. Each push in a direction emits one
## `flicked` step; holding it pushed repeats the step after a short pause.
## Works with a mouse too (Godot turns touches into mouse events).

signal flicked(dir: Vector2i)

## Size of the stick area (the knob scales with it).
var radius := 26.0
const FIRE_AT := 0.55   # fraction of radius that counts as a push
const REARM_AT := 0.3   # fraction the knob must come back to before the next push
const REPEAT_DELAY := 0.4
const REPEAT_EVERY := 0.22

var _dragging := false
var _knob := Vector2.ZERO
var _armed := true
var _held_dir := Vector2i.ZERO
var _hold_time := 0.0
var _next_repeat := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2 + 8, radius * 2 + 8)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _center() -> Vector2:
	return size / 2.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_update_knob(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_update_knob(event.position)
		accept_event()


func _release() -> void:
	_dragging = false
	_knob = Vector2.ZERO
	_armed = true
	_held_dir = Vector2i.ZERO
	queue_redraw()


func _update_knob(pos: Vector2) -> void:
	_knob = (pos - _center()).limit_length(radius)
	var strength := _knob.length() / radius
	if strength < REARM_AT:
		_armed = true
		_held_dir = Vector2i.ZERO
	elif strength >= FIRE_AT:
		var dir := _dominant(_knob)
		if _armed or dir != _held_dir:
			_armed = false
			_held_dir = dir
			_hold_time = 0.0
			_next_repeat = REPEAT_DELAY
			flicked.emit(dir)
	queue_redraw()


func _process(delta: float) -> void:
	if not _dragging or _held_dir == Vector2i.ZERO:
		return
	_hold_time += delta
	if _hold_time >= _next_repeat:
		_next_repeat += REPEAT_EVERY
		flicked.emit(_held_dir)


static func _dominant(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


func _draw() -> void:
	var c := _center()
	draw_circle(c, radius + 2, Color("152a22"))
	draw_arc(c, radius + 2, 0, TAU, 32, Color("3e6555"), 1.0)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a := maxf(4.0, radius * 0.14)
		var tip: Vector2 = c + d * (radius - 4)
		var side: Vector2 = Vector2(-d.y, d.x) * a * 0.8
		draw_colored_polygon(PackedVector2Array([tip, tip - d * a + side, tip - d * a - side]), Color("b5c4b2"))
	var k := radius * 0.4
	draw_circle(c + _knob, k + 2, Color("3e6555"))
	draw_circle(c + _knob, k, Color("eef2e6") if _dragging else Color("b5c4b2"))
