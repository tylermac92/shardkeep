extends RefCounted
## Shared test setup. Not a test script itself (GUT only collects test_*.gd).

## The (x + 3y) % 7 pattern: full, no matches, and no legal swap.
const DEAD_BOARD := """
	R B G Y S A $ R
	Y S A $ R B G Y
	$ R B G Y S A $
	G Y S A $ R B G
	A $ R B G Y S A
	B G Y S A $ R B
	S A $ R B G Y S
	R B G Y S A $ R
"""


## Spells that only tests use, for the effect ops and rules no M0 spell exercises.
const TEST_SPELLS := {
	"zap": {id = "zap", name = "Zap", cost = {red = 2}, effects = [{op = "damage", target = "enemy", amount = 7}]},
	"focus": {id = "focus", name = "Focus", cost = {yellow = 1}, effects = [{op = "gain_mana", target = "self", color = "blue", amount = 5}]},
	"transmute": {id = "transmute", name = "Transmute", cost = {red = 1}, effects = [{op = "convert_gems", from = "red", to = "gold", count = 2}]},
	"haste": {id = "haste", name = "Haste", cost = {yellow = 0}, effects = [{op = "extra_turn"}]},
	"stun_bolt": {id = "stun_bolt", name = "Stun Bolt", cost = {yellow = 0}, effects = [{op = "apply_status", target = "enemy", status = "stun", turns = 1}]},
	"ignite": {id = "ignite", name = "Ignite", cost = {red = 0}, effects = [{op = "apply_status", target = "enemy", status = "burn", turns = 3}]},
	"ward": {id = "ward", name = "Ward", cost = {green = 0}, effects = [{op = "apply_status", target = "self", status = "barrier", turns = 3, stacks = 4}]},
	"backfire": {id = "backfire", name = "Backfire", cost = {red = 0}, effects = [{op = "damage", target = "self", amount = 99}]},
}

## The M0 content plus TEST_SPELLS.
static var test_content: ContentLoader:
	get:
		if _test_content == null:
			_test_content = ContentLoader.new()
			_test_content.load_all()
			_test_content.spells.merge(TEST_SPELLS)
		return _test_content
static var _test_content: ContentLoader


## A battle on a golden board: both sides at 50 HP with 20-point mana pools.
static func state_of(text: String, battle_seed := 0) -> BattleState:
	var s := BattleState.new()
	s.content = test_content
	s.board = Board.from_text(text)
	s.streams = Streams.new(battle_seed)
	for side in s.sides:
		side.hp = 50
		side.hp_max = 50
		side.mana_cap = PackedInt32Array([20, 20, 20, 20])
	return s


## Gives a side these spells (with fresh cooldowns) and a weapon.
static func equip(side: SideState, spells: Array, weapon := &"") -> void:
	side.spells.assign(spells.map(func(id: String) -> StringName: return StringName(id)))
	side.cooldowns.resize(spells.size())
	side.cooldowns.fill(0)
	side.weapon = weapon


static func has_action(actions: Array[Action], kind: Action.Kind, spell := &"") -> bool:
	return actions.any(func(a: Action) -> bool: return a.kind == kind and a.spell == spell)


## The events of one type, in order.
static func of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


static func types(events: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in events:
		out.append(e.type)
	return out
