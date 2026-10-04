extends Control
## FIGHTERS: each fighter's level and XP, and the skins and name tag colors
## their levels have unlocked. Pick one of each; your matches use them.

signal back_requested

const Characters = preload("res://rules/characters.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const FighterPicker = preload("res://ui/fighter_picker.gd")
const Progress = preload("res://stats/progress.gd")
const Audio = preload("res://audio/audio.gd")

var fighter := "sebba"
var _picker: FighterPicker
var _detail: VBoxContainer
var _rainbow: Array[Control] = []  # the RAINBOW button (and your name, if it's picked): colors cycle


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 22)
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	head.add_child(UiTheme.label("FIGHTERS", 16, UiTheme.CHALK, true))
	head.add_child(UiTheme.label("PLAY MATCHES TO LEVEL UP (MAX 100) AND UNLOCK SKINS AND NAME TAGS", 8, UiTheme.GOLD))
	col.add_child(head)

	_picker = FighterPicker.new()
	_picker.picked.connect(func(id):
		Audio.play("click")
		fighter = id
		_fill())
	col.add_child(_picker)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	col.add_child(_detail)
	_fill()


func _fill() -> void:
	_picker.show_state(fighter, [])
	for c in _detail.get_children():
		c.queue_free()
	_rainbow.clear()
	var info := Progress.level_info(Progress.xp(fighter))
	var skin := Progress.chosen_skin(fighter)
	var tag := Progress.chosen_tag(fighter)

	# level, XP bar and what's next
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_detail.add_child(top)
	var name := UiTheme.label("%s  LV %d" % [Characters.ALL[fighter].name.to_upper(), info.level], 16, Progress.tag_by_id(tag).color, true)
	top.add_child(name)
	if tag == "rainbow":
		_rainbow.append(name)
	var bar := XpBar.new()
	bar.value = 1.0 if info.need == 0 else float(info.into) / info.need
	bar.custom_minimum_size = Vector2(200, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(bar)
	top.add_child(UiTheme.label("MAX LEVEL!" if info.need == 0 else "%d / %d XP" % [info.into, info.need], 8, UiTheme.CHALK))
	var next := _next_unlock(info.level)
	if next != "":
		var n := UiTheme.label(next, 8, UiTheme.CHALK_DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detail.add_child(n)

	# skins
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 6)
	_detail.add_child(srow)
	srow.add_child(_fixed(UiTheme.label("SKIN", 8, UiTheme.CHALK_DIM), 64))
	for s in Progress.SKIN_NAMES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.icon = PixelArt.character(fighter, false, s)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(76, 72)
		var open := Progress.skin_unlocked(fighter, s)
		b.text = Progress.SKIN_NAMES[s] if open else "LV %d" % Progress.SKIN_LEVELS[s]
		b.disabled = not open
		b.set_pressed_no_signal(s == skin)
		b.pressed.connect(func():
			Audio.play("click")
			Progress.choose_skin(fighter, s)
			_fill())
		srow.add_child(b)

	# name tag colors
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 4)
	_detail.add_child(trow)
	trow.add_child(_fixed(UiTheme.label("NAME TAG", 8, UiTheme.CHALK_DIM), 64))
	for t in Progress.TAGS:
		var b := Button.new()
		b.toggle_mode = true
		var open := Progress.tag_unlocked(fighter, t.id)
		b.text = t.name if open else "LV %d" % t.level
		b.custom_minimum_size = Vector2(62, 22)
		b.add_theme_color_override("font_color", t.color if open else UiTheme.CHALK_DIM)
		b.add_theme_color_override("font_pressed_color", t.color)
		b.add_theme_color_override("font_hover_color", t.color)
		b.disabled = not open
		b.set_pressed_no_signal(t.id == tag)
		b.pressed.connect(func():
			Audio.play("click")
			Progress.choose_tag(fighter, t.id)
			_fill())
		trow.add_child(b)
		if t.id == "rainbow" and open:
			_rainbow.append(b)


## The rainbow tag cycles through every color, like it does in battle.
func _process(_d: float) -> void:
	var c := Color.from_hsv(fmod(Time.get_ticks_msec() / 1500.0, 1.0), 0.6, 1.0)
	for n in _rainbow:
		if is_instance_valid(n):
			for key in ["font_color", "font_pressed_color", "font_hover_color"]:
				n.add_theme_color_override(key, c)


## "NEXT: NAME TAG BLUE AT LV 5" (or nothing once everything is unlocked).
func _next_unlock(level: int) -> String:
	for l in range(level + 1, Progress.MAX_LEVEL + 1):
		var u := Progress.unlocks_at(l)
		if not u.is_empty():
			return "NEXT: %s AT LV %d" % [" + ".join(u), l]
	return ""


func _fixed(c: Control, w: float) -> Control:
	c.custom_minimum_size.x = w
	return c


class XpBar extends Control:
	var value := 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("152a22"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(floorf(size.x * clampf(value, 0, 1)), size.y)), Color("74bf63"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("3e6555"), false, 1.0)
