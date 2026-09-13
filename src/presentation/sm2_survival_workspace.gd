class_name Sm2SurvivalWorkspace
extends Control
var expedition: Sm2ExpeditionView=Sm2ExpeditionView.new()
signal closed(state: Dictionary,message: String)
var session: Sm2JourneySession
var ui: Dictionary={"body":0,"tab":0,"part":"","item":"","destination":"","scope":1,"query":""}
var message: String=""
var view: Dictionary={}
var layout: Control
var details: VBoxContainer
var item_list: ItemList
var filtered: Array[Dictionary]=[]
var cards: Array[Dictionary]=[]
var artwork: Sm2WorkspaceArt=Sm2WorkspaceArt.new()
var composition: Sm2WorkspaceLayout
var container_bar: HBoxContainer
var development_screen: Sm2HeroDevelopmentScreen

const INK: Color=Sm2BronzeTheme.TEXT
const MUTED: Color=Sm2BronzeTheme.MUTED
const GOLD: Color=Color("d1b478")
const DANGER: Color=Color("ef9a83")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=Sm2BronzeTheme.create()
	theme.set_stylebox("background","ProgressBar",Sm2BronzeTheme.box(Sm2BronzeTheme.BACKGROUND,Sm2BronzeTheme.DIM_BORDER,0))
	theme.set_stylebox("fill","ProgressBar",Sm2BronzeTheme.box(Color("927347"),Sm2BronzeTheme.GOLD,0))
	artwork.prepare()
	refresh()

func refresh() -> void:
	ui.merge({"storage":"","kind":0,"sort":0},false)
	view=Sm2SurvivalWorkspaceView.build(session,int(ui.body))
	if composition!=null and resized.is_connected(composition.relayout): resized.disconnect(composition.relayout)
	if is_instance_valid(layout): remove_child(layout); layout.queue_free()
	item_list=null; details=null; container_bar=null
	layout=Control.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(layout)
	if not str(view.message).is_empty() or view.body.is_empty():
		var panel: PanelContainer=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_stylebox_override("panel",Sm2BronzeTheme.box()); layout.add_child(panel)
		var column: VBoxContainer=VBoxContainer.new(); panel.add_child(column)
		column.add_child(button("Вернуться","WorkspaceBack",func() -> void: closed.emit(ui.duplicate(true),message)))
		column.add_child(label(view.message if not str(view.message).is_empty() else "Нет доступного тела в этом месте.")); return
	ui.body=int(view.body.id)
	var valid: bool=false
	for part: Dictionary in view.parts:
		if part.id==ui.part: valid=true
	if not valid:
		ui.part=""
		for part: Dictionary in view.parts:
			if part.damaged or int(part.bleeding)>0: ui.part=part.id; break
		if str(ui.part).is_empty() and not view.parts.is_empty(): ui.part=view.parts[0].id
	composition=Sm2WorkspaceLayout.new(); composition.build(self)
	if int(ui.tab)==0: _body(composition.content)
	else: _inventory(composition.content)
	composition.relayout()

func change_tab(index: int) -> void:
	ui.tab=index; refresh()

func choose_person(id: int) -> void:
	ui.body=id; ui.part=""; ui.destination=""; ui.storage=""; refresh()

func select_equipment(id: String) -> void:
	ui.item=id; ui.tab=1; ui.scope=1; ui.storage=""; ui.query=""; ui.kind=0; refresh()

func open_development() -> void:
	if is_instance_valid(development_screen): return
	development_screen=Sm2HeroDevelopmentScreen.new(); development_screen.session=session; development_screen.back_text="К инвентарю"
	layout.hide(); add_child(development_screen)
	var back: Button=development_screen.find_child("HeroDevelopmentBack",true,false) as Button
	if back!=null: back.text="К телу и инвентарю"
	development_screen.camp_requested.connect(func() -> void:
		remove_child(development_screen); development_screen.queue_free(); development_screen=null; refresh())

