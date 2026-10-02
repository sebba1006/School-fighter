extends RefCounted
## One fighter in a battle: stats from the character definition plus
## everything that changes during a round.

var id: int
var char_id: String
var team: int
var def: Dictionary
var max_hp: int
var move: int

var hp: int
var pos := Vector2i.ZERO
var facing := Vector2i.RIGHT
var meter := 0
## {} for none, {"kind": "hp", "amount": n} (Rage) or {"kind": "block"} (Block).
var shield := {}
## Dizzy lands on the fighter's next turn: move range -1.
var dizzy_next := false
## Dizzy during this turn (one move less).
var dizzy_now := false
var rage_turns := 0
## True during the turn Rage was used, so that turn doesn't count down.
var rage_fresh := false
var rage_bonus := 0
var sugar_active := false
var sugar_multiplier := 1.0
var no_attack_next := false
var no_attack_now := false
## Melee / Ranged Guard in use: {"kind": "melee" | "ranged", "pct": 20-45, "turns": n} or {}.
var guard := {}
## Item held ("" = none; see Battle.ITEMS). Lost at the end of the round.
var item := ""
## Left the match (disconnected too long). Stays knocked out for the rest of it.
var forfeited := false


func _init(p_id: int, p_char_id: String, p_team: int, p_def: Dictionary) -> void:
	id = p_id
	char_id = p_char_id
	team = p_team
	def = p_def
	max_hp = p_def.hp
	move = p_def.move
	reset_for_round()


func reset_for_round() -> void:
	hp = 0 if forfeited else max_hp
	meter = 0
	shield = {}
	dizzy_next = false
	dizzy_now = false
	rage_turns = 0
	rage_fresh = false
	rage_bonus = 0
	sugar_active = false
	sugar_multiplier = 1.0
	no_attack_next = false
	no_attack_now = false
	item = ""
	guard = {}


func alive() -> bool:
	return hp > 0
