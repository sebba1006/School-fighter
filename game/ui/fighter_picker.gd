extends HBoxContainer
## One row of fighter cards (picture + name), used by every character select.
## Cards get narrower as more fighters are added, so the row keeps fitting
## (about 10 fighters at the narrowest). Optionally ends with a RANDOM card.

signal picked(id: String)

const Characters = preload("res://rules/characters.gd")
const PixelArt = preload("res://art/pixel_art.gd")

const RANDOM := "random"
const MAX_ROW_WIDTH := 600.0
const GAP := 4

var _buttons := {}  # id -> Button


func _init(with_random := false, max_width := MAX_ROW_WIDTH) -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", GAP)
	var ids: Array = Characters.ALL.keys()
	if with_random:
		ids.append(RANDOM)
	var w := clampf(floorf((max_width - GAP * (ids.size() - 1)) / ids.size()), 44.0, 56.0)
	for id in ids:
		var b := Button.new()
		b.toggle_mode = true
		if id == RANDOM:
			b.text = "RANDOM"
		else:
			b.text = Characters.ALL[id].name.to_upper().replace(" & ", " &\n")
			b.icon = PixelArt.character(id)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(w, 76)
		b.clip_text = true
		b.pressed.connect(func(): picked.emit(id))
		_buttons[id] = b
		add_child(b)


## Highlights `selected` and greys out the fighters in `taken`.
func show_state(selected: String, taken: Array) -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(id == selected)
		b.disabled = taken.has(id) and id != selected


func button(id: String) -> Button:
	return _buttons.get(id)
