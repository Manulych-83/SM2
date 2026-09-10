extends Control
## Decorative lines only; the presentation owns no game state.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10191e"))
	var horizon: float = size.y * 0.56
	var ridge: PackedVector2Array = PackedVector2Array([
		Vector2(0, size.y), Vector2(0, horizon + 90),
		Vector2(size.x * 0.12, horizon + 35), Vector2(size.x * 0.24, horizon + 100),
		Vector2(size.x * 0.39, horizon - 15), Vector2(size.x * 0.53, horizon + 80),
		Vector2(size.x * 0.69, horizon - 70), Vector2(size.x * 0.86, horizon + 5),
		Vector2(size.x, horizon - 35), Vector2(size.x, size.y)])
	draw_colored_polygon(ridge, Color("17232a"))
	for index: int in range(9):
		var y: float = horizon + float(index) * 35.0
		draw_line(Vector2(size.x * 0.44, y), Vector2(size.x, y - 130), Color(0.48, 0.59, 0.58, 0.035), 1.0)
	draw_circle(Vector2(size.x * 0.78, size.y * 0.25), 86, Color(0.76, 0.68, 0.46, 0.025))
	draw_arc(Vector2(size.x * 0.78, size.y * 0.25), 85, 0, TAU, 80, Color(0.76, 0.68, 0.46, 0.12), 1.0, true)
