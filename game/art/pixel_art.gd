extends RefCounted
## Draws the game's pixel art from code: characters (32x48) and map tiles
## (32x32, tall obstacles 32x48). Shapes are painted onto a grid of material
## names, then a shading pass (light from the top-left) and an outline pass
## turn them into real pixel art. Textures are cached.

const TILE := 32
const CHAR_W := 32
const CHAR_H := 48
const OUTLINE := Color("17121c")

## material -> [base, shade, highlight], or a single colour for flat materials
const PAL := {
	"skin": ["f2c7a5", "d49b78", "fbdcc2"],
	"hairBrown": ["7a4a26", "553117", "9a6437"],
	"hairChestnut": ["94602f", "6a401c", "b98049"],
	"hairDark": ["5a3a22", "3b2514", "7a5432"],
	"hairBlond": ["e8c25a", "bf922f", "f7df8e"],
	"teeGray": ["9a9ba3", "72737c", "babbc2"],
	"teeWhite": ["eceef1", "c3c7cf", "ffffff"],
	"teeBlack": ["393943", "26262d", "50505c"],
	"red": ["c8323a", "912029", "e3585d"],
	"hoodie": ["3b3b46", "26262e", "53535f"],
	"pocket": ["2e2e37", "22222a", "3b3b46"],
	"pantsBlack": ["2c2c34", "1d1d23", "3d3d47"],
	"pantsGray": ["6f7079", "54555d", "8a8b94"],
	"shoeBlack": ["1f1f25", "141418", "34343d"],
	"shoeRed": ["b62c33", "7f1c22", "d64b50"],
	"shoeBrown": ["5b3a26", "3f2718", "77513a"],
	"blade": ["cfd6e0", "98a1b0", "ffffff"],
	"guard": ["d4a640", "a07722", "f0cd6b"],
	"grip": ["6b3f22", "4a2a15", "8a5634"],
	"wood": ["9a6a3c", "6f4a26", "bd8a55"],
	"deskTop": ["c9955a", "a0723f", "e2b47c"],
	"deskFront": ["a6763f", "80592c", "bd8a55"],
	"teacherTop": ["8a5a34", "66401f", "a8744a"],
	"teacherFront": ["6f4526", "52321a", "86573a"],
	"metal": ["8f96a3", "656b77", "b5bcc7"],
	"locker": ["58789d", "3f5877", "7394ba"],
	"benchTop": ["d2a05c", "a87a3e", "e8bd7e"],
	"ballRed": ["d9463b", "a32d25", "f0776c"],
	"ballBlue": ["3f78c9", "2b5595", "6b9be0"],
	"ballOrange": ["e8893a", "b9651f", "f5ab69"],
	"eye": "ffffff",
	"pupil": "1a1420",
	"mouth": "7a2e2e",
	"frame": "1a1420",
	"string": "e6e6ea",
	"teeth": "ffffff",
	"seam": "34495f",
	"handle": "c9d3de",
	"crack": "2a1d14",
}

const LOOKS := {
	"sebba": {"legs": 10, "hair": "hairBrown", "hair_style": "neat", "shirt": "teeGray", "sleeve": "teeGray", "pants": "pantsBlack", "shoes": "shoeBlack", "glasses": true, "mouth": "flat", "pupil": 1},
	"william": {"legs": 13, "hair": "hairBlond", "hair_style": "swept", "shirt": "teeBlack", "sleeve": "red", "stripe": "red", "pants": "pantsBlack", "shoes": "shoeRed", "glasses": true, "mouth": "smile", "pupil": 0},
	"snorre": {"legs": 9, "hair": "hairChestnut", "hair_style": "messy", "shirt": "teeWhite", "sleeve": "teeWhite", "pants": "pantsGray", "shoes": "shoeBrown", "sword": true, "mouth": "smile", "pupil": 0},
	"mike": {"legs": 11, "hair": "hairDark", "hair_style": "short", "shirt": "hoodie", "sleeve": "hoodie", "hoodie": true, "pants": "pantsBlack", "shoes": "shoeBlack", "slingshot": true, "mouth": "smirk", "pupil": 1},
}

