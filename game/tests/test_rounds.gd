extends "res://tests/test_case.gd"

const Maps = preload("res://rules/maps.gd")


func test_2v2_turn_order_alternates_teams() -> void:
	var b := make(open_rows(), [["sebba", 0], ["william", 0], ["mike", 1], ["snorre", 1]])
	eq(b.order, [0, 2, 1, 3] as Array[int], "A1 B1 A2 B2")
	done()


func test_ffa_turn_order_rotates() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["snorre", 2]])
	eq(b.order, [0, 1, 2] as Array[int], "P1 P2 P3")
	done()


func test_knocked_out_fighters_are_skipped() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["william", 0], ["snorre", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	var r := attack(b, 0, 0, R)
	check(has_event(r, "ko"), "mike KO")
	eq(b.current().id, 3, "mike is out, so blue's other fighter (snorre) goes next")
	done()


func test_2v2_keeps_alternating_after_a_ko() -> void:
	# A1=0, A2=1 (team 0), B1=2, B2=3 (team 1); order A1 B1 A2 B2
	var b := make(open_rows(), [["sebba", 0], ["william", 0], ["mike", 1], ["snorre", 1]])
	b.fighters[1].hp = 0  # A2 is out
	var seen: Array[int] = []
	for i in 6:
		var cur := b.current()
		seen.append(cur.id)
		end_turn(b, cur.id)
	eq(seen, [0, 2, 0, 3, 0, 2] as Array[int], "A1 B1 A1 B2 A1 B1: teams alternate, B1 and B2 take turns")
	done()


func test_next_round_continues_the_alternation() -> void:
	var b := Battle.new({"map": "classroom", "rounds": 3, "seed": 3, "characters": Fixture.ALL,
		"players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}]})
	b.start_round()
	var last := b.current()
	b.fighters[1 - last.id].hp = 1
	b.fighters[1 - last.id].pos = last.pos + Vector2i(0, 1)
	b.apply(last.id, {"type": "attack", "slot": 0, "dir": Vector2i(0, 1)})
	eq(b.phase, Battle.Phase.ROUND_OVER, "round 1 over")
	b.start_round()
	check(b.current().team != last.team, "the other team starts round 2")
	done()


func test_round_and_match_win() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	var r := attack(b, 0, 0, R)
	check(has_event(r, "round_end"), "round over")
	eq(b.phase, Battle.Phase.ROUND_OVER, "phase")
	eq(b.round_wins[0], 1, "team 0 won round 1")
	eq(attack(b, 1, 0, L).error, "not_in_turn", "no actions between rounds")

	b.start_round()
	eq(hp(b, 1), 85, "hp reset")
	eq(b.fighters[0].meter, 0, "meter reset")
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	r = attack(b, 0, 0, R)
	check(has_event(r, "match_end"), "2-0 in a best of 3 ends the match")
	eq(b.match_winner, 0, "winner")
	eq(b.start_round(), [], "no rounds after the match")
	done()


func test_tie_goes_to_sudden_death() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 2)
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	attack(b, 0, 0, R)

	b.start_round()
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	end_turn(b, 0)
	b.fighters[0].hp = 1
	var r := attack(b, 1, 0, L)
	check(has_event(r, "round_end"), "round 2 over")
	check(not has_event(r, "match_end"), "1-1 is not decided")

	b.start_round()
	check(b.is_sudden_death(), "round 3 is sudden death")
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	r = attack(b, 0, 0, R)
	eq(b.match_winner, 0, "sudden death winner")
	done()


func test_ffa_last_one_standing_wins() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["snorre", 2]])
	put(b, 0, 4, 2)
	put(b, 1, 3, 2)
	put(b, 2, 5, 2)
	b.fighters[1].hp = 1
	b.fighters[2].hp = 1
	var r := attack(b, 0, 2, R)
	check(has_event(r, "match_end"), "sweep knocks out both")
	eq(b.match_winner, 0, "sebba wins")
	done()


