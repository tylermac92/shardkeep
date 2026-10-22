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


## A battle on a golden board: both sides at 50 HP with 20-point mana pools.
static func state_of(text: String, battle_seed := 0) -> BattleState:
	var s := BattleState.new()
	s.content = ContentDB.content
	s.board = Board.from_text(text)
	s.streams = Streams.new(battle_seed)
	for side in s.sides:
		side.hp = 50
		side.hp_max = 50
		side.mana_cap = PackedInt32Array([20, 20, 20, 20])
	return s


## The events of one type, in order.
static func of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


static func types(events: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in events:
		out.append(e.type)
	return out
