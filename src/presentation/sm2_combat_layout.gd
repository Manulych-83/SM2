class_name Sm2CombatLayout
extends RefCounted
## Spatial composition only. All actions and actor data stay in the HUD/session.
var hud: Sm2CombatHud:
	get: return owner.hud
var owner: Sm2BattleScreen
var header: PanelContainer
var queue: ScrollContainer
var utilities: GridContainer
var party: ScrollContainer
var sidebar: VBoxContainer
var actor_card: PanelContainer
var dock: PanelContainer
var control_panel: PanelContainer
var active_name: Label
var active_status: Label
var active_values: Label
var active_portrait: TextureRect
var active_ap: ProgressBar
var action_scroll: ScrollContainer
var categories: HBoxContainer

func build(value: Sm2CombatHud) -> void:
	owner=value.screen
	var bg: ColorRect=ColorRect.new(); bg.color=Color("13130f"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.mouse_filter=Control.MOUSE_FILTER_IGNORE; owner.add_child(bg)
	owner.board=Sm2HexBoard.new(); owner.board.name="Battlefield"; owner.add_child(owner.board); owner.board.enable_art(); hud.art=owner.board.art
	owner.board.panel_style=Sm2BronzeTheme.box(Color("13130f"),Color("13130f"),0)
	owner.board.cell_clicked.connect(owner._clicked); owner.board.cell_hovered.connect(owner._hovered)
	header=frame("HudHeaderFrame"); var titles: VBoxContainer=VBoxContainer.new(); header.add_child(titles)
	owner._title=Sm2CombatHud.label("",20,Sm2BronzeTheme.GOLD); owner._title.add_theme_font_override("font",Sm2BronzeTheme.SERIF); titles.add_child(owner._title)
	owner._queue=Sm2CombatHud.label("",12,Sm2BronzeTheme.MUTED); owner._queue.name="TurnQueue"; owner._queue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; titles.add_child(owner._queue)
	queue=ScrollContainer.new(); queue.name="HudQueue"; queue.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; owner.add_child(queue)
	var centered: CenterContainer=CenterContainer.new(); centered.size_flags_horizontal=Control.SIZE_EXPAND_FILL; queue.add_child(centered)
	hud.queue_row=HBoxContainer.new(); hud.queue_row.add_theme_constant_override("separation",6); centered.add_child(hud.queue_row)
	utilities=GridContainer.new(); utilities.columns=3; owner.add_child(utilities)
	for item: Array in [["Развитие","DevelopmentButton",owner._open_development],["Сохранить","SaveBattleButton",owner._save],["Загрузить","LoadBattleButton",owner._load],["Журнал","HudJournal",hud.open_tab.bind(1)],["Детали","HudDetails",owner._open_details_or_results],["Меню","BattleMenuButton",func() -> void: owner._path.clear(); owner.menu_requested.emit()]]:
		var button: Button=Sm2CombatHud.button(item[0],item[1],item[2]); button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; utilities.add_child(button)
	party=ScrollContainer.new(); party.name="HudParty"; party.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; owner.add_child(party)
	hud.party_column=VBoxContainer.new(); hud.party_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; hud.party_column.add_theme_constant_override("separation",10); party.add_child(hud.party_column)
	sidebar=VBoxContainer.new(); sidebar.name="HudContext"; owner.add_child(sidebar); hud.context_panel=sidebar
	var card: PanelContainer=PanelContainer.new(); card.name="HudActorFrame"; card.add_theme_stylebox_override("panel",Sm2CombatHud.box()); sidebar.add_child(card)
	var details: VBoxContainer=VBoxContainer.new(); card.add_child(details)
	var identity: HBoxContainer=HBoxContainer.new(); details.add_child(identity)
	hud.portrait=TextureRect.new(); hud.portrait.custom_minimum_size=Vector2(44,52); hud.portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; hud.portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; identity.add_child(hud.portrait)
	var text: VBoxContainer=VBoxContainer.new(); text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; identity.add_child(text)
	hud.person=Sm2CombatHud.label("",17,Sm2BronzeTheme.GOLD); hud.person.name="HudActorName"; hud.person.clip_text=true; text.add_child(hud.person)
	hud.status=Sm2CombatHud.label("",12,Sm2BronzeTheme.MUTED); hud.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; text.add_child(hud.status)
	var close: Button=Sm2CombatHud.button("×","HudCloseContext",hud.close_context); close.custom_minimum_size=Vector2(26,28); identity.add_child(close)
	hud.resources=GridContainer.new(); hud.resources.columns=2; details.add_child(hud.resources)
	hud.tabs=TabContainer.new(); hud.tabs.name="HudInformation"; hud.tabs.custom_minimum_size=Vector2(258,110); hud.tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; sidebar.add_child(hud.tabs)
	owner._preview=hud.page("Прогноз","ActionPreview",14)
	owner._log=hud.page("Журнал","BattleLog",13); owner._log.scroll_following=true
	owner._inspector=hud.page("Детали","ActorDetails",15,true)
	hud.tabs.tab_changed.connect(func(index: int) -> void: hud.resources.visible=index!=2; relayout())
	sidebar.hide()
	actor_card=frame("HudActiveActor"); var active: VBoxContainer=VBoxContainer.new(); actor_card.add_child(active)
	var active_top: HBoxContainer=HBoxContainer.new(); active.add_child(active_top)
	active_portrait=TextureRect.new(); active_portrait.custom_minimum_size=Vector2(44,48); active_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; active_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; active_top.add_child(active_portrait)
	var active_text: VBoxContainer=VBoxContainer.new(); active_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; active_top.add_child(active_text)
	active_name=Sm2CombatHud.label("",18,Sm2BronzeTheme.GOLD); active_name.name="HudActiveName"; active_name.clip_text=true; active_text.add_child(active_name)
	active_status=Sm2CombatHud.label("",12,Sm2BronzeTheme.MUTED); active_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; active_text.add_child(active_status)
	active_ap=ProgressBar.new(); active_ap.custom_minimum_size.y=7; active_ap.show_percentage=false; active_ap.add_theme_stylebox_override("fill",Sm2BronzeTheme.box(Sm2BronzeTheme.GOLD,Sm2BronzeTheme.GOLD,0)); active.add_child(active_ap)
	active_values=Sm2CombatHud.label("",12,Sm2BronzeTheme.TEXT); active_values.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; active.add_child(active_values)
	dock=frame("HudActionsFrame"); var action_column: VBoxContainer=VBoxContainer.new(); dock.add_child(action_column)
	action_scroll=ScrollContainer.new(); action_scroll.name="HudActionScroll"; action_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; action_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; action_column.add_child(action_scroll)
	owner._actions=HBoxContainer.new(); owner._actions.name="BattleActions"; owner._actions.add_theme_constant_override("separation",6); action_scroll.add_child(owner._actions)
	var category_scroll: ScrollContainer=ScrollContainer.new(); category_scroll.custom_minimum_size.y=37; category_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; action_column.add_child(category_scroll)
	categories=HBoxContainer.new(); category_scroll.add_child(categories)
	for item: Array in [["main","Основные"],["aimed","Прицельные"],["psi","Псионика"],["help","Помощь"],["all","Все"]]:
		var button: Button=Sm2CombatHud.button(item[1],"HudCategory_"+item[0],hud.set_category.bind(item[0])); button.custom_minimum_size.y=28; button.add_theme_font_size_override("font_size",12); categories.add_child(button)
	control_panel=frame("HudTurnControls"); hud.controls=VBoxContainer.new(); control_panel.add_child(hud.controls)
	owner._notice=Sm2CombatHud.label("",12,Sm2BronzeTheme.GOLD); owner._notice.name="BattleNotice"; owner._notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; owner.add_child(owner._notice)
	owner.resized.connect(relayout); relayout()

func frame(id: String) -> PanelContainer:
	var panel: PanelContainer=PanelContainer.new(); panel.name=id; panel.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.BORDER,8)); owner.add_child(panel); return panel

