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
	"hairLightBrown": ["a87a4a", "805a32", "c89a66"],
	"teeGray": ["9a9ba3", "72737c", "babbc2"],
	"teeWhite": ["eceef1", "c3c7cf", "ffffff"],
	"teeBlack": ["393943", "26262d", "50505c"],
	"teeBlue": ["3f78c9", "2b5595", "6b9be0"],
	"red": ["c8323a", "912029", "e3585d"],
	"hoodie": ["3b3b46", "26262e", "53535f"],
	"pocket": ["2e2e37", "22222a", "3b3b46"],
	"pantsBlack": ["2c2c34", "1d1d23", "3d3d47"],
	"pantsGray": ["6f7079", "54555d", "8a8b94"],
	"pantsLightGray": ["a4a6ae", "82848c", "c0c2c9"],
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
	"tableTop": ["dfe3e8", "b9bec7", "f3f5f8"],
	"tableEdge": ["9aa2ad", "7a828d", "b4bbc4"],
	"benchBlue": ["4f7fc4", "3a5f96", "6f9be0"],
	"steel": ["b8bfc9", "8f96a3", "d8dde4"],
	"steelDark": ["8f96a3", "6c727d", "a9b0ba"],
	"foodYellow": ["e8c84a", "b99a2a", "f5df7f"],
	"foodGreen": ["6cbf5a", "4c9640", "8fd77f"],
	"beagleTan": ["c8894a", "9e6534", "e0a86e"],
	"beagleBlack": ["3a332f", "241f1c", "524842"],
	"beagleWhite": ["f2efe8", "cdc8be", "ffffff"],
	"beagleEar": ["a8703c", "7e5129", "c08550"],
	"oldMuzzle": ["dcd8cf", "b9b4aa", "f0eee8"],
	"fence": ["9aa3ad", "6f7884", "c3cad2"],
	"leaf": ["4f9a45", "36702f", "74bf63"],
	"trunk": ["7a5232", "573821", "9a6c45"],
	"bikeRed": ["c8423a", "92281f", "e56a5f"],
	"labTop": ["3a3f48", "272b32", "565c67"],
	"labCab": ["e4e8ec", "b9c0c8", "f7f9fb"],
	"glass": ["a9d4ec", "7fb2d1", "d6eef9"],
	"flask": ["7fd36b", "58a848", "a8e898"],
	"bone": ["ece6d2", "c4bca4", "fffaea"],
	"pencil": ["f0c330", "c4961c", "f8dc72"],
	"pencilWood": ["e8c79a", "c9a272", "f5dfbf"],
	"eraser": ["e88aa0", "c46a80", "f5b3c3"],
	"puddle": ["7fbbe6", "5d9cd0", "b8def5"],
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
	"leon": {"legs": 11, "hair": "hairLightBrown", "hair_style": "swoop", "shirt": "teeBlue", "sleeve": "teeBlue", "pants": "pantsLightGray", "shoes": "shoeBlack", "mouth": "smile", "pupil": 1},
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
		var img := _dogs_image(bob) if char_id == "dogs" else _character_image(LOOKS[char_id], bob)
		_cache[key] = ImageTexture.create_from_image(img)
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
		"swoop":
			# fringe swept to one side with a little flick on top
			p.rect(10, hcy - 3, 16, hcy - 3, h)
			p.rect(10, hcy - 2, 12, hcy - 2, h)
			p.px(14, top - 3, h)
			p.px(15, top - 3, h)
			p.px(16, top - 2, h)

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


## Lucy (the puppy) lying on the back of Charlie (the older beagle), side view.
static func _dogs_image(bob: bool) -> Image:
	var p := Painter.new(CHAR_W, CHAR_H)
	# Charlie: the big one, standing, facing right
	p.rect(2, 27, 3, 34, "beagleTan")  # tail up
	p.rect(2, 26, 3, 27, "beagleWhite")
	p.ell(14, 37, 11, 5.5, "beagleTan")
	p.ell(13, 34, 8, 2.5, "beagleBlack")
	p.rect(7, 40, 21, 42, "beagleWhite")
	p.rect(22, 35, 24, 41, "beagleWhite")
	for x in [5, 9, 18, 22]:
		p.rect(x, 41, x + 1, 46, "beagleWhite")
	p.ell(26, 30, 4.5, 4.5, "beagleTan")
	p.rect(27, 31, 31, 34, "oldMuzzle")  # grey old-dog muzzle
	p.rect(26, 26, 27, 30, "oldMuzzle")
	p.rect(30, 31, 31, 32, "pupil")
	p.px(28, 29, "pupil")
	p.rect(22, 28, 24, 35, "beagleEar")
	# Lucy: the puppy, lying on his back (breathes with the idle bob).
	# Kept one row above him so the outline separates the two dogs.
	var o := 1 if bob else 0
	p.rect(3, 23 + o, 3, 27 + o, "beagleTan")
	p.px(3, 22 + o, "beagleWhite")
	p.ell(10, 28 + o, 6, 2.5, "beagleTan", 30 + o)
	p.ell(9, 26.5 + o, 4, 1.5, "beagleBlack")
	p.ell(15, 22 + o, 3.5, 3.5, "beagleTan")  # head up, looking ahead
	p.rect(17, 22 + o, 20, 24 + o, "beagleWhite")
	p.px(20, 22 + o, "pupil")
	p.px(16, 21 + o, "pupil")
	p.rect(15, 18 + o, 15, 21 + o, "beagleWhite")
	p.rect(12, 21 + o, 13, 26 + o, "beagleEar")
	p.rect(15, 29 + o, 18, 30, "beagleWhite")  # front paws
	return p.bake()


