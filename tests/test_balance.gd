extends GutTest
## The balance runner, played in-process on a few games.

const Runner := preload("res://tools/balance_runner.gd")
const ONE_MATCHUP := {"level": "easy", "matchups": [{"name": "a_vs_b", "loadouts": ["loadout_a", "loadout_b"]}]}


func test_same_seed_gives_identical_csvs() -> void:
	var content := _content()
	var texts := []
	for run in 2:
		var dir := "user://test_balance/run_%d" % run
		Runner.write(Runner.run(content, ONE_MATCHUP, 6, 42), dir, content)
		texts.append([_text(dir, "summary.csv"), _text(dir, "a_vs_b.csv")])
	assert_eq(texts[0], texts[1])
	assert_string_starts_with(texts[0][0], ",".join(Runner.SUMMARY_COLUMNS))
	assert_eq(texts[0][1].strip_edges().split("\n").size(), 7, "a header and one row per game")


func test_splitting_games_across_workers_changes_nothing() -> void:
	var content := _content()
	var whole := Runner.play_games(content, ONE_MATCHUP, 5, 9)
	var merged := {"0": {}}
	for worker in 2:
		var part := Runner.play_games(content, ONE_MATCHUP, 5, 9, worker, 2)
		merged["0"].merge(JSON.parse_string(JSON.stringify(part))["0"])  # as the parent reads it
	for i: String in merged["0"]:
		merged["0"][i] = Runner._ints(merged["0"][i])
	assert_eq(JSON.stringify(Runner.summarize_all(ONE_MATCHUP, merged)), JSON.stringify(Runner.summarize_all(ONE_MATCHUP, whole)))


func test_a_free_50_damage_spell_is_flagged_on_win_rate() -> void:
	var content := _content()
	content.spells["nuke"] = {"id": "nuke", "name": "Nuke", "cost": {}, "effects": [{"op": "damage", "target": "enemy", "amount": 50}]}
	var broken := {"hp": 50, "mana_cap": {"red": 20, "blue": 20, "green": 20, "yellow": 20}, "spells": ["nuke"], "weapon": "sword"}
	var spec := {"level": "easy", "matchups": [{"name": "broken_vs_b", "loadouts": [broken, "loadout_b"]}]}
	var m: Dictionary = Runner.run(content, spec, 8, 1)[0]
	assert_eq(m.win_rate, 1.0)
	assert_true(Array(m.flags).any(func(f: String) -> bool: return f.begins_with("win rate")), str(m.flags))


func test_the_extreme_battle_replays_exactly() -> void:
	var content := _content()
	var m: Dictionary = Runner.run(content, ONE_MATCHUP, 6, 5)[0]
	var original: Dictionary = m.battles.filter(func(b: Dictionary) -> bool: return b.seed == m.extreme_seed)[0]
	var again := Runner.play_battle(content, m.extreme_seed, m.extreme_loadouts, [AI.Level.EASY, AI.Level.EASY])
	assert_eq(again.hash, original.hash)
	assert_eq(again.turns, m.extreme_turns)
	var dir := "user://test_balance/extreme"
	Runner.write([m], dir, content)
	var rec: Dictionary = JSON.parse_string(_text(dir, "a_vs_b_extreme.json"))
	var r := Replay.play(rec, content)
	assert_eq(r.error, "")
	assert_eq(r.state.state_hash().hex_encode(), original.hash)


func test_flags_follow_the_design_thresholds() -> void:
	var fine := {"win_rate": 0.5, "first_mover_win_rate": 0.5, "avg_turns": 25.0, "longest_chain": 3, "cast_share": 0.2, "reshuffles_per_battle": 0.2}
	assert_eq(Runner.flags(fine, true), PackedStringArray())
	var cases := {"win_rate": 0.58, "first_mover_win_rate": 0.6, "avg_turns": 45.0, "longest_chain": 7, "cast_share": 0.05, "reshuffles_per_battle": 1.5}
	for key in cases:
		var s := fine.duplicate()
		s[key] = cases[key]
		assert_eq(Runner.flags(s, true).size(), 1, key)
	var lopsided := fine.duplicate()
	lopsided.win_rate = 0.6
	assert_eq(Runner.flags(lopsided, false).size(), 0, "a non-mirror may lean a little")
	lopsided.win_rate = 0.8
	assert_eq(Runner.flags(lopsided, false).size(), 1)


func _content() -> ContentLoader:
	var c := ContentLoader.new()
	c.load_all()
	return c


func _text(dir: String, file: String) -> String:
	return FileAccess.get_file_as_string(dir.path_join(file))
