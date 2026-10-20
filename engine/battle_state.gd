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


func clone() -> BattleState:
	var c := BattleState.new()
	c.board = board.clone()
	c.sides = [sides[0].clone(), sides[1].clone()]
	c.active_side = active_side
	c.turn = turn
	c.extra_turn_chain = extra_turn_chain
	c.streams = streams.clone()
	c.result = result
	return c