func _body(outer: VBoxContainer) -> void:
	if view.body.is_empty(): outer.add_child(label("Нет доступного тела в этом месте.")); return
	var body: Dictionary=view.body
	outer.add_child(label(("Жив" if body.alive else "Мёртвое тело")+" · кровь %s / %s мл · кровотечение %s мл/мин · груз %.2f кг" % [body.blood,body.blood_max,body.bleeding,int(body.mass)/1000.0],13,DANGER if int(body.bleeding)>0 else INK))
	var columns: HBoxContainer=HBoxContainer.new(); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; columns.add_theme_constant_override("separation",20); outer.add_child(columns)
	var left: VBoxContainer=scroll_column(columns,0.85)
	details=scroll_column(columns,1.6)
	if str(ui.part).is_empty():
		for part: Dictionary in view.parts:
			if int(part.bleeding)>0 or part.damaged: ui.part=part.id; break
		if str(ui.part).is_empty() and not view.parts.is_empty(): ui.part=view.parts[0].id
	for row: Dictionary in view.parts:
		var caption: String=row.name
		if int(row.bleeding)>0: caption+=" · кровотечение"
		elif not str(row.device).is_empty(): caption+=" · протез"
		elif row.damaged: caption+=" · повреждение"
		var part: Button=button(caption,"WorkspacePart_"+row.id,func() -> void: ui.part=row.id; refresh())
		part.toggle_mode=true; part.button_pressed=ui.part==row.id; part.alignment=HORIZONTAL_ALIGNMENT_LEFT
		if row.damaged: part.add_theme_color_override("font_color",DANGER)
		left.add_child(part)
		if ui.part==row.id: _part(row)

func _part(row: Dictionary) -> void:
	details.add_child(label(row.name,24,GOLD))
	details.add_child(label(row.status,17,DANGER if not row.working else INK))
	if not str(row.device).is_empty(): details.add_child(label(row.device,17,GOLD))
	for layer: Dictionary in row.layers:
		details.add_child(label("%s · %s / %s" % [layer.name,layer.current,layer.capacity]))
		var bar: ProgressBar=ProgressBar.new(); bar.max_value=int(layer.capacity); bar.value=int(layer.current); bar.show_percentage=false; bar.custom_minimum_size.y=14; details.add_child(bar)
	details.add_child(label("Раны",19,GOLD))
	if row.wounds.is_empty(): details.add_child(label("Ран на этой части нет.",16,MUTED))
	for wound: Dictionary in row.wounds:
		details.add_child(label("Рана %s · %s" % [wound.id,"не кровоточит" if int(wound.rate)==0 else "%s мл/мин" % wound.rate],17,DANGER if int(wound.rate)>0 else MUTED))
		if int(wound.rate)>0:
			add_action(details,"Перевязать · %s сек" % int(session.journey().survival.catalog.to_data().bandage_seconds),"WorkspaceBandage_"+str(ui.body)+"_"+wound.id,session.command("bandage",int(ui.body),wound.id))
	details.add_child(label("Повязка останавливает кровотечение. Повреждённые ткани и потерянная кровь от неё не восстанавливаются.",15,MUTED))
	if not str(row.device).is_empty() or not row.working: details.add_child(button("К протезам и вещам","WorkspaceToInventory",func() -> void: ui.tab=1; refresh()))

