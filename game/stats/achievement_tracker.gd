extends RefCounted
## Watches one match for achievements: the battle screen feeds it every rules
## event in order, and it counts progress and unlocks achievements for "your"
## fighters (online: yours; VS CPU: fighter 0; local: both players on this device).

const A = preload("res://stats/achievements.gd")
const Battle = preload("res://rules/battle.gd")

var data: Dictionary
var battle
var config: Dictionary
var mine: Array  # fighter ids that count for this device
var online := false
## Achievements and trophies won since the screen last asked (it shows a popup each).
var new_unlocks: Array = []
var new_trophies: Array = []
var changed := false

var _turn_damage := {}  # fighter id -> damage dealt this turn
var _attacker := -1  # who is attacking right now (-1 between attacks)
var _attack_kind := ""  # "super", "item" or ""
var _zone_hurt := {}  # fighter id -> took detention damage this round


func _init(p_data: Dictionary, p_battle, p_config: Dictionary, p_mine: Array, p_online: bool) -> void:
	data = p_data
	battle = p_battle
	config = p_config
	mine = p_mine
	online = p_online


func feed(e: Dictionary) -> void:
	match e.type:
		"round_start":
			_zone_hurt.clear()
		"turn_start":
			_turn_damage.clear()
			_attacker = -1
			_attack_kind = ""
		"attack":
			_attacker = e.fighter
			_attack_kind = "super" if e.get("super", false) else ("item" if e.get("item", false) else "")
			if e.get("super", false) and _mine(e.fighter):
				_count("supers")
		"damage":
			if e.get("zone", false):
				_zone_hurt[e.fighter] = true
			elif _mine(_attacker) and _enemy(e.fighter):
				var dealt: int = e.amount - e.absorbed
				_turn_damage[_attacker] = _turn_damage.get(_attacker, 0) + dealt
				if _turn_damage[_attacker] >= A.COMBO_DAMAGE:
					_unlock("combo")
		"ko":
			if _mine(_attacker) and _enemy(e.fighter):
				if _attack_kind == "super":
					_unlock("coolness")
				elif _attack_kind == "item":
					_unlock("item_master")
		"slam":
			if _mine(_attacker) and _enemy(e.fighter):
				_count("slams")
		"slip":
			if _mine(e.get("by", -1)) and _foes(e.by, e.fighter):
				_unlock("slippery")
		"item":
			if (e.get("from_box", false) or Battle.BOX_ITEMS.has(e.item)) and _mine(e.fighter):
				_count("boxes")
		"obstacle_broken":
			if e.obstacle == "L" and _mine(_attacker):
				_count("lockers")
		"round_end":
			for id in mine:
				var f = battle.fighters[id]
				if f.team != e.winner_team:
					continue
				if f.alive() and f.hp < A.COMEBACK_HP:
					_unlock("comeback")
				if battle.shrink_on and battle.zone_rings > 0 and not _zone_hurt.has(id):
					_unlock("survivor")
		"match_end":
			_match_won(e.winner_team)


func _match_won(team: int) -> void:
	var winner = null
	for id in mine:
		if battle.boss_mode and battle.fighters[id].team == Battle.BOSS_TEAM:
			continue  # the Principal's side is never "yours"
		if battle.fighters[id].team == team:
			winner = battle.fighters[id]
			break
	if winner == null:
		return
	_unlock("first_win")
	if battle.boss_mode:
		_boss_won(winner)
		return
	var four: bool = battle.fighters.size() == 4
	if four and battle.teams.size() == 2:
		_unlock("teamwork")
	if four and battle.teams.size() == 4:
		_unlock("last_one")
		_count("ffa4_wins")
	for i in battle.fighters.size():
		var p: Dictionary = config.players[i]
		if p.get("cpu", "") == "hard" and battle.fighters[i].team != team:
			_unlock("cpu_crusher")
	var map_id: String = config.map if config.map is String else ""
	if map_id == "cafeteria":
		_count("cafeteria_wins")
	if map_id != "":
		_add_to_set("maps", map_id)
	_add_to_set("fighters", winner.char_id)
	var key: String = "wins_" + winner.char_id
	data.counters[key] = int(data.counters.get(key, 0)) + 1
	data.counters.best_fighter_wins = maxi(int(data.counters.get("best_fighter_wins", 0)), data.counters[key])
	_check_counter("best_fighter_wins")
	if online:
		_count("online_wins")
	changed = true


## Beat the Principal: trophies (which unlock the boss league achievements).
func _boss_won(winner) -> void:
	var humans := 0
	for p in config.players:
		if not p.has("cpu"):
			humans += 1
	_add_to_set("bosses", battle.boss_id)
	var pre := "ll_" if battle.boss_id == "lunch_lady" else ""
	if humans == 1:
		_trophy(pre + "solo")
	if humans >= 2:
		_trophy(pre + "friends")
	if battle.fighters.all(func(f): return f.team == Battle.BOSS_TEAM or f.alive()):
		_trophy(pre + "untouchable")
		_unlock("not_a_scratch")
	if battle.boss_id == "principal":
		_trophy("with_" + winner.char_id)
	_add_to_set("fighters", winner.char_id)
	changed = true


func _trophy(id: String) -> void:
	var list: Array = data.sets.get("trophies", [])
	if list.has(id):
		return
	new_trophies.append(id)
	_add_to_set("trophies", id)


func _mine(id: int) -> bool:
	return mine.has(id)


## True if fighter `id` is on another team than the one attacking right now.
func _enemy(id: int) -> bool:
	return _foes(_attacker, id)


func _foes(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and battle.fighters[a].team != battle.fighters[b].team


func _count(key: String) -> void:
	data.counters[key] = int(data.counters.get(key, 0)) + 1
	changed = true
	_check_counter(key)


func _check_counter(key: String) -> void:
	for a in A.LIST:
		if a.get("counter", "") == key and int(data.counters.get(key, 0)) >= a.goal:
			_unlock(a.id)


func _add_to_set(key: String, value: String) -> void:
	var list: Array = data.sets.get(key, [])
	if not list.has(value):
		list.append(value)
		data.sets[key] = list
		changed = true
	for a in A.LIST:
		if a.get("set", "") == key and list.size() >= A.goal(a):
			_unlock(a.id)


func _unlock(id: String) -> void:
	if data.unlocked.has(id):
		return
	data.unlocked[id] = true
	new_unlocks.append(id)
	changed = true
