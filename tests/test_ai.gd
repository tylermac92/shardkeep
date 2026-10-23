extends GutTest

const Fixtures := preload("res://tests/fixtures.gd")
const Benchmark := preload("res://tools/benchmark.gd")

## Every swap here gives 3 mana and nothing else. The red one on the left (50-58) drops
## columns 0-2 by one, which lines up a blue 4-match for the other side; the rest don't.
const FOUR_MATCH_BOARD := """
	R B G Y S A $ R
	Y S B $ R B G Y
	B B Y G Y S A $
	G Y S B $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S A R G B G Y R
	R R G Y S R R B
"""
const GIVES_FOUR := [50, 58]
## FOUR_MATCH_BOARD plus the only skull swap (6-7), which makes 3 skulls in the top row.
const SKULL_BOARD := """
	R B G Y S S $ S
	Y S B $ R B G Y
	B B Y G Y S A $
	G Y S B $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S A R G B G Y R
	R R G Y S R R B
"""
const SKULL_SWAP := [6, 7]

var _content: ContentLoader


func before_all() -> void:
	_content = ContentLoader.new()
	_content.load_all()


func test_fog_hides_what_falls_after_the_ghost_row() -> void:
	var leaks := 0
	for s in Benchmark.positions(_content, 8):
		var other := _same_ghost_row_different_future(s)
		for level in [AI.Level.EASY, AI.Level.NORMAL]:
			assert_true(_same(AI.choose(s, level), AI.choose(other, level)), "level %d decides on hidden gems" % level)
		leaks += int(_futures_differ(s, other))
	assert_gt(leaks, 0, "the test positions should differ once hidden gems fall")


func test_fog_holds_for_hard() -> void:
	for s: BattleState in Benchmark.positions(_content, 18).slice(16):
		assert_true(_same(AI.choose(s, AI.Level.HARD), AI.choose(_same_ghost_row_different_future(s), AI.Level.HARD)))


func test_normal_avoids_leaving_a_four_match() -> void:
	var s := Fixtures.state_of(FOUR_MATCH_BOARD)
	s.active_side = 1
	var root := _fogged(s)
	var w := AI.DEFAULT_WEIGHTS
	var bad := Rules.apply(root, Action.swap(GIVES_FOUR[0], GIVES_FOUR[1])).state
	assert_true(_has_four_match(bad), "the left red swap should set up a 4-match")
	var pick := AI.choose(s, AI.Level.NORMAL)
	var after := Rules.apply(root, pick).state
	assert_false(_has_four_match(after))
	assert_eq(AI.score(root, after, 1, w), AI.score(root, bad, 1, w), "both moves should score the same right away")
	# Whatever the ghost row holds, Normal never takes the move that gives the player a 4-match.
	for battle_seed in 10:
		s = Fixtures.state_of(FOUR_MATCH_BOARD, battle_seed)
		s.active_side = 1
		assert_false(_is_swap(AI.choose(s, AI.Level.NORMAL), GIVES_FOUR), "seed %d" % battle_seed)


func test_every_level_takes_a_lethal_swap() -> void:
	for turn in 12:  # the turn shifts Easy's noise roll
		var s := Fixtures.state_of(SKULL_BOARD)
		s.turn = turn
		s.sides[1].hp = 3
		for level in AI.Level.size():
			assert_true(_is_swap(AI.choose(s, level), SKULL_SWAP), "level %d, turn %d" % [level, turn])


func test_easy_sometimes_picks_a_worse_move() -> void:
	var off_best := 0
	for turn in 40:
		var s := Fixtures.state_of(SKULL_BOARD)
		s.turn = turn
		off_best += int(not _is_swap(AI.choose(s, AI.Level.EASY), SKULL_SWAP))
		assert_true(_is_swap(AI.choose(s, AI.Level.NORMAL), SKULL_SWAP))
	assert_between(off_best, 4, 18, "Easy picks the 2nd or 3rd best about 25% of the time")


