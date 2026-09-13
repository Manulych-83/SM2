class_name Sm2InventoryLayout
extends Sm2CharacterLayout
## Paginated presentation over the existing detached inventory and command gateway.
const PAGE_SIZE: int=6
var groups: Array[Dictionary]=[]
var page_label: Label
var previous: Button
var next: Button
var storage: OptionButton
var rows: VBoxContainer
var row_buttons: Array[Button]=[]

func build(screen: Sm2SurvivalWorkspace) -> void:
	owner=screen; owner.layout.name="InventoryHome"; owner.layout.theme=B.create(); owner.layout.theme.default_font=B.SERIF
	owner.ui.merge({"inventory_page":0},false)
	var scene: Sm2CampScene=Sm2CampScene.new()
	scene.manifest=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/camp_scene.json"))
	scene.model={"location":owner.session.journey().region.location_id,"hero":{},"objects":[]}
	owner.layout.add_child(scene); place(scene,0.17,0,1,1)
	var shade: ColorRect=ColorRect.new(); shade.color=Color(0.025,0.028,0.025,0.65); shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	owner.layout.add_child(shade); place(shade,0.17,0,1,1)
	var rail: VBoxContainer=owner.scroll_column(panel(0,0,0.17,1),1)
	var hero: int=owner.session.world.hero_id()
	var portrait: TextureRect=TextureRect.new(); portrait.texture=owner.artwork.art.sprites.get("head_beard") if hero!=0 else null
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait.custom_minimum_size.y=145; rail.add_child(portrait)
	rail.add_child(owner.label("Герой" if hero!=0 else "Душа без тела",23,B.GOLD))
	rail.add_child(owner.button("Лагерь","InventoryCamp",_back))
	for entry: Dictionary in scene.manifest.navigation:
		var target: String=entry.action
		var button: Button=owner.button(entry.title,"InventoryNav_"+target,navigate.bind(target)); button.disabled=target=="inventory"; button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size.y=41; rail.add_child(button)
	var spacer: Control=Control.new(); spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL; rail.add_child(spacer)
	rail.add_child(owner.button("Настройки","InventorySettings",func() -> void: owner.navigation_requested.emit("settings")))
	rail.add_child(owner.button("Главное меню","InventoryMenu",func() -> void: owner.navigation_requested.emit("menu")))
	var title: Label=owner.label("ИНВЕНТАРЬ",32,B.GOLD); owner.layout.add_child(title); place(title,0.195,0.03,0.7,0.09)
	var back: Button=owner.button("В лагерь","WorkspaceBack",_back); owner.layout.add_child(back); place(back,0.865,0.03,0.98,0.08)
	var person: OptionButton=OptionButton.new(); person.name="WorkspacePerson"; owner.layout.add_child(person); place(person,0.28,0.11,0.46,0.16)
	for row: Dictionary in owner.view.people:
		person.add_item(row.name); person.set_item_metadata(person.item_count-1,row.id)
		if int(row.id)==int(owner.ui.body): person.select(person.item_count-1)
	person.item_selected.connect(func(index: int) -> void: select_person(int(person.get_item_metadata(index))))
	var figure: Sm2WorkspaceFigure=Sm2WorkspaceFigure.new(); figure.name="InventoryFigure"; figure.artwork=owner.artwork; figure.view=owner.view
	owner.layout.add_child(figure); place(figure,0.245,0.17,0.48,0.90)
	var index: int=0
	for slot: String in owner.artwork.metadata.slots:
		var found: Dictionary={}
		for item: Dictionary in owner.view.items:
			if int(item.owner)==int(owner.ui.body) and item.place=="equipped" and item.slot==slot: found=item; break
		var item_id: String=str(found.get("id",""))
		var button: Button=owner.button("","WorkspaceEquipment_"+slot,owner.select_equipment.bind(item_id)); button.disabled=found.is_empty(); button.tooltip_text=found.get("name","Ничего не надето")
		owner.layout.add_child(button)
		var left: float=0.19 if index<4 else 0.454
		var top: float=0.19+float(index if index<4 else index-4)*0.17
		place(button,left,top,left+0.066,top+0.145)
		var box: VBoxContainer=VBoxContainer.new(); box.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(box); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); box.offset_top=5; box.offset_left=4; box.offset_right=-4
		var icon: TextureRect=TextureRect.new(); icon.mouse_filter=Control.MOUSE_FILTER_IGNORE; icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.size_flags_vertical=Control.SIZE_EXPAND_FILL; box.add_child(icon)
		if not found.is_empty(): icon.texture=owner.artwork.icon(found)
		var caption: Label=owner.label(owner.artwork.metadata.slots[slot],13,B.TEXT); caption.mouse_filter=Control.MOUSE_FILTER_IGNORE; caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; box.add_child(caption); index+=1
	var mass: Label=owner.label("Надето и в контейнерах · %.2f кг" % (int(owner.view.body.mass)/1000.0),16,B.GOLD); owner.layout.add_child(mass); place(mass,0.20,0.92,0.52,0.965)
	var upper: VBoxContainer=VBoxContainer.new(); upper.add_theme_constant_override("separation",8); panel(0.54,0.11,0.985,0.59).add_child(upper)
	var places: HBoxContainer=HBoxContainer.new(); upper.add_child(places)
	for entry: Array in [["При герое",1,hero],["Спутник",1,4],["Тайник",3,0],["На земле",2,0],["Всё рядом",0,0]]:
		var button: Button=owner.button(entry[0],"InventoryScope_"+str(entry[1])+"_"+str(entry[2]),func() -> void:
			owner.ui.scope=entry[1]; owner.ui.storage=""; owner.ui.item=""; owner.ui.inventory_page=0
			if int(entry[2])!=0: owner.ui.body=int(entry[2])
			owner.refresh())
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.custom_minimum_size.x=60; button.add_theme_font_size_override("font_size",13); button.toggle_mode=true
		button.button_pressed=int(owner.ui.scope)==int(entry[1]) and (int(entry[2])==0 or int(owner.ui.body)==int(entry[2]))
		if int(entry[1])==1:
			button.disabled=true
			for row: Dictionary in owner.view.people:
				if int(row.id)==int(entry[2]): button.disabled=false
		places.add_child(button)
	var filters: HBoxContainer=HBoxContainer.new(); upper.add_child(filters)
	storage=OptionButton.new(); storage.name="InventoryStorage"; storage.fit_to_longest_item=false; storage.custom_minimum_size.x=140; storage.add_item("Все контейнеры"); storage.set_item_metadata(0,""); filters.add_child(storage)
	for row: Dictionary in owner.view.containers:
		if int(owner.ui.scope)==1 and int(row.owner)!=int(owner.ui.body): continue
		storage.add_item(row.name); storage.set_item_metadata(storage.item_count-1,row.id)
		if row.id==owner.ui.storage: storage.select(storage.item_count-1)
	if storage.selected==0: owner.ui.storage=""
	storage.item_selected.connect(func(value: int) -> void:
		owner.ui.storage=storage.get_item_metadata(value); owner.ui.item=""; owner.ui.inventory_page=0
		# A chosen container describes its contents, not its own ground placement.
		if value!=0 and int(owner.ui.scope) in [2,3]: owner.ui.scope=0
		owner.refresh())
	var search: LineEdit=LineEdit.new(); search.name="WorkspaceSearch"; search.placeholder_text="Поиск предметов…"; search.text=owner.ui.query; search.size_flags_horizontal=Control.SIZE_EXPAND_FILL; filters.add_child(search)
	search.text_changed.connect(func(value: String) -> void: owner.ui.query=value; reset_filter())
	for entry: Array in [["kind","WorkspaceKind",["Все типы","Снаряжение","Припасы","Контейнеры","Устройства"]],["sort","WorkspaceSort",["По имени","По массе","По объёму"]]]:
		var key: String=entry[0]; var selector: OptionButton=OptionButton.new(); selector.name=entry[1]; selector.fit_to_longest_item=false; selector.custom_minimum_size.x=100; filters.add_child(selector)
		for value: String in entry[2]: selector.add_item(value)
		selector.select(int(owner.ui[key])); selector.item_selected.connect(func(value: int) -> void: owner.ui[key]=value; reset_filter())
	rows=VBoxContainer.new(); rows.name="InventoryRows"; rows.add_theme_constant_override("separation",2); rows.size_flags_vertical=Control.SIZE_EXPAND_FILL; upper.add_child(rows)
	var pager: HBoxContainer=HBoxContainer.new(); upper.add_child(pager)
	previous=owner.button("‹","InventoryPrevious",page_by.bind(-1)); pager.add_child(previous)
	page_label=owner.label("",14,B.MUTED); page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; pager.add_child(page_label)
	next=owner.button("›","InventoryNext",page_by.bind(1)); pager.add_child(next)
	owner.details=owner.scroll_column(panel(0.54,0.61,0.985,0.955),1)
	var notice: Label=owner.label(owner.message,14,B.GOLD); notice.name="WorkspaceNotice"; owner.layout.add_child(notice); place(notice,0.20,0.97,0.98,0.999)
	populate()

