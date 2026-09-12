class_name Sm2RegionMap
extends Control
signal location_selected(id: String)
var model: Dictionary={}
var selected: String=""
var art: Dictionary={}
var choices: Dictionary={}

func _ready() -> void:
	custom_minimum_size=Vector2(320,290)
	art=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/region_map.json"))
	for place: Dictionary in model.places:
		var button: Button=Sm2SurvivalWorkspace.button(art.symbols.get(place.id,place.name),"MapLocation_"+place.id,func() -> void: location_selected.emit(place.id))
		button.custom_minimum_size=Vector2(126,52); button.toggle_mode=true; button.button_pressed=place.id==selected
		button.tooltip_text=place.name+" · "+("Вы здесь" if place.here else "Посещено" if place.visited else "Не посещено")
		add_child(button); choices[place.id]=button
	resized.connect(_layout); _layout()

func point(id: String) -> Vector2:
	var p: Array=art.positions.get(id,[0.5,0.5])
	return Vector2(72,48)+Vector2(float(p[0]),float(p[1]))*Vector2(maxf(size.x-144,0),maxf(size.y-96,0))

func _layout() -> void:
	for id: String in choices:
		var button: Button=choices[id]; button.position=point(id)-Vector2(63,26); button.size=Vector2(126,52)
	queue_redraw()

func _draw() -> void:
	draw_style_box(Sm2BronzeTheme.paper(0),Rect2(Vector2.ZERO,size))
	# Decorative route paper, without gameplay terrain, fog or simulated geography.
	for y: int in range(24,int(size.y),32): draw_line(Vector2(12,y),Vector2(size.x-12,y),Color(0.27,0.20,0.12,0.09),1)
	var drawn: Dictionary={}
	for route: Dictionary in model.routes:
		var pair: Array=[str(route.from),str(route.to)]; pair.sort(); var key: String=":".join(pair)
		if drawn.has(key): continue
		drawn[key]=true
		var active: bool=model.location in pair and selected in pair and selected!=model.location
		draw_line(point(route.from),point(route.to),Color("654f2d") if active else Color("94856b"),4 if active else 2,true)
	for place: Dictionary in model.places:
		if place.here: draw_arc(point(place.id),39,0,TAU,48,Color("386576"),3,true)
	draw_string(Sm2BronzeTheme.SERIF,Vector2(18,27),"Малая карта",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Sm2BronzeTheme.INK)
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-18),"Выбор места не начинает переход",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Sm2BronzeTheme.INK)