func test_same_state_gives_same_decision() -> void:
	var first := Benchmark.positions(_content, 6)
	var again := Benchmark.positions(_content, 6)
	for i in first.size():
		for level in [AI.Level.EASY, AI.Level.NORMAL]:
			var a := AI.choose(first[i], level)
			assert_true(_same(a, AI.choose(first[i], level)))
			assert_true(_same(a, AI.choose(again[i], level)))


func test_search_never_changes_the_state() -> void:
	for s: BattleState in Benchmark.positions(_content, 4).slice(2):
		var before := s.state_hash()
		for level in AI.Level.size():
			AI.choose(s, level)
		assert_eq(s.state_hash(), before)
		assert_true(s.sim_draw_budget.is_empty())


func test_no_action_after_the_battle_ends() -> void:
	var s := Fixtures.state_of(SKULL_BOARD)
	s.result = BattleState.Result.SIDE1_WON
	assert_null(AI.choose(s, AI.Level.NORMAL))


func test_weights_come_from_content() -> void:
	var w := AI.weights_for(_content.classes["loadout_b"])
	assert_eq(w.mana, 0.6)
	assert_eq(w.damage, AI.DEFAULT_WEIGHTS.damage)
	assert_eq(AI.weights_for({}), AI.DEFAULT_WEIGHTS)


func test_mana_toward_a_spell_is_worth_more() -> void:
	var s := Fixtures.state_of(Fixtures.DEAD_BOARD)
	Fixtures.equip(s.sides[0], ["firebolt"])  # costs 7 red
	var after := s.clone()
	after.sides[0].mana[0] = 3  # all of it toward firebolt
	var spare := s.clone()
	spare.sides[0].mana[1] = 3  # no spell needs blue
	after.active_side = 1
	spare.active_side = 1
	assert_gt(AI.score(s, after, 0, AI.DEFAULT_WEIGHTS), AI.score(s, spare, 0, AI.DEFAULT_WEIGHTS))


## A copy of s whose skyfall streams show the same ghost row but differ in the gem after it,
## and whose effects stream (mastery and resist rolls) is somewhere else entirely.
func _same_ghost_row_different_future(s: BattleState) -> BattleState:
	var other := s.clone()
	for x in Board.SIZE:
		var col := Streams.COL_0 + x
		var n := s.streams.draws[col]
		var m := n + 1
		while _gem_at(s, col, m) != _gem_at(s, col, n) or _gem_at(s, col, m + 1) == _gem_at(s, col, n + 1):
			m += 1
		other.streams.draws[col] = m
	other.streams.draws[Streams.EFFECTS] += 1000  # hidden rolls (mastery, resist) differ too
	return other


func _gem_at(s: BattleState, stream: int, n: int) -> int:
	var st := s.streams.clone()
	st.draws[stream] = n
	return st.next_weighted(stream, s.content.gem_weights)


## Whether some legal swap, played with full information, ends on different boards.
func _futures_differ(a: BattleState, b: BattleState) -> bool:
	for act in Rules.legal_actions(a):
		if Rules.apply(a, act).state.board.gems != Rules.apply(b, act).state.board.gems:
			return true
	return false


func _fogged(s: BattleState) -> BattleState:
	var root := s.clone()
	root.sim_draw_budget.resize(Board.SIZE)
	root.sim_draw_budget.fill(1)
	return root


func _has_four_match(s: BattleState) -> bool:
	for a in Rules.legal_actions(s):
		if Rules.apply(s, a).events.any(func(e: Dictionary) -> bool: return e.type == "matched" and e.group_size >= 4):
			return true
	return false


func _same(a: Action, b: Action) -> bool:
	return a.kind == b.kind and a.a == b.a and a.b == b.b and a.spell == b.spell


func _is_swap(a: Action, cells: Array) -> bool:
	return a.kind == Action.Kind.SWAP and a.a == cells[0] and a.b == cells[1]
