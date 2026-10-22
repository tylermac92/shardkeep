class_name BoardView
extends Control
## The 8x8 board with the ghost row above it. Turns clicks and drags into swap requests, and
## moves pieces as EventPlayer replays events. It shows the board; the rules never read it.

signal swap_requested(a: int, b: int)

const CELL := 56.0
const SNAP_SECONDS := 0.12


## One gem on screen. pos is in cells, in board coordinates (x right, y down, row 0 on top).
class Piece:
	var gem: int
	var special: int
	var pos: Vector2
	var scale := 1.0

	func _init(g: int, sp: int, p: Vector2) -> void:
		gem = g
		special = sp
		pos = p


var input_enabled := false
var _pieces: Array = []  # Piece or null, per cell
var _dying: Array[Piece] = []  # cleared pieces shrinking away during a step
var _ghost := PackedByteArray()
var _selected := -1
var _pressed := -1


func _init() -> void:
	custom_minimum_size = Vector2(CELL * Board.SIZE, CELL * (Board.SIZE + 1))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pieces.resize(Board.CELLS)


func _process(_delta: float) -> void:
	queue_redraw()


## Shows a board as it is, with no animation.
func show_board(board: Board) -> void:
	show_gems(board.gems, board.special, null)


func show_ghost_row(gems: PackedByteArray) -> void:
	_ghost = gems


## The gem in each cell as shown (EMPTY where there's none).
func shown_gems() -> PackedByteArray:
	var out := PackedByteArray()
	for p in _pieces:
		out.append(p.gem if p else Board.Gem.EMPTY)
	return out


func shown_specials() -> PackedByteArray:
	var out := PackedByteArray()
	for p in _pieces:
		out.append(p.special if p else Board.Special.NONE)
	return out


## The cell under a local position, or -1.
func cell_at(local: Vector2) -> int:
	var x := floori(local.x / CELL)
	var y := floori(local.y / CELL) - 1
	if x < 0 or x >= Board.SIZE or y < 0 or y >= Board.SIZE:
		return -1
	return y * Board.SIZE + x


## A cell's center, in local coordinates.
func cell_center(c: int) -> Vector2:
	return (_cell_pos(c) + Vector2(0.5, 1.5)) * CELL


# --- Steps for EventPlayer. tw is the step's tween, or null to jump straight to the end. ---

func swap_pieces(a: int, b: int, tw: Tween) -> void:
	var p: Piece = _pieces[a]
	_pieces[a] = _pieces[b]
	_pieces[b] = p
	_move(_pieces[a], a, tw)
	_move(_pieces[b], b, tw)


func clear_cells(cells: PackedInt32Array, tw: Tween) -> void:
	for c in cells:
		var p: Piece = _pieces[c]
		_pieces[c] = null
		if p and tw:
			_dying.append(p)
			tw.tween_property(p, "scale", 0.0, tw.get_meta("seconds"))


## moves are Vector2i(from, to), in the order the engine made them.
func move_pieces(moves: Array, tw: Tween) -> void:
	for m: Vector2i in moves:
		var p: Piece = _pieces[m.x]
		_pieces[m.x] = null
		_pieces[m.y] = p
		_move(p, m.y, tw)


## New gems drop in from above the board, each column's in one stack.
func spawn(cells: PackedInt32Array, gems: PackedInt32Array, tw: Tween) -> void:
	var per_column := {}
	for c in cells:
		per_column[c % Board.SIZE] = per_column.get(c % Board.SIZE, 0) + 1
	for i in cells.size():
		var c := cells[i]
		var p := Piece.new(gems[i], Board.Special.NONE, _cell_pos(c) - Vector2(0, per_column[c % Board.SIZE]))
		_pieces[c] = p
		_move(p, c, tw)


## Puts a gem in a cell (a new special, or a converted gem), popping in.
func set_piece(c: int, gem: int, special: int, tw: Tween) -> void:
	var p := Piece.new(gem, special, _cell_pos(c))
	_pieces[c] = p
	if tw:
		p.scale = 0.3
		tw.tween_property(p, "scale", 1.0, tw.get_meta("seconds"))


