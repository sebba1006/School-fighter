extends RefCounted
## Messages between the game and the server are JSON text. JSON has no
## Vector2i and turns every number into a float, so Vector2i values travel as
## {"__v": [x, y]}, whole numbers come back as ints, and number-like dictionary
## keys ("0", "1"… used for team ids) come back as ints.


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(_to_json(msg))


## Returns a Dictionary, or null if the text isn't a JSON object.
static func decode(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return _from_json(json.data)


static func _to_json(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2I:
			return {"__v": [v.x, v.y]}
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _to_json(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_to_json(x))
			return a
	return v


static func _from_json(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			if v == floorf(v) and absf(v) < 9.0e15:
				return int(v)
			return v
		TYPE_DICTIONARY:
			if v.size() == 1 and v.has("__v") and v.__v is Array and v.__v.size() == 2:
				return Vector2i(int(v.__v[0]), int(v.__v[1]))
			var d := {}
			for k in v:
				var key: Variant = int(k) if str(k).is_valid_int() else k
				d[key] = _from_json(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_from_json(x))
			return a
	return v
