class_name EventPlayer
extends Node
## Replays engine events on the battle screen, in order (technical_design.md, Client). The
## state is already final when playback starts, so speed only changes what's on screen.

signal message(text: String)

enum Speed { NORMAL, DOUBLE, INSTANT }

## Seconds per animated event at 1x. Events not listed apply at once.
const SECONDS := {"swapped": 0.18, "cleared": 0.22, "fell": 0.28, "spawned": 0.28, "special_created": 0.15, "converted": 0.25, "reshuffled": 0.4}
const SPECIAL_OF := [Board.Special.NONE, Board.Special.NONE, Board.Special.BURST, Board.Special.SKULL_BOMB]  # by Matcher.Creates

var board: BoardView
var panels: Array[SidePanel] = []
var content: ContentLoader
var speed := Speed.NORMAL


## Plays events; returns (when awaited) once the last animation has finished.
func play(events: Array[Dictionary]) -> void:
	var i := 0
	while i < events.size():
		var e := events[i]
		var tw := _step(e.type)
		match e.type:
			"swapped":
				board.swap_pieces(e.a, e.b, tw)
			"cleared":
				board.clear_cells(e.cells, tw)
			"fell":
				board.move_pieces(e.moves, tw)
				if i + 1 < events.size() and events[i + 1].type == "spawned":
					i += 1  # new gems drop in alongside the fall
					board.spawn(events[i].cells, events[i].gems, tw)
			"spawned":
				board.spawn(e.cells, e.gems, tw)
			"special_created":
				board.set_piece(e.cell, e.gem, SPECIAL_OF[e.kind], tw)
			"converted":
				for c in e.cells:
					board.set_piece(c, e.gem, board.special_at(c), tw)
			"reshuffled":
				board.show_gems(e.gems, e.special, tw)
				for side in e.mana_lost.size():
					for color in Rules.MANA_KINDS.size():
						panels[side].apply_delta(Rules.MANA_KINDS[color], -e.mana_lost[side][color])
				message.emit("No moves left: the board reshuffles")
			"resource_changed":
				panels[e.side].apply_delta(e.kind, e.delta)
			"spell_cast":
				var def: Dictionary = content.spells.get(e.spell, content.weapons.get(e.spell, {}))
				message.emit("%s %s %s" % [_who(e.side), "attacked with" if content.weapons.has(e.spell) else "cast", def.get("name", e.spell)])
			"extra_turn":
				message.emit("Extra turn for %s" % _who(e.side).to_lower())
			"status_applied":
				message.emit("%s on %s for %d turns" % [content.statuses[e.status].name, _who(e.side).to_lower(), e.turns])
			"status_blocked":
				message.emit("%s can't be stunned twice in a row" % _who(e.side))
		if tw:
			await tw.finished
			board.end_step()
		i += 1


## A tween for one animated event, or null to apply it at once.
func _step(type: String) -> Tween:
	if speed == Speed.INSTANT or not SECONDS.has(type):
		return null
	var seconds: float = SECONDS[type] / (2.0 if speed == Speed.DOUBLE else 1.0)
	var tw := create_tween().set_parallel()
	tw.set_meta("seconds", seconds)
	tw.tween_interval(seconds)  # every step lasts its full time, even with nothing to move
	return tw


func _who(side: int) -> String:
	return "You" if side == 0 else "The enemy"
