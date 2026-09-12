extends "res://tests/display_ui.gd"
const B=preload("res://src/presentation/sm2_bronze_theme.gd")
const FIGURE=preload("res://outputs/inventory-layout-1/figure.gd")
var canvas: Control
var art: Sm2BattleArt=Sm2BattleArt.new()
var view: Dictionary
var session: Sm2JourneySession
var evidence: Dictionary={}

func _run() -> void:
	OS.add_logger(captured); output="res://outputs/inventory-layout-1"
	session=Sm2JourneySession.new(Sm2SurvivalContentLoader.load_scenario(true,true),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://inventory-mockup"))
	t.expect(session.new_game().ok,"fresh local inventory session")
	t.expect(art.load_assets(),"current game artwork loaded")
	view=Sm2SurvivalWorkspaceView.build(session)
	var before: String=session.state_hash()
	for anatomy: bool in [false,true]:
		canvas=Control.new(); canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); canvas.theme=B.create(); root.add_child(canvas)
		build(anatomy)
		await _frames(); await RenderingServer.frame_post_draw
		for node: Node in canvas.find_children("*","Control",true,false):
			if node is Label: t.expect(canvas.get_global_rect().encloses((node as Control).get_global_rect()),"label fits QHD canvas: "+(node as Label).text)
		var picture: Image=root.get_texture().get_image()
		t.equal(picture.get_size(),Vector2i(2560,1440),"native QHD")
		t.equal(picture.save_png(output.path_join("02-body-2560.png" if anatomy else "01-inventory-2560.png")),OK,"write preview")
		canvas.queue_free(); await _frames()
	t.equal(session.state_hash(),before,"both mockups preserve session")
	evidence["view"]=view; evidence["read_only"]=session.state_hash()==before
	var file: FileAccess=FileAccess.open(output.path_join("evidence.json"),FileAccess.WRITE); file.store_string(JSON.stringify(evidence,"\t")); file.close()
	_finish()

