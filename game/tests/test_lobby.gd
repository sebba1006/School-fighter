extends "res://tests/test_case.gd"

const Lobby = preload("res://net/lobby.gd")
const Wire = preload("res://net/wire.gd")


## Messages the lobby queued for `token` (including broadcasts), then clears the outbox.
func _take(lobby: Lobby, token: String) -> Array:
	var out := []
	for item in lobby.outbox:
		if item[0] == token or item[0] == "*":
			out.append(item[1])
	return out


func _last(msgs: Array, t: String) -> Dictionary:
	for i in range(msgs.size() - 1, -1, -1):
		if msgs[i].t == t:
			return msgs[i]
	return {}


## A lobby with players "a", "b"... who picked characters, ready to start.
func _lobby(chars: Array) -> Lobby:
	var lobby := Lobby.new("TEST1")
	for i in chars.size():
		var tok := "abcd"[i]
		lobby.add_member(tok, "P" + tok, 0)
		lobby.handle(tok, {"t": "pick", "char": chars[i]}, 0)
		lobby.handle(tok, {"t": "ready", "ready": true}, 0)
	lobby.outbox.clear()
	return lobby


func test_join_limits_and_host() -> void:
	var lobby := Lobby.new("TEST1")
	for tok in ["a", "b", "c", "d"]:
		eq(lobby.add_member(tok, tok, 0), "", "join " + tok)
	eq(lobby.add_member("e", "e", 0), "full", "5th player")
	eq(lobby.host, "a", "creator is host")
	lobby.remove_member("a", 0)
	eq(lobby.host, "b", "host passes on")
	var teams := lobby.members.map(func(m): return m.team)
	teams.sort()
	eq(teams, [0, 1, 1], "teams balanced as people join")
	done()


func test_characters_are_unique() -> void:
	var lobby := Lobby.new("TEST1")
	lobby.add_member("a", "a", 0)
	lobby.add_member("b", "b", 0)
	lobby.handle("a", {"t": "pick", "char": "mike"}, 0)
	lobby.outbox.clear()
	lobby.handle("b", {"t": "pick", "char": "mike"}, 0)
	eq(_last(_take(lobby, "b"), "error").get("code"), "taken", "second mike")
	lobby.outbox.clear()
	lobby.handle("b", {"t": "pick", "char": "nobody"}, 0)
	eq(_last(_take(lobby, "b"), "error").get("code"), "bad_char", "unknown character")
	done()


func test_start_checks() -> void:
	var lobby := Lobby.new("TEST1")
	lobby.add_member("a", "a", 0)
	lobby.handle("a", {"t": "start"}, 0)
	eq(_last(_take(lobby, "a"), "error").get("code"), "need_players", "alone")
	lobby.add_member("b", "b", 0)
	lobby.handle("a", {"t": "pick", "char": "sebba"}, 0)
	lobby.handle("b", {"t": "pick", "char": "mike"}, 0)
	lobby.outbox.clear()
	lobby.handle("a", {"t": "start"}, 0)
	eq(_last(_take(lobby, "a"), "error").get("code"), "not_everyone_ready", "b not ready")
	lobby.outbox.clear()
	lobby.handle("b", {"t": "start"}, 0)
	check(not lobby.in_match(), "only the host can start")
	lobby.handle("b", {"t": "ready", "ready": true}, 0)
	lobby.handle("a", {"t": "start"}, 0)
	check(lobby.in_match(), "started")
	var msgs := _take(lobby, "b")
	eq(_last(msgs, "match_start").get("you"), 1, "b is fighter 1")
	eq(_last(msgs, "op").get("op"), "start_round", "round 1 starts")
	done()


func test_2v2_needs_even_teams() -> void:
	var lobby := _lobby(["sebba", "william", "snorre", "mike"])
	for m in lobby.members:
		m.team = 0
	lobby.handle("a", {"t": "start"}, 0)
	eq(_last(_take(lobby, "a"), "error").get("code"), "teams_uneven", "4 on one team")
	lobby.outbox.clear()
	var pids := lobby.members.map(func(m): return m.pid)
	lobby.handle("a", {"t": "team", "pid": pids[2], "team": 1}, 0)
	lobby.handle("a", {"t": "team", "pid": pids[3], "team": 1}, 0)
	lobby.handle("a", {"t": "start"}, 0)
	check(lobby.in_match(), "2v2 started")
	eq(lobby.battle.teams.size(), 2, "two teams")
	done()


