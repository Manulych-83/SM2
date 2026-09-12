class_name Sm2CampScreen
extends RefCounted
## Composes the current camp UI; simulation is only changed by captured commands.
var owner: Sm2LifeScreen
var model: Dictionary
var session: Sm2JourneySession

func build(screen: Sm2LifeScreen) -> void:
	owner=screen; session=owner.session as Sm2JourneySession; model=Sm2CampView.build(session)
	var surface: Panel=Panel.new(); owner._content=surface; surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); surface.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.BACKGROUND,Sm2BronzeTheme.BACKGROUND,0)); owner.add_child(surface)
	surface.theme=Sm2BronzeTheme.create(); surface.theme.set_stylebox("panel","PanelContainer",Sm2BronzeTheme.box())
	var margin: MarginContainer=MarginContainer.new(); surface.add_child(margin); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	var page: VBoxContainer=VBoxContainer.new(); page.add_theme_constant_override("separation",12); margin.add_child(page)
	var header: HBoxContainer=HBoxContainer.new(); frame(page).add_child(header)
	var title: Label=label("КАРТА И ЛАГЕРЬ",24,Sm2BronzeTheme.GOLD); title.add_theme_font_override("font",Sm2BronzeTheme.SERIF); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(button(Sm2Controls.caption("development","Развитие"),"WorldDevelopment",func() -> void: owner.development_requested.emit()))
	if not session.journey().busy() and not session.journey().receipt.is_empty():
		header.add_child(button("Последний бой","CampBattleResults",func() -> void: owner.battle_requested.emit()))
	header.add_child(button("Сохранить","WorldSave",owner._save)); header.add_child(button("Загрузить","WorldLoad",owner._load)); header.add_child(button("Меню","WorldMenu",func() -> void: owner.menu_requested.emit()))
	var seconds: int=int(model.seconds)
	@warning_ignore("integer_division")
	var clock_text: String="День %s · %02d:%02d:%02d" % [1+seconds/86400,(seconds/3600)%24,(seconds/60)%60,seconds%60]
	var clock_label: Label=label(clock_text+" · Безопасные переходы · Завершено встреч %s/%s" % [model.completed,model.total],14,Sm2BronzeTheme.MUTED); clock_label.name="RegionClock"; page.add_child(clock_label)
	var columns: HBoxContainer=HBoxContainer.new(); columns.add_theme_constant_override("separation",12); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; page.add_child(columns)
	if owner.size.x>=1200:
		var panel: PanelContainer=frame(columns); panel.custom_minimum_size.x=210; party(scroll(panel))
	var map_panel: PanelContainer=frame(columns); map_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; map_panel.size_flags_stretch_ratio=1.15
	var map_column: VBoxContainer=scroll(map_panel)
	var valid: bool=false
	for place: Dictionary in model.places:
		if place.id==owner._map_selection: valid=true
	if not valid: owner._map_selection=model.location
	var map: Sm2RegionMap=Sm2RegionMap.new(); map.name="RegionMap"; map.model=model; map.selected=owner._map_selection; map_column.add_child(map)
	map.location_selected.connect(func(id: String) -> void: owner._map_selection=id; owner.redraw())
	for place: Dictionary in model.places:
		if place.id!=owner._map_selection: continue
		map_column.add_child(label(place.name+" · "+("Вы здесь" if place.here else "Посещено" if place.visited else "Не посещено"),21,Sm2BronzeTheme.GOLD))
		map_column.add_child(label(place.description,14,Sm2BronzeTheme.MUTED))
	map_column.add_child(label("ПЕРЕХОДЫ ИЗ ТЕКУЩЕГО МЕСТА",13,Sm2BronzeTheme.GOLD))
	for place: Dictionary in model.places:
		var caption: String=place.name+" · "+("Вы здесь" if place.here else "%s мин" % (int(place.seconds)/60) if int(place.seconds)>0 else "Нет прямого пути")
		var route: Button=action(map_column,caption,"Travel_"+place.id,session.command("travel",0,place.id),false)
		route.tooltip_text=place.reason if not str(place.reason).is_empty() else "Перейти в выбранное место. Переносимые вещи и живой спутник идут с героем."
	Sm2JourneyGuide.build(owner,map_column)
	var actions_panel: PanelContainer=frame(columns); actions_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var actions: VBoxContainer=scroll(actions_panel)
	if owner.size.x<1200: party(actions)
	var here: String=session.journey().region_catalog.location(model.location).name
	actions.add_child(label("ЗАНЯТИЯ · "+here.to_upper(),20,Sm2BronzeTheme.GOLD))
	actions.add_child(button(Sm2Controls.caption("soul","Душа и воплощения"),"CampSoul",owner._open_soul))
	actions.add_child(button(Sm2Controls.caption("journal","Журнал путешествия"),"CampJournal",owner._open_journal))
	actions.add_child(button(Sm2Controls.caption("settings","Настройки и управление"),"CampSettings",func() -> void: owner.settings_requested.emit()))
	actions.add_child(button(Sm2Controls.caption("body","Тело, раны и перевязка"),"WorldBodyInventory",func() -> void: open_body(int(model.hero),0)))
	actions.add_child(button(Sm2Controls.caption("inventory","Снаряжение и припасы"),"CampInventory",func() -> void: open_body(int(model.hero),1)))
	if model.busy:
		actions.add_child(label("Сражение продолжается. Лагерные действия доступны после его завершения.",15,Sm2BronzeTheme.MUTED))
		actions.add_child(button("Вернуться в сражение","WorldBattle",func() -> void:
			if session.world.busy(): owner.battle_requested.emit()
			else: owner.redraw()))
	else:
		if int(model.hero)!=0:
			actions.add_child(label(session.view().encounter_name,17,Sm2BronzeTheme.GOLD))
			action(actions,"Войти в сражение","WorldBattle",session.command("start_battle"))
		var last_group: String=""
		for row: Dictionary in model.activities+model.carriers:
			if row.group!=last_group: actions.add_child(label(row.group.to_upper(),16,Sm2BronzeTheme.GOLD)); last_group=row.group
			var card: VBoxContainer=VBoxContainer.new(); frame(actions).add_child(card)
			card.add_child(label(row.title,17,Sm2BronzeTheme.TEXT)); card.add_child(label(row.description,13,Sm2BronzeTheme.MUTED))
			action(card,"Вселиться" if row.kind=="incarnate" else "Выполнить",control_id(row),session.command(row.kind,int(row.target),row.content))
		if int(model.hero)==0 and model.carriers.is_empty(): actions.add_child(label("Подходящих местных тел больше нет.",16,Sm2BronzeTheme.MUTED))
		actions.add_child(label("МИР И ДУША",16,Sm2BronzeTheme.GOLD))
		actions.add_child(label("Знания: "+", ".join(model.knowledge),14,Sm2BronzeTheme.MUTED))
		var v: Dictionary=session.view()
		actions.add_child(label("Памятный камень: "+("в тайнике лагеря" if v.item_owner==6 else v.item_owner_name),14,Sm2BronzeTheme.MUTED))
		action(actions,"Положить камень в тайник","WorldDeposit",session.command("deposit")); action(actions,"Забрать камень","WorldTake",session.command("take"))
		if int(model.hero)!=0:
			var end: Button=button("Завершить жизнь тела…","WorldEndLife",owner._confirm_end); end.disabled=not session.world.check(session.command("end_life")).is_empty(); actions.add_child(end)
	var text: String=owner._notice if not owner._notice.is_empty() else "Осмотр карты не тратит время. Вещи на земле и в тайнике остаются в своём месте."
	if session._store is Sm2CampaignStore and (session._store as Sm2CampaignStore).recovered: text="Загружена резервная копия. Сохраните игру для восстановления основного файла. "+text
	var notice: Label=label(text,13,Sm2BronzeTheme.GOLD); notice.name="CampNotice"; page.add_child(notice)

