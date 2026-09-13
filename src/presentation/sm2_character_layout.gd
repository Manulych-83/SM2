class_name Sm2CharacterLayout
extends RefCounted
## Camp-style character shell; body actions remain in the existing workspace.
const B=preload("res://src/presentation/sm2_bronze_theme.gd")
var owner: Sm2SurvivalWorkspace
var model: Dictionary
var column: VBoxContainer

func build(screen: Sm2SurvivalWorkspace) -> void:
	owner=screen; owner.layout.name="CharacterLayout"; owner.layout.theme=B.create(); owner.layout.theme.default_font=B.SERIF
	model=Sm2CharacterView.build(owner.session,int(owner.ui.body))
	var scene: Sm2CampScene=Sm2CampScene.new()
	scene.manifest=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/camp_scene.json"))
	scene.model={"location":owner.session.journey().region.location_id,"hero":{},"objects":[]}
	owner.layout.add_child(scene); place(scene,0.17,0,1,1)
	var shade: ColorRect=ColorRect.new(); shade.color=Color(0.025,0.028,0.025,0.63); shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	owner.layout.add_child(shade); place(shade,0.17,0,1,1)
	var rail: VBoxContainer=owner.scroll_column(panel(0,0,0.17,1),1)
	var portrait: TextureRect=TextureRect.new(); portrait.texture=owner.artwork.art.sprites.get("head_beard") if int(model.hero)!=0 else null
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait.custom_minimum_size.y=150; rail.add_child(portrait)
	rail.add_child(owner.label("Герой" if int(model.hero)!=0 else "Душа без тела",23,B.GOLD))
	if int(model.hero)!=0 and not owner.view.body.is_empty() and int(owner.ui.body)==int(model.hero):
		var blood: Label=owner.label("Кровь · %s / %s мл" % [owner.view.body.blood,owner.view.body.blood_max],14); blood.name="CharacterBlood"; rail.add_child(blood)
	rail.add_child(owner.button("Лагерь","CharacterCamp",_back))
	for entry: Dictionary in scene.manifest.navigation:
		var target: String=entry.action
		var button: Button=owner.button(entry.title,"CharacterNav_"+target,func() -> void: navigate(target))
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size.y=41; button.disabled=target=="body"; rail.add_child(button)
	var space: Control=Control.new(); space.size_flags_vertical=Control.SIZE_EXPAND_FILL; rail.add_child(space)
	rail.add_child(owner.button("Настройки","CharacterSettings",func() -> void: owner.navigation_requested.emit("settings")))
	rail.add_child(owner.button("Главное меню","CharacterMenu",func() -> void: owner.navigation_requested.emit("menu")))
	var title: Label=owner.label("ПЕРСОНАЖ",32,B.GOLD); owner.layout.add_child(title); place(title,0.195,0.035,0.70,0.10)
	var back: Button=owner.button("В лагерь","WorkspaceBack",_back); owner.layout.add_child(back); place(back,0.865,0.035,0.978,0.088)
	if not str(model.message).is_empty():
		var empty: VBoxContainer=owner.scroll_column(panel(0.22,0.23,0.93,0.63),1)
		empty.add_child(owner.label(model.message,22)); empty.add_child(owner.button("Душа и воплощения","CharacterIncarnate",func() -> void: navigate("soul"))); return
	var caption: Label=owner.label(owner.view.body.name+(" · Воплощение %s" % model.incarnation if int(owner.ui.body)==int(model.hero) else ""),23,B.GOLD)
	owner.layout.add_child(caption); place(caption,0.20,0.13,0.51,0.20)
	var figure: Sm2WorkspaceFigure=Sm2WorkspaceFigure.new(); figure.name="CharacterFigure"; figure.artwork=owner.artwork; figure.view=owner.view; figure.anatomy=owner.ui.character_page=="body"; figure.selected=owner.ui.part
	owner.layout.add_child(figure); place(figure,0.205,0.20,0.51,0.78)
	var status: VBoxContainer=owner.scroll_column(panel(0.20,0.79,0.505,0.94),1)
	var wounds: int=0
	for part: Dictionary in owner.view.parts: wounds+=part.wounds.size()
	status.add_child(owner.label("Ран: %s · Кровотечение: %s мл/мин" % [wounds,owner.view.body.bleeding],15))
	if owner.ui.character_page=="body": status.add_child(owner.label("Схема · точное состояние частей справа",13,B.MUTED))
	status.add_child(owner.button("Осмотреть тело","CharacterInspectBody",func() -> void: change_page("body")))
	var right: VBoxContainer=VBoxContainer.new(); right.add_theme_constant_override("separation",12); panel(0.525,0.13,0.98,0.94).add_child(right)
	var tabs: HBoxContainer=HBoxContainer.new(); right.add_child(tabs)
	for entry: Array in [["Обзор","overview"],["Тело","body"],["Улучшения","upgrades"]]:
		var tab: Button=owner.button(entry[0],"CharacterTab_"+entry[1],change_page.bind(entry[1])); tab.toggle_mode=true; tab.button_pressed=owner.ui.character_page==entry[1]; tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tabs.add_child(tab)
	var people: OptionButton=OptionButton.new(); people.name="CharacterPerson"; people.custom_minimum_size.y=32; right.add_child(people)
	for person: Dictionary in owner.view.people:
		people.add_item(person.name); people.set_item_metadata(people.item_count-1,person.id)
		if int(person.id)==int(owner.ui.body): people.select(people.item_count-1)
	people.item_selected.connect(func(index: int) -> void: owner.choose_person(int(people.get_item_metadata(index))))
	if owner.ui.character_page=="body":
		column=VBoxContainer.new(); column.size_flags_vertical=Control.SIZE_EXPAND_FILL; right.add_child(column)
	else:
		column=owner.scroll_column(right,1); column.add_theme_constant_override("separation",5)
	match str(owner.ui.character_page):
		"overview": overview()
		"body": owner._body(column)
		"upgrades": upgrades()
	var notice: Label=owner.label(owner.message,14,B.GOLD); notice.name="WorkspaceNotice"; owner.layout.add_child(notice); place(notice,0.20,0.955,0.98,0.99)