# ---------------------------------------------------------------- items

## 16x16 icon for an item: "book", "pencils" or "water".
static func item_icon(id: String) -> Texture2D:
	var key := "item_" + id
	if not _cache.has(key):
		var p := Painter.new(16, 16)
		match id:
			"book":
				p.rect(2, 3, 13, 13, "red")
				p.rect(3, 12, 13, 13, "teeWhite")  # page edges
				p.rect(2, 3, 3, 13, "pantsBlack")  # spine
				p.rect(6, 6, 11, 7, "guard")
			"pencils":
				for i in 3:
					var y := 3 + i * 4
					p.rect(4, y, 12, y + 1, "pencil")
					p.rect(13, y, 13, y + 1, "pencilWood")
					p.px(14, y, "pupil")
					p.rect(2, y, 3, y + 1, "eraser")
			"water":
				p.rect(5, 4, 10, 14, "glass")
				p.rect(6, 2, 9, 3, "glass")
				p.rect(6, 1, 9, 1, "ballBlue")
				p.rect(5, 8, 10, 10, "ballBlue")  # label
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


## A water puddle lying on a floor tile.
static func puddle() -> Texture2D:
	if not _cache.has("puddle"):
		var p := Painter.new(TILE, TILE)
		p.ell(15, 17, 12, 7, "puddle")
		p.ell(24, 21, 5, 4, "puddle")
		p.ell(8, 12, 4, 3, "puddle")
		p.rect(10, 14, 13, 14, "teeWhite")  # shine
		_cache["puddle"] = ImageTexture.create_from_image(p.bake())
	return _cache["puddle"]


# ---------------------------------------------------------------- tiles

