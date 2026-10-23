class_name Rules
extends RefCounted
## The engine's entry point (technical_design.md, Turn pipeline). apply() never changes the
## state it's given: it returns a new state plus the events for the client to animate.

const MANA_KINDS := ["red", "blue", "green", "yellow"]


class Outcome:
	var state: BattleState
	var events: Array[Dictionary] = []


## A new battle with its board drawn from the setup stream. loadouts, if given, equip side 0
## and side 1: each is a classes.json id or a class entry of its own (hp, mana_cap, spells,
## weapon). Without them the sides start empty for the caller to fill.
static func new_battle(battle_seed: int, content: ContentLoader, loadouts: Array = []) -> BattleState:
	var s := BattleState.new()
	s.content = content
	s.streams = Streams.new(battle_seed)
	for i in loadouts.size():
		var def: Dictionary = loadouts[i] if loadouts[i] is Dictionary else content.classes[loadouts[i]]
		var side := s.sides[i]
		side.hp = int(def.hp)
		side.hp_max = side.hp
		for color in MANA_KINDS.size():
			side.mana_cap[color] = int(def.mana_cap[MANA_KINDS[color]])
		for spell: String in def.spells:
			side.spells.append(StringName(spell))
		side.cooldowns.resize(side.spells.size())
		side.weapon = StringName(def.weapon)
	for color in MANA_KINDS.size():  # side 0 moves first; side 1 gets the head start
		s.sides[1].mana[color] = mini(content.second_mover_mana, s.sides[1].mana_cap[color])
	_fill_board(s, false)
	return s


## Every legal action for the active side: matching swaps, castable spells and an affordable
## attack, or just a pass when the side is stunned.
static func legal_actions(state: BattleState) -> Array[Action]:
	if state.result != BattleState.Result.ONGOING:
		return []
	var me := state.sides[state.active_side]
	if _is_stunned(state, me):
		return [Action.pass_turn()]
	var out := _swaps(state.board, false)
	for i in me.spells.size():
		if _can_cast(state, me, i):
			out.append(Action.cast(me.spells[i]))
	if _can_attack(state, me):
		out.append(Action.attack())
	return out


## Runs one action. Returns null, and changes nothing, if the action isn't legal.
static func apply(state: BattleState, action: Action) -> Outcome:
	if state.result != BattleState.Result.ONGOING:
		return null
	var s := state.clone()
	var side := s.active_side
	var me := s.sides[side]
	if _is_stunned(s, me) != (action.kind == Action.Kind.PASS):
		return null
	var out := Outcome.new()
	out.state = s
	var match_extra := false
	var spell_extra := false
	var ends_turn := true
	match action.kind:
		Action.Kind.SWAP:
			if not _adjacent(action.a, action.b) or not _swap_matches(s.board, action.a, action.b):
				return null
			_swap_cells(s.board, action.a, action.b)
			out.events.append({type = "swapped", a = action.a, b = action.b})
			match_extra = cascade(s, out.events, PackedInt32Array([action.a, action.b]))
		Action.Kind.CAST:
			var i := me.spells.find(action.spell)
			if i < 0 or not _can_cast(s, me, i):
				return null
			var def: Dictionary = s.content.spells[action.spell]
			for color in MANA_KINDS.size():
				var cost := int(def.cost.get(MANA_KINDS[color], 0))
				me.mana[color] -= cost
				_changed(out.events, side, MANA_KINDS[color], -cost)
			var cooldown := int(def.get("cooldown", 0))
			# +1 because the end of this turn ticks it too; it then blocks the next `cooldown` own turns.
			me.cooldowns[i] = cooldown + 1 if cooldown > 0 else 0
			out.events.append({type = "spell_cast", side = side, spell = action.spell})
			spell_extra = EffectRunner.run(s, def.effects, side, out.events)
			if s.result == BattleState.Result.ONGOING:
				match_extra = cascade(s, out.events)
			ends_turn = def.get("ends_turn", true)
		Action.Kind.ATTACK:
			if not _can_attack(s, me):
				return null
			var def: Dictionary = s.content.weapons[me.weapon]
			var ap_cost := int(def.ap_cost)
			me.action_points -= ap_cost
			_changed(out.events, side, "ap", -ap_cost)
			out.events.append({type = "spell_cast", side = side, spell = me.weapon})
			spell_extra = EffectRunner.run(s, def.effects, side, out.events)
			if s.result == BattleState.Result.ONGOING:
				match_extra = cascade(s, out.events)
	if s.result != BattleState.Result.ONGOING:
		return out
	if not ends_turn:
		pass  # a spell that doesn't end the turn: the same side acts again, swap included
	elif match_extra or spell_extra:
		out.events.append({type = "extra_turn", side = side, reason = "match" if match_extra else "spell"})
	else:
		_end_turn(s, out.events)
		if s.result != BattleState.Result.ONGOING:
			return out
	# No reshuffle in AI search: it would draw from hidden streams, and a fogged board can't settle.
	if _swaps(s.board, true).is_empty() and s.sim_draw_budget.is_empty():
		reshuffle(s, out.events)
	return out


