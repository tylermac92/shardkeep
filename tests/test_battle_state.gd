extends GutTest

const Fixtures := preload("res://tests/fixtures.gd")


func test_gem_enum_matches_content_order() -> void:
	for i in ContentLoader.GEM_IDS.size():
		assert_eq(Board.Gem.keys()[i], ContentLoader.GEM_IDS[i].to_upper())


func test_golden_board_round_trips() -> void:
	var text := "R B G Y S A $ W\n? . R B G Y S A\n" + "R B G Y S A $ W\n".repeat(6).strip_edges()
	var board := Board.from_text(text)
	assert_eq(board.to_text(), text)
	assert_eq(board.gems[7], Board.Gem.WILD)
	assert_eq(board.gems[8], Board.Gem.UNKNOWN)
	assert_eq(board.gems[9], Board.Gem.EMPTY)


func test_golden_board_rejects_bad_input() -> void:
	assert_null(Board.from_text("R B G"))
	assert_null(Board.from_text(". . . . . . . X\n".repeat(8)))
	assert_null(Board.from_text(". . . . . . .\n".repeat(8)))
	assert_push_error_count(3)


func test_clone_is_independent() -> void:
	var s := BattleState.new()
	s.board = Board.from_text("R B G Y S A $ W\n".repeat(8))
	s.sides[0].hp = 40
	s.sides[0].spells = [&"firebolt"]
	s.sides[0].cooldowns = PackedInt32Array([0])
	s.streams = Streams.new(9)

	var c := s.clone()
	c.board.gems[0] = Board.Gem.EMPTY
	c.board.special[0] = Board.Special.BURST
	c.board.locked[0] = 2
	c.sides[0].hp = 1
	c.sides[0].mana[0] = 5
	c.sides[0].spells.append(&"mend")
	c.sides[0].cooldowns[0] = 3
	c.sides[1].action_points = 4
	c.streams.next_int(Streams.SETUP)
	c.active_side = 1

	assert_eq(s.board.gems[0], Board.Gem.RED)
	assert_eq(s.board.special[0], Board.Special.NONE)
	assert_eq(s.board.locked[0], 0)
	assert_eq(s.sides[0].hp, 40)
	assert_eq(s.sides[0].mana[0], 0)
	assert_eq(s.sides[0].spells, [&"firebolt"] as Array[StringName])
	assert_eq(s.sides[0].cooldowns[0], 0)
	assert_eq(s.sides[1].action_points, 0)
	assert_eq(s.streams.draws[Streams.SETUP], 0)
	assert_eq(s.active_side, 0)
	assert_eq(c.board.gems[1], Board.Gem.BLUE, "clone copies the rest of the board")


func test_state_hash_is_canonical() -> void:
	var s := Rules.new_battle(3, Fixtures.test_content, ["loadout_a", "loadout_b"])
	var h := s.state_hash()
	assert_eq(h.size(), 32)
	assert_eq(s.clone().state_hash(), h)
	assert_eq(Rules.new_battle(3, Fixtures.test_content, ["loadout_a", "loadout_b"]).state_hash(), h)
	var changes: Array[Callable] = [
		func(c: BattleState) -> void: c.board.special[5] = Board.Special.BURST,
		func(c: BattleState) -> void: c.streams.draws[Streams.AI_1] += 1,
		func(c: BattleState) -> void: c.sim_draw_budget = PackedInt32Array([1]),
		func(c: BattleState) -> void: c.sides[1].mana[2] += 1,
		func(c: BattleState) -> void: c.sides[0].statuses.append({id = "burn", turns = 1, stacks = 1}),
		func(c: BattleState) -> void: c.sides[0].stunned_last_turn = true,
		func(c: BattleState) -> void: c.sides[1].stats[SideState.Stat.CUNNING] += 1,
	]
	for change in changes:
		var c := s.clone()
		change.call(c)
		assert_ne(c.state_hash(), h)