static var _cache := {}


# ---------------------------------------------------------------- painter

class Painter:
	var w: int
	var h: int
	var g := []

	func _init(p_w: int, p_h: int) -> void:
		w = p_w
		h = p_h
		for y in h:
			var row := []
			row.resize(w)
			row.fill("")
			g.append(row)

	func px(x: int, y: int, m: String) -> void:
		if x >= 0 and x < w and y >= 0 and y < h:
			g[y][x] = m

	func rect(x0: int, y0: int, x1: int, y1: int, m: String) -> void:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				px(x, y, m)

	func ell(cx: float, cy: float, rx: float, ry: float, m: String, max_y := 9999) -> void:
		for y in range(floori(cy - ry) - 1, ceili(cy + ry) + 2):
			if y > max_y:
				continue
			for x in range(floori(cx - rx) - 1, ceili(cx + rx) + 2):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0:
					px(x, y, m)

	func at(x: int, y: int) -> String:
		if x < 0 or y < 0 or x >= w or y >= h:
			return ""
		return g[y][x]

	## Shading + outline -> Image.
	func bake() -> Image:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in h:
			for x in w:
				var k: String = g[y][x]
				if k == "":
					var edge := at(x + 1, y) != "" or at(x - 1, y) != "" or at(x, y + 1) != "" or at(x, y - 1) != ""
					if edge:
						img.set_pixel(x, y, OUTLINE)
					continue
				var p = PAL[k]
				if p is String:
					img.set_pixel(x, y, Color(p))
					continue
				var same := func(a: String) -> bool: return a == k or (a != "" and PAL[a] is String)
				var r := at(x + 1, y)
				var b := at(x, y + 1)
				var l := at(x - 1, y)
				var a := at(x, y - 1)
				var shade: bool = not same.call(r) or not same.call(b) or (a != "" and not same.call(a))
				var light: bool = not shade and (not same.call(l) or a == "")
				img.set_pixel(x, y, Color(p[1] if shade else (p[2] if light else p[0])))
		return img


# ---------------------------------------------------------------- characters

## `bob` is the second idle frame (upper body 1px lower).
static func character(char_id: String, bob := false) -> Texture2D:
	var key := "char_%s_%s" % [char_id, bob]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_character_image(LOOKS[char_id], bob))
	return _cache[key]


