extends SceneTree
const PixelArt = preload("res://art/pixel_art.gd")
func _init():
	var scale := 5
	var items := [["snorre", 0], ["mike", 0], ["seif", 0], ["seif", 1], ["seif", 2], ["seif", 3], ["seif", 4]]
	var img := Image.create((items.size() * 36 + 4) * scale, 56 * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color("2b4a3f"))
	for i in items.size():
		var src: Image = PixelArt.character(items[i][0], false, items[i][1]).get_image()
		src.resize(32 * scale, 48 * scale, Image.INTERPOLATE_NEAREST)
		img.blend_rect(src, Rect2i(0, 0, 32 * scale, 48 * scale), Vector2i((4 + i * 36) * scale, 4 * scale))
	img.save_png(OS.get_cmdline_user_args()[0])
	quit()