func overview() -> void:
	if not model.companion.is_empty(): column.add_child(owner.label("Уровень %s · Общий опыт %s\nХарактеристики растут автоматически." % [model.companion.level,model.companion.earned],16,B.GOLD))
	var heading: HBoxContainer=HBoxContainer.new(); column.add_child(heading)
	attribute_cells(heading,"ХАРАКТЕРИСТИКИ","Своё","Итог",B.GOLD)
	var selected: Dictionary={}
	for row: Dictionary in model.attributes:
		if selected.is_empty() or row.id==owner.ui.get("attribute",""): selected=row
	if not selected.is_empty(): owner.ui.attribute=selected.id
	for row: Dictionary in model.attributes:
		var button: Button=owner.button("","CharacterAttribute_"+str(row.id).sha256_text().substr(0,12),func() -> void: owner.ui.attribute=row.id; owner.refresh())
		button.tooltip_text=row.name; button.custom_minimum_size.y=32; button.toggle_mode=true; button.button_pressed=row.id==owner.ui.attribute; column.add_child(button)
		var cells: HBoxContainer=HBoxContainer.new(); cells.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(cells); cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); cells.offset_left=8; cells.offset_right=-8
		attribute_cells(cells,row.name,str(row.level),str(row.effective),B.TEXT)
	if selected.is_empty(): return
	column.add_child(HSeparator.new())
	column.add_child(owner.label(selected.name,22,B.GOLD))
	column.add_child(owner.label("Собственное значение: %s\nПрибавки узлов: +%s" % [selected.level,selected.node_bonus],15))
	for source: Dictionary in selected.sources: column.add_child(owner.label("%s: +%s" % [source.name,source.amount],15))
	for source: Dictionary in selected.get("upgrade_sources",[]): column.add_child(owner.label("%s: +%s" % [source.name,source.amount],15))
	column.add_child(owner.label("Итог: %s" % selected.effective,21,B.GOLD))
	if model.companion.is_empty(): column.add_child(owner.label("Практика до следующего уровня: %s / %s\nДоступно для изучения узлов: %s XP" % [selected.progress,selected.needed,selected.available],14,B.MUTED))
	column.add_child(owner.button("Открыть развитие","CharacterDevelopment",owner.open_development))

func attribute_cells(parent: HBoxContainer,title: String,own: String,total: String,color: Color) -> void:
	for index: int in 3:
		var value: Label=owner.label([title,own,total][index],16,color); value.mouse_filter=Control.MOUSE_FILTER_IGNORE; value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		if index==0: value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		else: value.custom_minimum_size.x=64; value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(value)

func upgrades() -> void:
	for entry: Array in [["genetics","ГЕНЕТИКА"],["cybernetics","КИБЕРНЕТИКА"],["psionics","ПСИОНИКА"]]:
		column.add_child(owner.label(entry[1],20,B.GOLD)); var count: int=0
		for row: Dictionary in model.upgrades:
			if row.path!=entry[0]: continue
			count+=1; column.add_child(owner.label(row.name,18))
			for effect: String in row.effects: column.add_child(owner.label(effect,15,B.MUTED))
		if entry[0]=="cybernetics":
			for part: Dictionary in owner.view.parts:
				if str(part.device).is_empty(): continue
				count+=1; column.add_child(owner.label(part.name+" · "+part.device,15))
		if count==0: column.add_child(owner.label("Установленных улучшений нет.",15,B.MUTED))
	column.add_child(owner.label("Улучшения принадлежат этому телу. Изученные псионические способности находятся в разделе «Навыки».",15,B.MUTED))
	column.add_child(owner.button("Местные занятия и процедуры","CharacterProcedures",func() -> void: navigate("activities")))

func change_page(page: String) -> void:
	owner.ui.character_page=page; owner.refresh()

func navigate(target: String) -> void:
	if target=="inventory": owner.change_tab(1)
	elif target=="development": owner.open_development()
	else: owner.navigation_requested.emit(target)

func _back() -> void: owner.closed.emit(owner.ui.duplicate(true),owner.message)

func panel(left: float,top: float,right: float,bottom: float) -> PanelContainer:
	var value: PanelContainer=PanelContainer.new(); value.add_theme_stylebox_override("panel",B.box(Color(0.035,0.038,0.033,0.94),B.BORDER,14))
	owner.layout.add_child(value); place(value,left,top,right,bottom); return value

static func place(node: Control,left: float,top: float,right: float,bottom: float) -> void:
	Sm2CampHome.place(node,left,top,right,bottom)
