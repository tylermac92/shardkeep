extends GutTest
## Extra turns, knockouts and reshuffles.

const Fixtures := preload("res://tests/fixtures.gd")
const RulesTest := preload("res://tests/test_rules.gd")

## Swapping (2,6) with (2,7) makes a red 4 on row 7 and a blue 4 on row 6 at once.
const TWO_FOURS := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	B B R B G G Y S
	R R B R S A $ R
"""
## DEAD_BOARD plus one legal swap: (2,6) with (2,7) makes a red 3. With seed 0 the board is
## dead again after the refill.
const ONE_SWAP := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S A R R B G Y S
	R R B Y S A $ R
"""


func test_two_four_matches_grant_one_extra_turn() -> void:
	var s := Fixtures.state_of(TWO_FOURS)
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_eq(Fixtures.of_type(out.events, "matched").size(), 2)
	assert_eq(Fixtures.of_type(out.events, "extra_turn"), [{type = "extra_turn", side = 0, reason = "match"}] as Array[Dictionary])
	assert_eq(Fixtures.of_type(out.events, "turn_passed").size(), 0)
	assert_eq(out.state.active_side, 0)
	assert_eq(out.state.turn, 0)


func test_knockout_stops_the_cascade_and_ends_the_battle() -> void:
	var s := Fixtures.state_of(RulesTest.CASCADE_BOARD)
	s.sides[1].hp = 3  # the depth-2 skulls deal exactly 3
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_eq(out.events.back(), {type = "battle_ended", winner = 0})
	assert_eq(Fixtures.of_type(out.events, "matched").size(), 2, "no depth-3 match")
	assert_eq(Fixtures.types(out.events).slice(-3), PackedStringArray(["matched", "resource_changed", "battle_ended"]),
		"nothing is cleared after the knockout")
	assert_eq(out.state.result, BattleState.Result.SIDE0_WON)
	assert_eq(out.state.sides[1].hp, 0)
	assert_eq(Rules.legal_actions(out.state).size(), 0)
	assert_null(Rules.apply(out.state, Action.swap(0, 1)))


func test_knockout_by_the_second_side() -> void:
	var s := Fixtures.state_of(RulesTest.CASCADE_BOARD)
	s.active_side = 1
	s.sides[0].hp = 2
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_eq(out.events.back(), {type = "battle_ended", winner = 1})
	assert_eq(out.state.result, BattleState.Result.SIDE1_WON)
	assert_eq(out.state.sides[0].hp, 0, "HP stops at 0")


func test_dead_board_reshuffles_after_the_turn_passes() -> void:
	var s := Fixtures.state_of(ONE_SWAP)
	s.sides[0].mana = PackedInt32Array([8, 0, 0, 0])
	s.sides[1].mana = PackedInt32Array([0, 7, 3, 4])
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_eq(Fixtures.types(out.events).slice(-2), PackedStringArray(["turn_passed", "reshuffled"]))
	var reshuffled: Dictionary = out.events.back()
	assert_eq(reshuffled.mana_lost, [PackedInt32Array([2, 0, 0, 0]), PackedInt32Array([0, 1, 0, 1])], "a quarter, rounded down")
	assert_eq(out.state.sides[0].mana, PackedInt32Array([9, 0, 0, 0]), "8 + 3 matched, minus 2")
	assert_eq(out.state.sides[1].mana, PackedInt32Array([0, 6, 3, 3]))
	assert_eq(reshuffled.gems, out.state.board.gems)
	assert_playable(out.state)
	assert_eq(out.state.active_side, 1, "the reshuffle doesn't cost side 1 its turn")


func test_dead_board_reshuffles_at_the_start_of_an_extra_turn() -> void:
	var s := Fixtures.state_of(preload("res://tests/test_specials.gd").WILD_DOUBLES)
	var out := Rules.apply(s, Action.swap(50, 58))
	assert_eq(Fixtures.types(out.events).slice(-2), PackedStringArray(["extra_turn", "reshuffled"]))
	assert_eq(out.state.active_side, 0)
	assert_playable(out.state)


func test_100_forced_reshuffles_are_all_playable() -> void:
	var s := Fixtures.state_of(Fixtures.DEAD_BOARD, 31)
	var counts := gem_counts(s.board)
	for i in 100:
		var events: Array[Dictionary] = []
		Rules.reshuffle(s, events)
		assert_playable(s)
		assert_eq(gem_counts(s.board), counts, "reshuffle %d only moves gems" % i)
		if is_failing():
			return


func test_reshuffle_that_cant_settle_draws_a_fresh_board() -> void:
	var s := Fixtures.state_of("R R R R R R R R\n".repeat(8))
	Rules.reshuffle(s, [] as Array[Dictionary])
	assert_playable(s)
	assert_eq(s.streams.draws[Streams.SHUFFLE], 100 * 63, "gave up after 100 permutations")
	assert_gt(s.streams.draws[Streams.COL_0], 0, "fresh board came from the skyfall streams")


func assert_playable(s: BattleState) -> void:
	assert_eq(Matcher.find_groups(s.board).size(), 0, "no ready matches:\n" + s.board.to_text())
	assert_gt(Rules.legal_actions(s).size(), 0, "a legal swap:\n" + s.board.to_text())


func gem_counts(b: Board) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(Board.Gem.size())
	for g in b.gems:
		counts[g] += 1
	return counts