func build(anatomy: bool) -> void:
	var background: ColorRect=ColorRect.new(); background.color=Color("111310"); place(canvas,background,Rect2(0,0,1600,900))
	var nav: Control=panel(canvas,Rect2(128,16,1454,62))
	for i: int in 3:
		var title: String=["Инвентарь","Тело","Развитие"][i]
		var chosen: bool=i==(1 if anatomy else 0)
		var tab: Control=panel(nav,Rect2(10+i*160,8,154,46),B.PSI if chosen else B.DIM_BORDER)
		text(tab,title,Rect2(4,5,146,34),19,B.TEXT if chosen else B.MUTED,true,HORIZONTAL_ALIGNMENT_CENTER)
	text(nav,"%s  ·  Вне боя" % view.location,Rect2(872,12,260,30),16,B.MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)
	text(nav,"Переносимая масса  %.2f кг" % (view.body.mass/1000.0),Rect2(1150,12,286,30),15,B.GOLD,false,HORIZONTAL_ALIGNMENT_RIGHT)
	text(canvas,"ОТРЯД",Rect2(16,108,94,24),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	for i: int in 2:
		var person: Control=panel(canvas,Rect2(16,143+i*158,94,146),B.PSI if i==0 else B.BORDER)
		texture(person,art.sprites.head_hair,Rect2(16,12,62,77))
		text(person,["Герой","Спутник"][i],Rect2(3,94,88,23),13,B.GOLD,false,HORIZONTAL_ALIGNMENT_CENTER)
		text(person,"Без ран",Rect2(3,121,88,18),11,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	var nearby: Control=panel(canvas,Rect2(16,529,94,54))
	text(nearby,"Тела рядом\n1",Rect2(4,4,86,46),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	build_summary()
	build_figure(anatomy)
	if anatomy: build_anatomy()
	else: build_inventory()
	text(canvas,"Esc  Вернуться в лагерь",Rect2(20,864,350,22),14,B.MUTED)
	text(canvas,"МАКЕТ · 2560 × 1440",Rect2(1250,864,330,22),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)

func build_summary() -> void:
	var column: Control=panel(canvas,Rect2(128,100,242,744))
	text(column,"Герой",Rect2(20,17,202,37),29,B.GOLD,true)
	text(column,"Человек · в лагере",Rect2(20,58,202,26),14,B.MUTED)
	line(column,Rect2(20,102,202,1))
	text(column,"СОСТОЯНИЕ ТЕЛА",Rect2(20,124,202,23),12,B.GOLD)
	text(column,"Кровь",Rect2(20,160,202,21),14)
	text(column,"%s / %s мл" % [view.body.blood,view.body.blood_max],Rect2(20,189,202,26),21,B.TEXT,true)
	meter(column,Rect2(20,230,202,5),float(view.body.blood)/view.body.blood_max,Color("a37760"))
	text(column,"Кровотечение",Rect2(20,261,202,23),14,B.MUTED)
	text(column,"%s мл/мин" % view.body.bleeding,Rect2(20,289,202,25),18,Color("9bb58a"))
	text(column,"Функции сохранены",Rect2(20,332,202,25),15,Color("9bb58a"))
	line(column,Rect2(20,383,202,1))
	text(column,"СНАРЯЖЕНИЕ И ГРУЗ",Rect2(20,407,202,23),12,B.GOLD)
	text(column,"%.2f кг" % (view.body.mass/1000.0),Rect2(20,444,202,36),28,B.TEXT,true)
	text(column,"Включая надетые вещи\nи содержимое контейнеров",Rect2(20,490,202,47),13,B.MUTED)
	line(column,Rect2(20,568,202,1))
	text(column,"Карманы · Пояс · Рюкзак",Rect2(20,588,202,22),13,B.GOLD)
	text(column,"У каждого контейнера\nсвои пределы объёма,\nмассы и размера вещи.",Rect2(20,624,202,69),13,B.MUTED)

func build_figure(anatomy: bool) -> void:
	var center: Control=panel(canvas,Rect2(386,100,426,744),B.DIM_BORDER)
	text(center,"ТЕЛО" if anatomy else "НАДЕТО",Rect2(15,15,396,27),13,B.GOLD,false,HORIZONTAL_ALIGNMENT_CENTER)
	var actor: Dictionary={"side":"company","combat":{"items":[]},"body_functions":{"parts":[]}}
	if not anatomy:
		for item: Dictionary in view.items:
			if item.owner==2 and item.place=="equipped":
				var raw: Dictionary=session.journey().survival.inventory.items[item.id]
				actor.combat.items.append({"slot":item.slot,"definition_id":raw.definition_id,"current":item.current})
	var figure: Control=FIGURE.new(); figure.art=art; figure.actor=actor; figure.anatomy_mode=anatomy; place(center,figure,Rect2(90,73,246,540))
	if anatomy:
		text(center,"Правая рука",Rect2(15,637,396,28),20,B.PSI,true,HORIZONTAL_ALIGNMENT_CENTER)
		text(center,"Подробности выбранной части →",Rect2(15,675,396,24),13,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
		return
	for spec: Array in [["head",16,64],["body",16,195],["clothes",16,326],["shield",320,64],["belt",320,195],["backpack",320,326],["weapon",167,619]]:
		for item: Dictionary in view.items:
			if item.owner!=2 or item.place!="equipped" or item.slot!=spec[0]: continue
			var slot: Control=panel(center,Rect2(spec[1],spec[2],90,112))
			texture(slot,item_icon(item),Rect2(20,9,50,57))
			text(slot,short_name(item),Rect2(3,76,84,29),11,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)

func build_inventory() -> void:
	var right: Control=panel(canvas,Rect2(830,100,752,744))
	text(right,"ВЕЩИ ГЕРОЯ",Rect2(18,12,706,30),15,B.GOLD)
	var y: int=53
	for i: int in 4:
		var container: Dictionary={} if i==0 else find_container(["57","58","62"][i-1])
		var caption: String="Всё при герое" if i==0 else ["Карманы","Пояс","Рюкзак"][i-1]+"  %s/%s" % [container.volume,container.capacity]
		var tab: Control=panel(right,Rect2(18+i*180,y,174,43),B.PSI if i==0 else B.BORDER)
		text(tab,caption,Rect2(4,8,166,27),13,B.TEXT,false,HORIZONTAL_ALIGNMENT_CENTER)
	var search: Control=panel(right,Rect2(18,110,465,38),B.DIM_BORDER); text(search,"Поиск по названию…",Rect2(12,6,441,27),14,B.MUTED)
	text(right,"Тип: все  ▾    Сортировка: имя  ▾",Rect2(493,117,244,24),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)
	var owned: Array[Dictionary]=[]
	for item: Dictionary in view.items:
		if item.owner==2 and item.id not in ["60","61"]: owned.append(item)
	for i: int in owned.size():
		var item: Dictionary=owned[i]; var slot: Control=panel(right,Rect2(18+(i%4)*180,167+(i/4)*121,174,110),B.PSI if item.id=="59" else B.BORDER)
		texture(slot,item_icon(item),Rect2(66,7,42,48))
		text(slot,short_name(item),Rect2(4,61,166,22),13,B.TEXT,false,HORIZONTAL_ALIGNMENT_CENTER)
		text(slot,"Пояс · 3 шт." if item.id=="59" else "Надето",Rect2(4,85,166,18),11,B.PSI if item.id=="59" else B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	text(right,"Рядом: земля  ·  Лагерный сундук",Rect2(20,419,709,24),13,B.MUTED)
	line(right,Rect2(18,455,716,1))
	var selected: Dictionary=find_item("59")
	text(right,selected.name,Rect2(18,475,420,29),22,B.GOLD,true)
	text(right,"В поясной сумке героя · 3 отдельных предмета",Rect2(18,511,420,23),13,B.MUTED)
	text(right,"Один предмет: %.2f кг · объём %s · размер %s" % [selected.mass/1000.0,selected.volume,selected.size],Rect2(18,550,420,23),13)
	text(right,"Перевязка останавливает кровотечение.\nПовреждённые ткани при этом не восстанавливаются.",Rect2(18,587,420,45),13,B.MUTED)
	var backpack: Dictionary=find_container("62")
	var destination: Control=panel(right,Rect2(465,475,269,234),B.DIM_BORDER)
	text(destination,"КУДА ПЕРЕЛОЖИТЬ",Rect2(15,12,239,20),12,B.GOLD)
	text(destination,"Рюкзак героя  ▾",Rect2(15,43,239,26),18,B.TEXT,true)
	text(destination,"Объём %s / %s" % [backpack.volume,backpack.capacity],Rect2(15,87,239,21),13)
	meter(destination,Rect2(15,115,239,5),float(backpack.volume)/backpack.capacity,B.PSI)
	text(destination,"Масса %.2f / %.0f кг" % [backpack.mass/1000.0,backpack.max_mass/1000.0],Rect2(15,137,239,22),13,B.MUTED)
	var check: String=session.world.check(session.command("store_item",62,"59")); evidence["store_bandage"]=check
	t.expect(check.is_empty(),"displayed transfer is legal")
	var transfer: Control=panel(destination,Rect2(15,180,239,39),B.PSI); text(transfer,"Переложить 1 шт.",Rect2(3,6,233,27),14,B.TEXT,false,HORIZONTAL_ALIGNMENT_CENTER)
	var drop: Control=panel(right,Rect2(18,664,174,39)); text(drop,"Оставить на земле",Rect2(3,6,168,27),13,B.TEXT,false,HORIZONTAL_ALIGNMENT_CENTER)
	text(right,"Предметы показаны карточками; размещение без сетки.",Rect2(18,718,716,18),11,B.MUTED)

func build_anatomy() -> void:
	var right: Control=panel(canvas,Rect2(830,100,752,744))
	text(right,"АНАТОМИЯ",Rect2(20,16,710,28),15,B.GOLD)
	for i: int in view.parts.size():
		var part: Dictionary=view.parts[i]
		var row: Control=panel(right,Rect2(18,66+i*66,216,56),B.PSI if part.id=="right_hand" else B.DIM_BORDER)
		text(row,part.name,Rect2(12,6,192,23),15,B.TEXT)
		text(row,"Без повреждений",Rect2(12,32,192,17),11,Color("9bb58a"))
	var part: Dictionary={}
	for item: Dictionary in view.parts:
		if item.id=="right_hand": part=item
	text(right,part.name,Rect2(264,63,455,38),27,B.GOLD,true)
	text(right,part.status,Rect2(264,113,455,25),15,Color("9bb58a"))
	text(right,"ЦЕЛОСТНОСТЬ ТКАНЕЙ",Rect2(264,175,455,24),12,B.MUTED)
	for i: int in part.layers.size():
		var layer: Dictionary=part.layers[i]
		text(right,layer.name,Rect2(264,224+i*84,255,25),17)
		text(right,"%s / %s" % [layer.current,layer.capacity],Rect2(564,224+i*84,155,25),17,B.GOLD,false,HORIZONTAL_ALIGNMENT_RIGHT)
		meter(right,Rect2(264,261+i*84,455,6),float(layer.current)/layer.capacity,Color("9bb58a"))
	line(right,Rect2(264,494,455,1))
	text(right,"Раны отсутствуют",Rect2(264,518,455,28),19,B.TEXT,true)
	text(right,"Кровотечение: %s мл/мин\nПротез не установлен" % part.bleeding,Rect2(264,560,455,51),14,B.MUTED)
	var button: Control=panel(right,Rect2(264,647,203,44),B.DIM_BORDER); text(button,"Перевязать",Rect2(4,8,195,27),15,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	text(right,"Нет кровоточащей раны",Rect2(484,656,235,24),13,B.MUTED)
	text(right,"Осмотр тела не продвигает игровое время.",Rect2(20,713,710,23),12,B.MUTED)

func find_item(id: String) -> Dictionary:
	for item: Dictionary in view.items:
		if item.id==id: return item
	return {}
func find_container(id: String) -> Dictionary:
	for item: Dictionary in view.containers:
		if item.id==id: return item
	return {}
func short_name(item: Dictionary) -> String:
	return {"Стёганая броня":"Стёганка","Одежда с карманами":"Карманы","Поясная сумка":"Пояс","Перевязочный материал":"Перевязка"}.get(item.name,item.name)
func item_icon(item: Dictionary) -> Texture2D:
	var raw: Dictionary=session.journey().survival.inventory.items[item.id]
	if art.equipment.has(raw.definition_id): return art.sprites[art.equipment[raw.definition_id]]
	if item.name=="Перевязочный материал": return load("res://assets/hud/bandage.svg")
	# Native vector symbols for containers; no new game item artwork is claimed.
	var name: String={"clothes":"pockets","belt":"belt","backpack":"backpack"}.get(item.slot,"backpack")
	var image: Image=Image.new(); image.load_svg_from_string(FileAccess.get_file_as_string("res://outputs/inventory-layout-1/"+name+".svg"),2.0)
	return ImageTexture.create_from_image(image)
func place(parent: Control,node: Control,rect: Rect2) -> void:
	parent.add_child(node); node.position=rect.position; node.size=rect.size; node.mouse_filter=Control.MOUSE_FILTER_IGNORE
func panel(parent: Control,rect: Rect2,border: Color=B.BORDER) -> Control:
	var node: Panel=Panel.new(); node.add_theme_stylebox_override("panel",B.box(Color("191a14"),border,0)); place(parent,node,rect); return node
func text(parent: Control,value: String,rect: Rect2,font_size: int=14,color: Color=B.TEXT,serif: bool=false,align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var node: Label=Label.new(); node.text=value; node.horizontal_alignment=align; node.add_theme_font_size_override("font_size",font_size); node.add_theme_color_override("font_color",color)
	if serif: node.add_theme_font_override("font",B.SERIF)
	place(parent,node,rect)
func texture(parent: Control,image: Texture2D,rect: Rect2) -> void:
	var node: TextureRect=TextureRect.new(); node.texture=image; node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; place(parent,node,rect)
func line(parent: Control,rect: Rect2) -> void:
	var node: ColorRect=ColorRect.new(); node.color=B.DIM_BORDER; place(parent,node,rect)
func meter(parent: Control,rect: Rect2,ratio: float,color: Color) -> void:
	line(parent,rect); var fill: ColorRect=ColorRect.new(); fill.color=color; place(parent,fill,Rect2(rect.position,Vector2(rect.size.x*ratio,rect.size.y)))
