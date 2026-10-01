extends RefCounted
## Base class for tests: assertions plus helpers to set up small battles.
## Every test must call done() as its last line so a crash midway is caught.

const Battle = preload("res://rules/battle.gd")
const Fixture = preload("res://tests/fixture_characters.gd")

const R := Vector2i.RIGHT
const L := Vector2i.LEFT
const U := Vector2i.UP
const D := Vector2i.DOWN

var failures: Array[String] = []
var finished := false


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func done() -> void:
	finished = true


## Builds a battle on a custom map and starts round 1 with team 0 moving first.
## `players` is a list of [char, team] pairs; fighter ids follow list order.
func make(rows: Array, players: Array, rounds := 1) -> Battle:
	var list := []
	for p in players:
		list.append({"char": p[0], "team": p[1]})
	var b := Battle.new({
		"map": {"name": "test", "rows": rows, "ffa_spawns": [[0, 0], [1, 0], [2, 0]]},
		"players": list,
		"rounds": rounds,
		"first_team": 0,
		"characters": Fixture.ALL,
	})
	b.start_round()
	return b


## An open 9x5 room with spawns on both sides.
func open_rows() -> Array:
	return [
		"1.......2",
		"1.......2",
		".........",
		".........",
		".........",
	]


func put(b: Battle, id: int, x: int, y: int) -> void:
	b.fighters[id].pos = Vector2i(x, y)
	if b.current().id == id:
		b.turn_start_pos = Vector2i(x, y)


func hp(b: Battle, id: int) -> int:
	return b.fighters[id].hp


func attack(b: Battle, id: int, slot: int, dir = null, dist := 0) -> Dictionary:
	return b.apply(id, {"type": "attack", "slot": slot, "dir": dir, "dist": dist})


func step(b: Battle, id: int, dir: Vector2i) -> Dictionary:
	return b.apply(id, {"type": "move", "dir": dir})


func end_turn(b: Battle, id: int) -> Dictionary:
	return b.apply(id, {"type": "end_turn"})


func has_event(result: Dictionary, type: String) -> bool:
	for e in result.events:
		if e.type == type:
			return true
	return false