func test_real_maps_place_everyone_on_free_tiles() -> void:
	for map_id in Maps.ALL:
		for players in [
			[{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}],
			[{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}, {"char": "snorre", "team": 2}],
			[{"char": "sebba", "team": 0}, {"char": "william", "team": 0}, {"char": "mike", "team": 1}, {"char": "snorre", "team": 1}],
		]:
			var b := Battle.new({"map": map_id, "players": players, "seed": 7})
			b.start_round()
			var seen := {}
			for f in b.fighters:
				check(b._in_bounds(f.pos), "%s: fighter %d in bounds" % [map_id, f.id])
				check(not b.obstacles.has(f.pos), "%s: fighter %d not on an obstacle" % [map_id, f.id])
				check(not seen.has(f.pos), "%s: fighter %d has its own tile" % [map_id, f.id])
				seen[f.pos] = true
	done()


## Plays many random matches and checks nothing ever breaks the rules.
func test_random_matches_keep_invariants() -> void:
	var chars := ["sebba", "william", "snorre", "mike", "leon"]
	var rng := RandomNumberGenerator.new()
	for s in 60:
		rng.seed = s
		var count := 2 + s % 3
		var players := []
		for i in count:
			var team := i if count == 3 else i % 2
			players.append({"char": chars[(i + s) % chars.size()], "team": team})
		var b := Battle.new({"map": Maps.ALL.keys()[s % Maps.ALL.size()], "players": players, "rounds": 3, "seed": s})
		b.start_round()
		var actions := 0
		while b.phase != Battle.Phase.MATCH_OVER and actions < 20000:
			actions += 1
			if b.phase == Battle.Phase.ROUND_OVER:
				b.start_round()
				continue
			# Simple bot: mostly walks and attacks toward the nearest enemy.
			var me := b.current()
			var dirs := [R, L, U, D]
			var toward: Vector2i = dirs[rng.randi_range(0, 3)]
			var best := 999
			for f in b.fighters:
				if f.alive() and f.team != me.team:
					var diff := f.pos - me.pos
					if absi(diff.x) + absi(diff.y) < best:
						best = absi(diff.x) + absi(diff.y)
						if absi(diff.x) >= absi(diff.y):
							toward = Vector2i(signi(diff.x), 0)
						else:
							toward = Vector2i(0, signi(diff.y))
			var dir: Vector2i = toward if rng.randf() < 0.7 else dirs[rng.randi_range(0, 3)]
			var roll := rng.randi_range(0, 9)
			if roll < 5:
				b.apply(me.id, {"type": "move", "dir": dir})
			elif roll < 9:
				b.apply(me.id, {"type": "attack", "slot": rng.randi_range(0, 4), "dir": dir, "dist": rng.randi_range(1, 5)})
			else:
				b.apply(me.id, {"type": "end_turn"})
			var tiles := {}
			for f in b.fighters:
				check(f.hp >= 0 and f.hp <= f.max_hp, "seed %d: hp in range" % s)
				check(f.meter >= 0 and f.meter <= 100, "seed %d: meter in range" % s)
				if f.alive():
					check(b._in_bounds(f.pos), "seed %d: in bounds" % s)
					check(not b.obstacles.has(f.pos), "seed %d: not inside an obstacle" % s)
					check(not tiles.has(f.pos), "seed %d: two fighters on one tile" % s)
					tiles[f.pos] = true
			if not failures.is_empty():
				done()
				return
		check(b.phase == Battle.Phase.MATCH_OVER, "seed %d: match finished" % s)
	done()


func test_bonus_hp_setting() -> void:
	for bonus in Battle.BONUS_HP_CHOICES:
		var b := Battle.new({"map": "classroom", "rounds": 2, "bonus_hp": bonus, "characters": Fixture.ALL,
			"players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}]})
		b.start_round()
		var base: int = Fixture.ALL.sebba.hp
		eq(b.fighters[0].max_hp, base + bonus, "max hp +%d" % bonus)
		eq(b.fighters[0].hp, base + bonus, "starts full")
	var silly := Battle.new({"map": "classroom", "bonus_hp": 9999, "characters": Fixture.ALL,
		"players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}]})
	eq(silly.fighters[0].max_hp, Fixture.ALL.sebba.hp + Battle.MAX_BONUS_HP, "capped")
	done()