## The next gem each column will drop: the ghost row both sides see above the board.
static func ghost_row(state: BattleState) -> PackedByteArray:
	var peek := state.streams.clone()
	var out := PackedByteArray()
	for x in Board.SIZE:
		out.append(peek.next_weighted(Streams.COL_0 + x, state.content.gem_weights))
	return out


## Deals damage to a side. Barrier soaks it up first; a knockout ends the battle, and if both
## sides are down the acting side loses.
static func damage(s: BattleState, target: int, amount: int, events: Array[Dictionary]) -> void:
	var side := s.sides[target]
	for st in side.statuses.duplicate():
		if amount > 0 and s.content.statuses[st.id].get("absorbs_damage", false):
			var soaked := mini(st.stacks, amount)
			st.stacks -= soaked
			amount -= soaked
			events.append({type = "damage_absorbed", side = target, status = st.id, amount = soaked})
			if st.stacks <= 0:
				side.statuses.erase(st)
				events.append({type = "status_expired", side = target, status = st.id})
	var dmg := mini(amount, side.hp)
	side.hp -= dmg
	_changed(events, target, "hp", -dmg)
	var me := s.active_side
	var winner := -1
	if s.sides[me].hp <= 0:
		winner = 1 - me
	elif s.sides[1 - me].hp <= 0:
		winner = me
	if winner >= 0:
		s.result = BattleState.Result.SIDE0_WON if winner == 0 else BattleState.Result.SIDE1_WON
		events.append({type = "battle_ended", winner = winner})


## Adds mana up to the pool's cap.
static func gain_mana(s: BattleState, target: int, color: int, amount: int, events: Array[Dictionary]) -> void:
	var side := s.sides[target]
	var gain := clampi(side.mana_cap[color] - side.mana[color], 0, amount)
	side.mana[color] += gain
	_changed(events, target, MANA_KINDS[color], gain)


## Match, pay the active side, clear (with blasts), place new specials, fall and refill,
## until the board settles or a side is knocked out. Returns whether any group earned an
## extra turn. swapped holds the cells of the swap that started it, if any.
static func cascade(s: BattleState, events: Array[Dictionary], swapped := PackedInt32Array()) -> bool:
	var extra_turn := false
	var depth := 0
	while true:
		var groups := Matcher.find_groups(s.board)
		if groups.is_empty():
			return extra_turn
		depth += 1
		var b := s.board
		var hit := {}
		for g in groups:
			events.append({type = "matched", cells = g.cells, gem = g.gem, group_size = g.cells.size(), cascade_depth = depth})
			var wild := 1
			for c in g.cells:
				hit[c] = true
				if b.gems[c] == Board.Gem.WILD:
					wild = 2
			_pay(s, g.gem, g.cells.size() * wild, events)
			if s.result != BattleState.Result.ONGOING:
				return extra_turn
			extra_turn = extra_turn or g.extra_turn
		var matched := PackedInt32Array(hit.keys())
		matched.sort()
		events.append({type = "cleared", cells = matched, cause = "match"})
		if not _blast(s, matched, hit, events):
			return extra_turn
		for c in hit:
			_clear_cell(b, c)
		for g in groups:
			if g.creates != Matcher.Creates.NOTHING:
				_place_special(s, g, swapped if depth == 1 else PackedInt32Array(), events)
		fall_and_refill(s, events)
	return extra_turn


