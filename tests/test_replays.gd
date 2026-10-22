extends GutTest
## Replay fixtures (battles played on the battle screen and saved with F9) and the fuzz run.

const Fuzz := preload("res://tools/fuzz.gd")
const FIXTURES := "res://tests/replays"
const FUZZ_OUT := "user://test_fuzz"


func test_fixtures_replay_to_their_recorded_state() -> void:
	var files := _fixtures()
	assert_eq(files.size(), 3)
	for path in files:
		var r := Replay.play(_read(path), _content())
		assert_eq(r.error, "", path)


func test_changing_a_gem_weight_breaks_the_fixtures_and_says_where() -> void:
	var content := _content()
	content.gem_weights[Board.Gem.GOLD] += 1
	for path in _fixtures():
		var r := Replay.play(_read(path), content)
		assert_string_contains(r.error, "action 0", path)  # the board itself is drawn differently
		gut.p("%s: %s" % [path, r.error])


func test_record_and_play_round_trip() -> void:
	var content := _content()
	var s := Rules.new_battle(9, content, ["loadout_a", "loadout_b"])
	var actions: Array[Action] = []
	for i in 12:
		var a := AI.choose(s, AI.Level.EASY)
		actions.append(a)
		s = Rules.apply(s, a).state
	var rec := Replay.record(9, ["loadout_a", "loadout_b"], actions, content)
	assert_eq(rec.hash, s.state_hash().hex_encode())
	var back: Dictionary = JSON.parse_string(Replay.to_json(rec))
	var r := Replay.play(back, content)
	assert_eq(r.error, "")
	assert_eq(r.state.state_hash(), s.state_hash())
	back.checks[5] = "000000000000"
	assert_string_contains(Replay.play(back, content).error, "after action 5")


func test_actions_survive_json() -> void:
	for a in [Action.swap(9, 1), Action.cast(&"firebolt"), Action.attack(), Action.pass_turn()]:
		var back := Replay.from_dict(JSON.parse_string(JSON.stringify(Replay.to_dict(a))))
		assert_eq(Replay.describe(back), Replay.describe(a))
	assert_null(Replay.from_dict({"kind": "dance"}))
	assert_string_contains(Replay.play({"seed": 1}, _content()).error, "missing")


func test_fuzz_holds_its_invariants() -> void:
	var r := Fuzz.run(_content(), 300, 3, FUZZ_OUT)
	assert_eq(r.error, "")
	assert_eq(r.actions, 300)


func test_a_failing_fuzz_run_writes_a_replayable_file() -> void:
	var content := _content()
	var fails_on_turn_4 := func(s: BattleState) -> String: return "turn 4 reached" if s.turn >= 4 else ""
	var r := Fuzz.run(content, 300, 5, FUZZ_OUT, fails_on_turn_4)
	assert_string_contains(r.error, "turn 4 reached")
	assert_true(FileAccess.file_exists(r.path), r.path)
	var rec := _read(r.path)
	assert_string_contains(rec.error, "turn 4 reached")
	var replayed := Replay.play(rec, content)
	assert_eq(replayed.error, "")
	assert_eq(fails_on_turn_4.call(replayed.state), "turn 4 reached", "the file reproduces the failing state")


func test_invariant_check_catches_bad_states() -> void:
	var s := Rules.new_battle(2, _content(), ["loadout_a", "loadout_b"])
	assert_eq(Fuzz.check(s), "")
	var broken: Array[Callable] = [
		func(c: BattleState) -> void: c.board.gems[0] = Board.Gem.UNKNOWN,
		func(c: BattleState) -> void: c.board.gems[0] = Board.Gem.EMPTY,
		func(c: BattleState) -> void: c.board = Board.from_text(preload("res://tests/fixtures.gd").DEAD_BOARD),
		func(c: BattleState) -> void: c.sides[1].hp = c.sides[1].hp_max + 1,
		func(c: BattleState) -> void: c.sides[0].mana[2] = -1,
		func(c: BattleState) -> void: c.sim_draw_budget = PackedInt32Array([1]),
	]
	for change in broken:
		var c := s.clone()
		change.call(c)
		assert_ne(Fuzz.check(c), "")
	var matched := s.clone()
	for x in 3:
		matched.board.gems[x] = Board.Gem.RED
	assert_string_contains(Fuzz.check(matched), "match")


func _fixtures() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(FIXTURES):
		if f.ends_with(".json"):
			out.append(FIXTURES.path_join(f))
	return out


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _content() -> ContentLoader:
	var c := ContentLoader.new()
	c.load_all()
	return c
