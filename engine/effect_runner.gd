class_name EffectRunner
extends RefCounted
## Runs effect ops for spells, weapons and statuses (technical_design.md, Effects, spells and
## status). "self" in an effect is its owner: the caster, or the side holding the status.

const OPS := ["damage", "damage_per_gem", "gain_mana", "convert_gems", "apply_status", "extra_turn"]
const MAX_SPELL_EXTRA_TURNS := 2


## Runs effects in order and stops if the battle ends. Returns whether an extra_turn op granted one.
## Board changes aren't settled here; the caller runs the cascade afterwards. damage_bonus is
## added to each damage op aimed at the enemy (Might, for weapon swings).
static func run(s: BattleState, effects: Array, owner: int, events: Array[Dictionary], damage_bonus := 0) -> bool:
	var extra := false
	for e: Dictionary in effects:
		var target := owner if e.get("target", "self") == "self" else 1 - owner
		match e.op:
			"damage":
				Rules.damage(s, target, int(e.amount) + (damage_bonus if target != owner else 0), events)
			"damage_per_gem":
				var n := s.board.gems.count(ContentLoader.GEM_IDS.find(e.gem))
				Rules.damage(s, target, n * int(e.per), events)
			"gain_mana":
				Rules.gain_mana(s, target, Rules.MANA_KINDS.find(e.color), int(e.amount), events)
			"convert_gems":
				_convert(s, ContentLoader.GEM_IDS.find(e.from), ContentLoader.GEM_IDS.find(e.to), e.count, events)
			"apply_status":
				apply_status(s, target, e.status, int(e.turns), int(e.get("stacks", 1)), events, target != owner)
			"extra_turn":
				if s.extra_turn_chain < MAX_SPELL_EXTRA_TURNS:
					s.extra_turn_chain += 1
					extra = true
			_:
				push_error("unknown effect op \"%s\"" % e.op)
		if s.result != BattleState.Result.ONGOING:
			break
	return extra


## Adds a status, or refreshes it (longest duration, stacks add up). Stun is blocked on a side
## that was stunned on its previous turn. A resistible status from the enemy (from_enemy) can
## be resisted with Cunning.
static func apply_status(s: BattleState, target: int, id: String, turns: int, stacks: int, events: Array[Dictionary], from_enemy := false) -> void:
	var side := s.sides[target]
	var def: Dictionary = s.content.statuses[id]
	if def.get("skips_turn", false) and side.stunned_last_turn:
		events.append({type = "status_blocked", side = target, status = id})
		return
	if from_enemy and def.get("resistible", false) \
			and Rules.roll(s, side.stats[SideState.Stat.CUNNING] * int(s.content.stat_rules.get("cunning_resist_percent", 0))):
		events.append({type = "status_resisted", side = target, status = id})
		return
	for st in side.statuses:
		if st.id == id:
			st.turns = maxi(st.turns, turns)
			st.stacks += stacks
			events.append({type = "status_applied", side = target, status = id, turns = st.turns, stacks = st.stacks})
			return
	side.statuses.append({id = id, turns = turns, stacks = stacks})
	events.append({type = "status_applied", side = target, status = id, turns = turns, stacks = stacks})


## Turns gems of one type into another. A numeric count picks that many with the effects stream.
static func _convert(s: BattleState, from: int, to: int, count: Variant, events: Array[Dictionary]) -> void:
	var cells := PackedInt32Array()
	for c in Board.CELLS:
		if s.board.gems[c] == from:
			cells.append(c)
	if count is not String and int(count) < cells.size():
		var n := int(count)
		for i in n:  # partial Fisher-Yates: the first n cells become a random pick
			var j := i + s.streams.next_int(Streams.EFFECTS) % (cells.size() - i)
			var t := cells[i]
			cells[i] = cells[j]
			cells[j] = t
		cells = cells.slice(0, n)
		cells.sort()
	for c in cells:
		s.board.gems[c] = to
	if not cells.is_empty():
		events.append({type = "converted", cells = cells, gem = to})
