class_name AI
extends RefCounted
## Picks the active side's action by simulating with Rules.apply() under fog (technical_design.md,
## AI). Every simulated turn is one action plus greedy extra-turn continuations.

enum Level { EASY, NORMAL, HARD }

const DEFAULT_WEIGHTS := {"damage": 1.0, "hurt": 1.0, "mana": 0.5, "ap": 0.4, "extra_turn": 1.0, "status": 1.0}
const WIN := 1.0e9
const BEAM := 6
## Extra-turn continuations per simulated turn, so a long chain can't blow up the search.
const MAX_CONTINUATIONS := 3
## Mana past the most any equipped spell costs in that color is worth this fraction.
const SPARE_MANA := 0.25
## A turn skipped by stun is worth this many points to the side that skips it, negated.
const STUN_VALUE := 5.0
const EASY_NOISE_PERCENT := 25


## DEFAULT_WEIGHTS overridden by a content entry's "ai": {"weights": {...}}.
static func weights_for(def: Dictionary) -> Dictionary:
	var w := DEFAULT_WEIGHTS.duplicate()
	w.merge(def.get("ai", {}).get("weights", {}), true)
	return w


## The action the active side should take, or null if it has none. Never changes state.
## weights needs every DEFAULT_WEIGHTS key (see weights_for).
static func choose(state: BattleState, level: Level, weights := DEFAULT_WEIGHTS) -> Action:
	var actions := Rules.legal_actions(state)
	if actions.is_empty():
		return null
	var root := state.clone()
	# Fog: one more gem per column (the ghost row) for the whole search, then UNKNOWN.
	root.sim_draw_budget.resize(Board.SIZE)
	root.sim_draw_budget.fill(1)
	var me := root.active_side
	var keys := _keys(root, actions.size() + 1)
	var children: Array[BattleState] = []
	for a in actions:
		children.append(_play(root, a, weights))
	var values := PackedFloat64Array()
	for c in children:
		values.append(score(root, c, me, weights))
	var order := _ranked(values, keys, true)
	if level == Level.HARD:
		order = order.slice(0, BEAM)
	if level != Level.EASY:
		var plies := 1 if level == Level.NORMAL else 2
		for i in order:
			values[i] = _value(root, children[i], me, weights, plies, BEAM if level == Level.HARD else 0)
		order = _ranked(values, keys, true, order)
	var pick := order[0]
	var roll := keys[actions.size()]
	if level == Level.EASY and order.size() > 1 and values[pick] < WIN and roll % 100 < EASY_NOISE_PERCENT:
		pick = order[1 + (roll / 100) % mini(2, order.size() - 1)]
	return actions[pick]


## How much better after is than before for side me. A won battle is WIN, a lost one -WIN.
static func score(before: BattleState, after: BattleState, me: int, w: Dictionary) -> float:
	if after.result != BattleState.Result.ONGOING:
		return WIN if (after.result == BattleState.Result.SIDE0_WON) == (me == 0) else -WIN
	var opp := 1 - me
	var v: float = w.damage * (before.sides[opp].hp - after.sides[opp].hp) \
			- w.hurt * (before.sides[me].hp - after.sides[me].hp)
	v += _resources(after, me, w) - _resources(before, me, w)
	v -= _resources(after, opp, w) - _resources(before, opp, w)
	if after.active_side == me:
		v += w.extra_turn
	return v


## One full turn for the active side: the action, then the best immediate continuation while
## it keeps the turn.
static func _play(s: BattleState, action: Action, w: Dictionary) -> BattleState:
	var side := s.active_side
	var st := Rules.apply(s, action).state
	for i in MAX_CONTINUATIONS:
		if st.result != BattleState.Result.ONGOING or st.active_side != side:
			break
		var best: BattleState = null
		var best_v := -INF
		for a in Rules.legal_actions(st):
			var next := Rules.apply(st, a).state
			var v := score(st, next, side, w)
			if v > best_v:
				best_v = v
				best = next
		if best == null:
			break
		st = best
	return st


## Minimax over plies more turns from st, scored against root for side me. With a beam, only
## that many children (best for the side to move by immediate score) are searched further.
static func _value(root: BattleState, st: BattleState, me: int, w: Dictionary, plies: int, beam: int) -> float:
	if st.result != BattleState.Result.ONGOING:
		return score(root, st, me, w) * (1.0 + plies * 0.001)  # a sooner win (or a later loss) is better
	if plies == 0:
		return score(root, st, me, w)
	var actions := Rules.legal_actions(st)
	if actions.is_empty():
		return score(root, st, me, w)
	var mine := st.active_side == me
	var children: Array[BattleState] = []
	var values := PackedFloat64Array()
	for a in actions:
		var c := _play(st, a, w)
		children.append(c)
		values.append(score(root, c, me, w))
	var order := _ranked(values, PackedInt64Array(), mine)
	if beam > 0:
		order = order.slice(0, beam)
	if plies == 1:
		return values[order[0]]
	var best := -INF if mine else INF
	for i in order:
		var v := _value(root, children[i], me, w, plies - 1, beam)
		best = maxf(best, v) if mine else minf(best, v)
	return best


## Indexes (all, or just those in subset) best first: highest value if high_first, else lowest.
## Equal values go by key, then index.
static func _ranked(values: PackedFloat64Array, keys: PackedInt64Array, high_first: bool, subset := PackedInt32Array()) -> PackedInt32Array:
	var order: Array[int] = []
	if subset.is_empty():
		order.assign(range(values.size()))
	else:
		order.assign(subset)
	order.sort_custom(func(i: int, j: int) -> bool:
		if values[i] != values[j]:
			return values[i] > values[j] if high_first else values[i] < values[j]
		if not keys.is_empty() and keys[i] != keys[j]:
			return keys[i] < keys[j]
		return i < j)
	return PackedInt32Array(order)


## Tie-break keys and the noise roll from the side's AI stream. Search may not change the real
## state, so the stream counter never advances; each decision reads it at an offset from the
## turn and the board instead (not the skyfall counters, which would leak hidden gems).
static func _keys(s: BattleState, count: int) -> PackedInt64Array:
	var salt := s.turn
	for g in s.board.gems:
		salt = (salt * 31 + g) & Streams.MASK
	var out := PackedInt64Array()
	for i in count:
		out.append(Streams.mix(s.streams.battle_seed, Streams.AI_0 + s.active_side, (salt + i) & Streams.MASK))
	return out


## Mana (worth more up to what the side's spells cost), action points and statuses.
static func _resources(s: BattleState, side: int, w: Dictionary) -> float:
	var me := s.sides[side]
	var v := 0.0
	for color in Rules.MANA_KINDS.size():
		var need := 0
		for id in me.spells:
			need = maxi(need, int(s.content.spells[id].cost.get(Rules.MANA_KINDS[color], 0)))
		var useful := mini(me.mana[color], need)
		v += w.mana * (useful + SPARE_MANA * (me.mana[color] - useful))
	v += w.ap * me.action_points
	for st in me.statuses:
		var def: Dictionary = s.content.statuses[st.id]
		var sv := 0.0
		if def.get("absorbs_damage", false):
			sv += st.stacks
		if def.get("skips_turn", false):
			sv -= STUN_VALUE * st.turns
		for e: Dictionary in def.get("on_turn_start", []):
			if e.op == "damage" and e.get("target", "self") == "self":
				sv -= int(e.amount) * st.turns
		v += w.status * sv
	return v