func special_at(c: int) -> int:
	return _pieces[c].special if _pieces[c] else Board.Special.NONE


## Replaces every gem (a reshuffle), fading the new board in.
func show_gems(gems: PackedByteArray, special: PackedByteArray, tw: Tween) -> void:
	_selected = -1
	for c in Board.CELLS:
		_pieces[c] = null if gems[c] == Board.Gem.EMPTY else Piece.new(gems[c], special[c], _cell_pos(c))
		if _pieces[c] and tw:
			_pieces[c].scale = 0.0
			tw.tween_property(_pieces[c], "scale", 1.0, tw.get_meta("seconds"))


## Called after each animated step.
func end_step() -> void:
	_dying.clear()


## An illegal swap: the two gems trade places and slide back.
func snap_back(a: int, b: int) -> void:
	var pa: Piece = _pieces[a]
	var pb: Piece = _pieces[b]
	if not pa or not pb:
		return
	var tw := create_tween().set_parallel()
	tw.tween_property(pa, "pos", _cell_pos(b), SNAP_SECONDS)
	tw.tween_property(pb, "pos", _cell_pos(a), SNAP_SECONDS)
	tw.chain().tween_property(pa, "pos", _cell_pos(a), SNAP_SECONDS)
	tw.tween_property(pb, "pos", _cell_pos(b), SNAP_SECONDS)


func _move(p: Piece, c: int, tw: Tween) -> void:
	if not p:
		return
	if tw:
		tw.tween_property(p, "pos", _cell_pos(c), tw.get_meta("seconds"))
	else:
		p.pos = _cell_pos(c)


func _cell_pos(c: int) -> Vector2:
	return Vector2(c % Board.SIZE, c / Board.SIZE)


func _gui_input(event: InputEvent) -> void:
	if not input_enabled:
		_selected = -1
		_pressed = -1
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(button.position)
		if not button.pressed:
			_pressed = -1
		elif _selected >= 0 and c >= 0 and _adjacent(_selected, c):
			_request(_selected, c)  # second click of click-to-swap
		else:
			_selected = -1 if c == _selected else c
			_pressed = c
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _pressed >= 0 and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var c := cell_at(motion.position)
		if c >= 0 and c != _pressed and _adjacent(_pressed, c):
			_request(_pressed, c)  # drag-to-swap
		accept_event()


func _request(a: int, b: int) -> void:
	_selected = -1
	_pressed = -1
	swap_requested.emit(a, b)


func _adjacent(a: int, b: int) -> bool:
	var d := absi(a - b)
	return d == Board.SIZE or (d == 1 and a / Board.SIZE == b / Board.SIZE)


func _draw() -> void:
	for c in Board.CELLS:
		var light := (c % Board.SIZE + c / Board.SIZE) % 2 == 0
		draw_rect(Rect2(_cell_pos(c) * CELL + Vector2(0, CELL), Vector2(CELL, CELL)), Color(0.16, 0.16, 0.2) if light else Color(0.12, 0.12, 0.15))
	var r := CELL * 0.4
	for x in _ghost.size():
		GemStyle.draw_gem(self, _ghost[x], Board.Special.NONE, Vector2((x + 0.5) * CELL, 0.5 * CELL), r * 0.8, 0.45)
	draw_line(Vector2(0, CELL), Vector2(CELL * Board.SIZE, CELL), Color(1, 1, 1, 0.25), 1.0)
	for p in _dying:
		_draw_piece(p, r)
	for p in _pieces:
		if p:
			_draw_piece(p, r)
	if _selected >= 0:
		draw_rect(Rect2(_cell_pos(_selected) * CELL + Vector2(2, CELL + 2), Vector2(CELL - 4, CELL - 4)), Color.WHITE, false, 3.0)


func _draw_piece(p: Piece, r: float) -> void:
	var center := (p.pos + Vector2(0.5, 1.5)) * CELL
	if center.y < CELL * 0.5:
		return  # still above the ghost row
	GemStyle.draw_gem(self, p.gem, p.special, center, r * p.scale)
