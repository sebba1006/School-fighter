extends Control
## Your achievements, easiest first: unlocked ones in gold, locked ones grey with
## how far along you are.

signal back_requested

const UiTheme = preload("res://ui/ui_theme.gd")
const Achievements = preload("res://stats/achievements.gd")

var _grid: GridContainer
var _count: Label
var _confirm_reset := false


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 22)
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	head.add_child(UiTheme.label("ACHIEVEMENTS", 16, UiTheme.CHALK, true))
	_count = UiTheme.label("", 8, UiTheme.GOLD)
	head.add_child(_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var reset := Button.new()
	reset.text = "RESET"
	reset.custom_minimum_size = Vector2(70, 22)
	reset.pressed.connect(func():
		if _confirm_reset:
			Achievements.reset()
			_confirm_reset = false
			reset.text = "RESET"
			_fill()
		else:
			_confirm_reset = true
			reset.text = "SURE?")
	head.add_child(reset)
	outer.add_child(head)

	# two columns, read top to bottom: easiest on the left, hardest bottom right
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 3)
	outer.add_child(_grid)
	_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var data := Achievements.load_data()
	_count.text = "%d / %d UNLOCKED" % [Achievements.unlocked_count(data), Achievements.LIST.size()]
	var half := ceili(Achievements.LIST.size() / 2.0)
	for row in half:
		for column in 2:
			var i := row + column * half
			if i < Achievements.LIST.size():
				_grid.add_child(_entry(i + 1, Achievements.LIST[i], data))


func _entry(number: int, a: Dictionary, data: Dictionary) -> Control:
	var done: bool = data.unlocked.has(a.id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(300, 0)
	var p := Achievements.progress(data, a)
	var title := "%d. %s" % [number, a.name.to_upper()]
	if done:
		title += "  - UNLOCKED!"
	elif p[1] > 1:
		title += "  (%d/%d)" % [p[0], p[1]]
	box.add_child(UiTheme.label(title, 8, UiTheme.GOLD if done else UiTheme.CHALK))
	box.add_child(UiTheme.label(a.desc.to_upper(), 8, UiTheme.CHALK if done else UiTheme.CHALK_DIM))
	return box
