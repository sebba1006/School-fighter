extends RefCounted
## One lobby on the server: its players, the host's settings, and the match.
## Pure logic with no sockets, so it can be unit tested. Everything it wants to
## send is queued in `outbox` as [token, message] pairs (token "*" = everyone)
## and the server delivers it.
##
## During a match the server is the referee: it checks each move with its own
## copy of the battle, then relays accepted moves ("ops") to every player, whose
## game applies the same op to its own copy. The rules are deterministic, so all
## copies stay identical; each op carries a state hash so a client can notice if
## it ever drifts and ask for a resync.

const Battle = preload("res://rules/battle.gd")
const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const Bot = preload("res://ai/bot.gd")

const MAX_PLAYERS := 4
const TIMER_CHOICES := [0, 15, 30, 45, 60]
const DISCONNECT_GRACE_MS := 60000
## Quick-chat emotes (texts live in the game); at most one per player per 1.5 s.
const EMOTE_COUNT := 16
const EMOTE_COOLDOWN_MS := 1500
## Boss fights: the team is always 3; CPU teammates fill the empty spots and the
## server plays them, waiting a moment first so everyone can follow.
const BOSS_TEAM_SIZE := 3
const CPU_DELAY_MS := 900

var code: String
var host := ""  # token of the host
## [{"token", "pid", "name", "char", "team", "ready", "connected", "gone_since"}]
var members: Array = []
## public: listed in the server's open-lobby list (otherwise code only)
var settings := {"map": "classroom", "rounds": 3, "timer": 30, "items": true, "public": true, "bonus_hp": 0, "shrink": false, "four": "2v2", "boss": false, "boss_id": "principal"}
var battle: Battle = null
var config := {}
var fighter_of := {}  # token -> fighter id
var ops: Array = []  # every op of the current match, for players who rejoin
var turn_deadline := 0  # msec; 0 = no timer running
var outbox: Array = []
## Tokens the host kicked out; they can't come back to this lobby.
var kicked := {}

var _next_pid := 1
var _turn_key := ""
var _cpu_due := 0  # when the CPU whose turn it is may play
var _now := 0


func _init(p_code: String) -> void:
	code = p_code


func is_empty() -> bool:
	return members.is_empty()


func in_match() -> bool:
	return battle != null


func member(token: String) -> Dictionary:
	for m in members:
		if m.token == token:
			return m
	return {}


## Shown in the open-lobby list: public, waiting for players, not full.
func is_open() -> bool:
	return settings.public and not in_match() and members.size() < MAX_PLAYERS and connected_count() > 0


func connected_count() -> int:
	var n := 0
	for m in members:
		if m.connected:
			n += 1
	return n


# ---------------------------------------------------------------- membership

## Returns "" or an error code.
func add_member(token: String, name: String, now: int) -> String:
	_now = now
	if not member(token).is_empty():
		set_connected(token, true, now)
		return ""
	if kicked.has(token):
		return "kicked"
	if in_match():
		return "in_match"
	if members.size() >= MAX_PLAYERS:
		return "full"
	var t0 := 0
	for m in members:
		if m.team == 0:
			t0 += 1
	members.append({
		"token": token, "pid": _next_pid, "name": name, "char": "",
		"team": 0 if t0 * 2 <= members.size() else 1,
		"ready": false, "connected": true, "gone_since": 0,
	})
	_next_pid += 1
	if host == "":
		host = token
	_broadcast_state()
	return ""


func remove_member(token: String, now: int) -> void:
	_now = now
	var m := member(token)
	if m.is_empty():
		return
	if in_match() and fighter_of.has(token):
		_apply_op({"op": "forfeit", "fighter": fighter_of[token]})
		fighter_of.erase(token)
	members.erase(m)
	if host == token:
		host = members[0].token if not members.is_empty() else ""
		for other in members:
			if other.connected:
				host = other.token
				break
	_broadcast_state()


func set_connected(token: String, on: bool, now: int) -> void:
	_now = now
	var m := member(token)
	if m.is_empty():
		return
	m.connected = on
	m.gone_since = 0 if on else now
	if not on and host == token:
		# hand the host role to someone who is still here
		for other in members:
			if other.connected:
				host = other.token
				break
	if on:
		_send(token, state_for(token))
		if in_match():
			_send(token, _match_sync(token))
	_broadcast_state()


# ---------------------------------------------------------------- messages

