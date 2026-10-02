extends Node2D
## One fighter on the board: sprite with an idle bob, a team-coloured ring,
## and a bouncing arrow over whoever's turn it is.

const PixelArt = preload("res://art/pixel_art.gd")
const TILE := 32

var char_id: String
var team_color: Color
var active := false:
	set(v):
		active = v
		queue_redraw()
var knocked_out := false
## The boss: a 96x128 sprite standing on the 3x3 tiles around his tile.
var big := false

var _sprite := Sprite2D.new()
var _frames: Array[Texture2D] = []
var _t := 0.0
var _frame := 0


func setup(p_char_id: String, p_team_color: Color) -> void:
	char_id = p_char_id
	team_color = p_team_color
	big = char_id == "principal"
	if big:
		_frames = [PixelArt.boss(false), PixelArt.boss(true)]
	else:
		_frames = [PixelArt.character(char_id, false), PixelArt.character(char_id, true)]
	_sprite.texture = _frames[0]
	_sprite.centered = false
	_sprite.position = Vector2(-32, -64) if big else Vector2(0, -16)
	add_child(_sprite)


## Back to standing normally (a new round after a knock-out).
func reset_pose() -> void:
	knocked_out = false
	_sprite.rotation = 0
	_sprite.position = Vector2(-32, -64) if big else Vector2(0, -16)
	_sprite.modulate = Color.WHITE


func tile_to_pos(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE, t.y * TILE)


func set_tile(t: Vector2i) -> void:
	position = tile_to_pos(t)
	z_index = (t.y + (1 if big else 0)) * 10 + 5


func move_to(t: Vector2i, duration: float) -> Tween:
	z_index = maxi(z_index, t.y * 10 + 5)
	var tw := create_tween()
	tw.tween_property(self, "position", tile_to_pos(t), duration)
	tw.tween_callback(func(): z_index = t.y * 10 + 5)
	return tw


## Quick step toward `dir` and back, for attacks.
func lunge(dir: Vector2i) -> Tween:
	var home := position
	var tw := create_tween()
	tw.tween_property(self, "position", home + Vector2(dir) * 6, 0.07)
	tw.tween_property(self, "position", home, 0.09)
	return tw


## Jump in an arc onto `t` (Mike's Flying Tackle).
func leap_to(t: Vector2i, duration: float) -> Tween:
	var start := position
	var end := tile_to_pos(t)
	z_index = 2000
	var tw := create_tween()
	tw.tween_method(func(k: float):
		position = start.lerp(end, k) + Vector2(0, -28 * sin(k * PI)), 0.0, 1.0, duration)
	return tw


func flash(color: Color) -> void:
	var tw := create_tween()
	_sprite.modulate = color
	tw.tween_property(_sprite, "modulate", Color.WHITE if not knocked_out else Color(0.5, 0.5, 0.55, 0.6), 0.25)


func knock_out() -> Tween:
	knocked_out = true
	active = false
	var tw := create_tween().set_parallel()
	if big:  # the Principal slowly sinks and fades
		tw.tween_property(_sprite, "modulate", Color(0.5, 0.5, 0.55, 0.0), 1.2)
		tw.tween_property(_sprite, "position", _sprite.position + Vector2(0, 24), 1.2)
		return tw
	tw.tween_property(_sprite, "modulate", Color(0.5, 0.5, 0.55, 0.6), 0.3)
	tw.tween_property(_sprite, "rotation", PI / 2, 0.3)
	tw.tween_property(_sprite, "position", Vector2(40, 12), 0.3)
	return tw


func _process(delta: float) -> void:
	if knocked_out:
		return
	_t += delta
	if _t >= 0.6:
		_t = 0.0
		_frame = 1 - _frame
		_sprite.texture = _frames[_frame]
	if active:
		queue_redraw()


func _draw() -> void:
	if knocked_out:
		return
	# ring under the feet in the team colour
	var c := Vector2(16, 60) if big else Vector2(16, 29)
	var r := 44.0 if big else 12.0
	draw_set_transform(c, 0, Vector2(1, 0.35 if big else 0.4))
	draw_circle(Vector2.ZERO, r, Color(team_color, 0.35))
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, team_color, 2.0)
	draw_set_transform(Vector2.ZERO)
	if active:
		var bob := roundf(sin(Time.get_ticks_msec() / 150.0) * 2)
		var tip := Vector2(16, (-70 if big else -22) + bob)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -6), tip + Vector2(5, -6)]), Color("f2c14e"))
		draw_polyline(PackedVector2Array([tip, tip + Vector2(-5, -6), tip + Vector2(5, -6), tip]), Color("17121c"), 1.0)
