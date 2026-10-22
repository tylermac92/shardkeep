class_name GemStyle
extends RefCounted
## Placeholder gem art. Every type has its own shape, a color of distinct brightness and its
## golden-board letter, so the board reads in grayscale and for color-blind players.

enum Shape { TRIANGLE, CIRCLE, SQUARE, DIAMOND, CROSS, STAR, HEXAGON, RING, QUESTION }

## Indexed by Board.Gem, RED through UNKNOWN.
const SHAPES := [Shape.TRIANGLE, Shape.CIRCLE, Shape.SQUARE, Shape.DIAMOND, Shape.CROSS, Shape.STAR, Shape.HEXAGON, Shape.RING, Shape.QUESTION]
const COLORS := [
	Color8(200, 40, 40), Color8(60, 130, 235), Color8(60, 185, 70), Color8(250, 225, 70),
	Color8(245, 245, 245), Color8(90, 30, 150), Color8(235, 160, 40), Color8(255, 255, 255), Color8(120, 120, 120),
]
const OUTLINE := Color(0.05, 0.05, 0.08)


## Rec. 601 luma: how bright the color looks in grayscale.
static func luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Draws one gem centered at center with radius r. alpha fades it (the ghost row uses this).
static func draw_gem(canvas: CanvasItem, gem: int, special: int, center: Vector2, r: float, alpha := 1.0) -> void:
	if gem > Board.Gem.UNKNOWN or r <= 0.5:
		return
	var color: Color = COLORS[gem]
	color.a = alpha
	var outline := Color(OUTLINE, alpha)
	match SHAPES[gem]:
		Shape.TRIANGLE:
			_polygon(canvas, _regular(center, r * 1.1, 3, -PI / 2, Vector2(0, r * 0.15)), color, outline)
		Shape.CIRCLE:
			canvas.draw_circle(center, r * 0.9, color)
			canvas.draw_arc(center, r * 0.9, 0, TAU, 32, outline, 2.0)
		Shape.SQUARE:
			_polygon(canvas, _regular(center, r * 1.1, 4, PI / 4), color, outline)
		Shape.DIAMOND:
			_polygon(canvas, PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.7, 0), center + Vector2(0, r), center + Vector2(-r * 0.7, 0)]), color, outline)
		Shape.CROSS:
			var pts := PackedVector2Array()
			for k in 4:  # an X: four arms, each a pair of points along a diagonal
				var a := PI / 4 + k * PI / 2
				pts.append(center + Vector2.from_angle(a - 0.32) * r)
				pts.append(center + Vector2.from_angle(a + 0.32) * r)
				pts.append(center + Vector2.from_angle(a + PI / 4) * r * 0.32)
			_polygon(canvas, pts, color, outline)
		Shape.STAR:
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(center + Vector2.from_angle(-PI / 2 + k * PI / 5) * (r if k % 2 == 0 else r * 0.45))
			_polygon(canvas, pts, color, outline)
		Shape.HEXAGON:
			_polygon(canvas, _regular(center, r * 0.95, 6, 0), color, outline)
		Shape.RING:
			canvas.draw_arc(center, r * 0.7, 0, TAU, 32, outline, r * 0.5)
			canvas.draw_arc(center, r * 0.7, 0, TAU, 32, color, r * 0.32)
		Shape.QUESTION:
			canvas.draw_circle(center, r * 0.8, color)
	var letter := Board.SYMBOLS[gem]
	var font := ThemeDB.fallback_font
	var size := int(r * 0.8)
	if size < 6:
		return  # shrinking away; too small to read
	var text_color := Color(Color.BLACK if luma(COLORS[gem]) > 0.5 else Color.WHITE, alpha)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	canvas.draw_string(font, center + Vector2(-text_size.x / 2, size * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, text_color)
	match special:
		Board.Special.BURST:
			canvas.draw_arc(center, r * 1.12, 0, TAU, 32, Color(1, 1, 1, alpha), 3.0)
		Board.Special.SKULL_BOMB:
			canvas.draw_arc(center, r * 1.12, 0, TAU, 32, Color(1, 0.15, 0.1, alpha), 4.0)
			canvas.draw_arc(center, r * 1.12, 0, TAU, 8, Color(OUTLINE, alpha), 1.5)


static func _regular(center: Vector2, r: float, n: int, rotation: float, offset := Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		pts.append(center + offset + Vector2.from_angle(rotation + k * TAU / n) * r)
	return pts


static func _polygon(canvas: CanvasItem, pts: PackedVector2Array, color: Color, outline: Color) -> void:
	canvas.draw_colored_polygon(pts, color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, outline, 2.0)
