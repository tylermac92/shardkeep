extends GutTest
## Golden-board tests for match detection. Each group is summarized as
## "<gem symbol> <shape> <creates> <extra turn?> [cells]" so a failure reads like the rule it broke.

const S := Matcher.Shape
const C := Matcher.Creates


func groups_of(text: String) -> PackedStringArray:
	var board := Board.from_text(text)
	assert_not_null(board, "golden board parses")
	var out := PackedStringArray()
	for g in Matcher.find_groups(board):
		out.append("%s %s %s %s %s" % [Board.SYMBOLS[g.gem], S.keys()[g.shape], C.keys()[g.creates], "XT" if g.extra_turn else "-", g.cells])
	return out


func test_straight_3() -> void:
	assert_eq(groups_of("""
		. . . . . . . .
		. R R R . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray(["R STRAIGHT_3 NOTHING - [9, 10, 11]"]))


func test_straight_3_vertical() -> void:
	assert_eq(groups_of("""
		. . . . . . . G
		. . . . . . . G
		. . . . . . . G
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray(["G STRAIGHT_3 NOTHING - [7, 15, 23]"]))


func test_straight_4() -> void:
	assert_eq(groups_of("""
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . A A A A
	"""), PackedStringArray(["A STRAIGHT_4 NOTHING XT [60, 61, 62, 63]"]))


func test_straight_5_and_more() -> void:
	assert_eq(groups_of("""
		B B B B B . . .
		. . . . . . . .
		$ $ $ $ $ $ $ $
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray([
		"B STRAIGHT_5 WILD XT [0, 1, 2, 3, 4]",
		"$ STRAIGHT_5 WILD XT [16, 17, 18, 19, 20, 21, 22, 23]",
	]))


func test_l_shape() -> void:
	assert_eq(groups_of("""
		. . . . . . . .
		. Y . . . . . .
		. Y . . . . . .
		. Y Y Y . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray(["Y CROSS BURST XT [9, 17, 25, 26, 27]"]))


func test_t_shape() -> void:
	assert_eq(groups_of("""
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . R R R . .
		. . . . R . . .
		. . . . R . . .
	"""), PackedStringArray(["R CROSS BURST XT [43, 44, 45, 52, 60]"]))


func test_skull_3_is_a_plain_match() -> void:
	assert_eq(groups_of("""
		S S S . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray(["S STRAIGHT_3 NOTHING - [0, 1, 2]"]))


func test_skull_4_plus_makes_a_bomb() -> void:
	assert_eq(groups_of("""
		S S S S . . . .
		. . . . . . . .
		. . . . . . S .
		. . . . . . S .
		. . . . S S S .
		. . . . . . . .
		S S S S S . . .
		. . . . . . . .
	"""), PackedStringArray([
		"S STRAIGHT_4 SKULL_BOMB XT [0, 1, 2, 3]",
		"S CROSS SKULL_BOMB XT [22, 30, 36, 37, 38]",
		"S STRAIGHT_5 SKULL_BOMB XT [48, 49, 50, 51, 52]",
	]))


func test_wild_between_red_and_blue_completes_both_as_two_groups() -> void:
	assert_eq(groups_of("""
		R R W B B . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray([
		"R STRAIGHT_3 NOTHING - [0, 1, 2]",
		"B STRAIGHT_3 NOTHING - [2, 3, 4]",
	]))


func test_wild_extends_a_color_run() -> void:
	assert_eq(groups_of("""
		. . . . . . . .
		. . . . . . . .
		. . . G . . . .
		. . . W . . . .
		. . . G . . . .
		. . . W . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray(["G STRAIGHT_4 NOTHING XT [19, 27, 35, 43]"]))


func test_three_wilds_alone_dont_match() -> void:
	assert_eq(groups_of("""
		W W W . . . . .
		. . . . . . . .
		. . . . . . . W
		. . . . . . . W
		. . . . . . . W
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray())


func test_wild_never_joins_skull_action_or_gold() -> void:
	assert_eq(groups_of("""
		S S W . . . . .
		. . . . . . . .
		A W A . . . . .
		. . . . . . . .
		W $ $ . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray())


func test_unknown_and_empty_never_match() -> void:
	assert_eq(groups_of("""
		? ? ? ? . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray())


func test_unknown_breaks_a_run() -> void:
	assert_eq(groups_of("""
		R R ? R . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray())


func test_parallel_runs_stay_separate_groups() -> void:
	assert_eq(groups_of("""
		G G G . . . . .
		G G G . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
		. . . . . . . .
	"""), PackedStringArray([
		"G STRAIGHT_3 NOTHING - [0, 1, 2]",
		"G STRAIGHT_3 NOTHING - [8, 9, 10]",
	]))


func test_full_board_without_matches() -> void:
	assert_eq(groups_of("""
		R B G Y S A $ R
		R B G Y S A $ R
		B R R G Y S A $
		G Y S A $ R B G
		G Y S A $ R B G
		Y S A $ R B G Y
		S A $ R B G Y S
		S A $ R B G Y S
	"""), PackedStringArray())