## Floor tile. `alt` shifts the checker so tiles don't repeat identically.
## Styles: "lino" (classroom beige) or "cafeteria" (blue and white).
static func floor_tile(alt := false, style := "lino") -> Texture2D:
	var key := "floor_%s_%s" % [alt, style]
	if not _cache.has(key):
		var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		var a := Color("d8cdb4")
		var b := Color("c9bc9f")
		if style == "cafeteria":
			a = Color("e9eef3")
			b = Color("b9cde6")
		elif style == "lab":
			a = Color("e3e6ea")
			b = Color("d3d8de")
		for y in TILE:
			for x in TILE:
				var col: Color
				if style == "grass":
					# mown stripes plus scattered blades (same pattern every time)
					col = Color("6fae4f") if (int(y / 16.0) + (1 if alt else 0)) % 2 == 0 else Color("64a246")
					var n := (x * 7 + y * 13 + (5 if alt else 0)) % 23
					if n == 0:
						col = Color("4f8a37")
					elif n == 11:
						col = Color("86c262")
				elif style == "lab":
					var check := (int(x / 16.0) + int(y / 16.0) + (1 if alt else 0)) % 2 == 0
					col = a if check else b
					if x % 16 == 0 or y % 16 == 0:
						col = col.darkened(0.12)
				else:
					var check := (int(x / 8.0) + int(y / 8.0) + (1 if alt else 0)) % 2 == 0
					col = a if check else b
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
		"F":  # lunch table: segments join up into long tables, with a bench in front
			p.rect(0, o + 6, 31, o + 14, "tableTop")
			p.rect(0, o + 15, 31, o + 17, "tableEdge")
			p.rect(14, o + 18, 17, o + 22, "steelDark")
			p.rect(0, o + 24, 31, o + 27, "benchBlue")
			p.rect(3, o + 28, 4, o + 30, "steelDark")
			p.rect(27, o + 28, 28, o + 30, "steelDark")
			if damaged:
				for c in [[8, o + 7], [9, o + 8], [9, o + 9], [10, o + 10], [22, o + 12], [23, o + 13]]:
					p.px(c[0], c[1], "crack")
		"K":  # food counter: steel front, food along the top
			var top := 2 if tall else o + 1
			p.rect(0, top + 6, 31, o + 29, "steel")
			p.rect(0, top + 6, 31, top + 8, "steelDark")
			p.rect(2, o + 18, 29, o + 18, "seam")
			p.ell(6, top + 4, 3, 3, "ballRed")
			p.ell(15.5, top + 4, 4, 2.5, "foodYellow")
			p.ell(25, top + 4, 3, 3, "foodGreen")
			if damaged:
				for c in [[9, o + 22], [10, o + 23], [10, o + 24], [11, o + 25], [21, o + 12], [22, o + 13]]:
					p.px(c[0], c[1], "crack")
		"N":  # chain-link fence
			var top := 2 if tall else o + 4
			p.rect(1, top, 2, o + 29, "fence")
			p.rect(29, top, 30, o + 29, "fence")
			p.rect(0, top, 31, top + 1, "fence")
			for y in range(top + 3, o + 28, 4):
				for x in range(3, 29, 4):
					p.px(x + ((y >> 2) % 2) * 2, y, "fence")
			p.rect(0, o + 28, 31, o + 29, "fence")
			if damaged:
				p.rect(12, o + 10, 18, o + 16, "")
		"R":  # tree: round crown, may poke a little above its tile
			p.rect(13, o + 18, 18, o + 29, "trunk")
			p.ell(15.5, o + 8, 13, 11, "leaf")
			p.ell(9, o + 13, 6, 5, "leaf")
			p.ell(22, o + 13, 6, 5, "leaf")
			if damaged:
				for c in [[14, o + 21], [15, o + 22], [15, o + 23], [16, o + 24]]:
					p.px(c[0], c[1], "crack")
		"Y":  # bike rack (a steel hoop) with a red bike in it, side view
			p.rect(3, o + 12, 28, o + 13, "metal")
			p.rect(3, o + 12, 4, o + 29, "metal")
			p.rect(27, o + 12, 28, o + 29, "metal")
			for wx in [9, 23]:
				p.ell(wx, o + 23, 6, 6, "shoeBlack")
				p.ell(wx, o + 23, 4.5, 4.5, "")
				p.px(wx, o + 23, "metal")
			for i in 8:  # frame: rear wheel -> pedals -> front wheel, and up to the seat
				p.px(9 + i, o + 23 - i / 2, "bikeRed")
				p.px(9 + i, o + 22 - i / 2, "bikeRed")
			p.rect(16, o + 18, 22, o + 19, "bikeRed")
			p.rect(21, o + 15, 22, o + 23, "bikeRed")
			p.rect(13, o + 16, 14, o + 20, "bikeRed")
			p.rect(11, o + 15, 15, o + 15, "pupil")  # seat
			p.rect(20, o + 14, 24, o + 14, "pupil")  # handlebar
			if damaged:
				p.rect(15, o + 18, 17, o + 19, "crack")
		"A":  # lab table: black top, white cupboards, a flask
			p.rect(1, o + 8, 30, o + 12, "labTop")
			p.rect(2, o + 13, 29, o + 29, "labCab")
			p.rect(15, o + 14, 16, o + 28, "seam")
			p.rect(12, o + 20, 12, o + 22, "handle")
			p.rect(19, o + 20, 19, o + 22, "handle")
			p.rect(7, o + 2, 8, o + 4, "glass")
			p.ell(7.5, o + 6, 3, 2.5, "flask")
			if damaged:
				for c in [[6, o + 15], [7, o + 16], [7, o + 17], [8, o + 18], [24, o + 22], [25, o + 23]]:
					p.px(c[0], c[1], "crack")
		"G":  # glass cabinet: breaks easily
			var top := 2 if tall else o + 2
			p.rect(3, top, 28, o + 29, "wood")
			p.rect(5, top + 2, 26, o + 27, "glass")
			p.rect(15, top + 2, 16, o + 27, "wood")
			var shelf := top + int((o + 27 - top) / 2.0)
			p.rect(5, shelf, 26, shelf, "wood")
			p.ell(9, shelf - 3, 2, 2.5, "flask")
			p.ell(21, shelf - 3, 2, 2.5, "ballRed")
			p.rect(9, o + 24, 12, o + 26, "bone")
			if damaged:
				for c in [[6, top + 4], [7, top + 5], [8, top + 6], [8, top + 7], [20, o + 20], [21, o + 19], [22, o + 18], [23, o + 18]]:
					p.px(c[0], c[1], "crack")
		"S":  # classroom skeleton on a stand
			p.ell(16, o + 1, 4, 4, "bone")
			p.px(14, o + 1, "pupil")
			p.px(17, o + 1, "pupil")
			p.rect(15, o + 5, 16, o + 18, "bone")
			for y in [8, 10, 12]:
				p.rect(11, o + y, 20, o + y, "bone")
			p.rect(9, o + 7, 10, o + 15, "bone")
			p.rect(21, o + 7, 22, o + 15, "bone")
			p.rect(13, o + 18, 14, o + 25, "bone")
			p.rect(17, o + 18, 18, o + 25, "bone")
			p.rect(15, o + 25, 16, o + 28, "metal")
			p.rect(10, o + 29, 21, o + 29, "metal")
			if damaged:
				p.rect(21, o + 7, 22, o + 15, "")
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
