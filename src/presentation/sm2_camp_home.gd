class_name Sm2CampHome
extends RefCounted
## Camp hub composition. Existing commands remain in Sm2CampScreen and LifeScreen.
const B=preload("res://src/presentation/sm2_bronze_theme.gd")
var ui: Sm2CampScreen
var surface: Control
var manifest: Dictionary

func build(controller: Sm2CampScreen) -> void:
	ui=controller
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/camp_scene.json"))
	surface=Control.new(); surface.name="CampHome"; ui.owner._content=surface; ui.owner.add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); surface.theme=B.create(); surface.theme.default_font=B.SERIF
	var scene: Sm2CampScene=Sm2CampScene.new(); scene.manifest=manifest; scene.model=Sm2CampSceneView.build(ui.session)
	surface.add_child(scene); place(scene,0.17,0,1,1)
	var shade: ColorRect=ColorRect.new(); shade.color=Color(0.04,0.03,0.02,0.12); shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(shade); place(shade,0.17,0,1,1)
	var left: PanelContainer=panel(0,0,0.17,1,12)
	var rail: VBoxContainer=VBoxContainer.new(); rail.add_theme_constant_override("separation",5); left.add_child(rail)
	var portrait: TextureRect=TextureRect.new(); portrait.name="CampHeroPortrait"
	portrait.texture=scene.art.sprites.get("head_beard") if int(ui.model.hero)!=0 else null
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size.y=180; rail.add_child(portrait)
	rail.add_child(ui.label("Герой" if int(ui.model.hero)!=0 else "Душа без тела",23,B.GOLD))
	if ui.model.busy: rail.add_child(ui.label("Сражение продолжается",14,B.MUTED))
	else:
		for member: Dictionary in ui.model.party:
			if int(member.id)!=int(ui.model.hero): continue
			rail.add_child(ui.label("Кровь · %s / %s мл" % [member.blood,member.blood_max],14,B.TEXT))
			var health: ProgressBar=ProgressBar.new(); health.name="CampBlood"; health.max_value=member.blood_max; health.value=member.blood; health.show_percentage=false; health.custom_minimum_size.y=8; rail.add_child(health)
			health.add_theme_stylebox_override("fill",B.box(Color("853b35"),Color("853b35"),0)); health.add_theme_stylebox_override("background",B.box(Color("272521"),B.DIM_BORDER,0))
			rail.add_child(ui.label("Кровотечение: %s мл/мин" % member.bleeding if int(member.bleeding)>0 else "Кровотечения нет",14,Color("dc987b") if int(member.bleeding)>0 else B.MUTED))
	var current: Button=ui.button("Лагерь","CampHomeSelected",func() -> void: pass); current.disabled=true; current.custom_minimum_size.y=42; rail.add_child(current)
	for entry: Dictionary in manifest.navigation:
		var target: String=entry.action
		var caption: String=Sm2Controls.caption(target,entry.title) if target in ["body","inventory","development","soul","journal"] else str(entry.title)
		var nav: Button=ui.button(caption,entry.id,func() -> void: navigate(target))
		nav.alignment=HORIZONTAL_ALIGNMENT_LEFT; nav.icon=load(entry.icon); nav.expand_icon=true; nav.add_theme_constant_override("icon_max_width",22); nav.custom_minimum_size.y=43
		rail.add_child(nav)
	var spacer: Control=Control.new(); spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL; rail.add_child(spacer)
	rail.add_child(ui.button(Sm2Controls.caption("settings","Настройки"),"CampSettings",func() -> void: ui.owner.settings_requested.emit()))
	rail.add_child(ui.button("Главное меню","WorldMenu",func() -> void: ui.owner.menu_requested.emit()))
	var title: Label=ui.label("ЛАГЕРЬ",36,B.GOLD); surface.add_child(title); place(title,0.195,0.035,0.6,0.10)
	var subtitle: Label=ui.label("Походная стоянка" if not ui.model.busy else "Идёт сражение",18,B.TEXT); surface.add_child(subtitle); place(subtitle,0.197,0.10,0.64,0.15)
	var time: int=int(ui.model.seconds)
	@warning_ignore("integer_division")
	var clock_label: Label=ui.label("День %s · %02d:%02d" % [1+time/86400,(time/3600)%24,(time/60)%60],17,B.TEXT)
	clock_label.name="RegionClock"; clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; surface.add_child(clock_label); place(clock_label,0.76,0.025,0.975,0.065)
	var right: PanelContainer=panel(0.785,0.09,0.98,0.71,14)
	var details: VBoxContainer=ui.scroll(right); details.add_theme_constant_override("separation",12)
	details.add_child(ui.label("МЕСТО СТОЯНКИ",17,B.GOLD))
	for location: Dictionary in ui.model.places:
		if not location.here: continue
		details.add_child(ui.label(location.name,23,B.TEXT)); details.add_child(ui.label(location.description,14,B.MUTED))
	Sm2ExpeditionScreen.card(ui.owner,details)
	details.add_child(ui.button("Выбрать маршрут","CampChooseRoute",func() -> void: navigate("map")))
	if ui.model.busy: details.add_child(ui.button("Вернуться в сражение","WorldBattle",func() -> void: ui.owner.battle_requested.emit()))
	elif int(ui.model.hero)!=0 and ui.session.world.check(ui.session.command("start_battle")).is_empty():
		ui.action(details,"Войти в сражение","WorldBattle",ui.session.command("start_battle"))
	elif int(ui.model.hero)==0: details.add_child(ui.button("Выбрать воплощение","CampIncarnation",ui.owner._open_soul))
	if not ui.session.journey().busy() and not ui.session.journey().receipt.is_empty():
		details.add_child(ui.button("Последний бой","CampBattleResults",func() -> void: ui.owner.battle_requested.emit()))
	var save_row: HBoxContainer=HBoxContainer.new(); details.add_child(save_row)
	for entry: Array in [["Сохранить","WorldSave",ui.owner._save],["Загрузить","WorldLoad",ui.owner._load]]:
		var value: Button=ui.button(entry[0],entry[1],entry[2]); value.size_flags_horizontal=Control.SIZE_EXPAND_FILL; value.add_theme_font_size_override("font_size",14); save_row.add_child(value)
	var dock: PanelContainer=panel(0.22,0.83,0.95,0.94,12)
	var dock_row: HBoxContainer=HBoxContainer.new(); dock_row.add_theme_constant_override("separation",12); dock.add_child(dock_row)
	for entry: Array in [["Отдых","CampRest","","res://assets/hud/wait.svg"],["Лечение","CampTreatment","body","res://assets/hud/bandage.svg"],["Ремесло","CampCraft","","res://assets/hud/hand.svg"],["Припасы","CampSupplies","inventory","res://assets/inventory/backpack.svg"]]:
		var route: String=entry[2]
		var value: Button=ui.button(entry[0],entry[1],func() -> void: navigate(route))
		value.icon=load(entry[3]); value.expand_icon=true; value.add_theme_constant_override("icon_max_width",34); value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		value.disabled=route.is_empty() or bool(ui.model.busy); value.tooltip_text="Занятие пока недоступно." if route.is_empty() else "Доступно вне боя" if ui.model.busy else ""
		dock_row.add_child(value)
	var notice: Label=ui.label(ui.owner._notice,14,B.GOLD); notice.name="CampNotice"
	if ui.session._store is Sm2CampaignStore and (ui.session._store as Sm2CampaignStore).recovered: notice.text="Загружена резервная копия. Сохраните игру для восстановления основного файла. "+notice.text
	surface.add_child(notice); place(notice,0.22,0.947,0.975,0.995)

func navigate(target: String) -> void:
	match target:
		"body": ui.open_body(int(ui.model.hero),0)
		"inventory": ui.open_body(int(ui.model.hero),1)
		"development": ui.owner.development_requested.emit()
		"soul": ui.owner._open_soul()
		"journal": ui.owner._open_journal()
		"map", "activities": ui.owner._camp_page=target; ui.owner.redraw()

func panel(left: float,top: float,right: float,bottom: float,padding: int) -> PanelContainer:
	var value: PanelContainer=PanelContainer.new(); value.add_theme_stylebox_override("panel",B.box(Color(0.045,0.043,0.036,0.94),B.BORDER,padding))
	surface.add_child(value); place(value,left,top,right,bottom); return value

static func place(node: Control,left: float,top: float,right: float,bottom: float) -> void:
	node.anchor_left=left; node.anchor_top=top; node.anchor_right=right; node.anchor_bottom=bottom
