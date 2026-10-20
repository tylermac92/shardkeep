class_name SideState
extends RefCounted
## One combatant's resources. Mana arrays are indexed RED, BLUE, GREEN, YELLOW.

var hp := 0
var hp_max := 0
var mana := PackedInt32Array([0, 0, 0, 0])
var mana_cap := PackedInt32Array([0, 0, 0, 0])
var action_points := 0
var gold_gained := 0
## Content ids, up to 6; cooldowns[i] belongs to spells[i].
var spells: Array[StringName] = []
var cooldowns := PackedInt32Array()
var weapon: StringName = &""


func clone() -> SideState:
	var c := SideState.new()
	c.hp = hp
	c.hp_max = hp_max
	c.mana = mana.duplicate()
	c.mana_cap = mana_cap.duplicate()
	c.action_points = action_points
	c.gold_gained = gold_gained
	c.spells = spells.duplicate()
	c.cooldowns = cooldowns.duplicate()
	c.weapon = weapon
	return c