func handle(token: String, msg: Dictionary, now: int) -> void:
	_now = now
	var m := member(token)
	if m.is_empty():
		return
	var is_host := token == host
	match msg.get("t"):
		"pick":
			if in_match():
				return
			var c = msg.get("char")
			if not c is String or not Characters.ALL.has(c):
				_error(token, "bad_char")
				return
			for other in members:
				if other != m and other.char == c:
					_error(token, "taken")
					return
			m.char = c
			m.ready = false
			_broadcast_state()
		"ready":
			if in_match():
				return
			if m.char == "":
				_error(token, "pick_first")
				return
			m.ready = msg.get("ready") == true
			_broadcast_state()
		"settings":
			if not is_host or in_match():
				return
			if msg.get("map") is String and Maps.ALL.has(msg.map):
				settings.map = msg.map
			if msg.get("rounds") is int:
				settings.rounds = clampi(msg.rounds, 1, 5)
			if msg.get("timer") is int and TIMER_CHOICES.has(msg.timer):
				settings.timer = msg.timer
			if msg.get("items") is bool:
				settings.items = msg.items
			if msg.get("public") is bool:
				settings.public = msg.public
			if msg.get("shrink") is bool:
				settings.shrink = msg.shrink
			if msg.get("four") in ["2v2", "ffa"]:
				settings.four = msg.four
			if msg.get("boss") is bool:
				settings.boss = msg.boss
			if msg.get("boss_id") is String and Characters.BOSSES.has(msg.boss_id):
				settings.boss_id = msg.boss_id
			if msg.get("bonus_hp") is int and Battle.BONUS_HP_CHOICES.has(msg.bonus_hp):
				settings.bonus_hp = msg.bonus_hp
			_broadcast_state()
		"kick":
			if not is_host or in_match():
				return
			for other in members:
				if other.pid == msg.get("pid") and other.token != token:
					kicked[other.token] = true
					_send(other.token, {"t": "kicked"})
					remove_member(other.token, now)
					print("lobby %s: host kicked a player" % code)
					break
		"team":
			if not is_host or in_match():
				return
			for other in members:
				if other.pid == msg.get("pid"):
					other.team = 1 if msg.get("team") == 1 else 0
			_broadcast_state()
		"start":
			if not is_host:
				return
			var err := _start_match()
			if err != "":
				_error(token, err)
		"intent":
			if not in_match() or battle.phase != Battle.Phase.TURN:
				_error(token, "not_in_turn")
				return
			if not fighter_of.has(token) or fighter_of[token] != battle.current().id:
				_error(token, "not_your_turn")
				return
			var intent := _clean_intent(msg.get("intent"))
			var err := _apply_op({"op": "intent", "fighter": fighter_of[token], "intent": intent})
			if err != "":
				_error(token, err)
		"next_round":
			if is_host and in_match() and battle.phase == Battle.Phase.ROUND_OVER:
				_apply_op({"op": "start_round"})
		"to_lobby":
			if is_host and in_match() and battle.phase == Battle.Phase.MATCH_OVER:
				_end_match()
		"sync":
			if in_match():
				_send(token, _match_sync(token))
		"emote":
			var id = msg.get("id")
			if not in_match() or not fighter_of.has(token) or not id is int or id < 0 or id >= EMOTE_COUNT:
				return
			if now - int(m.get("last_emote", -EMOTE_COOLDOWN_MS)) < EMOTE_COOLDOWN_MS:
				return
			m.last_emote = now
			_send("*", {"t": "emote", "fighter": fighter_of[token], "id": id})


## Called regularly by the server: turn timer and disconnect grace.
func tick(now: int) -> void:
	_now = now
	if in_match() and battle.phase == Battle.Phase.TURN and _is_cpu(battle.current().id) and now >= _cpu_due:
		_play_cpu_turn()
	if in_match() and turn_deadline > 0 and now >= turn_deadline and battle.phase == Battle.Phase.TURN:
		_apply_op({"op": "intent", "fighter": battle.current().id, "intent": {"type": "end_turn"}, "timeout": true})
	for m in members.duplicate():
		if m.connected or m.gone_since == 0 or now - m.gone_since < DISCONNECT_GRACE_MS:
			continue
		if in_match() and fighter_of.has(m.token):
			if not battle.fighters[fighter_of[m.token]].forfeited:
				_apply_op({"op": "forfeit", "fighter": fighter_of[m.token]})
			m.gone_since = 0  # stays in the lobby list as disconnected until the match ends
		else:
			remove_member(m.token, now)


# ---------------------------------------------------------------- match