func _inventory(outer: VBoxContainer) -> void:
	outer.add_child(label("ВЕЩИ · %s · %.2f кг" % [view.body.name,int(view.body.mass)/1000.0],16,GOLD))
	var container_scroll: ScrollContainer=ScrollContainer.new(); container_scroll.custom_minimum_size.y=44; container_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; outer.add_child(container_scroll)
	container_bar=HBoxContainer.new(); container_scroll.add_child(container_bar)
	var all_button: Button=button("При участнике","WorkspaceContainer_all",func() -> void: ui.scope=1; ui.storage=""; _items()); all_button.custom_minimum_size.x=138; all_button.toggle_mode=true; container_bar.add_child(all_button)
	var valid_storage: bool=str(ui.storage).is_empty()
	for row: Dictionary in view.containers:
		if int(row.owner)!=int(ui.body): continue
		if row.id==ui.storage: valid_storage=true
		var choice: Button=button("%s %s/%s" % [artwork.caption(row),row.volume,row.capacity],"WorkspaceContainer_"+row.id,func() -> void: ui.scope=1; ui.storage=row.id; _items())
		choice.custom_minimum_size.x=138; choice.toggle_mode=true; choice.tooltip_text=row.name+" · "+row.where; container_bar.add_child(choice)
	if not valid_storage: ui.storage=""
	var filters: HBoxContainer=HBoxContainer.new(); outer.add_child(filters)
	var search: LineEdit=LineEdit.new(); search.name="WorkspaceSearch"; search.placeholder_text="Найти предмет…"; search.text=ui.query; search.size_flags_horizontal=Control.SIZE_EXPAND_FILL; filters.add_child(search)
	var scope: OptionButton=OptionButton.new(); scope.name="WorkspaceScope"; scope.fit_to_longest_item=false; scope.custom_minimum_size.x=172; filters.add_child(scope)
	for title: String in ["Всё рядом","При участнике","На земле","В тайнике"]: scope.add_item(title)
	scope.select(int(ui.scope))
	var kind: OptionButton=OptionButton.new(); kind.name="WorkspaceKind"; kind.fit_to_longest_item=false; kind.custom_minimum_size.x=114; filters.add_child(kind)
	for title: String in ["Все типы","Снаряжение","Припасы","Контейнеры","Устройства"]: kind.add_item(title)
	kind.select(int(ui.kind))
	var sort: OptionButton=OptionButton.new(); sort.name="WorkspaceSort"; sort.fit_to_longest_item=false; sort.custom_minimum_size.x=108; filters.add_child(sort)
	for title: String in ["По имени","По массе","По объёму"]: sort.add_item(title)
	sort.select(int(ui.sort))
	item_list=ItemList.new(); item_list.name="WorkspaceItems"; item_list.max_columns=0; item_list.fixed_column_width=138; item_list.fixed_icon_size=Vector2i(48,48); item_list.icon_mode=ItemList.ICON_MODE_TOP; item_list.max_text_lines=2
	item_list.size_flags_vertical=Control.SIZE_EXPAND_FILL; item_list.custom_minimum_size.y=170; item_list.size_flags_stretch_ratio=1.1; item_list.add_theme_font_size_override("font_size",13); outer.add_child(item_list)
	item_list.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.BACKGROUND,Sm2BronzeTheme.DIM_BORDER,8))
	for state: String in ["selected","selected_focus","hovered","hovered_selected","hovered_selected_focus"]:
		item_list.add_theme_stylebox_override(state,Sm2BronzeTheme.box(Sm2BronzeTheme.BUTTON,Sm2BronzeTheme.GOLD,6))
	item_list.add_theme_color_override("font_color",INK); item_list.add_theme_color_override("font_selected_color",GOLD)
	item_list.add_theme_constant_override("h_separation",8); item_list.add_theme_constant_override("v_separation",12)
	details=scroll_column(outer,1); (details.get_parent() as ScrollContainer).custom_minimum_size.y=185
	search.text_changed.connect(func(value: String) -> void: ui.query=value; _items())
	scope.item_selected.connect(func(index: int) -> void: ui.scope=index; ui.storage=""; _items())
	kind.item_selected.connect(func(index: int) -> void: ui.kind=index; _items())
	sort.item_selected.connect(func(index: int) -> void: ui.sort=index; _items())
	item_list.item_selected.connect(func(index: int) -> void: ui.item=str(item_list.get_item_metadata(index)); _item(item_by_id(ui.item)))
	_items()