## Permutes the gems with the shuffle stream until the board has no matches and a legal swap
## (after 100 tries, draws a fresh board from the skyfall streams). Both sides then lose a
## quarter of each mana pool, rounded down. The acting side keeps its turn.
static func reshuffle(s: BattleState, events: Array[Dictionary]) -> void:
	var b := s.board
	var settled := false
	for attempt in 100:
		for i in range(Board.CELLS - 1, 0, -1):
			_swap_cells(b, i, s.streams.next_int(Streams.SHUFFLE) % (i + 1))
		if Matcher.find_groups(b).is_empty() and not _swaps(b, true).is_empty():
			settled = true
			break
	if not settled:
		_fill_board(s, true)
	var lost := []
	for side in s.sides:
		var loss := PackedInt32Array()
		for color in 4:
			loss.append(side.mana[color] / 4)
			side.mana[color] -= loss[color]
		lost.append(loss)
	events.append({type = "reshuffled", gems = b.gems.duplicate(), special = b.special.duplicate(), mana_lost = lost})


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
			var fogged := not s.sim_draw_budget.is_empty() and s.sim_draw_budget[x] >= 0
			if fogged and s.sim_draw_budget[x] == 0:
				b.gems[c] = Board.Gem.UNKNOWN  # AI search: past what the player can see
			else:
				if fogged:
					s.sim_draw_budget[x] -= 1
				b.gems[c] = s.streams.next_weighted(Streams.COL_0 + x, s.content.gem_weights)
			spawned_cells.append(c)
			spawned_gems.append(b.gems[c])
	if not moves.is_empty():
		events.append({type = "fell", moves = moves})
	if not spawned_cells.is_empty():
		events.append({type = "spawned", cells = spawned_cells, gems = spawned_gems})


## Pays count gems of one type to the active side (skull damage hits the other side).
static func _pay(s: BattleState, gem: int, count: int, events: Array[Dictionary]) -> void:
	var def: Dictionary = s.content.gem_defs[gem]
	var amount: int = int(def.amount) * count
	var side := s.active_side
	var me := s.sides[side]
	match def.reward:
		"mana":
			gain_mana(s, side, gem, amount, events)
		"damage":
			damage(s, 1 - side, amount, events)
		"ap":
			me.action_points += amount
			_changed(events, side, "ap", amount)
		"gold":
			me.gold_gained += amount
			_changed(events, side, "gold", amount)


## Sets off every BURST and SKULL_BOMB among the cleared cells, chaining into specials they hit.
## Blasted gems pay out. Adds blasted cells to hit. Returns false if the battle ended.
static func _blast(s: BattleState, cleared: PackedInt32Array, hit: Dictionary, events: Array[Dictionary]) -> bool:
	var b := s.board
	var queue: Array[int] = []
	for c in cleared:
		if b.special[c] != Board.Special.NONE:
			queue.append(c)
	while not queue.is_empty():
		var center: int = queue.pop_front()
		var bomb := b.special[center] == Board.Special.SKULL_BOMB
		var cells := PackedInt32Array()
		var counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
		var cx := center % Board.SIZE
		var cy := center / Board.SIZE
		for y in range(maxi(cy - 1, 0), mini(cy + 2, Board.SIZE)):
			for x in range(maxi(cx - 1, 0), mini(cx + 2, Board.SIZE)):
				var c := y * Board.SIZE + x
				if hit.has(c) or b.gems[c] == Board.Gem.EMPTY:
					continue
				hit[c] = true
				cells.append(c)
				if b.gems[c] <= Board.Gem.GOLD:
					counts[b.gems[c]] += 1
				if b.special[c] != Board.Special.NONE:
					queue.append(c)
		events.append({type = "cleared", cells = cells, cause = "bomb" if bomb else "burst"})
		for gem in counts.size():
			if counts[gem] > 0:
				_pay(s, gem, counts[gem], events)
				if s.result != BattleState.Result.ONGOING:
					return false
		if bomb:
			damage(s, 1 - s.active_side, s.content.skull_bomb_damage, events)
			if s.result != BattleState.Result.ONGOING:
				return false
	return true