func populate() -> void:
	var result: Dictionary=Sm2InventoryCards.build(owner.view,owner.ui); owner.filtered.assign(result.rows); groups.assign(result.groups)
	for index: int in groups.size():
		if str(owner.ui.item) in groups[index].ids: owner.ui.inventory_page=floori(float(index)/PAGE_SIZE); break
	draw_page()

func draw_page() -> void:
	var pages: int=maxi(1,ceili(float(groups.size())/PAGE_SIZE)); owner.ui.inventory_page=clampi(int(owner.ui.inventory_page),0,pages-1)
	var first: int=int(owner.ui.inventory_page)*PAGE_SIZE
	owner.cards.assign(groups.slice(first,first+PAGE_SIZE)); owner.clear(rows); row_buttons.clear(); var selected: int=0
	for index: int in owner.cards.size():
		var group: Dictionary=owner.cards[index]; var row: Dictionary=group.row; var id: String=str(owner.ui.item) if str(owner.ui.item) in group.ids else str(group.ids[0])
		var button: Button=owner.button("","InventoryRow_"+str(index),select_row.bind(index)); button.set_meta("item",id); button.toggle_mode=true; button.size_flags_vertical=Control.SIZE_EXPAND_FILL; rows.add_child(button); row_buttons.append(button)
		button.tooltip_text="%s · %s · всего %.2f кг" % [row.name,row.where,int(row.mass)*group.ids.size()/1000.0]
		var line: HBoxContainer=HBoxContainer.new(); line.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(line); line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); line.offset_left=6; line.offset_right=-6
		var icon: TextureRect=TextureRect.new(); icon.texture=owner.artwork.icon(row); icon.mouse_filter=Control.MOUSE_FILTER_IGNORE; icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size.x=32; line.add_child(icon)
		for cell: Array in [[row.name+(" ×%s" % group.ids.size() if group.ids.size()>1 else ""),2.0,14],[row.where,1.5,12],["%.2f кг/шт." % (int(row.mass)/1000.0),0.8,12]]:
			var label: Label=owner.label(cell[0],cell[2]); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; label.size_flags_stretch_ratio=cell[1]; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; label.max_lines_visible=2; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; line.add_child(label)
		if id==str(owner.ui.item): selected=index
	page_label.text="%s–%s из %s" % [first+1 if not groups.is_empty() else 0,mini(first+PAGE_SIZE,groups.size()),groups.size()]; previous.disabled=int(owner.ui.inventory_page)==0; next.disabled=int(owner.ui.inventory_page)>=pages-1
	if owner.cards.is_empty():
		owner.ui.item=""; owner.clear(owner.details); owner.details.add_child(owner.label("Подходящих вещей нет. Измените поиск или место хранения.")); return
	select_row(selected)

func select_row(index: int) -> void:
	owner.ui.item=str(row_buttons[index].get_meta("item"))
	for row: Button in row_buttons: row.button_pressed=row==row_buttons[index]
	owner._item(owner.item_by_id(owner.ui.item))

func select_instance(id: String) -> void:
	for index: int in owner.cards.size():
		if id in owner.cards[index].ids: row_buttons[index].set_meta("item",id); select_row(index); return

func reset_filter() -> void:
	owner.ui.item=""; owner.ui.inventory_page=0; populate()

func page_by(delta: int) -> void:
	owner.ui.item=""; owner.ui.inventory_page=int(owner.ui.inventory_page)+delta; draw_page()

func select_person(id: int) -> void:
	owner.ui.scope=1; owner.ui.item=""; owner.ui.inventory_page=0; owner.choose_person(id)

func navigate(target: String) -> void:
	if target=="body": owner.ui.character=true; owner.ui.character_page="overview"; owner.ui.tab=0; owner.refresh()
	elif target=="development": owner.open_development()
	else: owner.navigation_requested.emit(target)