func test_three_players_is_free_for_all() -> void:
	var lobby := _lobby(["sebba", "william", "snorre"])
	lobby.handle("a", {"t": "start"}, 0)
	eq(lobby.battle.teams.size(), 3, "three teams")
	done()


func test_moves_are_checked_and_relayed() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "start"}, 0)
	var client := Battle.new(_take(lobby, "a")[0].config)  # what a player's game builds
	for msg in _take(lobby, "a"):
		if msg.t == "op":
			client.start_round()
	lobby.outbox.clear()
	var turn_token := "a" if lobby.battle.current().id == 0 else "b"
	var other := "b" if turn_token == "a" else "a"

	lobby.handle(other, {"t": "intent", "intent": {"type": "end_turn"}}, 0)
	eq(_last(_take(lobby, other), "error").get("code"), "not_your_turn", "wrong player")
	lobby.outbox.clear()

	lobby.handle(turn_token, {"t": "intent", "intent": {"type": "move", "dir": Vector2i(0, -1)}}, 0)
	eq(_last(_take(lobby, turn_token), "error").get("code"), "blocked", "into a locker")
	lobby.outbox.clear()

	lobby.handle(turn_token, {"t": "intent", "intent": {"type": "move", "dir": Vector2i(0, 1)}}, 0)
	var op := _last(_take(lobby, other), "op")
	eq(op.get("op"), "intent", "relayed to the other player")
	# The other player's game applies the same op and must end up identical.
	client.apply(op.fighter, op.intent)
	eq(client.state_hash(), op.hash, "client copy matches the server")
	done()


func test_ops_survive_the_wire() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "start"}, 0)
	var fighter := lobby.battle.current().id
	var tok := "a" if fighter == 0 else "b"
	lobby.handle(tok, {"t": "intent", "intent": {"type": "move", "dir": Vector2i(0, 1)}}, 0)
	var sync: Dictionary = Wire.decode(Wire.encode(lobby._match_sync("a")))
	var client := Battle.new(sync.config)
	for op in sync.ops:
		match op.op:
			"start_round":
				client.start_round()
			"intent":
				client.apply(op.fighter, op.intent)
	eq(client.state_hash(), sync.hash, "rejoining player rebuilds the same battle")
	done()


func test_turn_timer_ends_the_turn() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "settings", "timer": 15}, 0)
	lobby.handle("a", {"t": "start"}, 1000)
	var first := lobby.battle.current().id
	lobby.outbox.clear()
	lobby.tick(15999)
	eq(lobby.battle.current().id, first, "still their turn at 14.9s")
	lobby.tick(16000)
	check(lobby.battle.current().id != first, "turn passed at 15s")
	check(_last(_take(lobby, "a"), "op").get("timeout", false), "marked as timeout")
	done()


func test_disconnect_grace_then_forfeit() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "settings", "timer": 0}, 0)
	lobby.handle("a", {"t": "start"}, 0)
	lobby.set_connected("b", false, 1000)
	eq(lobby.host, "a", "host stays")
	lobby.tick(60000)
	check(lobby.battle.phase != Battle.Phase.MATCH_OVER, "still waiting at 59s")
	lobby.set_connected("b", true, 30000)
	lobby.set_connected("b", false, 40000)
	lobby.tick(99999)
	check(lobby.battle.phase != Battle.Phase.MATCH_OVER, "grace restarted after reconnect")
	lobby.tick(100000)
	eq(lobby.battle.match_winner, 0, "b forfeits after 60s away")
	done()


func test_host_disconnect_hands_over_host() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.set_connected("a", false, 0)
	eq(lobby.host, "b", "b is host now")
	done()


func test_rounds_and_back_to_lobby() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "settings", "rounds": 1}, 0)
	lobby.handle("a", {"t": "start"}, 0)
	var loser := 1 - lobby.battle.current().id
	lobby.battle.fighters[loser].hp = 1
	var cur := lobby.battle.current()
	lobby.battle.fighters[loser].pos = cur.pos + Vector2i(0, 1)
	var tok := "a" if cur.id == 0 else "b"
	lobby.handle(tok, {"t": "intent", "intent": {"type": "attack", "slot": 0, "dir": Vector2i(0, 1)}}, 0)
	eq(lobby.battle.phase, Battle.Phase.MATCH_OVER, "best of 1 is over")
	lobby.handle("b", {"t": "to_lobby"}, 0)
	check(lobby.in_match(), "only host goes back")
	lobby.handle("a", {"t": "to_lobby"}, 0)
	check(not lobby.in_match(), "back in the lobby")
	check(lobby.members.all(func(m): return not m.ready), "everyone un-readied")
	done()