func party(parent: VBoxContainer) -> void:
	parent.add_child(label("ОТРЯД",16,Sm2BronzeTheme.GOLD))
	if int(model.hero)==0: parent.add_child(label("Душа без тела\nВыберите местного носителя.",16,Sm2BronzeTheme.GOLD))
	for row: Dictionary in model.party:
		var column: VBoxContainer=VBoxContainer.new(); frame(parent).add_child(column)
		column.add_child(label(row.name,22,Sm2BronzeTheme.GOLD))
		if model.busy: column.add_child(label("В сражении · состояние смотрите в бою",14,Sm2BronzeTheme.MUTED)); continue
		column.add_child(label("Погиб" if not row.alive else "В отряде" if model.hero!=0 else "Ждёт воплощения",14,Sm2BronzeTheme.MUTED))
		column.add_child(label("Кровь %s / %s мл\nКровотечение\n%s мл/мин" % [row.blood,row.blood_max,row.bleeding],14,Sm2SurvivalWorkspace.DANGER if int(row.bleeding)>0 else Sm2BronzeTheme.TEXT))
		column.add_child(label("Утрачено функций: %s\nГруз %.2f кг" % [row.lost_functions,int(row.mass)/1000.0],14,Sm2BronzeTheme.MUTED))
		if not row.local: column.add_child(label("Остался: "+row.location,14,Sm2BronzeTheme.MUTED))
		else: column.add_child(button("Осмотреть","CampBody_"+str(row.id),open_body.bind(int(row.id),0)))

func open_body(id: int,tab: int) -> void:
	owner._workspace_state={"body":id,"tab":tab,"part":"","item":"","destination":"","scope":1,"query":""}; owner._open_workspace()

func action(parent: VBoxContainer,title: String,id: String,command: Sm2WorldCommand,show_reason: bool=true) -> Button:
	var reason: String=session.world.check(command)
	var value: Button=button(title,id,func() -> void:
		var before: Dictionary=session.view(); var result: Dictionary=session.act(command)
		owner._notice=Sm2JourneyGuideView.feedback(command.kind,before,session.view()) if result.ok else str(result.errors[0])
		if result.ok and command.kind=="start_battle": owner.battle_requested.emit()
		else: owner.redraw())
	value.disabled=not reason.is_empty(); value.tooltip_text=reason; parent.add_child(value)
	if show_reason and not reason.is_empty(): parent.add_child(label(reason,13,Sm2BronzeTheme.MUTED))
	return value

static func control_id(row: Dictionary) -> String:
	match str(row.kind):
		"practice": return "PsiTrain" if row.content=="p5:activity.psionics" else "CampPractice_"+str(row.content).sha256_text().substr(0,12)
		"explore": return "Explore_"+row.content
		"collect_upgrade": return "UpgradeCollect_"+str(row.content).get_slice(".",1)
		"apply_upgrade": return "UpgradeApply_"+str(row.content).get_slice(".",1)
		"incarnate": return "WorldIncarnate%s" % row.target
	return "CampAction_"+str(row.content)

static func frame(parent: Node) -> PanelContainer:
	var panel: PanelContainer=PanelContainer.new(); panel.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.BORDER,12)); parent.add_child(panel); return panel
static func scroll(parent: Node) -> VBoxContainer: return Sm2SurvivalWorkspace.scroll_column(parent,1)
static func label(text: String,font: int,color: Color) -> Label: return Sm2SurvivalWorkspace.label(text,font,color)
static func button(text: String,id: String,callback: Callable) -> Button: return Sm2SurvivalWorkspace.button(text,id,callback)
