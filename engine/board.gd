class_name Board
extends RefCounted
## 8x8 board. Cell index = y * SIZE + x, with y = 0 the top row.

## Gem types. RED..GOLD follow ContentLoader.GEM_IDS, so gem_weights[gem] is that gem's weight.
enum Gem { RED, BLUE, GREEN, YELLOW, SKULL, ACTION, GOLD, WILD, UNKNOWN, EMPTY }
## BURST and SKULL_BOMB sit on top of a gem and keep its type.
enum Special { NONE, BURST, SKULL_BOMB }

const SIZE := 8
const CELLS := SIZE * SIZE
## Golden board text symbol per Gem, in enum order.
const SYMBOLS := "RBGYSA$W?."
## Golden board suffix per Special, in enum order: "R+" is a red BURST, "S*" a SKULL_BOMB.
const SPECIAL_SUFFIXES := ["", "+", "*"]

var gems := PackedByteArray()
var special := PackedByteArray()
## Turns each gem stays locked; 0 = free.
var locked := PackedByteArray()


func _init() -> void:
	gems.resize(CELLS)
	gems.fill(Gem.EMPTY)
	special.resize(CELLS)
	locked.resize(CELLS)


func clone() -> Board:
	var c := Board.new()
	c.gems = gems.duplicate()
	c.special = special.duplicate()
	c.locked = locked.duplicate()
	return c


## Parses the golden board format: 8 lines of 8 space-separated symbols from SYMBOLS,
## each optionally followed by a suffix from SPECIAL_SUFFIXES.
## Blank lines and surrounding whitespace are ignored. Returns null on bad input.
static func from_text(text: String) -> Board:
	var rows := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().is_empty():
			rows.append(line)
	if rows.size() != SIZE:
		push_error("golden board: expected %d rows, got %d" % [SIZE, rows.size()])
		return null
	var b := Board.new()
	for y in SIZE:
		var symbols := rows[y].strip_edges().split(" ", false)
		if symbols.size() != SIZE:
			push_error("golden board row %d: expected %d symbols, got %d" % [y, SIZE, symbols.size()])
			return null
		for x in SIZE:
			var token := symbols[x]
			var gem := SYMBOLS.find(token.left(1))
			var sp := SPECIAL_SUFFIXES.find(token.substr(1))
			if gem < 0 or sp < 0 or token.length() > 2:
				push_error("golden board row %d: unknown symbol \"%s\"" % [y, token])
				return null
			b.gems[y * SIZE + x] = gem
			b.special[y * SIZE + x] = sp
	return b


func to_text() -> String:
	var rows := PackedStringArray()
	for y in SIZE:
		var row := PackedStringArray()
		for x in SIZE:
			row.append(SYMBOLS[gems[y * SIZE + x]] + SPECIAL_SUFFIXES[special[y * SIZE + x]])
		rows.append(" ".join(row))
	return "\n".join(rows)