func test_wire_round_trip() -> void:
	var msg := {"t": "x", "dir": Vector2i(-1, 0), "n": 3, "f": 1.5, "wins": {0: 2, 1: 0}, "list": [Vector2i(2, 3)]}
	var back = Wire.decode(Wire.encode(msg))
	eq(back.dir, Vector2i(-1, 0), "vector")
	check(back.n is int, "int stays int")
	eq(back.f, 1.5, "float stays float")
	eq(back.wins[0], 2, "int keys")
	eq(back.list[0], Vector2i(2, 3), "vector in array")
	eq(Wire.decode("not json"), null, "garbage")
	done()


func test_leaving_mid_match_forfeits() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "start"}, 0)
	lobby.outbox.clear()
	lobby.remove_member("b", 0)
	eq(lobby.battle.phase, Battle.Phase.MATCH_OVER, "1v1 ends when one player leaves")
	eq(lobby.battle.match_winner, 0, "the player who stayed wins")
	check(_take(lobby, "a").any(func(m): return m.t == "op" and m.op == "forfeit"), "forfeit relayed")
	done()


func test_emotes_are_relayed_with_a_cooldown() -> void:
	var lobby := _lobby(["sebba", "mike"])
	lobby.handle("a", {"t": "emote", "id": 0}, 0)
	check(_take(lobby, "b").is_empty(), "no emotes outside a match")
	lobby.handle("a", {"t": "start"}, 0)
	lobby.outbox.clear()
	lobby.handle("a", {"t": "emote", "id": 2}, 10000)
	var got := _last(_take(lobby, "b"), "emote")
	eq(got.get("id"), 2, "relayed to the other player")
	eq(got.get("fighter"), 0, "with the sender's fighter")
	lobby.outbox.clear()
	lobby.handle("a", {"t": "emote", "id": 3}, 10500)
	check(_take(lobby, "b").is_empty(), "too soon: ignored")
	lobby.handle("a", {"t": "emote", "id": 99}, 20000)
	check(_take(lobby, "b").is_empty(), "unknown emote ignored")
	lobby.handle("a", {"t": "emote", "id": 1}, 20000)
	eq(_last(_take(lobby, "b"), "emote").get("id"), 1, "after the cooldown it works again")
	done()


func test_open_lobbies_are_public_waiting_and_not_full() -> void:
	var lobby := Lobby.new("TEST1")
	lobby.add_member("a", "a", 0)
	check(lobby.is_open(), "new lobbies are public")
	lobby.handle("a", {"t": "settings", "public": false}, 0)
	check(not lobby.is_open(), "private: not listed")
	lobby.handle("a", {"t": "settings", "public": true}, 0)
	for tok in ["b", "c", "d"]:
		lobby.add_member(tok, tok, 0)
	check(not lobby.is_open(), "full: not listed")
	var two := _lobby(["sebba", "mike"])
	two.handle("a", {"t": "start"}, 0)
	check(not two.is_open(), "playing: not listed")
	done()


func test_host_can_kick_and_they_cannot_return() -> void:
	var lobby := _lobby(["sebba", "mike"])
	var b_pid: int = lobby.member("b").pid
	lobby.handle("b", {"t": "kick", "pid": lobby.member("a").pid}, 0)
	eq(lobby.members.size(), 2, "only the host can kick")
	lobby.handle("a", {"t": "kick", "pid": b_pid}, 0)
	eq(lobby.members.size(), 1, "b is out")
	eq(_last(_take(lobby, "b"), "kicked").get("t"), "kicked", "b is told")
	eq(lobby.add_member("b", "b", 0), "kicked", "b can't come back")
	lobby.handle("a", {"t": "kick", "pid": lobby.member("a").pid}, 0)
	eq(lobby.members.size(), 1, "the host can't kick themself")
	done()
