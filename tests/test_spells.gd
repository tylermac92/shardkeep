extends GutTest
## Casting, attacking, cooldowns, statuses and the M0 content.

const Fixtures := preload("res://tests/fixtures.gd")
const RulesTest := preload("res://tests/test_rules.gd")
const K := Action.Kind


func duel(spells0: Array, spells1: Array = []) -> BattleState:
	var s := Fixtures.state_of(RulesTest.CASCADE_BOARD)
	Fixtures.equip(s.sides[0], spells0, &"sword")
	Fixtures.equip(s.sides[1], spells1, &"mace")
	return s


## Applies the action, failing the test if it's illegal.
func act(s: BattleState, action: Action) -> Rules.Outcome:
	var out := Rules.apply(s, action)
	assert_not_null(out, "action kind %d (%s) is legal" % [action.kind, action.spell])
	return out


func test_too_little_mana_or_cooldown_keeps_a_spell_out_of_legal_actions() -> void:
	var s := duel(["tidal_shift"])
	s.sides[0].mana[Board.Gem.BLUE] = 4
	assert_false(Fixtures.has_action(Rules.legal_actions(s), K.CAST, &"tidal_shift"), "4 of 5 blue")
	assert_null(Rules.apply(s, Action.cast(&"tidal_shift")))
	s.sides[0].mana[Board.Gem.BLUE] = 10
	assert_true(Fixtures.has_action(Rules.legal_actions(s), K.CAST, &"tidal_shift"))
	var after := act(s, Action.cast(&"tidal_shift")).state
	assert_eq(after.sides[0].mana[Board.Gem.BLUE], 5, "still enough mana")
	assert_false(Fixtures.has_action(Rules.legal_actions(after), K.CAST, &"tidal_shift"), "on cooldown")
	assert_null(Rules.apply(after, Action.cast(&"tidal_shift")))


func test_cooldown_blocks_the_next_two_own_turns() -> void:
	var s := Rules.new_battle(5, Fixtures.test_content, ["loadout_a", "loadout_b"])
	s.sides[0].mana = PackedInt32Array([0, 20, 0, 0])
	s = act(s, Action.cast(&"tidal_shift")).state  # cooldown 2; doesn't end the turn
	var castable := []  # at the start of each of side 0's next turns
	while castable.size() < 3:
		var turn := s.turn
		s = act(s, first_swap(s)).state
		if s.turn != turn and s.active_side == 0:
			s.sides[0].mana[Board.Gem.BLUE] = 20  # so only the cooldown decides
			castable.append(Fixtures.has_action(Rules.legal_actions(s), K.CAST, &"tidal_shift"))
	assert_eq(castable, [false, false, true])


func test_swap_is_still_allowed_after_a_spell_that_doesnt_end_the_turn() -> void:
	var s := duel(["tidal_shift"])
	s.sides[0].mana[Board.Gem.BLUE] = 5
	var out := act(s, Action.cast(&"tidal_shift"))
	assert_eq(out.state.active_side, 0)
	assert_eq(Fixtures.of_type(out.events, "turn_passed").size(), 0)
	assert_true(Fixtures.has_action(Rules.legal_actions(out.state), K.SWAP), "swaps are legal")


func test_attack_costs_action_points() -> void:
	var s := duel([])
	s.sides[0].action_points = 3
	assert_false(Fixtures.has_action(Rules.legal_actions(s), K.ATTACK), "sword needs 4")
	assert_null(Rules.apply(s, Action.attack()))
	s.sides[0].action_points = 5
	var out := act(s, Action.attack())
	assert_eq(out.events, [
		{type = "resource_changed", side = 0, kind = "ap", delta = -4},
		{type = "spell_cast", side = 0, spell = &"sword"},
		{type = "resource_changed", side = 1, kind = "hp", delta = -5},
		{type = "turn_passed", to_side = 1},
	] as Array[Dictionary])


func test_stun_makes_the_target_pass_and_cant_be_chained() -> void:
	var s := duel(["stun_bolt", "ignite"])
	s = act(s, Action.cast(&"ignite")).state  # burn 3 turns on side 1
	# Side 1 takes its turn (burn ticks to 2), then side 0 stuns it.
	assert_eq(s.active_side, 1)
	assert_eq(s.sides[1].hp, 48, "burn hit at the start of side 1's turn")
	s = act(s, first_swap(s)).state
	while s.active_side != 0:
		s = act(s, first_swap(s)).state
	var stunned := act(s, Action.cast(&"stun_bolt"))
	assert_has(stunned.events, {type = "status_applied", side = 1, status = "stun", turns = 1, stacks = 1})
	s = stunned.state
	assert_eq(s.active_side, 1)
	assert_eq(Rules.legal_actions(s).size(), 1)
	assert_eq(Rules.legal_actions(s)[0].kind, K.PASS, "a stunned side can only pass")
	assert_null(Rules.apply(s, Action.swap(50, 58)), "and can't swap")
	var burn_turns: int = status(s.sides[1], "burn").turns
	var passed := act(s, Action.pass_turn())
	assert_has(passed.events, {type = "status_expired", side = 1, status = "stun"})
	assert_eq(status(passed.state.sides[1], "burn").turns, burn_turns - 1, "statuses tick on the skipped turn")
	s = passed.state
	assert_eq(s.active_side, 0)
	assert_null(Rules.apply(duel([]), Action.pass_turn()), "pass isn't legal for a side that isn't stunned")
	var blocked := act(s, Action.cast(&"stun_bolt"))
	assert_has(blocked.events, {type = "status_blocked", side = 1, status = "stun"}, "stunned on its previous turn")
	s = blocked.state
	assert_eq(s.active_side, 1)
	assert_ne(Rules.legal_actions(s)[0].kind, K.PASS, "side 1 plays normally")
	while s.active_side != 0:
		s = act(s, first_swap(s)).state
	assert_has(act(s, Action.cast(&"stun_bolt")).events, {type = "status_applied", side = 1, status = "stun", turns = 1, stacks = 1},
		"stun works again once side 1 has had a normal turn")


