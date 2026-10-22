class_name SideState
extends RefCounted
## One combatant's resources. Mana arrays are indexed RED, BLUE, GREEN, YELLOW.

var hp := 0
var hp_max := 0
var mana := PackedInt32Array([0, 0, 0, 0])
var mana_cap := PackedInt32Array([0, 0, 0, 0])
var action_points := 0
var gold_gained := 0
## Content ids, up to 6; cooldowns[i] belongs to spells[i], so both have the same size.
var spells: Array[StringName] = []
var cooldowns := PackedInt32Array()
var weapon: StringName = &""
## Active statuses as {id, turns, stacks}. For barrier, stacks is the damage it can still absorb.
var statuses: Array[Dictionary] = []
## Whether this side's most recent turn was skipped by stun, which blocks the next stun.
var stunned_last_turn := false


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
	c.statuses = statuses.duplicate(true)
	c.stunned_last_turn = stunned_last_turn
	return c


## Writes every field in a fixed order, for BattleState.state_hash().
func serialize(buf: StreamPeerBuffer) -> void:
	for v in [hp, hp_max, action_points, gold_gained, int(stunned_last_turn)]:
		buf.put_64(v)
	for ints: PackedInt32Array in [mana, mana_cap, cooldowns]:
		buf.put_32(ints.size())
		buf.put_data(ints.to_byte_array())
	buf.put_32(spells.size())
	for id in spells:
		buf.put_utf8_string(id)
	buf.put_utf8_string(weapon)
	buf.put_32(statuses.size())
	for st in statuses:
		buf.put_utf8_string(str(st.id))
		buf.put_64(st.turns)
		buf.put_64(st.stacks)
