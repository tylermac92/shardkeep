class_name Matcher
extends RefCounted
## Match detection (technical_design.md, Match rules): runs of 3+ in rows and columns,
## merged per gem type with union-find, each group classified by the match table.

## STRAIGHT_5 is a single run of 5 or more; CROSS is an L or T (row and column runs joined).
enum Shape { STRAIGHT_3, STRAIGHT_4, STRAIGHT_5, CROSS }
## What a group leaves behind. WILD replaces the gem; BURST and SKULL_BOMB are Board.Special.
enum Creates { NOTHING, WILD, BURST, SKULL_BOMB }

const _ROW := 1
const _COL := 2


class Group:
	var gem: int
	## Ascending cell indexes. A WILD shared by two colors appears in both groups.
	var cells := PackedInt32Array()
	var shape: int
	var extra_turn: bool
	var creates: int
	var _dirs := 0


## Every match on the board, ordered by gem type, then by first cell.
static func find_groups(board: Board) -> Array[Group]:
	var groups: Array[Group] = []
	for gem in range(Board.Gem.RED, Board.Gem.GOLD + 1):
		groups.append_array(_groups_for(board, gem))
	return groups


## True if the row or column through cell holds a run of 3+. On a board that had no
## matches before a swap, that is exactly "the swap creates a match".
static func has_match_through(board: Board, cell: int) -> bool:
	var x := cell % Board.SIZE
	var row := cell - x
	var none_i := PackedInt32Array()
	var none_b := PackedByteArray()
	for gem in range(Board.Gem.RED, Board.Gem.GOLD + 1):
		if _scan(board, gem, row, 1, 0, none_i, none_b) or _scan(board, gem, x, Board.SIZE, 0, none_i, none_b):
			return true
	return false


## One pass per gem type, so a WILD shared by a red and a blue run doesn't merge the two.
static func _groups_for(board: Board, gem: int) -> Array[Group]:
	var parent := PackedInt32Array()
	parent.resize(Board.CELLS)
	for i in Board.CELLS:
		parent[i] = i
	var dirs := PackedByteArray()  # _ROW / _COL bits for cells in a run
	dirs.resize(Board.CELLS)
	for line in Board.SIZE:
		_scan(board, gem, line * Board.SIZE, 1, _ROW, parent, dirs)
		_scan(board, gem, line, Board.SIZE, _COL, parent, dirs)

	var groups: Array[Group] = []
	var by_root := {}
	for c in Board.CELLS:
		if dirs[c] == 0:
			continue
		var root := _find(parent, c)
		if not by_root.has(root):
			var g := Group.new()
			g.gem = gem
			by_root[root] = g
			groups.append(g)
		var group: Group = by_root[root]
		group.cells.append(c)
		group._dirs |= dirs[c]
	for g in groups:
		_classify(g)
	return groups


## Finds runs of 3+ along one row or column and unions their cells (dir 0 only reports).
## A run needs one real gem of the type; WILD stands in for mana colors only.
static func _scan(board: Board, gem: int, start: int, step: int, dir: int, parent: PackedInt32Array, dirs: PackedByteArray) -> bool:
	var found := false
	var use_wild := gem <= Board.Gem.YELLOW
	var run_start := 0
	var length := 0
	var has_real := false
	for i in Board.SIZE + 1:
		if i < Board.SIZE:
			var c := start + i * step
			var g := board.gems[c]
			if g == gem or (use_wild and g == Board.Gem.WILD):
				if length == 0:
					run_start = c
					has_real = false
				length += 1
				has_real = has_real or g == gem
				continue
		if length >= 3 and has_real:
			found = true
			if dir == 0:
				return true
			for k in length:
				var cell := run_start + k * step
				dirs[cell] |= dir
				parent[_find(parent, cell)] = _find(parent, run_start)
		length = 0
	return found


static func _find(parent: PackedInt32Array, c: int) -> int:
	while parent[c] != c:
		c = parent[c]
	return c


static func _classify(g: Group) -> void:
	var n := g.cells.size()
	if g._dirs == _ROW | _COL:
		g.shape = Shape.CROSS
	elif n == 3:
		g.shape = Shape.STRAIGHT_3
	elif n == 4:
		g.shape = Shape.STRAIGHT_4
	else:
		g.shape = Shape.STRAIGHT_5
	g.extra_turn = n >= 4
	if g.gem == Board.Gem.SKULL and n >= 4:
		g.creates = Creates.SKULL_BOMB
	elif g.shape == Shape.CROSS:
		g.creates = Creates.BURST
	elif g.shape == Shape.STRAIGHT_5:
		g.creates = Creates.WILD
	else:
		g.creates = Creates.NOTHING
