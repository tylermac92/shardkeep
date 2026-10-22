extends GutTest
## Special gems: where they're created, what they blast, and the WILD multiplier.

const Fixtures := preload("res://tests/fixtures.gd")
const C := Matcher.Creates

## Swapping (2,5) with (3,5) completes a red column of 5 with the swapped cell in the middle.
const WILD_SWAP := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y R A $ R B G
	A $ R B G Y S A
	B G Y R A $ R B
	S A R R B G Y S
	R B R Y S A $ R
"""
## Swapping (1,5) with (2,5) completes a blue L whose corner is the swapped cell.
const BURST_SWAP := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B B Y B B $ R B
	S A B R B G Y S
	R B B Y S A $ R
"""
## Swapping (2,6) with (2,7) clears red on row 7; the skulls in row 5 then drop next to
## the two at (3,6) and (4,6), making a skull 4 in the cascade.
const BOMB_CASCADE := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B S S B A $ R B
	S A R S S G Y S
	R R B Y S A $ R
"""
## Swapping (1,6) with (1,7) matches the red BURST at (2,7), whose blast reaches the SKULL_BOMB at (3,6).
const BURST_HITS_BOMB := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S R $ S* B G Y S
	R B R+ Y S A $ R
"""
## Swapping (2,6) with (2,7) makes R W R R: a red 4 with a WILD in it.
const WILD_DOUBLES := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S A R R B G Y S
	R W B R S A $ R
"""
## A red column of 5 already on the board (column 3, rows 2-6), lowest cell 51.
const READY_VERTICAL_5 := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B R Y S A $
	G Y S R $ R B G
	A $ R R G Y S A
	B G Y R A $ R B
	S A $ R B G Y S
	R B G Y S A $ R
"""
## A green L already on the board: row 7 x2-4 and column 4 rows 5-7. Lowest row 7, leftmost 58.
const READY_L := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B A Y S A
	B G Y S G $ R B
	S A $ R G G Y S
	R B G G G A $ R
"""


func created(events: Array[Dictionary]) -> Array[Dictionary]:
	return Fixtures.of_type(events, "special_created")


func test_wild_goes_on_the_swapped_cell() -> void:
	var out := Rules.apply(Fixtures.state_of(WILD_SWAP), Action.swap(42, 43))
	assert_eq(Fixtures.of_type(out.events, "matched")[0].cells, PackedInt32Array([26, 34, 42, 50, 58]))
	assert_eq(created(out.events), [{type = "special_created", cell = 42, kind = C.WILD, gem = Board.Gem.WILD}] as Array[Dictionary],
		"the swapped cell, not the lowest one (58)")


func test_burst_goes_on_the_swapped_cell_and_keeps_its_color() -> void:
	var out := Rules.apply(Fixtures.state_of(BURST_SWAP), Action.swap(41, 42))
	assert_eq(Fixtures.of_type(out.events, "matched")[0].cells, PackedInt32Array([42, 43, 44, 50, 58]))
	assert_eq(created(out.events), [{type = "special_created", cell = 42, kind = C.BURST, gem = Board.Gem.BLUE}] as Array[Dictionary])
	assert_eq(out.state.board.gems[58], Board.Gem.BLUE, "the burst gem fell to the bottom of column 2")
	assert_eq(out.state.board.special[58], Board.Special.BURST)


func test_skull_bomb_in_a_cascade_goes_lowest_then_leftmost() -> void:
	var out := Rules.apply(Fixtures.state_of(BOMB_CASCADE), Action.swap(50, 58))
	var skulls: Dictionary = Fixtures.of_type(out.events, "matched")[1]
	assert_eq(skulls.cells, PackedInt32Array([49, 50, 51, 52]))
	assert_eq(skulls.cascade_depth, 2)
	assert_eq(created(out.events), [{type = "special_created", cell = 49, kind = C.SKULL_BOMB, gem = Board.Gem.SKULL}] as Array[Dictionary])
	assert_eq(out.state.board.special[49], Board.Special.SKULL_BOMB)


func test_cascade_special_goes_on_the_lowest_cell() -> void:
	var events: Array[Dictionary] = []
	Rules.cascade(Fixtures.state_of(READY_VERTICAL_5), events)
	assert_eq(created(events)[0].cell, 51)
	assert_eq(created(events)[0].kind, C.WILD)


func test_cascade_special_breaks_ties_on_the_leftmost_cell() -> void:
	var events: Array[Dictionary] = []
	Rules.cascade(Fixtures.state_of(READY_L), events)
	assert_eq(created(events)[0].cell, 58)
	assert_eq(created(events)[0].kind, C.BURST)


func test_burst_blast_sets_off_a_skull_bomb_in_the_same_step() -> void:
	var out := Rules.apply(Fixtures.state_of(BURST_HITS_BOMB), Action.swap(49, 57))
	var step := []
	for e in out.events.slice(1, out.events.find(Fixtures.of_type(out.events, "fell")[0])):
		step.append(e)
	assert_eq(step, [
		{type = "matched", cells = PackedInt32Array([56, 57, 58]), gem = Board.Gem.RED, group_size = 3, cascade_depth = 1},
		{type = "resource_changed", side = 0, kind = "red", delta = 3},
		{type = "cleared", cells = PackedInt32Array([56, 57, 58]), cause = "match"},
		# Burst at (2,7): the rest of its 3x3, including the bomb at (3,6). Each gem pays out.
		{type = "cleared", cells = PackedInt32Array([49, 50, 51, 59]), cause = "burst"},
		{type = "resource_changed", side = 0, kind = "blue", delta = 1},
		{type = "resource_changed", side = 0, kind = "yellow", delta = 1},
		{type = "resource_changed", side = 1, kind = "hp", delta = -1},
		{type = "resource_changed", side = 0, kind = "gold", delta = 1},
		# Bomb at (3,6): the rest of its 3x3, then its bonus damage.
		{type = "cleared", cells = PackedInt32Array([42, 43, 44, 52, 60]), cause = "bomb"},
		{type = "resource_changed", side = 0, kind = "blue", delta = 1},
		{type = "resource_changed", side = 0, kind = "yellow", delta = 1},
		{type = "resource_changed", side = 1, kind = "hp", delta = -2},
		{type = "resource_changed", side = 0, kind = "ap", delta = 1},
		{type = "resource_changed", side = 1, kind = "hp", delta = -ContentDB.content.skull_bomb_damage},
	])
	assert_eq(out.state.sides[1].hp, 50 - 3 - ContentDB.content.skull_bomb_damage)


func test_wild_doubles_its_group() -> void:
	var out := Rules.apply(Fixtures.state_of(WILD_DOUBLES), Action.swap(50, 58))
	assert_eq(Fixtures.of_type(out.events, "resource_changed")[0], {type = "resource_changed", side = 0, kind = "red", delta = 8},
		"4 gems x 1 mana x 2 for the WILD")


func test_golden_format_reads_and_writes_specials() -> void:
	var b := Board.from_text(BURST_HITS_BOMB)
	assert_eq(b.special[58], Board.Special.BURST)
	assert_eq(b.gems[58], Board.Gem.RED)
	assert_eq(b.special[51], Board.Special.SKULL_BOMB)
	assert_eq(b.to_text(), Board.from_text(b.to_text()).to_text())
	assert_true(b.to_text().contains("R+") and b.to_text().contains("S*"))
