extends GutTest
## Stats: Might, Vitality, mastery and Cunning (content/stats.json says what a point is worth).

const Fixtures := preload("res://tests/fixtures.gd")
const AITest := preload("res://tests/test_ai.gd")
const S := SideState.Stat

## FOUR_MATCH_BOARD's swap 55-63 makes exactly 3 red (seed 0 refills without a cascade).
const RED_SWAP := [55, 63]
## FOUR_MATCH_BOARD's swap 9-10 makes 3 blue.
const BLUE_SWAP := [9, 10]


func test_might_adds_to_skull_matches() -> void:
	var dealt := []
	for might in [0, 2]:
		var s := Fixtures.state_of(AITest.SKULL_BOARD)
		s.sides[0].stats[S.MIGHT] = might
		var after := Rules.apply(s, Action.swap(AITest.SKULL_SWAP[0], AITest.SKULL_SWAP[1])).state
		dealt.append(50 - after.sides[1].hp)
	assert_eq(dealt[1] - dealt[0], 2 * _rule("might_damage"))


func test_might_adds_to_skull_bombs_too() -> void:
	var dealt := []
	for might in [0, 3]:
		var s := Fixtures.state_of(AITest.SKULL_BOARD.replace("R B G Y S S $ S", "R B G Y S* S $ S"))
		s.sides[0].stats[S.MIGHT] = might
		var out := Rules.apply(s, Action.swap(AITest.SKULL_SWAP[0], AITest.SKULL_SWAP[1]))
		assert_true(Fixtures.types(out.events).has("cleared"))
		dealt.append(50 - out.state.sides[1].hp)
	assert_eq(dealt[1] - dealt[0], 2 * 3 * _rule("might_damage"), "once for the skull match, once for the bomb")


func test_might_adds_to_weapon_swings() -> void:
	var dealt := []
	for might in [0, 4]:
		var s := Fixtures.state_of(Fixtures.DEAD_BOARD)
		Fixtures.equip(s.sides[0], [], &"sword")
		s.sides[0].action_points = 10
		s.sides[0].stats[S.MIGHT] = might
		dealt.append(50 - Rules.apply(s, Action.attack()).state.sides[1].hp)
	assert_eq(dealt, [5, 5 + 4 * _rule("might_damage")])


func test_mastery_adds_mana_per_match_of_its_color() -> void:
	var gained := []
	for mastery in [0, 6]:
		var s := Fixtures.state_of(AITest.FOUR_MATCH_BOARD)
		s.sides[0].stats[S.RED] = mastery
		gained.append(Rules.apply(s, Action.swap(RED_SWAP[0], RED_SWAP[1])).state.sides[0].mana[Board.Gem.RED])
	assert_eq(gained, [3, 3 + 6 / _rule("mastery_points_per_mana")])


func test_mastery_can_grant_an_extra_turn() -> void:
	var procs := 0
	for battle_seed in 40:
		var s := Fixtures.state_of(AITest.FOUR_MATCH_BOARD, battle_seed)
		s.sides[0].stats[S.BLUE] = 25  # 50%, the cap
		var out := Rules.apply(s, Action.swap(BLUE_SWAP[0], BLUE_SWAP[1]))
		var proc := Fixtures.types(out.events).has("mastery_extra_turn")
		procs += int(proc)
		assert_eq(out.state.active_side == 0, proc, "seed %d: the extra turn is the mastery's" % battle_seed)
		assert_eq(Fixtures.types(Rules.apply(s, Action.swap(BLUE_SWAP[0], BLUE_SWAP[1])).events).has("mastery_extra_turn"), proc, "same seed, same roll")
	assert_between(procs, 8, 32, "about half of 40")
	var none := Fixtures.state_of(AITest.FOUR_MATCH_BOARD)
	assert_false(Fixtures.types(Rules.apply(none, Action.swap(BLUE_SWAP[0], BLUE_SWAP[1])).events).has("mastery_extra_turn"))


func test_search_never_reads_hidden_rolls() -> void:
	for mastery in [20, 25]:  # 40% and 50%
		var s := Fixtures.state_of(AITest.FOUR_MATCH_BOARD)
		s.sides[0].stats[S.BLUE] = mastery
		s.sim_draw_budget.resize(Board.SIZE)
		s.sim_draw_budget.fill(1)
		var out := Rules.apply(s, Action.swap(BLUE_SWAP[0], BLUE_SWAP[1]))
		assert_eq(Fixtures.types(out.events).has("mastery_extra_turn"), mastery == 25, "the likelier outcome")
		assert_eq(out.state.streams.draws[Streams.EFFECTS], 0, "no roll drawn")


