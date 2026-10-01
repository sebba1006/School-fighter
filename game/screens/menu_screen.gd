extends Control
## Title screen: play online or a local battle on one device.

signal online_pressed
signal local_pressed

const Characters = preload("res://rules/characters.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title := UiTheme.label("SCHOOL FIGHTER", 32, UiTheme.CHALK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for id in Characters.ALL:
		var t := TextureRect.new()
		t.texture = PixelArt.character(id)
		t.custom_minimum_size = Vector2(32, 48)
		row.add_child(t)
	col.add_child(row)

	for item in [["PLAY ONLINE", online_pressed], ["LOCAL BATTLE", local_pressed]]:
		var b := Button.new()
		b.text = item[0]
		b.add_theme_font_override("font", UiTheme.title_font())
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(180, 30)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sig: Signal = item[1]
		b.pressed.connect(func(): sig.emit())
		col.add_child(b)

	var sub := UiTheme.label("online: 2-4 players, each on their own device", 8, UiTheme.CHALK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
