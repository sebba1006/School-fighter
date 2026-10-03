extends SceneTree
## End-to-end check of online play over real WebSockets: starts a server and
## N bot players in one process, they create/join a lobby, pick fighters, play
## a whole match (one bot's connection is dropped halfway and must rejoin),
## then go back to the lobby. Every client's copy of the battle must match the
## server's after every move.
##   godot --headless --path game -s res://tools/net_smoke.gd -- [players=2] [boss]
## With "boss" the players team up against the Principal (1-3 players); a boss
## id (lunch_lady, gym_teacher, final_principal) picks that boss.
## Exits with code 1 on any problem.

const Server = preload("res://net/server.gd")
const Client = preload("res://net/client.gd")
const Battle = preload("res://rules/battle.gd")
const Characters = preload("res://rules/characters.gd")
const PORT := 9123
const CHARS := ["sebba", "william", "snorre", "mike"]

var problems: Array[String] = []
var bots: Array = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if not args.is_empty() else 2
	var boss_id := "principal"
	for a in args:
		if Characters.BOSSES.has(a):
			boss_id = a
	var boss := args.has("boss") or Characters.BOSSES.has(boss_id) and boss_id != "principal" or args.has("principal")
	rng.seed = 7
	var server := Server.new()
	root.add_child(server)
	if server.start(PORT) != OK:
		_finish("could not start server")
		return

	for i in n:
		var c := Client.new()
		c.persist = false
		root.add_child(c)
		var bot := {"i": i, "client": c, "lobby": {}, "battle": null, "you": -1, "waiting": false, "ops": 0, "errors": []}
		c.message.connect(func(msg): _on_message(bot, msg))
		bots.append(bot)
		c.go_online("ws://127.0.0.1:%d" % PORT, "Bot%d" % i)
	if not await _until(func(): return bots.all(func(b): return b.client.token != ""), 5.0):
		_finish("bots did not connect")
		return

	var host: Dictionary = bots[0]
	host.client.send({"t": "create"})
	if not await _until(func(): return host.lobby.get("code", "") != "", 3.0):
		_finish("no lobby code")
		return
	var code: String = host.lobby.code
	print("lobby code ", code)
	for b in bots.slice(1):
		b.client.send({"t": "join", "code": code.to_lower()})
	if not await _until(func(): return bots.all(func(b): return b.lobby.get("members", []).size() == n), 3.0):
		_finish("not everyone joined")
		return
	for b in bots:
		b.client.send({"t": "pick", "char": CHARS[b.i]})
		if b.i > 0:
			b.client.send({"t": "ready", "ready": true})
	host.client.send({"t": "settings", "rounds": 2, "timer": 30, "map": "gym", "boss": boss, "boss_id": boss_id})
	await _until(func(): return host.lobby.members.all(func(m): return m.ready or m.pid == host.lobby.host_pid), 3.0)
	host.client.send({"t": "start"})
	if not await _until(func(): return bots.all(func(b): return b.battle != null and b.battle.round_number == 1), 3.0):
		_finish("match did not start: %s" % str(host.errors))
		return
	print("match started with %d players %s" % [n, ("against the " + boss_id) if boss else "on the gym"])

	var dropped := false
	var steps := 0
	var round_requested := 0
	while steps < (40000 if boss else 4000):
		steps += 1
		await process_frame
		var hb: Battle = host.battle
		if hb == null:
			break
		if hb.phase == Battle.Phase.MATCH_OVER:
			break
		if hb.phase == Battle.Phase.ROUND_OVER and round_requested < hb.round_number:
			round_requested = hb.round_number
			host.client.send({"t": "next_round"})
			continue
		if not dropped and host.ops > 25:
			dropped = true
			var victim: Dictionary = bots[n - 1]
			print("dropping bot %d's connection" % victim.i)
			victim.battle = null
			victim.client.drop_connection()
		_bot_turn()

	if host.battle == null or host.battle.phase != Battle.Phase.MATCH_OVER:
		_finish("match did not finish (%d steps)" % steps)
		return
	if not await _until(func(): return bots.all(func(b): return b.battle != null and b.battle.phase == Battle.Phase.MATCH_OVER), 5.0):
		_finish("not every bot saw the end of the match")
		return
	print("match over after %d moves, winner team %d" % [host.ops, host.battle.match_winner])

	host.client.send({"t": "to_lobby"})
	if not await _until(func(): return bots.all(func(b): return b.lobby.get("in_match", true) == false), 3.0):
		_finish("did not return to lobby")
		return
	_finish("")


func _on_message(bot: Dictionary, msg: Dictionary) -> void:
	match msg.t:
		"lobby":
			bot.lobby = msg
		"match_start":
			bot.battle = Battle.new(msg.config)
			bot.you = msg.you
		"match_sync":
			var b := Battle.new(msg.config)
			for op in msg.ops:
				_apply(b, op)
			bot.battle = b
			bot.you = msg.you
			print("bot %d rejoined and replayed %d moves" % [bot.i, msg.ops.size()])
			if b.state_hash() != msg.hash:
				problems.append("bot %d out of sync after rejoining" % bot.i)
		"op":
			bot.ops += 1
			bot.waiting = false
			if bot.battle == null:
				return  # dropped, waiting for the resync
			_apply(bot.battle, msg)
			if bot.battle.state_hash() != msg.hash:
				problems.append("bot %d out of sync after op %s" % [bot.i, str(msg)])
		"error":
			bot.waiting = false
			bot.errors.append(msg.code)


func _apply(b: Battle, op: Dictionary) -> void:
	match op.op:
		"start_round":
			b.start_round()
		"intent":
			b.apply(op.fighter, op.intent)
		"forfeit":
			b.forfeit(op.fighter)


## The bot whose turn it is picks something to do: mostly walk or attack
## toward the nearest enemy.
func _bot_turn() -> void:
	for bot in bots:
		var b: Battle = bot.battle
		if b == null or b.phase != Battle.Phase.TURN or b.current().id != bot.you or bot.waiting:
			continue
		if bot.client.status != "online":
			continue
		var me := b.current()
		var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
		var toward: Vector2i = dirs[rng.randi_range(0, 3)]
		var best := 999
		for f in b.fighters:
			if f.alive() and f.team != me.team:
				var d := f.pos - me.pos
				if absi(d.x) + absi(d.y) < best:
					best = absi(d.x) + absi(d.y)
					toward = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
		var dir: Vector2i = toward if rng.randf() < 0.75 else dirs[rng.randi_range(0, 3)]
		var roll := rng.randi_range(0, 9)
		var intent := {"type": "move", "dir": dir}
		if roll >= 5 and roll < 9:
			intent = {"type": "attack", "slot": rng.randi_range(0, 4), "dir": dir, "dist": rng.randi_range(2, 4)}
		elif roll == 9:
			intent = {"type": "end_turn"}
		bot.waiting = true
		bot.client.send({"t": "intent", "intent": intent})


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _finish(error: String) -> void:
	if error != "":
		problems.append(error)
	for p in problems:
		print("PROBLEM: ", p)
	print("NET SMOKE %s" % ("OK" if problems.is_empty() else "FAILED"))
	quit(0 if problems.is_empty() else 1)
