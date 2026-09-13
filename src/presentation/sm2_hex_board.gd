class_name Sm2HexBoard
extends Control
signal cell_clicked(cell: Vector2i, right: bool)
signal cell_hovered(cell: Vector2i)
var state: Dictionary = {}
var field: Sm2Battlefield = null
var reachable: Dictionary = {}
var targets: Dictionary = {}
var area_cells: Array[Vector2i] = []
var area_targets: Array[Vector2i] = []
var route: Array[Vector2i] = []
var hover: Vector2i = Vector2i(-1, -1)
var inspected: int = 0
var art: Sm2BattleArt = null
var panel_style: StyleBoxFlat = null
var motion: Sm2BattleMotion = Sm2BattleMotion.new()
var _radius: float = 26.0
var _offset: Vector2 = Vector2.ZERO
const GOLD: Color = Color("e3bf7b")
const BLUE: Color = Color("72c5d4")
const RED: Color = Color("dc8b77")

func _ready() -> void:
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void: hover = Vector2i(-1, -1); route.clear(); cell_hovered.emit(hover); queue_redraw())
	resized.connect(queue_redraw)

func update_view(data: Dictionary, available: Dictionary, attack_targets: Dictionary, inspect_id: int) -> void:
	if state.get("battle_id", data.battle_id) != data.battle_id or int(data.revision) < int(state.get("revision", 0)): clear_motion()
	state = data.duplicate(true)
	field = Sm2Battlefield.new()
	field.build(data.field)
	reachable = available.duplicate(true)
	targets = attack_targets.duplicate(true)
	inspected = inspect_id
	queue_redraw()

func enable_art() -> bool:
	var candidate: Sm2BattleArt = Sm2BattleArt.new()
	if not candidate.load_assets():
		push_warning("Battle art unavailable: " + candidate.error)
		return false
	art = candidate; queue_redraw(); return true

func play_events(events: Array[Dictionary]) -> void:
	if art == null: return
	motion.play(events, state.get("actors", []))
	set_process(not motion.cues.is_empty()); queue_redraw()

func clear_motion() -> void:
	motion.clear(); set_process(false); queue_redraw()

func _process(delta: float) -> void:
	motion.advance(delta); queue_redraw()
	if motion.cues.is_empty(): set_process(false)

func _layout() -> void:
	if field == null: return
	var width_units: float = sqrt(3.0) * (float(field.width()) + float(field.height() - 1) / 2.0)
	var height_units: float = 1.5 * float(field.height() - 1) + 2.0
	_radius = minf((size.x - 48.0) / width_units, (size.y - 62.0) / height_units)
	_offset = (size - Vector2(width_units, height_units) * _radius) / 2.0 + Vector2(sqrt(3.0) / 2.0, 1.0) * _radius

func center(cell: Vector2i) -> Vector2:
	_layout()
	var elevation: float = float(field.cell(cell).elevation) if field != null and field.in_bounds(cell) else 0.0
	return _offset + Vector2(sqrt(3.0) * (cell.x + cell.y / 2.0), 1.5 * cell.y) * _radius - Vector2(0, elevation * 5.0)

func polygon(cell: Vector2i, scale_value: float = 1.0) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var at: Vector2 = center(cell)
	for index: int in 6:
		points.append(at + Vector2.from_angle(deg_to_rad(60.0 * index - 90.0)) * _radius * scale_value)
	return points

func pick(point: Vector2) -> Vector2i:
	if field == null: return Vector2i(-1, -1)
	# Reverse paint order resolves shared edges and elevated overlap consistently.
	for r: int in range(field.height() - 1, -1, -1):
		for q: int in range(field.width() - 1, -1, -1):
			var cell: Vector2i = Vector2i(q, r)
			if Geometry2D.is_point_in_polygon(point, polygon(cell)): return cell
	return Vector2i(-1, -1)