func rect(node: Control,x: float,y: float,w: float,h: float) -> void:
	node.position=Vector2(x,y); node.size=Vector2(w,h)

func relayout() -> void:
	var w: float=owner.size.x; var h: float=owner.size.y
	var left: float=92 if w>=1200 else 76
	var right: float=296 if w>=1200 else 258
	var hero: float=300 if w>=1200 else 234
	var end: float=164 if w>=1200 else 138
	var bottom: float=h-208
	rect(header,12,12,232,85); rect(queue,260,12,maxf(170,w-558),116)
	rect(utilities,w-286,12,274,82)
	rect(party,12,132,left,bottom-146)
	rect(owner.board,left+28,122,w-left-right-56,bottom-136)
	var context_y: float=132 if hud.tabs.current_tab==2 else maxf(132,bottom-440)
	rect(sidebar,w-right-12,context_y,right,bottom-context_y-14)
	rect(actor_card,12,bottom,hero,170)
	rect(dock,hero+24,bottom,w-hero-end-48,170)
	rect(control_panel,w-end-12,bottom,end,170)
	rect(owner._notice,12,h-30,w-24,28)

func refresh_active(actor: Dictionary) -> void:
	var data: Dictionary=Sm2CombatHudView.card(actor)
	if data.is_empty(): return
	active_name.text=data.name; active_portrait.texture=hud.portrait_texture()
	active_status.text="ОД %s/%s · %s" % [data.ap[0],data.ap[1],Sm2BattleText.MORALE.get(data.morale,data.morale)]
	active_ap.max_value=maxi(1,int(data.ap[1])); active_ap.value=data.ap[0]
	active_values.text="Усталость %s/%s · Конц. %s/%s\nСостояние %s/%s · Пси-щит %s\nКровотечение %s мл/мин" % [data.fatigue[0],data.fatigue[1],data.focus[0],data.focus[1],data.condition[0],data.condition[1],data.barrier,data.bleeding]
	active_values.tooltip_text="Состояние — сводка анатомии. Кровь: %s мл.\nПолная анатомия доступна через «Детали»." % data.blood
