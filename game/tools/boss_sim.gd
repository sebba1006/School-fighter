extends SceneTree
## Boss fight check: three CPU players fight the Principal many times.
##   godot --headless --path game -s res://tools/boss_sim.gd -- [matches=60] [noise=4] [boss=principal]

const Battle = preload("res://rules/battle.gd")
const Characters = preload("res://rules/characters.gd")
const Bot = preload("res://ai/bot.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if not args.is_empty() else 60
	var noise := float(args[1]) if args.size() > 1 else 4.0
	var boss: String = args[2] if args.size() > 2 else "principal"
	var chars: Array = Characters.ALL.keys()
	var wins := 0
	var turns_total := 0
	var kos_total := 0
	var boss_hp_left := 0
	for m in n:
		seed(m)
		var team := []
		var pool := chars.duplicate()
		for i in 3:
			team.append({"char": pool.pop_at((m * 7 + i * 3) % pool.size()), "team": 0})
		var b := Battle.new({"boss": boss, "players": team, "seed": m})
		b.start_round()
		var turns := 0
		while b.phase == Battle.Phase.TURN and turns < 600:
			Bot.play_turn(b, noise)
			turns += 1
		turns_total += turns
		if b.match_winner == 0:
			wins += 1
		else:
			boss_hp_left += b.boss().hp
		for f in b.fighters:
			if f.team != Battle.BOSS_TEAM and not f.alive():
				kos_total += 1
	print("players win %d%% (%d/%d), %.1f player turns per fight, %.1f players KO'd per fight, boss HP left when he wins: %d" % [
		100 * wins / n, wins, n, float(turns_total) / n, float(kos_total) / n, boss_hp_left / maxi(1, n - wins)])
	quit()