func _items() -> void:
	var result: Dictionary=Sm2InventoryCards.build(view,ui)
	filtered.assign(result.rows); cards.assign(result.groups); item_list.clear()
	var selected: int=-1
	for index: int in cards.size():
		var group: Dictionary=cards[index]; var row: Dictionary=group.row
		var id: String=str(ui.item) if str(ui.item) in group.ids else str(group.ids[0])
		item_list.add_item(artwork.caption(row)+( " ×%s" % group.ids.size() if group.ids.size()>1 else "")+"\n"+row.where,artwork.icon(row)); item_list.set_item_metadata(index,id)
		item_list.set_item_tooltip(index,row.name+" · "+row.where+"\n%s отдельных предметов" % group.ids.size())
		if str(ui.item) in group.ids: selected=index
	if selected<0 and not cards.is_empty(): selected=0
	if selected>=0:
		ui.item=str(item_list.get_item_metadata(selected)); item_list.select(selected); item_list.call_deferred("ensure_current_is_visible"); _item(item_by_id(ui.item))
	else:
		ui.item=""; clear(details); details.add_child(label("Подходящих вещей нет. Измените поиск или место хранения.",15,MUTED))
	if is_instance_valid(container_bar):
		for node: Node in container_bar.get_children():
			var choice: Button=node as Button; choice.button_pressed=int(ui.scope)==1 and str(choice.name)=="WorkspaceContainer_"+("all" if str(ui.storage).is_empty() else str(ui.storage))
	var scope: OptionButton=layout.find_child("WorkspaceScope",true,false) as OptionButton
	if scope!=null: scope.select(int(ui.scope))

func item_by_id(id: String) -> Dictionary:
	for row: Dictionary in view.items:
		if row.id==id: return row
	return {}

func _item(row: Dictionary) -> void:
	clear(details)
	if row.is_empty(): return
	var goal: Dictionary=expedition.build(session) if row.definition_id=="medical_kit" else {}
	var columns: HBoxContainer=HBoxContainer.new(); columns.add_theme_constant_override("separation",14); details.add_child(columns)
	var description: VBoxContainer=VBoxContainer.new(); description.size_flags_horizontal=Control.SIZE_EXPAND_FILL; description.size_flags_stretch_ratio=1.2; columns.add_child(description)
	var actions: VBoxContainer=VBoxContainer.new(); actions.size_flags_horizontal=Control.SIZE_EXPAND_FILL; columns.add_child(actions)
	for group: Dictionary in cards:
		if not str(row.id) in group.ids or group.ids.size()<2: continue
		description.add_child(label("%s отдельных предметов · действие с одним" % group.ids.size(),13,MUTED))
		var instance: OptionButton=OptionButton.new(); instance.name="WorkspaceInstance"; instance.fit_to_longest_item=false; description.add_child(instance)
		for id: String in group.ids:
			instance.add_item("Экземпляр №"+id+(" · из руин" if goal.get("ok",false) and id in goal.ids else "")); instance.set_item_metadata(instance.item_count-1,id)
			if id==row.id: instance.select(instance.item_count-1)
		instance.item_selected.connect(func(index: int) -> void: select_instance(str(instance.get_item_metadata(index))))
	description.add_child(label(row.name,20,GOLD)); description.add_child(label(row.where,14))
	if goal.get("ok",false) and str(row.id) in goal.ids: description.add_child(label("Находка из первого похода · доставка засчитана" if goal.complete else "Находка для первого похода · в лагерный сундук",14,GOLD))
	description.add_child(label("Масса %.2f кг · объём %s · размер %s" % [int(row.mass)/1000.0,row.volume,row.size],13,MUTED))
	if row.device: description.add_child(label("Прочность %s / %s" % [row.current,row.device_max],18))
	if not view.containers.is_empty():
		actions.add_child(label("Куда положить",16,GOLD))
		var destination: OptionButton=OptionButton.new(); destination.name="WorkspaceDestination"; destination.fit_to_longest_item=false; destination.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(destination)
		var selected: int=-1; var preferred: int=0
		for index: int in view.containers.size():
			var container: Dictionary=view.containers[index]
			destination.add_item(container.name+" · "+container.where); destination.set_item_metadata(index,container.id)
			if int(container.owner)==int(ui.body): preferred=index
			if container.id==ui.destination: selected=index
		if selected<0: selected=preferred; ui.destination=view.containers[selected].id
		destination.select(selected)
		var target: Dictionary=view.containers[selected]
		actions.add_child(label("Объём: %s / %s · масса: %.2f / %.2f кг%s" % [target.volume,target.capacity,int(target.mass)/1000.0,int(target.max_mass)/1000.0," · быстрый доступ" if target.quick else ""],13,MUTED))
		destination.item_selected.connect(func(index: int) -> void: ui.destination=view.containers[index].id; _item(row))
		add_action(actions,"Положить в контейнер","WorkspaceStore",session.command("store_item",int(ui.destination),row.id))
	if not str(row.slot).is_empty(): add_action(actions,"Надеть выбранному участнику","WorkspaceWear",session.command("wear_item",int(ui.body),row.id))
	if row.device:
		for action: Array in [["attach_device","Установить","WorkspaceAttach",int(ui.body)],["detach_device","Снять на землю","WorkspaceDetach",0],["repair_device","Отремонтировать","WorkspaceRepair",0]]:
			var price: Dictionary=session.journey().survival.catalog.devices().procedures[action[0]]
			add_action(actions,"%s · %s сек · %s компл." % [action[1],int(price.seconds),int(price.parts)],action[2],session.command(action[0],action[3],row.id))
	add_action(actions,"Оставить на земле здесь","WorkspaceDrop",session.command("drop_item",0,row.id))
	description.add_child(label("Вещи на земле и в стационарном тайнике остаются здесь при переходе. Переносите находки в надетых контейнерах.",15,MUTED))