static func _character_image(c: Dictionary, bob: bool) -> Image:
	var p := Painter.new(CHAR_W, CHAR_H)
	var T := 10
	var u := 1 if bob else 0
	var pants_top: int = 45 - c.legs
	var tt: int = pants_top - T + u
	var hcy: int = pants_top - T - 8 + u

	if c.get("sword", false):
		var x := 4
		var y := tt - 7
		for t in 24:
			var m := "grip" if t < 3 else "blade"
			p.px(x, y, m)
			if t > 0 and t < 23:
				p.px(x + 1, y, m)
			if t == 3:
				for o in [[2, -2], [1, -1], [-1, 1], [-2, 2], [0, 0], [1, 0]]:
					p.px(x + o[0], y + o[1], "guard")
			x += 1
			y += 1
	if c.get("hoodie", false):
		p.ell(16, tt - 1, 10, 3, "hoodie")

	p.rect(10, pants_top, 21, 44, c.pants)
	p.rect(15, pants_top + 2, 16, 44, "")
	p.rect(9, 45, 14, 46, c.shoes)
	p.rect(17, 45, 22, 46, c.shoes)

	var hoodie: bool = c.get("hoodie", false)
	p.rect(10, tt, 21, pants_top + 1 if hoodie else pants_top, c.shirt)
	p.rect(7, tt, 24, tt, c.sleeve)
	var sleeve_rows := T - 1 if hoodie else 3
	for r in range(1, T):
		var m: String = c.sleeve if r <= sleeve_rows else "skin"
		p.rect(7, tt + r, 8, tt + r, m)
		p.rect(23, tt + r, 24, tt + r, m)
	p.rect(7, tt + T, 8, tt + T + 1, "skin")
	p.rect(23, tt + T, 24, tt + T + 1, "skin")
	if not hoodie:
		p.rect(14, tt, 17, tt, "skin")
		p.rect(15, tt + 1, 16, tt + 1, "skin")
	if c.has("stripe"):
		p.rect(10, tt + 3, 21, tt + 4, c.stripe)
	if hoodie:
		p.rect(12, tt + 6, 19, tt + 8, "pocket")
		p.rect(14, tt + 1, 14, tt + 3, "string")
		p.rect(17, tt + 1, 17, tt + 3, "string")

	p.ell(16, hcy, 8, 8, "skin")
	p.rect(7, hcy, 7, hcy + 1, "skin")
	p.rect(24, hcy, 24, hcy + 1, "skin")

	var h: String = c.hair
	var top := hcy - 8
	p.ell(16, hcy - 4, 9, 6, h, hcy - 4)
	p.rect(8, hcy - 3, 9, hcy - 2, h)
	p.rect(22, hcy - 3, 23, hcy - 2, h)
	match c.hair_style:
		"neat":
			p.rect(10, hcy - 3, 13, hcy - 3, h)
			p.px(10, hcy - 2, h)
		"swept":
			p.rect(15, hcy - 3, 21, hcy - 3, h)
			p.rect(19, hcy - 2, 21, hcy - 2, h)
			for x in [12, 13, 18]:
				p.px(x, top - 3, h)
		"messy":
			for x in [10, 11, 13, 14, 17, 19, 20]:
				p.px(x, hcy - 3, h)
			p.px(11, hcy - 2, h)
			p.px(19, hcy - 2, h)
			p.px(10, top - 2, h)
			p.px(15, top - 3, h)
			p.px(16, top - 3, h)
			p.px(21, top - 2, h)
		"short":
			p.rect(17, hcy - 3, 21, hcy - 3, h)
			p.px(21, hcy - 2, h)

	p.rect(11, hcy - 1, 13, hcy + 1, "eye")
	p.rect(18, hcy - 1, 20, hcy + 1, "eye")
	var pu: int = c.get("pupil", 0)
	p.rect(12 + pu, hcy, 12 + pu, hcy + 1, "pupil")
	p.rect(19 + pu, hcy, 19 + pu, hcy + 1, "pupil")

	var my := hcy + 4
	match c.mouth:
		"flat":
			p.rect(14, my, 17, my, "mouth")
		"smile":
			p.px(13, my - 1, "mouth")
			p.px(18, my - 1, "mouth")
			p.rect(14, my, 17, my, "mouth")
		"smirk":
			p.rect(15, my, 18, my, "mouth")
			p.px(19, my - 1, "mouth")

	if c.get("glasses", false):
		for x0 in [10, 17]:
			p.rect(x0, hcy - 2, x0 + 4, hcy - 2, "frame")
			p.rect(x0, hcy + 2, x0 + 4, hcy + 2, "frame")
			p.rect(x0, hcy - 2, x0, hcy + 2, "frame")
			p.rect(x0 + 4, hcy - 2, x0 + 4, hcy + 2, "frame")
		p.rect(15, hcy - 1, 16, hcy - 1, "frame")
		p.px(9, hcy - 1, "frame")
		p.px(22, hcy - 1, "frame")

	if c.get("slingshot", false):
		var hy := tt + T
		p.px(25, hy, "skin")
		p.px(26, hy, "skin")
		p.rect(27, hy - 1, 27, hy + 1, "wood")
		for o in [[26, -2], [28, -2], [26, -3], [28, -3]]:
			p.px(o[0], hy + o[1], "wood")
	return p.bake()


# ---------------------------------------------------------------- tiles