func test_barrier_absorbs_weapon_and_skull_damage_before_hp() -> void:
	var s := duel([])
	EffectRunner.apply_status(s, 1, "barrier", 5, 10, [] as Array[Dictionary])
	s.sides[0].action_points = 4
	var hit := act(s, Action.attack())
	assert_has(hit.events, {type = "damage_absorbed", side = 1, status = "barrier", amount = 5})
	assert_eq(hit.state.sides[1].hp, 50, "sword damage absorbed")
	assert_eq(status(hit.state.sides[1], "barrier").stacks, 5)

	var t := duel([])
	EffectRunner.apply_status(t, 1, "barrier", 5, 2, [] as Array[Dictionary])
	var out := act(t, Action.swap(50, 58))  # the depth-2 skulls deal 3
	var absorbed := Fixtures.of_type(out.events, "damage_absorbed")
	assert_eq(absorbed, [{type = "damage_absorbed", side = 1, status = "barrier", amount = 2}] as Array[Dictionary])
	assert_has(out.events, {type = "status_expired", side = 1, status = "barrier"})
	assert_eq(out.state.sides[1].hp, 49, "the 1 the barrier couldn't hold reaches HP")


func test_burn_can_knock_out_a_side_at_the_start_of_its_turn() -> void:
	var s := duel(["ignite"])
	s = act(s, Action.cast(&"ignite")).state
	s.active_side = 0
	s.sides[1].hp = 2
	var out := act(s, Action.cast(&"ignite"))
	assert_eq(Fixtures.types(out.events).slice(-3), PackedStringArray(["turn_passed", "resource_changed", "battle_ended"]))
	assert_eq(out.state.result, BattleState.Result.SIDE0_WON)


func test_a_spell_that_knocks_out_its_caster_loses() -> void:
	var out := act(duel(["backfire"]), Action.cast(&"backfire"))
	assert_eq(out.events.back(), {type = "battle_ended", winner = 1})


func test_loadouts_equip_both_sides() -> void:
	var s := Rules.new_battle(1, ContentDB.content, ["loadout_a", "loadout_b"])
	assert_eq(s.sides[0].spells, [&"firebolt", &"tidal_shift"] as Array[StringName])
	assert_eq(s.sides[1].spells, [&"stone_barrier", &"concussion"] as Array[StringName])
	assert_eq([s.sides[0].weapon, s.sides[1].weapon], [&"sword", &"mace"])
	assert_eq(s.sides[0].hp, 50)
	assert_eq(s.sides[1].mana_cap, PackedInt32Array([20, 20, 20, 20]))
	assert_eq(s.sides[0].cooldowns, PackedInt32Array([0, 0]))


func test_m0_content_passes_validation() -> void:
	assert_eq(ContentDB.content.validate(), PackedStringArray())


func test_validation_fails_on_unknown_ops_and_references() -> void:
	var c := ContentLoader.new()
	c.load_all()
	c.spells["firebolt"] = {id = "firebolt", cost = {red = 1}, effects = [{op = "teleport"}]}
	c.weapons["sword"] = {id = "sword", ap_cost = 1, effects = [{op = "apply_status", target = "enemy", status = "frozen", turns = 1}]}
	c.classes["loadout_b"] = {id = "loadout_b", spells = ["nope"], weapon = "spoon"}
	assert_eq(c.validate(), PackedStringArray([
		"spells.json: firebolt uses unknown effect op \"teleport\"",
		"weapons.json: sword applies unknown status \"frozen\"",
		"classes.json: loadout_b lists unknown spell \"nope\"",
		"classes.json: loadout_b has unknown weapon \"spoon\"",
	]))


func first_swap(s: BattleState) -> Action:
	return Rules.legal_actions(s).filter(func(a: Action) -> bool: return a.kind == K.SWAP)[0]


func status(side: SideState, id: String) -> Dictionary:
	for st in side.statuses:
		if st.id == id:
			return st
	return {}