func select_instance(id: String) -> void:
	ui.item=id
	# Focus returning from the popup must not restore the group's first object.
	for index: int in cards.size():
		if id in cards[index].ids: item_list.set_item_metadata(index,id); break
	_item(item_by_id(id))

func add_action(parent: VBoxContainer,title: String,id: String,command: Sm2WorldCommand) -> void:
	var reason: String=session.world.check(command)
	var action: Button=button(title,id,func() -> void:
		var result: Dictionary=session.act(command)
		message="Действие выполнено." if result.ok else str(result.errors[0]); refresh())
	action.disabled=not reason.is_empty(); action.tooltip_text=reason; parent.add_child(action)
	if not reason.is_empty(): parent.add_child(label(reason,14,MUTED))

static func clear(node: Node) -> void:
	for child: Node in node.get_children(): node.remove_child(child); child.queue_free()

static func scroll_column(parent: Node,ratio: float) -> VBoxContainer:
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.size_flags_stretch_ratio=ratio; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; parent.add_child(scroll)
	var column: VBoxContainer=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",10); scroll.add_child(column)
	return column

static func label(text: String,font_size: int=15,color: Color=INK) -> Label:
	var value: Label=Label.new(); value.text=text; value.size_flags_horizontal=Control.SIZE_EXPAND_FILL; value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; value.add_theme_font_size_override("font_size",font_size); value.add_theme_color_override("font_color",color); return value

static func button(text: String,id: String,callback: Callable) -> Button:
	var value: Button=Button.new(); value.name=id; value.text=text; value.clip_text=true; value.tooltip_text=text; value.custom_minimum_size=Vector2(90,38); value.add_theme_font_size_override("font_size",14); value.pressed.connect(callback); return value

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(development_screen): return
	if Sm2Controls.back(event):
		get_viewport().set_input_as_handled(); closed.emit(ui.duplicate(true),message)
