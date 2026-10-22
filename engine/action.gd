class_name Action
extends RefCounted
## One move by the active side.

## PASS is only legal for a stunned side, and is its only legal action.
enum Kind { SWAP, CAST, ATTACK, PASS }

var kind: Kind
## Swapped cells, a < b.
var a := -1
var b := -1
## Spell id for CAST.
var spell: StringName = &""


static func swap(c1: int, c2: int) -> Action:
	var act := Action.new()
	act.kind = Kind.SWAP
	act.a = mini(c1, c2)
	act.b = maxi(c1, c2)
	return act


static func cast(spell_id: StringName) -> Action:
	var act := Action.new()
	act.kind = Kind.CAST
	act.spell = spell_id
	return act


static func attack() -> Action:
	var act := Action.new()
	act.kind = Kind.ATTACK
	return act


static func pass_turn() -> Action:
	var act := Action.new()
	act.kind = Kind.PASS
	return act
