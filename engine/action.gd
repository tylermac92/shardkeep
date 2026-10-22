class_name Action
extends RefCounted
## One move by the active side. Only swaps exist so far; casts and attacks come with spells.

enum Kind { SWAP }

var kind: Kind
## Swapped cells, a < b.
var a := -1
var b := -1


static func swap(c1: int, c2: int) -> Action:
	var act := Action.new()
	act.kind = Kind.SWAP
	act.a = mini(c1, c2)
	act.b = maxi(c1, c2)
	return act