func _start_match() -> String:
	if in_match():
		return "in_match"
	var n := members.size()
	if settings.boss:
		if n > BOSS_TEAM_SIZE:
			return "boss_max_3"
	elif n < 2:
		return "need_players"
	for m in members:
		if not m.connected:
			return "someone_offline"
		if m.char == "":
			return "not_everyone_picked"
		if m.token != host and not m.ready:
			return "not_everyone_ready"
	# Everyone for themselves unless it is a 4-player match set to 2v2.
	var ffa: bool = n != 4 or settings.four == "ffa"
	if n == 4 and not ffa and not settings.boss:
		var t0 := 0
		for m in members:
			if m.team == 0:
				t0 += 1
		if t0 != 2:
			return "teams_uneven"
	var players := []
	fighter_of.clear()
	for i in n:
		var m: Dictionary = members[i]
		var team: int = i if ffa else m.team
		players.append({"char": m.char, "team": 0 if settings.boss else team, "name": m.name, "pid": m.pid})
		fighter_of[m.token] = i
	if settings.boss:
		# fill the team up to 3 with CPU teammates on fighters nobody picked
		var free: Array = Characters.ALL.keys().filter(func(c): return not players.any(func(p): return p.char == c))
		free.shuffle()
		while players.size() < BOSS_TEAM_SIZE:
			players.append({"char": free.pop_back(), "team": 0, "name": "CPU", "cpu": "normal"})
		config = {"boss": settings.boss_id, "timer": settings.timer, "items": settings.items, "seed": randi(), "players": players}
	else:
		config = {"map": settings.map, "rounds": settings.rounds, "timer": settings.timer, "items": settings.items, "bonus_hp": settings.bonus_hp, "shrink": settings.shrink, "seed": randi(), "players": players}
	battle = Battle.new(config)
	print("lobby %s: match started, %d players on %s" % [code, n, settings.boss_id if settings.boss else settings.map])
	ops.clear()
	_turn_key = ""
	for m in members:
		_send(m.token, {"t": "match_start", "config": config, "you": fighter_of[m.token]})
	_broadcast_state()
	_apply_op({"op": "start_round"})
	return ""


func _end_match() -> void:
	battle = null
	config = {}
	fighter_of.clear()
	ops.clear()
	turn_deadline = 0
	for m in members.duplicate():
		m.ready = false
		if not m.connected:
			members.erase(m)
	if member(host).is_empty() and not members.is_empty():
		host = members[0].token
	_broadcast_state()


## Applies an op to the server's battle and relays it. Returns "" or an error.
func _apply_op(op: Dictionary) -> String:
	match op.op:
		"start_round":
			battle.start_round()
		"intent":
			var r := battle.apply(op.fighter, op.intent)
			if not r.ok:
				return r.error
		"forfeit":
			battle.forfeit(op.fighter)
	ops.append(op)
	_update_deadline()
	var out := op.duplicate()
	out.t = "op"
	out.hash = battle.state_hash()
	out.turn_ms = _turn_ms()
	_send("*", out)
	return ""


func _is_cpu(fighter_id: int) -> bool:
	return fighter_id < config.players.size() and config.players[fighter_id].has("cpu")


## Plays a CPU teammate's whole turn, as ops like a player's moves.
func _play_cpu_turn() -> void:
	var f := battle.current()
	var p := Bot.plan_level(battle, config.players[f.id].cpu)
	for t in p.path:
		if battle.phase != Battle.Phase.TURN or battle.current() != f:
			return
		if _apply_op({"op": "intent", "fighter": f.id, "intent": {"type": "move", "dir": t - f.pos}}) != "":
			break
	for intent in p.intents:
		if battle.phase != Battle.Phase.TURN or battle.current() != f:
			return
		if _apply_op({"op": "intent", "fighter": f.id, "intent": _clean_intent(intent)}) != "":
			break
	if battle.phase == Battle.Phase.TURN and battle.current() == f:
		_apply_op({"op": "intent", "fighter": f.id, "intent": {"type": "end_turn"}})


func _update_deadline() -> void:
	if battle == null or battle.phase != Battle.Phase.TURN:
		turn_deadline = 0
		_turn_key = ""
		return
	var key := "%d:%d" % [battle.round_number, battle.current().id]
	if key != _turn_key:
		_turn_key = key
		_cpu_due = _now + CPU_DELAY_MS
		turn_deadline = _now + settings.timer * 1000 if settings.timer > 0 else 0


func _turn_ms() -> int:
	return maxi(0, turn_deadline - _now) if turn_deadline > 0 else -1


func _match_sync(token: String) -> Dictionary:
	return {"t": "match_sync", "config": config, "you": fighter_of.get(token, -1), "ops": ops, "turn_ms": _turn_ms(), "hash": battle.state_hash()}


## Only the fields the rules engine reads, with safe types.
func _clean_intent(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var out := {"type": str(raw.get("type", ""))}
	if raw.get("dir") is Vector2i:
		out.dir = raw.dir
	if raw.get("slot") is int:
		out.slot = raw.slot
	if raw.get("dist") is int:
		out.dist = raw.dist
	return out


# ---------------------------------------------------------------- output

func state_for(token: String) -> Dictionary:
	var list := []
	var host_pid := -1
	for m in members:
		list.append({"pid": m.pid, "name": m.name, "char": m.char, "team": m.team, "ready": m.ready, "connected": m.connected})
		if m.token == host:
			host_pid = m.pid
	var me := member(token)
	return {
		"t": "lobby", "code": code, "members": list, "host_pid": host_pid,
		"you_pid": me.get("pid", -1), "settings": settings.duplicate(), "in_match": in_match(),
	}


func _broadcast_state() -> void:
	for m in members:
		_send(m.token, state_for(m.token))


func _send(token: String, msg: Dictionary) -> void:
	outbox.append([token, msg])


func _error(token: String, code_: String) -> void:
	_send(token, {"t": "error", "code": code_})
