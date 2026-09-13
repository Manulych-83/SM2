class_name Sm2StartScreen
extends RefCounted
const B: GDScript=preload("res://src/presentation/sm2_bronze_theme.gd")

static func build(owner: Control) -> void:
	var host: Control=owner._body; host.theme=B.create()
	var background: TextureRect=TextureRect.new(); background.name="MenuIllustration"
	background.texture=preload("res://assets/start_screen/valley.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; host.add_child(background)
	var heading: Label=label("S M 2",46,B.TEXT); heading.add_theme_font_override("font",B.SERIF)
	heading.position=Vector2(36,26); heading.size=Vector2(300,80); host.add_child(heading)
	var panel: PanelContainer=PanelContainer.new(); panel.name="MainStartPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left=-552; panel.offset_top=-682; panel.offset_right=-32; panel.offset_bottom=-32
	panel.add_theme_stylebox_override("panel",B.box(Color(0.06,0.045,0.03,0.94),B.BORDER,22)); host.add_child(panel)
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.name="MenuScroll"; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.add_child(scroll)
	var actions: VBoxContainer=VBoxContainer.new(); actions.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_theme_constant_override("separation",12); scroll.add_child(actions)
	actions.add_child(label("ОТ ЧЕЛОВЕКА К СВЕРХСУЩЕСТВУ",14,B.GOLD))
	var rows: Array[Dictionary]=owner._campaigns().inspect()
	var latest: int=Sm2Campaigns.latest(rows,owner._campaigns().selected())
	var caption: String="Продолжить поход" if latest<0 else "Продолжить · Кампания "+str(latest+1)
	actions.add_child(owner._button(caption,"ContinueSurvivalTissuesButton",owner._start_survival_tissues.bind(true),latest<0,true))
	actions.add_child(owner._button("Новая кампания","NewSurvivalTissuesButton",owner._start_survival_tissues.bind(false)))
	actions.add_child(owner._button("Кампании · выбрать сохранение","CampaignsButton",owner._show_campaigns))
	actions.add_child(owner._button("Вернуться в начатую игру","ResumeMainButton",owner._resume_main,owner._life==null))
	var live: Label=label(current_text(owner._life),14,B.PSI); live.name="MenuCurrentGame"; actions.add_child(live)
	var note: Label=label("Продолжить — последнее доступное сохранение. Вернуться — текущая игра без загрузки. Новая кампания займёт пустой слот; сохраняйте её в лагере.",14,B.MUTED); note.name="MenuSaveHint"; actions.add_child(note)
	actions.add_child(owner._button("Дополнительные режимы","OtherModesButton",owner._toggle_modes))
	actions.add_child(owner._button(Sm2Controls.caption("settings","Настройки и управление"),"SettingsButton",owner._open_settings.bind("menu")))
	actions.add_child(owner._button("Выйти из игры","QuitButton",owner._quit_game))
	var status: Label=label(owner._notice,14,Color("f0a491") if owner._is_error else B.GOLD); status.name="StatusLabel"; status.visible=not owner._notice.is_empty(); actions.add_child(status)
	actions.add_child(label("Ранняя версия · "+str(ProjectSettings.get_setting("application/config/version")),12,B.MUTED))
	# Current demos by default; historical controls require the explicit compatibility launch.
	var extra: VBoxContainer=dialog(host,"OtherModesOverlay",Vector2(1050,730)); extra.get_parent().get_parent().visible=owner._modes_expanded
	extra.add_child(owner._button("Закрыть дополнительные режимы","CloseModesButton",owner._toggle_modes))
	var modes_scroll: ScrollContainer=ScrollContainer.new(); modes_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; modes_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; extra.add_child(modes_scroll)
	var modes: BoxContainer=VBoxContainer.new() if host.get_viewport_rect().size.x<1200 else HBoxContainer.new(); modes.size_flags_horizontal=Control.SIZE_EXPAND_FILL; modes_scroll.add_child(modes)
	var left: VBoxContainer=VBoxContainer.new(); left.name="OtherModesLeft"; modes.add_child(left)
	var right: VBoxContainer=VBoxContainer.new(); right.name="OtherModesRight"; modes.add_child(right)
	owner._build_other_modes(left,right)
	if owner._campaigns_open: campaigns(owner,rows)
	if owner._campaign_delete>=0: deletion(owner)

static func dialog(host: Control,id: String,dimensions: Vector2) -> VBoxContainer:
	dimensions=dimensions.min(host.get_viewport_rect().size-Vector2(40,40))
	var overlay: Control=Control.new(); overlay.name=id; overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host.add_child(overlay)
	var shade: ColorRect=ColorRect.new(); shade.color=Color(0,0,0,0.72); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.add_child(shade)
	var panel: PanelContainer=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-dimensions.x/2; panel.offset_top=-dimensions.y/2; panel.offset_right=dimensions.x/2; panel.offset_bottom=dimensions.y/2
	panel.add_theme_stylebox_override("panel",B.box(B.PANEL,B.BORDER,20)); overlay.add_child(panel)
	var column: VBoxContainer=VBoxContainer.new(); column.add_theme_constant_override("separation",12); panel.add_child(column); return column

static func campaigns(owner: Control,rows: Array[Dictionary]) -> void:
	var column: VBoxContainer=dialog(owner._body,"CampaignChooser",Vector2(820,720))
	column.add_child(label("КАМПАНИИ",26,B.GOLD))
	column.add_child(label("Каждый слот — отдельный мир со всеми воплощениями Души.",16,B.MUTED))
	var selected: int=owner._campaigns().selected()
	for row: Dictionary in rows:
		var panel: PanelContainer=PanelContainer.new(); panel.add_theme_stylebox_override("panel",B.box(B.BUTTON,B.GOLD if selected==row.index else B.BORDER,12)); column.add_child(panel)
		var body: VBoxContainer=VBoxContainer.new(); body.add_theme_constant_override("separation",6); panel.add_child(body)
		var header: HBoxContainer=HBoxContainer.new(); body.add_child(header)
		var choose: Button=owner._button(row.title+(" · выбрана" if selected==row.index else ""),"CampaignSelect_"+str(row.index),owner._select_campaign.bind(row.index)); choose.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(choose)
		if row.occupied:
			header.add_child(owner._button("Удалить","CampaignDelete_"+str(row.index),owner._request_campaign_delete.bind(row.index,row.token)))
		var text: String="Пустой слот" if not row.occupied else "Сохранение повреждено или несовместимо"
		if row.ok: text=("Резервная копия · " if row.recovered else "Сохранено · ")+row.date+"\n"+row.location+" · "+row.state+"\nПолная проверка — при загрузке."
		var info: Label=label(text,15,B.PSI if row.recovered else B.MUTED); info.name="CampaignInfo_"+str(row.index); body.add_child(info)
		body.add_child(owner._button("Восстановить резервную копию" if row.recovered else "Загрузить" if row.occupied else "Начать кампанию","CampaignOpen_"+str(row.index),owner._open_campaign.bind(row.index,row.occupied),row.occupied and not row.ok))
	if not owner._notice.is_empty(): column.add_child(label(owner._notice,14,Color("f0a491")))
	column.add_child(owner._button("Закрыть","CampaignClose",func() -> void: owner._campaigns_open=false; owner._redraw_page()))

static func deletion(owner: Control) -> void:
	var column: VBoxContainer=dialog(owner._body,"CampaignDeleteDialog",Vector2(610,300))
	column.add_child(label("Удалить кампанию "+str(owner._campaign_delete+1)+"?",25,B.GOLD))
	column.add_child(label("Будут удалены сохранение этого мира и его резервная копия. Начатая игра этой кампании тоже закроется. Отменить удаление нельзя.",17,B.TEXT))
	column.add_child(owner._button("Отмена","CampaignCancelDelete",func() -> void: owner._campaign_delete=-1; owner._redraw_page()))
	column.add_child(owner._button("Удалить кампанию","CampaignConfirmDelete",owner._confirm_campaign_delete))

static func current_text(session: Sm2LifeSession) -> String:
	if session==null: return "Сейчас нет начатой игры."
	if session is Sm2JourneySession:
		var view: Dictionary=Sm2CampView.build(session as Sm2JourneySession)
		if not view.is_empty():
			var place: String=view.location
			for entry: Dictionary in view.places:
				if entry.here: place=entry.name
			var state: String="В сражении" if view.busy else ("Душа ищет тело" if not view.hero else "Вне боя")
			return "Начатый поход · %s\n%s · Завершено встреч: %s/%s" % [place,state,view.completed,view.total]
	return "Начат прежний пример. «Вернуться» откроет его; сохранённый поход загружается отдельно."

static func label(text: String,size: int,color: Color) -> Label:
	var value: Label=Label.new(); value.text=text; value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size",size); value.add_theme_color_override("font_color",color)
	return value
