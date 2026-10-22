extends GutTest
## One test per effect op, run through real casts.

const Fixtures := preload("res://tests/fixtures.gd")
const RulesTest := preload("res://tests/test_rules.gd")

## DEAD_BOARD with a blue at (3,7): row 7 reads R B G B, so turning greens blue makes B B B.
const CONVERT_BOARD := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S A $ R B G Y S
	R B G B S A $ R
"""


## Side 0 on the cascade board (it has a legal swap and no matches), holding these spells and 20 of each mana.
func caster(spells: Array, text := RulesTest.CASCADE_BOARD) -> BattleState:
	var s := Fixtures.state_of(text)
	Fixtures.equip(s.sides[0], spells)
	s.sides[0].mana = PackedInt32Array([20, 20, 20, 20])
	return s


func test_damage() -> void:
	var out := Rules.apply(caster(["zap"]), Action.cast(&"zap"))
	assert_eq(out.events, [
		{type = "resource_changed", side = 0, kind = "red", delta = -2},
		{type = "spell_cast", side = 0, spell = &"zap"},
		{type = "resource_changed", side = 1, kind = "hp", delta = -7},
		{type = "turn_passed", to_side = 1},
	] as Array[Dictionary])
	assert_eq(out.state.sides[1].hp, 43)
	assert_eq(out.state.sides[0].mana[Board.Gem.RED], 18)


func test_damage_per_gem_counts_the_board_at_cast_time() -> void:
	var s := caster(["firebolt"])
	var reds := s.board.gems.count(Board.Gem.RED)
	assert_gt(reds, 0)
	var out := Rules.apply(s, Action.cast(&"firebolt"))
	assert_eq(out.state.sides[1].hp, 50 - reds)
	assert_eq(out.state.sides[0].mana[Board.Gem.RED], 13, "Firebolt costs 7 red")


func test_gain_mana_stops_at_the_cap() -> void:
	var s := caster(["focus"])
	s.sides[0].mana[Board.Gem.BLUE] = 18
	var out := Rules.apply(s, Action.cast(&"focus"))
	assert_has(out.events, {type = "resource_changed", side = 0, kind = "blue", delta = 2})
	assert_eq(out.state.sides[0].mana[Board.Gem.BLUE], 20)


func test_convert_all_triggers_a_cascade_paid_to_the_caster() -> void:
	var s := Fixtures.state_of(CONVERT_BOARD)
	s.active_side = 1
	Fixtures.equip(s.sides[1], ["tidal_shift"])
	s.sides[1].mana = PackedInt32Array([0, 5, 0, 0])
	var greens := PackedInt32Array()
	for c in Board.CELLS:
		if s.board.gems[c] == Board.Gem.GREEN:
			greens.append(c)
	var out := Rules.apply(s, Action.cast(&"tidal_shift"))
	assert_eq(Fixtures.of_type(out.events, "converted"), [{type = "converted", cells = greens, gem = Board.Gem.BLUE}] as Array[Dictionary])
	var first: Dictionary = Fixtures.of_type(out.events, "matched")[0]
	assert_eq(first.gem, Board.Gem.BLUE)
	assert_eq(first.cells, PackedInt32Array([57, 58, 59]))
	for e in Fixtures.of_type(out.events, "resource_changed").slice(1):  # [0] is the spell's cost
		assert_eq(e.side, 0 if e.kind == "hp" else 1, "cascade rewards go to the caster: %s" % e)
	assert_gt(out.state.sides[1].mana[Board.Gem.BLUE], 0)
	assert_eq(out.state.active_side, 1, "Tidal Shift doesn't end the turn")


func test_convert_a_count_picks_with_the_effects_stream() -> void:
	var s := caster(["transmute"])
	var out := Rules.apply(s, Action.cast(&"transmute"))
	var converted: Dictionary = Fixtures.of_type(out.events, "converted")[0]
	assert_eq(converted.cells.size(), 2)
	for c in converted.cells:
		assert_eq(s.board.gems[c], Board.Gem.RED, "cell %d was red" % c)
	assert_eq(out.state.streams.draws[Streams.EFFECTS], 2)
	assert_eq(Rules.apply(s, Action.cast(&"transmute")).events, out.events, "same seed, same picks")


func test_apply_status_adds_then_refreshes() -> void:
	var s := caster(["ward"])
	var first := Rules.apply(s, Action.cast(&"ward"))
	assert_has(first.events, {type = "status_applied", side = 0, status = "barrier", turns = 3, stacks = 4})
	var again := first.state.clone()
	again.active_side = 0
	var second := Rules.apply(again, Action.cast(&"ward"))
	assert_has(second.events, {type = "status_applied", side = 0, status = "barrier", turns = 3, stacks = 8},
		"stacks add up; turns keep the longer of the two (2 left after one tick vs 3)")
	assert_eq(second.state.sides[0].statuses.size(), 1)


func test_extra_turn_spell_chain_stops_after_two() -> void:
	var s := caster(["haste"])
	var reasons := []
	for i in 3:
		var out := Rules.apply(s, Action.cast(&"haste"))
		s = out.state
		reasons.append(out.events.back().type)
		if i < 2:
			assert_has(out.events, {type = "extra_turn", side = 0, reason = "spell"}, "cast %d" % (i + 1))
	assert_eq(reasons, ["extra_turn", "extra_turn", "turn_passed"])
	assert_eq(s.active_side, 1)
	assert_eq(s.extra_turn_chain, 0, "the chain resets when the turn passes")