func actor_at(cell: Vector2i) -> Dictionary:
	for actor: Dictionary in state.get("actors", []):
		if actor.alive and actor.on_field and Vector2i(int(actor.q), int(actor.r)) == cell: return actor
	return {}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next: Vector2i = pick(event.position)
		if next != hover:
			hover = next
			cell_hovered.emit(hover)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		cell_clicked.emit(pick(event.position), event.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()

func _draw() -> void:
	draw_style_box(_panel(), Rect2(Vector2.ZERO, size))
	if field == null: return
	_layout()
	for r: int in field.height():
		for q: int in field.width():
			var cell: Vector2i = Vector2i(q, r)
			var tile: Dictionary = field.cell(cell)
			var points: PackedVector2Array = polygon(cell, 0.97)
			var base: Color = Color("414c40") if (q + r) % 2 == 0 else Color("465143")
			if tile.surface_id.ends_with("rough"): base = Color("68604a")
			if int(tile.elevation) > 0: base = base.lightened(0.08 * int(tile.elevation))
			if not tile.passable: base = Color("303d39")
			var shadow: PackedVector2Array = []
			for point: Vector2 in points: shadow.append(point + Vector2(0, 5 + int(tile.elevation) * 4))
			draw_colored_polygon(shadow, Color("182522"))
			draw_colored_polygon(points, base)
			if art != null:
				var material: int = 1 if tile.surface_id.ends_with("rough") else 2 if q >= 3 and q <= 5 else 0
				if not tile.passable: material = 3
				art.tile(self, points, center(cell), _radius, material, Color("b2b2aa").lightened(0.06 * int(tile.elevation)))
			_outline(points, Color("66715b"), 1.0)
			if reachable.has(cell):
				draw_colored_polygon(points, Color(0.22, 0.65, 0.71, 0.16))
				_outline(points, Color(0.44, 0.76, 0.80, 0.5), 1.1)
			if targets.has(cell):
				_outline(polygon(cell, 0.9), RED, 2.5)
			if area_cells.has(cell):
				draw_colored_polygon(points,Color(0.75,0.48,0.95,0.22))
				_outline(polygon(cell,0.93),Color("c49fe3"),2.0)
			if area_targets.has(cell): _outline(polygon(cell,0.84),RED,3.0)
			var at: Vector2 = center(cell)
			if art != null:
				pass # Tall props are drawn with figures in depth order below.
			elif not tile.passable:
				_rock(at, _radius)
			elif tile.opaque:
				draw_colored_polygon(PackedVector2Array([at+Vector2(-13, 8), at+Vector2(0,-24), at+Vector2(14,8)]), Color("26372c"))
			elif tile.surface_id.ends_with("rough"):
				for index: int in 3: draw_line(at + Vector2(-11 + index * 8, 4), at + Vector2(-7 + index * 8, -3), Color("96805a"), 2)
			if int(tile.elevation) > 0: _text(at + Vector2(_radius * 0.4, _radius * 0.6), "+%s" % tile.elevation, 10, Color("c3c4a2"))
	if not route.is_empty():
		var previous: Vector2 = center(_active_cell())
		for cell: Vector2i in route:
			var at: Vector2 = center(cell)
			draw_line(previous, at, GOLD, 2, true)
			draw_circle(at, 3, GOLD)
			previous = at
	if art != null: _illustrated_scene()
	for actor: Dictionary in ([] if art != null else state.actors):
		if not actor.on_field: continue
		var cell: Vector2i = Vector2i(int(actor.q), int(actor.r))
		if not actor.alive:
			var at: Vector2 = center(cell)
			draw_line(at + Vector2(-9,-6), at+Vector2(9,6), Color("88675a"), 4, true)
			draw_line(at + Vector2(9,-6), at+Vector2(-9,6), Color("88675a"), 4, true)
			continue
		_pawn(actor, center(cell))
	if field.in_bounds(hover): _outline(polygon(hover), Color("efdfb7"), 2.0)
	_text(Vector2(17, 24), "ЗАРОСШИЕ РУИНЫ" if art != null else "СЕВЕРНЫЙ ТРАКТ", 12, Color("b9b494"))
	_text(Vector2(17, size.y - 15), "Синие — ваш отряд    •    Красные — противник", 12, Color("a4b1a7"))

func _illustrated_scene() -> void:
	# Background ornaments sit in the empty corners, outside every selectable hex.
	var backdrop_tint: Color = Color("737a69")
	art.stamp(self, "pillar", Vector2(size.x - _radius * 1.25, _radius * 2.1), _radius * 1.6, Vector2(0.5, 1), backdrop_tint)
	art.stamp(self, "rocks", Vector2(size.x - _radius * 2.35, _radius * 1.95), _radius * 0.75, Vector2(0.5, 1), backdrop_tint)
	art.stamp(self, "pillar", Vector2(_radius * 1.5, size.y - 50), _radius * 1.85, Vector2(0.5, 1), backdrop_tint)
	art.stamp(self, "grass", Vector2(_radius * 2.05, size.y - 43), _radius * 0.65, Vector2(0.5, 1), backdrop_tint)
	var entries: Array[Dictionary] = []
	for r: int in field.height():
		for q: int in field.width():
			var cell: Vector2i = Vector2i(q, r); var tile: Dictionary = field.cell(cell)
			if not tile.passable or tile.opaque:
				entries.append({"y": center(cell).y, "cell": cell, "prop": "pillar" if tile.opaque else "rocks"})
			elif (q * 13 + r * 7) % 9 == 0 and actor_at(cell).is_empty():
				art.stamp(self, "grass", center(cell) + Vector2(_radius * 0.32, _radius * 0.15), _radius * 0.48, Vector2(0.5, 1), Color("b4b6a0"))
	for actor: Dictionary in state.actors:
		if actor.on_field: entries.append({"y": displayed_center(actor).y, "actor": actor})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	for entry: Dictionary in entries:
		if entry.has("prop"):
			art.stamp(self, entry.prop, center(entry.cell) + Vector2(0, _radius * 0.45), _radius * (1.5 if entry.prop == "pillar" else 0.85))
		else: _illustrated_actor(entry.actor)
	if motion.cues.is_empty(): return
	var cue: Dictionary = motion.cues[0]
	var from: Vector2 = center(cue.from) - Vector2(0, _radius * 0.2)
	var to: Vector2 = center(cue.to) - Vector2(0, _radius * 0.2)
	var phase: float = motion.phase()
	var tint: Color = Color("a8e5ed") if cue.psi else GOLD
	if cue.kind == "moved": return
	if cue.kind == "barrier_cast":
		var glow: Color = tint; glow.a = 1.0 - phase
		draw_arc(from, _radius * (0.35 + phase * 0.70), 0, TAU, 48, glow, 3, true)
		return
	if cue.ranged:
		var tip: Vector2 = from.lerp(to, minf(1, phase * 2))
		draw_line(tip - (to - from).normalized() * _radius * 0.45, tip, tint, 3 if cue.psi else 2, true)
	if phase > 0.35:
		var fade: Color = tint if cue.hit else Color("e4ddc9")
		fade.a = (1.0 - phase) / 0.65
		if cue.hit: draw_arc(to, _radius * (0.18 + phase * 0.25), 0, TAU, 20, fade, 2, true)
		else: _text(to + Vector2(0, -_radius * phase), "Промах", 12, fade)

func displayed_center(actor: Dictionary) -> Vector2:
	var actual: Vector2i = Vector2i(int(actor.q), int(actor.r))
	if not actor.alive: return center(actual)
	var segment: Dictionary = motion.segment(int(actor.actor_id), actual)
	return center(segment.from).lerp(center(segment.to), float(segment.blend))

func _illustrated_actor(actor: Dictionary) -> void:
	var at: Vector2 = displayed_center(actor)
	var tint: Color = BLUE if actor.side == "company" else RED
	if not actor.alive:
		# A quiet fallen figure is a presentation symbol; wounds remain in the body screen.
		draw_set_transform(at + Vector2(0, _radius * 0.2), PI / 2, Vector2.ONE)
		art.stamp(self, "human", Vector2.ZERO, _radius * 1.1, Vector2(0.5, 0.5), Color("79766d"))
		draw_set_transform(Vector2.ZERO); return
	var foot: Vector2 = at + Vector2(0, _radius * 0.5)
	draw_set_transform(foot, 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, _radius * 0.52, Color(0.04, 0.04, 0.03, 0.65))
	draw_arc(Vector2.ZERO, _radius * 0.6, 0, TAU, 40, GOLD if int(actor.actor_id) == int(state.active_actor_id) else tint, 3, true)
	if int(actor.actor_id) == inspected and int(actor.actor_id) != int(state.active_actor_id): draw_arc(Vector2.ZERO, _radius * 0.7, 0, TAU, 40, Color("efdfb7"), 2, true)
	draw_set_transform(Vector2.ZERO)
	if not motion.cues.is_empty():
		var cue: Dictionary = motion.cues[0]
		foot += motion.offset(int(actor.actor_id), center(cue.from), center(cue.to), _radius)
	art.figure(self, actor, foot, _radius * 1.62)
	var barrier: Dictionary = actor.get("barrier", {})
	if int(barrier.get("remaining", 0)) > 0:
		var strength: float = float(barrier.remaining) / float(barrier.capacity)
		draw_set_transform(at - Vector2(0, _radius * 0.22), 0, Vector2(0.68, 1))
		draw_circle(Vector2.ZERO, _radius * 0.98, Color(0.38, 0.78, 0.91, 0.07))
		draw_arc(Vector2.ZERO, _radius * 0.98, 0, TAU, 48, Color(0.48, 0.84, 0.96, 0.7), 1.5, true)
		draw_arc(Vector2.ZERO, _radius * 1.03, -PI/2, -PI/2 + TAU * strength, 48, Color("95e3f4"), 2.5, true)
		draw_set_transform(Vector2.ZERO)
		_text(at + Vector2(_radius * 0.63, -_radius * 0.9), str(barrier.remaining), 13, Color("b4edf7"))
	if actor.combat.shieldwall_source != "0": draw_arc(at, _radius * 0.84, PI * 0.9, PI * 2.1, 24, Color("80c8ea"), 3, true)
	var width_value: float = _radius * 1.05
	draw_rect(Rect2(at + Vector2(-width_value / 2, _radius * 0.70), Vector2(width_value, 5)), Color("202523"))
	draw_rect(Rect2(at + Vector2(-width_value / 2, _radius * 0.70), Vector2(width_value * float(actor.combat.hp) / float(actor.hp_max), 5)), tint)
	_text(at + Vector2(-_radius * 0.73, -_radius * 0.65), str(actor.actor_id), 12, Color("f4e6c7"))
	if actor.morale != "steady": _text(at + Vector2(_radius * 0.55, -_radius * 0.5), "!!" if actor.morale == "fleeing" else "!", 15, GOLD)

func _pawn(actor: Dictionary, at: Vector2) -> void:
	var tint: Color = BLUE if actor.side == "company" else RED
	var scale_value: float = _radius / 29.0
	draw_ellipse_shadow(at, scale_value)
	if int(actor.actor_id) == int(state.active_actor_id): draw_arc(at+Vector2(0,9), _radius * 0.7, 0, TAU, 40, GOLD, 3, true)
	elif int(actor.actor_id) == inspected: draw_arc(at+Vector2(0,9), _radius * 0.65, 0, TAU, 40, tint, 2, true)
	var body: PackedVector2Array = PackedVector2Array([at+Vector2(-11,14)*scale_value, at+Vector2(-8,-7)*scale_value, at+Vector2(8,-7)*scale_value, at+Vector2(12,14)*scale_value])
	var tunic: Color = Color(actor.appearance.tunic_color) if actor.get("appearance",{}).has("tunic_color") else tint.darkened(0.3)
	draw_colored_polygon(body, tunic)
	_outline(body, tint, 1.2)
	draw_circle(at + Vector2(0,-12)*scale_value, 7.0*scale_value, Color("cab798"))
	if not Sm2BattleText.item(actor,"head").is_empty(): draw_arc(at+Vector2(0,-13)*scale_value, 7*scale_value, PI, TAU, 12, Color("c3c8bd"), 3*scale_value, true)
	var weapon: String = Sm2BattleText.item(actor, "weapon").get("definition_id","")
	if weapon.is_empty():
		draw_circle(at+Vector2(14,0)*scale_value,4*scale_value,Color("cab798"))
	elif weapon.ends_with("bow"):
		draw_arc(at + Vector2(13,-1)*scale_value, 13*scale_value, -PI/2, PI/2, 16, Color("c6a574"), 2, true)
		draw_line(at + Vector2(13,-14)*scale_value, at + Vector2(13,12)*scale_value, Color("d9ceaa"), 1)
	else:
		var length_value: float = 29 if weapon.ends_with("spear") else 18
		draw_line(at+Vector2(14,11)*scale_value, at+Vector2(14,-length_value)*scale_value, Color("d0c8ac"), 2.5, true)
		if weapon.ends_with("axe"): draw_rect(Rect2(at+Vector2(10,-21)*scale_value,Vector2(12,9)*scale_value),Color("c3c8bd"))
		else: draw_line(at+Vector2(10,-8)*scale_value,at+Vector2(18,-8)*scale_value,Color("c3c8bd"),2)
	var shield: Dictionary = Sm2BattleText.item(actor, "shield")
	if not shield.is_empty() and int(shield.current) > 0:
		draw_circle(at+Vector2(-12,3)*scale_value, 8*scale_value, Color("273735"))
		draw_arc(at+Vector2(-12,3)*scale_value,8*scale_value,0,TAU,20,tint,2,true)
		if actor.combat.shieldwall_source != "0": draw_arc(at, _radius*0.8, PI*0.9, PI*2.1, 24, Color("80c8ea"),3,true)
	var hp_width: float = _radius * 1.12
	draw_rect(Rect2(at+Vector2(-hp_width/2,22*scale_value),Vector2(hp_width,4)),Color("1a2425"))
	draw_rect(Rect2(at+Vector2(-hp_width/2,22*scale_value),Vector2(hp_width*float(actor.combat.hp)/float(actor.hp_max),4)),tint)
	_text(at+Vector2(-_radius*0.7,-_radius*0.65),str(actor.actor_id),12,Color("f4e6c7"))
	if actor.morale != "steady": _text(at+Vector2(18,-15), "!!" if actor.morale == "fleeing" else "!", 15, GOLD)

func draw_ellipse_shadow(at: Vector2, scale_value: float) -> void:
	draw_circle(at+Vector2(0,10)*scale_value, 16*scale_value, Color(0.04,0.08,0.08,0.55))

func _active_cell() -> Vector2i:
	for actor: Dictionary in state.actors:
		if actor.actor_id == state.active_actor_id: return Vector2i(int(actor.q),int(actor.r))
	return Vector2i.ZERO

func _rock(at: Vector2, radius: float) -> void:
	var points: PackedVector2Array = PackedVector2Array([at+Vector2(-0.6,0.3)*radius,at+Vector2(-0.45,-0.4)*radius,at+Vector2(0.1,-0.65)*radius,at+Vector2(0.6,-0.15)*radius,at+Vector2(0.4,0.5)*radius])
	draw_colored_polygon(points, Color("73796a"))
	draw_line(points[1],points[2],Color("a5a994"),2)
	draw_line(points[2],points[4],Color("535e55"),2)

func _outline(points: PackedVector2Array, tint: Color, width: float) -> void:
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed,tint,width,true)

func _text(at: Vector2, value: String, font_size: int, tint: Color) -> void:
	draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,tint)

func _panel() -> StyleBoxFlat:
	if panel_style != null: return panel_style
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("142321")
	box.border_color = Color("455347")
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	return box
