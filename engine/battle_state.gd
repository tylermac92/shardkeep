class_name BattleState
extends RefCounted
## Everything about a battle in progress. Cheap to clone: the AI clones it hundreds of times per decision.

enum Result { ONGOING, SIDE0_WON, SIDE1_WON }

var board := Board.new()
## [0] = player, [1] = enemy.
var sides: Array[SideState] = [SideState.new(), SideState.new()]
var active_side := 0
var turn := 0
## Spell-granted extra turns in the current chain (cap 2).
var extra_turn_chain := 0
## Battle seed plus values used per stream.
var streams := Streams.new()
var result := Result.ONGOING
## AI search only: skyfall draws left per column, counted from the search root. Past it a
## column spawns UNKNOWN. Empty (or -1 for a column) = unlimited, as in real play.
var sim_draw_budget := PackedInt32Array()
## Content definitions, shared by reference with every clone and never mutated.
var content: ContentLoader


func clone() -> BattleState:
	var c := BattleState.new()
	c.board = board.clone()
	c.sides = [sides[0].clone(), sides[1].clone()]
	c.active_side = active_side
	c.turn = turn
	c.extra_turn_chain = extra_turn_chain
	c.streams = streams.clone()
	c.result = result
	c.sim_draw_budget = sim_draw_budget.duplicate()
	c.content = content
	return c


## SHA-256 of a canonical byte serialization: fixed field order, packed arrays as raw bytes,
## a length before anything variable. Content isn't part of the state and isn't hashed.
func state_hash() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	for bytes in [board.gems, board.special, board.locked]:
		buf.put_data(bytes)
	for v in [active_side, turn, extra_turn_chain, result, streams.battle_seed]:
		buf.put_64(v)
	for ints: PackedInt32Array in [streams.draws, sim_draw_budget]:
		buf.put_32(ints.size())
		buf.put_data(ints.to_byte_array())
	for side in sides:
		side.serialize(buf)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf.data_array)
	return ctx.finish()
