extends Control
## Trophies for beating the Principal in different ways: a gold cup for each one
## you've won, a grey one for the rest.

signal back_requested

const UiTheme = preload("res://ui/ui_theme.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const Achievements = preload("res://stats/achievements.gd")


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var data := Achievements.load_data()
	var won: Array = data.sets.get("trophies", [])
	var all := Achievements.trophy_list()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 22)
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	head.add_child(UiTheme.label("TROPHIES", 16, UiTheme.CHALK, true))
	head.add_child(UiTheme.label("%d / %d WON - BEAT THE PRINCIPAL IN BOSS FIGHT TO EARN THEM" % [won.size(), all.size()], 8, UiTheme.GOLD))
	outer.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for t in all:
		grid.add_child(_card(t, won.has(t.id)))


## One trophy: the cup, its name and how to win it.
func _card(t: Dictionary, has_it: bool) -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.GOLD.darkened(0.4), 0.2) if has_it else Color(0, 0, 0, 0.15)
	style.border_color = UiTheme.GOLD if has_it else UiTheme.CHALK_DIM.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(5)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(198, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = PixelArt.trophy(has_it)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	col.add_child(UiTheme.label(t.name.to_upper(), 8, UiTheme.GOLD if has_it else UiTheme.CHALK))
	var desc := UiTheme.label(t.desc.to_upper(), 8, UiTheme.CHALK if has_it else UiTheme.CHALK_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size.x = 150
	col.add_child(desc)
	return box
