class_name Sm2BronzeTheme
extends RefCounted
## Shared presentation materials. No simulation state or gameplay identifiers.
const BACKGROUND: Color=Color("0d0b08")
const PANEL: Color=Color("1b1610")
const BUTTON: Color=Color("282017")
const BORDER: Color=Color("715932")
const DIM_BORDER: Color=Color("493c29")
const GOLD: Color=Color("d5b56c")
const TEXT: Color=Color("e4d9c3")
const MUTED: Color=Color("b9aa8e")
const PSI: Color=Color("8ac6db")
const INK: Color=Color("332719")
const SERIF: Font=preload("res://assets/fonts/pt_serif/PT_Serif-Web-Regular.ttf")
const SERIF_BOLD: Font=preload("res://assets/fonts/pt_serif/PT_Serif-Web-Bold.ttf")
const PARCHMENT: Texture2D=preload("res://assets/ui_bronze/parchment.png")

static func box(fill: Color=PANEL,border: Color=BORDER,padding: int=6) -> StyleBoxFlat:
	var value: StyleBoxFlat=StyleBoxFlat.new(); value.bg_color=fill; value.border_color=border
	value.set_border_width_all(1); value.set_corner_radius_all(1)
	value.content_margin_left=padding; value.content_margin_right=padding
	value.content_margin_top=padding; value.content_margin_bottom=padding
	return value

static func paper(padding: int=12) -> StyleBoxTexture:
	var value: StyleBoxTexture=StyleBoxTexture.new(); value.texture=PARCHMENT
	for side: int in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		value.set_texture_margin(side,32); value.set_content_margin(side,padding)
	return value

static func create() -> Theme:
	var value: Theme=Theme.new()
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style: StyleBoxFlat=box(BUTTON)
		match state:
			"hover": style=box(Color("3a2e1d"),GOLD)
			"pressed": style=box(Color("44331c"),GOLD)
			"disabled": style=box(Color("17140f"),DIM_BORDER)
			"focus":
				style=box(Color.TRANSPARENT,GOLD); style.draw_center=false; style.set_border_width_all(2)
		value.set_stylebox(state,"Button",style)
	for type: String in ["Button","TabContainer","TabBar","Label"]:
		value.set_color("font_color",type,TEXT)
		value.set_color("font_hover_color",type,Color("f2dfb3"))
		value.set_color("font_pressed_color",type,Color("f2dfb3"))
		value.set_color("font_disabled_color",type,Color("a49883"))
	value.set_stylebox("panel","TabContainer",box(PANEL))
	for type: String in ["TabContainer","TabBar"]:
		value.set_stylebox("tab_selected",type,box(Color("372b1b"),GOLD,8))
		value.set_stylebox("tab_unselected",type,box(PANEL,DIM_BORDER,8))
		value.set_stylebox("tab_hovered",type,box(BUTTON,BORDER,8))
		value.set_color("font_selected_color",type,GOLD)
		value.set_color("font_unselected_color",type,MUTED)
		value.set_font_size("font_size",type,13)
	for type: String in ["VScrollBar","HScrollBar"]:
		value.set_stylebox("scroll",type,box(Color("100e0a"),DIM_BORDER,3))
		value.set_stylebox("grabber",type,box(Color("705b38"),BORDER,3))
		value.set_stylebox("grabber_highlight",type,box(Color("9d8050"),GOLD,3))
		value.set_stylebox("grabber_pressed",type,box(GOLD,BORDER,3))
	value.set_stylebox("panel","TooltipPanel",paper())
	value.set_font("font","TooltipLabel",SERIF)
	value.set_font_size("font_size","TooltipLabel",15)
	value.set_color("font_color","TooltipLabel",INK)
	return value

static func corners(parent: Control) -> void:
	# Draw in the parent's coordinates: Container children would be inset over text.
	var draw_frame: Callable=draw_corners.bind(parent)
	if not parent.draw.is_connected(draw_frame): parent.draw.connect(draw_frame)
	if not parent.resized.is_connected(parent.queue_redraw): parent.resized.connect(parent.queue_redraw)

static func draw_corners(parent: Control) -> void:
	for entry: Vector2 in [Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)]:
		var origin: Vector2=Vector2(1 if entry.x>0 else parent.size.x-1,1 if entry.y>0 else parent.size.y-1)
		var points: PackedVector2Array=PackedVector2Array([origin,origin+Vector2(8*entry.x,0),origin+Vector2(0,8*entry.y)])
		parent.draw_colored_polygon(points,Color("2d2418"))
		points.append(origin); parent.draw_polyline(points,BORDER,1,true)
