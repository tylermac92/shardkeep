class_name Rules
extends RefCounted
## The engine's entry point (technical_design.md, Turn pipeline). apply() never changes the
## state it's given: it returns a new state plus the events for the client to animate.

const MANA_KINDS := ["red", "blue", "green", "yellow"]


class Outcome:
	var state: BattleState
	var events: Array[Dictionary] = []


## A new battle with its board drawn from the setup stream. Sides start empty; the caller fills them.
static func new_battle(battle_seed: int, content: ContentLoader) -> BattleState:
	var s := BattleState.new()
	s.content = content
	s.streams = Streams.new(battle_seed)
	var b := s.board
	var weights := content.gem_weights
	while true:
		for c in Board.CELLS:
			var g := s.streams.next_weighted(Streams.SETUP, weights)
			# Redraw any gem that would complete a run with the two to its left or above.
			while (c % Board.SIZE >= 2 and b.gems[c - 1] == g and b.gems[c - 2] == g) \
					or (c >= 2 * Board.SIZE and b.gems[c - Board.SIZE] == g and b.gems[c - 2 * Board.SIZE] == g):
				g = s.streams.next_weighted(Streams.SETUP, weights)
			b.gems[c] = g
		if not _swaps(b, true).is_empty():
			break
	return s


## Every legal action for the active side: swaps of adjacent, unlocked gems that make a match.
static func legal_actions(state: BattleState) -> Array[Action]:
	if state.result != BattleState.Result.ONGOING:
		return []
	return _swaps(state.board, false)


## Runs one action. Returns null, and changes nothing, if the action isn't legal.
static func apply(state: BattleState, action: Action) -> Outcome:
	if state.result != BattleState.Result.ONGOING or action.kind != Action.Kind.SWAP or not _adjacent(action.a, action.b):
		return null
	var s := state.clone()
	if not _swap_matches(s.board, action.a, action.b):
		return null
	var out := Outcome.new()
	out.state = s
	_swap_cells(s.board, action.a, action.b)
	out.events.append({type = "swapped", a = action.a, b = action.b})
	cascade(s, out.events)
	s.active_side = 1 - s.active_side
	s.turn += 1
	out.events.append({type = "turn_passed", to_side = s.active_side})
	return out


## Match, pay the active side, clear, fall and refill, until the board settles.
static func cascade(s: BattleState, events: Array[Dictionary]) -> void:
	var depth := 0
	while true:
		var groups := Matcher.find_groups(s.board)
		if groups.is_empty():
			return
		depth += 1
		var hit := {}
		for g in groups:
			events.append({type = "matched", cells = g.cells, gem = g.gem, group_size = g.cells.size(), cascade_depth = depth})
			_pay(s, g, events)
			for c in g.cells:
				hit[c] = true
		var cells := PackedInt32Array(hit.keys())
		cells.sort()
		for c in cells:
			_clear_cell(s.board, c)
		events.append({type = "cleared", cells = cells, cause = "match"})
		fall_and_refill(s, events)


## Drops gems into empty cells, then fills each column from its own skyfall stream.
## The first gem drawn lands lowest, so the ghost row always shows the next gem to enter.
static func fall_and_refill(s: BattleState, events: Array[Dictionary]) -> void:
	var b := s.board
	var moves: Array[Vector2i] = []
	var spawned_cells := PackedInt32Array()
	var spawned_gems := PackedInt32Array()
	for x in Board.SIZE:
		var write := Board.SIZE - 1
		for y in range(Board.SIZE - 1, -1, -1):
			var c := y * Board.SIZE + x
			if b.gems[c] == Board.Gem.EMPTY:
				continue
			if y != write:
				var to := write * Board.SIZE + x
				b.gems[to] = b.gems[c]
				b.special[to] = b.special[c]
				b.locked[to] = b.locked[c]
				_clear_cell(b, c)
				moves.append(Vector2i(c, to))
			write -= 1
		for y in range(write, -1, -1):
			var c := y * Board.SIZE + x
			b.gems[c] = s.streams.next_weighted(Streams.COL_0 + x, s.content.gem_weights)
			spawned_cells.append(c)
			spawned_gems.append(b.gems[c])
	if not moves.is_empty():
		events.append({type = "fell", moves = moves})
	if not spawned_cells.is_empty():
		events.append({type = "spawned", cells = spawned_cells, gems = spawned_gems})


## Base reward for a matched group, paid to the active side (skull damage hits the other side).
static func _pay(s: BattleState, g: Matcher.Group, events: Array[Dictionary]) -> void:
	var def: Dictionary = s.content.gem_defs[g.gem]
	var amount: int = int(def.amount) * g.cells.size()
	var side := s.active_side
	var me := s.sides[side]
	match def.reward:
		"mana":
			var gain := clampi(me.mana_cap[g.gem] - me.mana[g.gem], 0, amount)
			me.mana[g.gem] += gain
			_changed(events, side, MANA_KINDS[g.gem], gain)
		"damage":
			var foe := s.sides[1 - side]
			var dmg := mini(amount, foe.hp)
			foe.hp -= dmg
			_changed(events, 1 - side, "hp", -dmg)
		"ap":
			me.action_points += amount
			_changed(events, side, "ap", amount)
		"gold":
			me.gold_gained += amount
			_changed(events, side, "gold", amount)


static func _changed(events: Array[Dictionary], side: int, kind: String, delta: int) -> void:
	if delta != 0:
		events.append({type = "resource_changed", side = side, kind = kind, delta = delta})


## All matching swaps on the board, or just the first one when first_only is set.
static func _swaps(board: Board, first_only: bool) -> Array[Action]:
	var work := board.clone()  # _swap_matches swaps and restores; keep the caller's board untouched
	var out: Array[Action] = []
	for a in Board.CELLS:
		for b in [a + 1, a + Board.SIZE]:
			if _adjacent(a, b) and _swap_matches(work, a, b):
				out.append(Action.swap(a, b))
				if first_only:
					return out
	return out


static func _adjacent(a: int, b: int) -> bool:
	if a < 0 or b >= Board.CELLS or a >= b:
		return false
	return (b == a + 1 and a % Board.SIZE != Board.SIZE - 1) or b == a + Board.SIZE


## Whether swapping a and b makes a match. Leaves the board as it found it.
static func _swap_matches(board: Board, a: int, b: int) -> bool:
	if board.locked[a] > 0 or board.locked[b] > 0 or board.gems[a] == board.gems[b]:
		return false
	_swap_cells(board, a, b)
	var hit := Matcher.has_match_through(board, a) or Matcher.has_match_through(board, b)
	_swap_cells(board, a, b)
	return hit


static func _swap_cells(board: Board, a: int, b: int) -> void:
	var g := board.gems[a]
	board.gems[a] = board.gems[b]
	board.gems[b] = g
	var sp := board.special[a]
	board.special[a] = board.special[b]
	board.special[b] = sp


static func _clear_cell(board: Board, c: int) -> void:
	board.gems[c] = Board.Gem.EMPTY
	board.special[c] = Board.Special.NONE
	board.locked[c] = 0