func test_vitality_raises_max_hp() -> void:
	var s := Rules.new_battle(1, Fixtures.test_content, [_loadout({"vitality": 2}), _loadout({})])
	assert_eq(s.sides[0].hp_max, 40 + 2 * _rule("vitality_hp"))
	assert_eq(s.sides[0].hp, s.sides[0].hp_max)
	assert_eq(s.sides[1].hp_max, 40)


func test_higher_cunning_moves_first_and_the_other_side_gets_the_head_start() -> void:
	for battle_seed in 10:
		for order in [[3, 1], [1, 3]]:
			var s := Rules.new_battle(battle_seed, Fixtures.test_content, [_loadout({"cunning": order[0]}), _loadout({"cunning": order[1]})])
			var first := 0 if order[0] > order[1] else 1
			assert_eq(s.active_side, first)
			var head := mini(Fixtures.test_content.second_mover_mana, 20)
			assert_eq(s.sides[1 - first].mana, PackedInt32Array([head, head, head, head]))
			assert_eq(s.sides[first].mana, PackedInt32Array([0, 0, 0, 0]))


func test_equal_cunning_goes_by_the_seed() -> void:
	var firsts := {}
	for battle_seed in 20:
		var s := Rules.new_battle(battle_seed, Fixtures.test_content, ["loadout_a", "loadout_b"])
		firsts[s.active_side] = true
		assert_eq(Rules.new_battle(battle_seed, Fixtures.test_content, ["loadout_a", "loadout_b"]).active_side, s.active_side)
		assert_eq(s.board.gems, _board_without_stats(battle_seed), "the tie-break doesn't change the board")
	assert_eq(firsts.size(), 2, "both sides move first sometimes")


func test_cunning_resists_enemy_stuns() -> void:
	var resisted := 0
	for battle_seed in 40:
		var s := _stun_duel(battle_seed, 20)  # 60%, capped at 50%
		var types := Fixtures.types(Rules.apply(s, Action.cast(&"stun_bolt")).events)
		assert_ne(types.has("status_resisted"), types.has("status_applied"))
		resisted += int(types.has("status_resisted"))
	assert_between(resisted, 8, 32)
	for battle_seed in 10:
		assert_false(Fixtures.types(Rules.apply(_stun_duel(battle_seed, 0), Action.cast(&"stun_bolt")).events).has("status_resisted"))


func test_only_resistible_statuses_from_the_enemy_are_resisted() -> void:
	for battle_seed in 20:
		var s := _stun_duel(battle_seed, 20)
		Fixtures.equip(s.sides[0], ["ignite"])  # burn isn't resistible
		assert_false(Fixtures.types(Rules.apply(s, Action.cast(&"ignite")).events).has("status_resisted"))
		var own := _stun_duel(battle_seed, 0)
		own.sides[0].stats[S.CUNNING] = 20
		var events: Array[Dictionary] = []
		EffectRunner.apply_status(own, 0, "stun", 1, 1, events)  # a side's own status is never resisted
		assert_eq(Fixtures.types(events), PackedStringArray(["status_applied"]))


func test_resist_rolls_are_hidden_from_search() -> void:
	var s := _stun_duel(0, 20)
	s.sim_draw_budget.resize(Board.SIZE)
	s.sim_draw_budget.fill(1)
	var out := Rules.apply(s, Action.cast(&"stun_bolt"))
	assert_true(Fixtures.types(out.events).has("status_resisted"), "50% rounds to resisted")
	assert_eq(out.state.streams.draws[Streams.EFFECTS], 0)


func test_balance_runner_counts_who_really_moved_first() -> void:
	var Runner := preload("res://tools/balance_runner.gd")
	var quick := _loadout({"cunning": 5})
	var spec := {"level": "easy", "matchups": [{"name": "quick_vs_b", "loadouts": [quick, "loadout_b"]}]}
	var m: Dictionary = Runner.run(Fixtures.test_content, spec, 4, 3)[0]
	for b: Dictionary in m.battles:
		assert_eq(b.first, 0, "the higher-Cunning loadout moves first on either side")


func _stun_duel(battle_seed: int, cunning: int) -> BattleState:
	var s := Fixtures.state_of(Fixtures.DEAD_BOARD, battle_seed)
	Fixtures.equip(s.sides[0], ["stun_bolt"])
	s.sides[1].stats[S.CUNNING] = cunning
	return s


func _loadout(stats: Dictionary) -> Dictionary:
	return {"hp": 40, "mana_cap": {"red": 20, "blue": 20, "green": 20, "yellow": 20}, "spells": [], "weapon": "sword", "stats": stats}


func _board_without_stats(battle_seed: int) -> PackedByteArray:
	return Rules.new_battle(battle_seed, Fixtures.test_content).board.gems


func _rule(key: String) -> int:
	return int(Fixtures.test_content.stat_rules[key])
