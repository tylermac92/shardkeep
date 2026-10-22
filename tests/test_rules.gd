extends GutTest

const Fixtures := preload("res://tests/fixtures.gd")

## Swapping (2,6) with (2,7) starts a 3-step cascade: red on row 7, then the skulls in
## row 5 drop next to (3,6), then three greens from different heights meet on row 5.
const CASCADE_BOARD := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y G A $ R B G
	A $ R G A Y S A
	B S S B G $ R B
	S A R S B G Y S
	R R B Y S A $ R
"""
## CASCADE_BOARD after the swap with seed 0. The new gems at the top were checked against
## an independent Python implementation of the column streams.
const CASCADE_AFTER := """
	S B A G S A $ R
	R $ R R S B G Y
	Y B S Y R S A $
	$ S G $ Y R B G
	G R A G $ Y S A
	A Y B A A $ R B
	B $ R B B G Y S
	S A B Y S A $ R
"""


func state_of(text: String, battle_seed := 0) -> BattleState:
	return Fixtures.state_of(text, battle_seed)


## Events with the long "fell" move lists reduced to their type; the final board covers them.
func summary(events: Array[Dictionary]) -> Array:
	var out := []
	for e in events:
		out.append({type = "fell"} if e.type == "fell" else e)
	return out


func test_generated_boards_are_settled_and_playable() -> void:
	for battle_seed in 1000:
		var s := Rules.new_battle(battle_seed, ContentDB.content)
		if not Matcher.find_groups(s.board).is_empty() or Rules.legal_actions(s).is_empty():
			fail_test("seed %d:\n%s" % [battle_seed, s.board.to_text()])
			return
	pass_test("1,000 boards have no matches and a legal swap")


func test_same_seed_same_board() -> void:
	assert_eq(Rules.new_battle(77, ContentDB.content).board.gems, Rules.new_battle(77, ContentDB.content).board.gems)
	assert_ne(Rules.new_battle(77, ContentDB.content).board.gems, Rules.new_battle(78, ContentDB.content).board.gems)


func test_illegal_swaps_are_rejected_and_state_is_unchanged() -> void:
	var s := state_of(CASCADE_BOARD)
	var locked := state_of(CASCADE_BOARD)
	locked.board.locked[58] = 1
	var cases := [
		[s, Action.swap(0, 1), "no match"],
		[s, Action.swap(0, 2), "not adjacent"],
		[s, Action.swap(0, 9), "diagonal"],
		[s, Action.swap(7, 8), "wraps around a row"],
		[s, Action.swap(63, 64), "off the board"],
		[locked, Action.swap(50, 58), "locked gem"],
	]
	for case in cases:
		var state: BattleState = case[0]
		var before := state.board.to_text()
		assert_null(Rules.apply(state, case[1]), case[2])
		assert_eq(state.board.to_text(), before, case[2] + ": board unchanged")
		assert_eq(state.sides[0].mana, PackedInt32Array([0, 0, 0, 0]), case[2] + ": sides unchanged")
		assert_eq(state.streams.draws, _zeros(), case[2] + ": streams unchanged")
		assert_eq(state.active_side, 0, case[2] + ": turn unchanged")


func _zeros() -> PackedInt32Array:
	var z := PackedInt32Array()
	z.resize(Streams.COUNT)
	return z


func test_legal_actions_match_what_apply_accepts() -> void:
	var s := state_of(CASCADE_BOARD)
	var legal := {}
	for act in Rules.legal_actions(s):
		legal[Vector2i(act.a, act.b)] = true
	assert_true(legal.has(Vector2i(50, 58)), "the cascade swap is listed")
	for a in Board.CELLS:
		for b in [a + 1, a + Board.SIZE]:
			if b < Board.CELLS and (b == a + Board.SIZE or a % Board.SIZE != Board.SIZE - 1):
				assert_eq(Rules.apply(s, Action.swap(a, b)) != null, legal.has(Vector2i(a, b)), "swap %d-%d" % [a, b])
	assert_eq(s.board.to_text(), Board.from_text(CASCADE_BOARD).to_text(), "listing actions leaves the board alone")


func test_three_step_cascade() -> void:
	var s := state_of(CASCADE_BOARD)
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_not_null(out)
	assert_eq(summary(out.events), [
		{type = "swapped", a = 50, b = 58},
		{type = "matched", cells = PackedInt32Array([56, 57, 58]), gem = Board.Gem.RED, group_size = 3, cascade_depth = 1},
		{type = "resource_changed", side = 0, kind = "red", delta = 3},
		{type = "cleared", cells = PackedInt32Array([56, 57, 58]), cause = "match"},
		{type = "fell"},
		{type = "spawned", cells = PackedInt32Array([0, 1, 2]), gems = PackedInt32Array([Board.Gem.SKULL, Board.Gem.GOLD, Board.Gem.SKULL])},
		{type = "matched", cells = PackedInt32Array([49, 50, 51]), gem = Board.Gem.SKULL, group_size = 3, cascade_depth = 2},
		{type = "resource_changed", side = 1, kind = "hp", delta = -3},
		{type = "cleared", cells = PackedInt32Array([49, 50, 51]), cause = "match"},
		{type = "fell"},
		{type = "spawned", cells = PackedInt32Array([1, 2, 3]), gems = PackedInt32Array([Board.Gem.BLUE, Board.Gem.RED, Board.Gem.RED])},
		{type = "matched", cells = PackedInt32Array([42, 43, 44]), gem = Board.Gem.GREEN, group_size = 3, cascade_depth = 3},
		{type = "resource_changed", side = 0, kind = "green", delta = 3},
		{type = "cleared", cells = PackedInt32Array([42, 43, 44]), cause = "match"},
		{type = "fell"},
		{type = "spawned", cells = PackedInt32Array([2, 3, 4]), gems = PackedInt32Array([Board.Gem.ACTION, Board.Gem.GREEN, Board.Gem.SKULL])},
		{type = "turn_passed", to_side = 1},
	])
	assert_eq(out.state.board.to_text(), Board.from_text(CASCADE_AFTER).to_text())
	assert_eq(out.state.sides[0].mana, PackedInt32Array([3, 0, 3, 0]))
	assert_eq(out.state.sides[1].hp, 47)
	assert_eq(out.state.turn, 1)
	assert_eq(s.board.to_text(), Board.from_text(CASCADE_BOARD).to_text(), "apply leaves its input alone")


func test_first_fall_moves_every_gem_above_the_cleared_cells() -> void:
	var out := Rules.apply(state_of(CASCADE_BOARD), Action.swap(50, 58))
	var fell: Dictionary = out.events[4]
	assert_eq(fell.type, "fell")
	assert_eq(fell.moves.size(), 21, "7 gems drop one cell in each of columns 0-2")
	assert_eq(fell.moves[0], Vector2i(48, 56), "bottom of column 0 first")


func test_cascade_rewards_go_to_the_acting_side() -> void:
	var s := state_of(CASCADE_BOARD)
	s.active_side = 1
	var out := Rules.apply(s, Action.swap(50, 58))
	var deepest := 0
	var changes := 0
	for e in out.events:
		if e.type == "matched":
			deepest = maxi(deepest, e.cascade_depth)
		if e.type == "resource_changed":
			changes += 1
			assert_eq(e.side, 0 if e.kind == "hp" else 1, "%s at depth %d" % [e.kind, deepest])
	assert_eq(deepest, 3)
	assert_eq(changes, 3)
	assert_eq(out.state.sides[1].mana, PackedInt32Array([3, 0, 3, 0]))
	assert_eq(out.state.sides[0].mana, PackedInt32Array([0, 0, 0, 0]))
	assert_eq(out.state.sides[0].hp, 47)
	assert_eq(out.state.active_side, 0)


func test_mana_stops_at_the_cap() -> void:
	var s := state_of(CASCADE_BOARD)
	s.sides[0].mana[Board.Gem.RED] = 19
	s.sides[0].mana_cap[Board.Gem.GREEN] = 0
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_eq(out.state.sides[0].mana, PackedInt32Array([20, 0, 0, 0]))
	for e in out.events:
		if e.type == "resource_changed" and e.kind == "red":
			assert_eq(e.delta, 1)
		assert_false(e.type == "resource_changed" and e.kind == "green", "nothing reported when the pool is full")


func test_clearing_column_2_never_changes_what_falls_in_column_5() -> void:
	var few := state_of(CASCADE_BOARD, 7)
	var many := state_of(CASCADE_BOARD, 7)
	for y in 3:
		few.board.gems[y * Board.SIZE + 2] = Board.Gem.EMPTY
	for y in 7:
		many.board.gems[y * Board.SIZE + 2] = Board.Gem.EMPTY
	for round in 3:
		for y in [6, 7]:
			few.board.gems[y * Board.SIZE + 5] = Board.Gem.EMPTY
			many.board.gems[y * Board.SIZE + 5] = Board.Gem.EMPTY
		var ignored: Array[Dictionary] = []
		Rules.fall_and_refill(few, ignored)
		Rules.fall_and_refill(many, ignored)
		for y in Board.SIZE:
			assert_eq(few.board.gems[y * Board.SIZE + 5], many.board.gems[y * Board.SIZE + 5], "round %d, row %d" % [round, y])
	assert_eq(few.streams.draws[Streams.COL_5], 6)
	assert_eq(few.streams.draws[Streams.COL_2], 3)
	assert_eq(many.streams.draws[Streams.COL_2], 7)


func test_search_budget_spawns_unknown_past_the_ghost_row() -> void:
	var s := state_of(CASCADE_BOARD, 7)
	var ghost := s.clone()
	var ignored: Array[Dictionary] = []
	ghost.board.gems[7 * Board.SIZE + 2] = Board.Gem.EMPTY
	Rules.fall_and_refill(ghost, ignored)  # real play: one gem from column 2's stream
	s.sim_draw_budget.resize(Board.SIZE)
	s.sim_draw_budget.fill(1)
	s.sim_draw_budget[4] = -1  # -1 = unlimited for that column
	for y in 3:
		s.board.gems[(5 + y) * Board.SIZE + 2] = Board.Gem.EMPTY
		s.board.gems[(5 + y) * Board.SIZE + 4] = Board.Gem.EMPTY
	Rules.fall_and_refill(s, ignored)
	assert_eq(s.board.gems[2 * Board.SIZE + 2], ghost.board.gems[2], "the lowest new gem is the ghost gem")
	for y in 2:
		assert_eq(s.board.gems[y * Board.SIZE + 2], Board.Gem.UNKNOWN)
	for y in 3:
		assert_true(s.board.gems[y * Board.SIZE + 4] <= Board.Gem.GOLD)
	assert_eq(s.sim_draw_budget[2], 0)
	assert_eq(s.streams.draws[Streams.COL_2], 1, "fogged draws don't use the stream")


func test_ghost_row_is_what_falls_next() -> void:
	var s := state_of(CASCADE_BOARD, 7)
	var draws := s.streams.draws.duplicate()
	var ghost := Rules.ghost_row(s)
	assert_eq(s.streams.draws, draws, "peeking doesn't use the streams")
	for x in Board.SIZE:
		s.board.gems[7 * Board.SIZE + x] = Board.Gem.EMPTY
	var ignored: Array[Dictionary] = []
	Rules.fall_and_refill(s, ignored)
	assert_eq(s.board.gems.slice(0, Board.SIZE), ghost)
