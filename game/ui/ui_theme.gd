extends RefCounted
## Shared look: chalkboard greens, chalk text, crisp pixel fonts.

const BOARD := Color("1f3a30")
const BOARD_DEEP := Color("152a22")
const PANEL := Color("264638")
const LINE := Color("3e6555")
const CHALK := Color("eef2e6")
const CHALK_DIM := Color("b5c4b2")
const GOLD := Color("f2c14e")
const HIT := Color("e8575e")
const DIZZY := Color("b08cf0")
const HEAL := Color("7fd08a")
## Team colours: team 0 blue, team 1 red, team 2 yellow, team 3 green
const TEAM := [Color("5b9bf0"), Color("e8575e"), Color("f2c14e"), Color("7fd08a")]

static var _label_font: Font
static var _title_font: Font
static var _theme: Theme


## Silkscreen: small caps pixel font, crisp at 8px and multiples.
static func label_font() -> Font:
	if _label_font == null:
		_label_font = _pixel_font("res://fonts/Silkscreen-Regular.ttf")
	return _label_font


## Pixelify Sans: headings, crisp at 16px and multiples.
static func title_font() -> Font:
	if _title_font == null:
		_title_font = _pixel_font("res://fonts/PixelifySans.ttf")
	return _title_font


static func _pixel_font(path: String) -> Font:
	var f: FontFile = load(path)
	var copy: FontFile = f.duplicate()
	copy.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	copy.hinting = TextServer.HINTING_NONE
	copy.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	copy.force_autohinter = false
	return copy


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = label_font()
	t.default_font_size = 8
	t.set_color("font_color", "Label", CHALK)

	var normal := _box(PANEL, LINE)
	var hover := _box(PANEL.lightened(0.08), CHALK_DIM)
	var pressed := _box(LINE, CHALK)
	var disabled := _box(BOARD_DEEP, BOARD_DEEP.lightened(0.1))
	var focus := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBox = {"normal": normal, "hover": hover, "pressed": pressed, "disabled": disabled, "focus": focus}[s]
		t.set_stylebox(s, "Button", box)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_color", "Button", CHALK)
	t.set_color("font_hover_color", "Button", CHALK)
	t.set_color("font_pressed_color", "Button", CHALK)
	t.set_color("font_disabled_color", "Button", CHALK_DIM.darkened(0.45))
	t.set_font_size("font_size", "Button", 8)

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, LINE))
	t.set_stylebox("panel", "Panel", _box(PANEL, LINE))
	_theme = t
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(1)
	b.set_content_margin_all(3)
	b.anti_aliasing = false
	return b


static func label(text: String, size := 8, color := CHALK, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font() if title else label_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