## Puts a group's new special on its swapped cell if it has one, else its lowest, then leftmost cell.
static func _place_special(s: BattleState, g: Matcher.Group, swapped: PackedInt32Array, events: Array[Dictionary]) -> void:
	var cell := -1
	for c in swapped:
		if g.cells.has(c):
			cell = c
			break
	if cell < 0:
		cell = g.cells[0]
		for c in g.cells:
			if c / Board.SIZE > cell / Board.SIZE or (c / Board.SIZE == cell / Board.SIZE and c < cell):
				cell = c
	var b := s.board
	match g.creates:
		Matcher.Creates.WILD:
			b.gems[cell] = Board.Gem.WILD
		Matcher.Creates.BURST:
			b.gems[cell] = g.gem
			b.special[cell] = Board.Special.BURST
		Matcher.Creates.SKULL_BOMB:
			b.gems[cell] = Board.Gem.SKULL
			b.special[cell] = Board.Special.SKULL_BOMB
	events.append({type = "special_created", cell = cell, kind = g.creates, gem = b.gems[cell]})


## Ends the active side's turn: its cooldowns and statuses tick down, then the other side's
## turn starts with its on_turn_start statuses (which can end the battle).
static func _end_turn(s: BattleState, events: Array[Dictionary]) -> void:
	var me := s.sides[s.active_side]
	for i in me.cooldowns.size():
		me.cooldowns[i] = maxi(me.cooldowns[i] - 1, 0)
	for st in me.statuses.duplicate():
		st.turns -= 1
		if st.turns <= 0:
			me.statuses.erase(st)
			events.append({type = "status_expired", side = s.active_side, status = st.id})
	s.active_side = 1 - s.active_side
	s.turn += 1
	s.extra_turn_chain = 0
	events.append({type = "turn_passed", to_side = s.active_side})
	var next := s.sides[s.active_side]
	next.stunned_last_turn = _is_stunned(s, next)
	for st in next.statuses.duplicate():
		var hook: Array = s.content.statuses[st.id].get("on_turn_start", [])
		if not hook.is_empty():
			EffectRunner.run(s, hook, s.active_side, events)
			if s.result != BattleState.Result.ONGOING:
				return


static func _is_stunned(s: BattleState, side: SideState) -> bool:
	for st in side.statuses:
		if s.content.statuses[st.id].get("skips_turn", false):
			return true
	return false


static func _can_cast(s: BattleState, me: SideState, i: int) -> bool:
	if me.cooldowns[i] > 0:
		return false
	var cost: Dictionary = s.content.spells[me.spells[i]].cost
	for color in MANA_KINDS.size():
		if me.mana[color] < int(cost.get(MANA_KINDS[color], 0)):
			return false
	return true


static func _can_attack(s: BattleState, me: SideState) -> bool:
	return me.weapon != &"" and me.action_points >= int(s.content.weapons[me.weapon].ap_cost)


static func _changed(events: Array[Dictionary], side: int, kind: String, delta: int) -> void:
	if delta != 0:
		events.append({type = "resource_changed", side = side, kind = kind, delta = delta})


## Draws a full board with no matches and at least one legal swap, from the setup stream or,
## for a reshuffle that gave up, from each column's skyfall stream.
static func _fill_board(s: BattleState, from_columns: bool) -> void:
	var b := s.board
	var weights := s.content.gem_weights
	while true:
		for c in Board.CELLS:
			var stream := Streams.COL_0 + c % Board.SIZE if from_columns else Streams.SETUP
			var g := s.streams.next_weighted(stream, weights)
			# Redraw any gem that would complete a run with the two to its left or above.
			while (c % Board.SIZE >= 2 and b.gems[c - 1] == g and b.gems[c - 2] == g) \
					or (c >= 2 * Board.SIZE and b.gems[c - Board.SIZE] == g and b.gems[c - 2 * Board.SIZE] == g):
				g = s.streams.next_weighted(stream, weights)
			b.gems[c] = g
			b.special[c] = Board.Special.NONE
			b.locked[c] = 0
		if not _swaps(b, true).is_empty():
			return


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