## Linoleum floor tile. `alt` shifts the checker so tiles don't repeat identically.
static func floor_tile(alt := false) -> Texture2D:
	var key := "floor_%s" % alt
	if not _cache.has(key):
		var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		var a := Color("d8cdb4")
		var b := Color("c9bc9f")
		for y in TILE:
			for x in TILE:
				var check := (int(x / 8.0) + int(y / 8.0) + (1 if alt else 0)) % 2 == 0
				var col := a if check else b
				if x == 0 or y == 0:
					col = col.darkened(0.08)
				img.set_pixel(x, y, col)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Obstacle art. Size is 32x48 so tall things (lockers) can rise above their tile;
## the bottom 32 rows sit on the tile. `damaged` adds cracks. Lockers are only
## `tall` along the top wall; elsewhere they stay inside their tile so they
## don't hide the row above.
static func obstacle(kind: String, damaged := false, tall := true) -> Texture2D:
	var key := "obs_%s_%s_%s" % [kind, damaged, tall]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_obstacle_image(kind, damaged, tall))
	return _cache[key]


static func _obstacle_image(kind: String, damaged: bool, tall: bool) -> Image:
	var p := Painter.new(TILE, 48)
	var o := 16  # tile top inside the 48px image
	match kind:
		"L":  # locker
			var top := 2 if tall else o + 1
			var k := 1.0 if tall else 0.6  # squash the details into a short locker
			p.rect(2, top, 29, o + 29, "locker")
			p.rect(15, top + 1, 16, o + 28, "seam")
			for i in 3:
				var y := top + roundi((6 + i * 3) * k)
				p.rect(5, y, 11, y, "seam")
				p.rect(20, y, 26, y, "seam")
			var hy := top + roundi(20 * k)
			p.rect(12, hy, 12, hy + 3, "handle")
			p.rect(19, hy, 19, hy + 3, "handle")
			if damaged:
				for c in [[7, 30], [8, 31], [8, 32], [9, 33], [23, 36], [24, 37], [24, 38]]:
					p.px(c[0], c[1], "crack")
		"D":  # desk
			p.rect(3, o + 6, 28, o + 14, "deskTop")
			p.rect(3, o + 15, 28, o + 18, "deskFront")
			p.rect(5, o + 19, 6, o + 28, "metal")
			p.rect(25, o + 19, 26, o + 28, "metal")
			p.rect(5, o + 24, 26, o + 24, "metal")
			if damaged:
				for c in [[10, o + 7], [11, o + 8], [11, o + 9], [12, o + 10], [20, o + 12], [21, o + 13]]:
					p.px(c[0], c[1], "crack")
		"T":  # teacher's desk
			p.rect(1, o + 3, 30, o + 11, "teacherTop")
			p.rect(1, o + 12, 30, o + 29, "teacherFront")
			p.rect(4, o + 16, 27, o + 16, "seam")
			p.rect(14, o + 14, 17, o + 14, "handle")
			if damaged:
				for c in [[8, o + 5], [9, o + 6], [9, o + 7], [10, o + 8], [22, o + 20], [23, o + 21], [23, o + 22]]:
					p.px(c[0], c[1], "crack")
		"B":  # gym bench
			p.rect(1, o + 12, 30, o + 17, "benchTop")
			p.rect(4, o + 18, 6, o + 27, "metal")
			p.rect(25, o + 18, 27, o + 27, "metal")
			if damaged:
				for c in [[12, o + 13], [13, o + 14], [13, o + 15], [14, o + 16]]:
					p.px(c[0], c[1], "crack")
		"C":  # ball cart
			p.rect(3, o + 12, 28, o + 24, "metal")
			p.rect(5, o + 14, 26, o + 22, "")
			p.ell(10, o + 12, 5, 5, "ballRed")
			p.ell(21, o + 12, 5, 5, "ballBlue")
			p.ell(15.5, o + 7, 5, 5, "ballOrange")
			p.rect(5, o + 25, 7, o + 28, "metal")
			p.rect(24, o + 25, 26, o + 28, "metal")
			if damaged:
				p.rect(13, o + 16, 18, o + 18, "crack")
	return p.bake()
