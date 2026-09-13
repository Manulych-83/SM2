extends Control
## A small working front end. All game changes go through Sm2Session.

const Backdrop: GDScript = preload("res://src/presentation/sm2_backdrop.gd")
const INK: Color = Color("e9e8de")
const MUTED: Color = Color("a3b0b4")
const GOLD: Color = Color("d1b478")
var _session: Sm2Session
var _page: String = "menu"
var _modes_expanded: bool=false
var _campaign_service: Sm2Campaigns
var _campaigns_open: bool=false
var _campaign_delete: int=-1
var _campaign_delete_step: int=0
var _campaign_token: String=""
var _start_resize_pending: bool=false
var _settings_return: String="menu"
var _expedition_seen: Dictionary={}
var _notice: String = ""
var _is_error: bool = false
var _body: Control
var _battle: Sm2BattleRunner = null
var _progress: Sm2ProgressSession = null
var _attributes: Sm2ProgressSession = null
var _life: Sm2LifeSession = null
var _journey_store: Sm2SaveStore = Sm2SaveStore.new("user://journey")
var _life_store: Sm2SaveStore = Sm2SaveStore.new("user://world")
var _exploration_store: Sm2SaveStore=Sm2SaveStore.new("user://exploration_journey")
var _search_store: Sm2SaveStore=Sm2SaveStore.new("user://search_journey")
var _hybrid_store: Sm2SaveStore=Sm2SaveStore.new("user://hybrid_journey")
var _survival_tissues_store: Sm2SaveStore=Sm2SaveStore.new("user://survival_tissues")
var _survival_devices_store: Sm2SaveStore=Sm2SaveStore.new("user://survival_devices")
var _survival_store: Sm2SaveStore=Sm2SaveStore.new("user://survival_journey")
var _region_store: Sm2SaveStore=Sm2SaveStore.new("user://region_journey")
var _implant_store: Sm2SaveStore=Sm2SaveStore.new("user://implant_journey")
var _upgrade_store: Sm2SaveStore=Sm2SaveStore.new("user://upgrade_journey")
var _psionic_shield_store: Sm2SaveStore=Sm2SaveStore.new("user://psionic_shield_journey")
var _psionic_growth_store: Sm2SaveStore=Sm2SaveStore.new("user://psionic_growth_journey")
var _psionic_store: Sm2SaveStore=Sm2SaveStore.new("user://psionic_journey")
var _discovery_store: Sm2SaveStore=Sm2SaveStore.new("user://discovery_journey")
var _care_store: Sm2SaveStore=Sm2SaveStore.new("user://care_journey")
var _prosthesis_store: Sm2SaveStore=Sm2SaveStore.new("user://prosthesis_journey")
var _body_store: Sm2SaveStore=Sm2SaveStore.new("user://body_journey")
var _party_store: Sm2SaveStore=Sm2SaveStore.new("user://party_journey")
var _development_store: Sm2SaveStore = Sm2SaveStore.new("user://development")
var _magic_store: Sm2SaveStore = Sm2SaveStore.new("user://magic")
var _area_store: Sm2SaveStore = Sm2SaveStore.new("user://areas")
var _effects_store: Sm2SaveStore = Sm2SaveStore.new("user://effects")
var _sequence_store: Sm2SaveStore = Sm2SaveStore.new("user://effect_sequences")
var _creature_content: Dictionary = {}
var _creature_page: int = 0
var _battle_store: Sm2SaveStore = Sm2SaveStore.new("user://battles")

func _ready() -> void:
	Sm2Controls.initialize()
	var display: Dictionary=Sm2DisplayPreferences.new().read()
	if display.ok and display.exists: Sm2DisplaySettings.apply(get_window(),display.value)
	resized.connect(_resize_start)
	_apply_theme()
	var result: Dictionary = Sm2ContentLoader.load_catalog()
	if result.get("ok", false):
		var catalog: Sm2Catalog = result["catalog"]
		_session = Sm2Session.new(catalog, Sm2SaveStore.new())
	else:
		_notice = "Не удалось загрузить игру.\n" + "\n".join(result.get("errors", PackedStringArray()))
		_is_error = true
	_redraw_page()

func _apply_theme() -> void:
	var game_theme: Theme = Theme.new()
	game_theme.default_font_size = 16
	game_theme.set_color("font_color", "Label", INK)
	game_theme.set_color("font_color", "Button", INK)
	game_theme.set_color("font_disabled_color", "Button", Color("65767d"))
	game_theme.set_color("font_hover_color", "Button", Color.WHITE)
	game_theme.set_constant("outline_size", "Label", 0)
	game_theme.set_constant("separation", "VBoxContainer", 14)
	game_theme.set_constant("separation", "HBoxContainer", 24)
	game_theme.set_stylebox("normal", "Button", _box(Color("22333b"), Color("40525b"), 8, 10))
	game_theme.set_stylebox("hover", "Button", _box(Color("2e434d"), GOLD, 8, 10))
	game_theme.set_stylebox("pressed", "Button", _box(Color("17272f"), GOLD, 8, 10))
	game_theme.set_stylebox("disabled", "Button", _box(Color("172329"), Color("29383f"), 8, 10))
	game_theme.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, GOLD, 8, 3))
	theme = game_theme

func _redraw_page() -> void:
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	_body = Control.new()
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_body)
	if _page=="settings":
		var settings: Sm2SettingsScreen=Sm2SettingsScreen.new(); settings.name="SettingsScreen"
		settings.closed.connect(func() -> void: _page=_settings_return; _redraw_page())
		_body.add_child(settings); return
	if _page == "life" and _life != null:
		var life_screen: Sm2LifeScreen=Sm2LifeScreen.new()
		life_screen.name="LifeScreen"; life_screen.session=_life
		life_screen.expedition_seen=_expedition_seen
		life_screen.menu_requested.connect(_show_menu)
		life_screen.settings_requested.connect(_open_settings.bind("life"))
		life_screen.development_requested.connect(func() -> void: _page="hero_development"; _redraw_page())
		life_screen.battle_requested.connect(func() -> void: _page="life_battle"; _redraw_page())
		_body.add_child(life_screen)
		return
	if _page == "hero_development" and _life != null:
		var hero_screen: Sm2HeroDevelopmentScreen=Sm2HeroDevelopmentScreen.new()
		hero_screen.name="HeroDevelopmentScreen"; hero_screen.session=_life
		hero_screen.camp_requested.connect(func() -> void: _page="life"; _redraw_page())
		_body.add_child(hero_screen)
		return
	if _page == "life_battle" and _life != null:
		var life_battle: Sm2BattleScreen=Sm2BattleScreen.new()
		life_battle.name="BattleScreen"; life_battle.life_session=_life; life_battle.runner=_life.runner
		life_battle.menu_requested.connect(func() -> void: _page="life"; _redraw_page())
		life_battle.aftermath_requested.connect(func(tab: int,body_id: int) -> void:
			if _life==null or _life.world.busy(): return
			_page="life"; _redraw_page()
			var target: Sm2LifeScreen=_body.find_child("LifeScreen",true,false) as Sm2LifeScreen
			target._workspace_state={"body":body_id,"tab":tab,"part":"","item":"","destination":"","scope":0,"query":""}
			target._open_workspace())
		_body.add_child(life_battle)
		return
	if _page == "attributes" and _attributes != null:
		var attribute_screen: Sm2AttributeScreen = Sm2AttributeScreen.new()
		attribute_screen.name="AttributeScreen"; attribute_screen.session=_attributes
		attribute_screen.menu_requested.connect(_show_menu); _body.add_child(attribute_screen)
		return
	if _page == "progress" and _progress != null:
		var progress_screen: Sm2ProgressScreen = Sm2ProgressScreen.new()
		progress_screen.name="ProgressScreen"; progress_screen.session=_progress
		progress_screen.menu_requested.connect(_show_menu)
		_body.add_child(progress_screen)
		return
	if _page == "battle" and _battle != null:
		var screen: Sm2BattleScreen = Sm2BattleScreen.new()
		screen.name = "BattleScreen"
		screen.runner = _battle
		screen.menu_requested.connect(_show_menu)
		_body.add_child(screen)
		return
	if _page == "menu":
		Sm2StartScreen.build(self)
		return
	var backdrop: Control = Control.new()
	backdrop.set_script(Backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(backdrop)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 44)
	for side: String in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 30)
	_body.add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margins.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_child(_label("S M 2", 26, GOLD))
	var version: Label = _label("ТАКТИЧЕСКАЯ РОЛЕВАЯ ИГРА  /  РАННЯЯ ВЕРСИЯ", 12, MUTED)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(version)
	column.add_child(header)
	var separator: HSeparator = HSeparator.new()
	separator.modulate = Color("4a575c")
	column.add_child(separator)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 46)
	if _page=="party":
		column.add_child(row)
	else:
		var menu_scroll: ScrollContainer=ScrollContainer.new()
		menu_scroll.name="MenuScroll"
		menu_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.add_child(menu_scroll); menu_scroll.add_child(row)
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation",10)
	left.custom_minimum_size.x = 330
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	row.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 340
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	if _page == "party" and _session != null and _session.has_active_game():
		_build_party(left, right)
	else:
		_build_other_modes(left, right)
	var status: Label = _label(_notice, 14, Color("f0a491") if _is_error else GOLD)
	status.name = "StatusLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 0 if _notice.is_empty() else 40
	column.add_child(status)
	var footer: Label = _label("Герой и спутник · Пошаговые бои · Раздельные сохранения", 13, MUTED)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footer)

func _open_settings(return_page: String="menu") -> void:
	_settings_return=return_page; _page="settings"; _redraw_page()

func _resize_start() -> void:
	if _page!="menu" or _start_resize_pending: return
	_start_resize_pending=true; call_deferred("_reflow_start")

func _reflow_start() -> void:
	_start_resize_pending=false
	if is_inside_tree() and _page=="menu": _redraw_page()

func _unhandled_key_input(event: InputEvent) -> void:
	if _page=="menu" and not _modes_expanded and not _campaigns_open and _campaign_delete<0 and not Sm2Controls.text_focused(self) and Sm2Controls.action(event)=="settings":
		get_viewport().set_input_as_handled(); _open_settings(); return
	if _page!="menu" or not event is InputEventKey or not event.pressed or event.echo or event.physical_keycode!=KEY_ESCAPE: return
	if _campaign_delete>=0: _campaign_delete=-1; _campaign_delete_step=0
	elif _campaigns_open: _campaigns_open=false
	elif _modes_expanded: _modes_expanded=false
	else: return
	get_viewport().set_input_as_handled(); _redraw_page()

func _resume_main() -> void:
	if _life == null: return
	_page="life"; _campaigns_open=false; _notice=""; _is_error=false; _redraw_page()

func _toggle_modes() -> void:
	_modes_expanded=not _modes_expanded
	_redraw_page()

func _campaigns() -> Sm2Campaigns:
	if _campaign_service==null: _campaign_service=Sm2Campaigns.new(_survival_tissues_store._base_directory)
	return _campaign_service

func _show_campaigns() -> void:
	_campaigns_open=true; _campaign_delete=-1; _redraw_page()

func _select_campaign(index: int) -> void:
	if not _campaigns().select(index): _notice="Не удалось запомнить выбранную кампанию."
	_redraw_page()

func _open_campaign(index: int,from_save: bool) -> void:
	var result: Dictionary=_campaigns().open(index,from_save)
	if _handle_result(result,""):
		_life=result.session; _page="life"; _campaigns_open=false; _campaign_delete=-1
		_campaigns().select(index)
	_redraw_page()

func _request_campaign_delete(index: int,token: String) -> void:
	_campaign_delete=index; _campaign_token=token; _campaign_delete_step=1; _redraw_page()

func _advance_campaign_delete(index: int,token: String) -> void:
	if _campaign_delete_step!=1 or index!=_campaign_delete or token!=_campaign_token: return
	if _campaigns().token(index)!=token:
		_campaign_delete=-1; _campaign_delete_step=0; _notice="Сохранение изменилось. Выберите его заново."; _is_error=true
	else: _campaign_delete_step=2
	_redraw_page()

func _confirm_campaign_delete(index: int,token: String) -> void:
	if _campaign_delete_step!=2 or index!=_campaign_delete or token!=_campaign_token: return
	var result: Dictionary=_campaigns().delete(index,token)
	if _handle_result(result,"Кампания удалена.") and _life!=null and _life._store is Sm2CampaignStore:
		if (_life._store as Sm2CampaignStore).campaign_index==index: _life=null
	_campaign_delete=-1; _campaign_delete_step=0; _redraw_page()

func _update_modes_button() -> void:
	var button: Button=_body.find_child("OtherModesButton",true,false) as Button
	if button!=null: button.text="Скрыть дополнительные режимы" if _modes_expanded else "Дополнительные режимы"

func _build_other_modes(left: VBoxContainer, right: VBoxContainer) -> void:
	if OS.get_environment("SM2_LEGACY_DEMOS") == "1":
		_build_legacy_modes(left,right)
		return
	left.add_child(_label("ДОПОЛНИТЕЛЬНЫЕ РЕЖИМЫ",12,GOLD))
	left.add_child(_label("Отдельные сражения",23,INK))
	var description: Label = _label("Здесь можно попробовать новые боевые возможности. У каждой встречи своё сохранение.",16,MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(description)
	if _battle != null:
		left.add_child(_button("Вернуться на поле","ResumeBattleButton",_resume_battle))
	_build_current_modes(right)

func _build_current_modes(right: VBoxContainer) -> void:
	var row_sequences: HBoxContainer = HBoxContainer.new()
	right.add_child(row_sequences)
	row_sequences.add_child(_button("Составные воздействия", "NewSequencesButton", _start_effects.bind(false,true)))
	row_sequences.add_child(_button("Продолжить", "ContinueSequencesButton", _start_effects.bind(true,true),not _sequence_store.has_slot(Sm2BattleRunner.EFFECT_SLOT)))
	if _creature_content.is_empty(): _creature_content = Sm2CreatureContentLoader.load_catalog()
	if _creature_content.ok:
		right.add_child(_label("ВСТРЕЧИ ИЗ ШАБЛОНОВ",12,GOLD))
		var creature_ids: Array[String] = _creature_content.catalog.encounters()
		for index: int in range(_creature_page*12,mini((_creature_page+1)*12,creature_ids.size())):
			var id: String = creature_ids[index]
			var row: HBoxContainer = HBoxContainer.new(); right.add_child(row)
			row.add_child(_button(_creature_content.catalog.encounter(id).name,"NewCreature_%s" % index,_start_creatures.bind(id,false)))
			row.add_child(_button("Продолжить","ContinueCreature_%s" % index,_start_creatures.bind(id,true),not _creature_store(id).has_slot(Sm2BattleRunner.EFFECT_SLOT)))
		if creature_ids.size() > 12:
			var pages: HBoxContainer = HBoxContainer.new(); right.add_child(pages)
			pages.add_child(_button("Предыдущие","CreaturePrevious",_show_creature_page.bind(_creature_page-1),_creature_page == 0))
			pages.add_child(_button("Следующие","CreatureNext",_show_creature_page.bind(_creature_page+1),(_creature_page+1)*12 >= creature_ids.size()))


func _build_legacy_modes(left: VBoxContainer, right: VBoxContainer) -> void:
	left.add_child(_button("Тело и протезы","NewSurvivalDevicesButton",_start_survival_devices.bind(false),false,true))
	left.add_child(_button("Продолжить с протезами","ContinueSurvivalDevicesButton",_start_survival_devices.bind(true),not _survival_devices_store.has_slot("survival_devices")))
	left.add_child(_button("Тело и инвентарь · новый пример","NewSurvivalButton",_start_survival.bind(false),false,true))
	left.add_child(_button("Продолжить пример тела","ContinueSurvivalButton",_start_survival.bind(true),not _survival_store.has_slot("survival_journey")))
	left.add_child(_button("Малая карта · прежний пример","NewRegionButton",_start_region.bind(false),false,true))
	left.add_child(_button("Продолжить пример карты","ContinueRegionButton",_start_region.bind(true),not _region_store.has_slot(Sm2JourneySession.REGION_SLOT)))
	left.add_theme_constant_override("separation",6)
	right.add_theme_constant_override("separation",8)
	left.add_child(_label("ДОПОЛНИТЕЛЬНЫЕ РЕЖИМЫ",12,GOLD))
	left.add_child(_label("Отдельные сохранения",23,INK))
	var description: Label = _label("Каждый режим продолжает свою отдельную игру.", 16, MUTED)
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	left.add_child(description)
	var implant_row: HBoxContainer=HBoxContainer.new(); left.add_child(implant_row)
	var hybrid_row: HBoxContainer=HBoxContainer.new(); left.add_child(hybrid_row)
	hybrid_row.add_child(_button("Три пути: псионический удар","NewHybridButton",_start_hybrids.bind(false),false,true))
	hybrid_row.add_child(_button("Продолжить","ContinueHybridButton",_start_hybrids.bind(true),not _hybrid_store.has_slot(Sm2JourneySession.HYBRID_SLOT)))
	implant_row.add_child(_button("Три пути: пси-усилитель","NewImplantButton",_start_implants.bind(false),false,true))
	implant_row.add_child(_button("Продолжить","ContinueImplantButton",_start_implants.bind(true),not _implant_store.has_slot(Sm2JourneySession.IMPLANT_SLOT)))
	var upgrade_row: HBoxContainer=HBoxContainer.new(); left.add_child(upgrade_row)
	upgrade_row.add_child(_button("Генетика и псионика","NewUpgradeButton",_start_upgrades.bind(false),false,true))
	upgrade_row.add_child(_button("Продолжить","ContinueUpgradeButton",_start_upgrades.bind(true),not _upgrade_store.has_slot(Sm2JourneySession.UPGRADE_SLOT)))
	var psionic_shield_row: HBoxContainer=HBoxContainer.new(); left.add_child(psionic_shield_row)
	psionic_shield_row.add_child(_button("Псионика: атака и защита","NewPsionicShieldButton",_start_psionic_shield.bind(false),false,true))
	psionic_shield_row.add_child(_button("Продолжить","ContinuePsionicShieldButton",_start_psionic_shield.bind(true),not _psionic_shield_store.has_slot(Sm2JourneySession.PSIONIC_SHIELD_SLOT)))
	var psionic_growth_row: HBoxContainer=HBoxContainer.new(); left.add_child(psionic_growth_row)
	psionic_growth_row.add_child(_button("Псионика: сила развития","NewPsionicGrowthButton",_start_psionic_growth.bind(false),false,true))
	psionic_growth_row.add_child(_button("Продолжить","ContinuePsionicGrowthButton",_start_psionic_growth.bind(true),not _psionic_growth_store.has_slot(Sm2JourneySession.PSIONIC_GROWTH_SLOT)))
	var psionic_row: HBoxContainer=HBoxContainer.new(); left.add_child(psionic_row)
	psionic_row.add_child(_button("Путь героя: псионика","NewPsionicButton",_start_psionic.bind(false),false,true))
	psionic_row.add_child(_button("Продолжить","ContinuePsionicButton",_start_psionic.bind(true),not _psionic_store.has_slot(Sm2JourneySession.PSIONIC_SLOT)))
	var discovery_row: HBoxContainer=HBoxContainer.new(); left.add_child(discovery_row)
	discovery_row.add_child(_button("Тайники и узлы","NewDiscoveryButton",_start_discovery.bind(false),false,true))
	discovery_row.add_child(_button("Продолжить","ContinueDiscoveryButton",_start_discovery.bind(true),not _discovery_store.has_slot(Sm2JourneySession.DISCOVERY_SLOT)))
	var search_row: HBoxContainer=HBoxContainer.new(); left.add_child(search_row)
	search_row.add_child(_button("Исследование и опыт","NewSearchButton",_start_search.bind(false),false,true))
	search_row.add_child(_button("Продолжить","ContinueSearchButton",_start_search.bind(true),not _search_store.has_slot(Sm2JourneySession.SEARCH_SLOT)))
	var exploration_row: HBoxContainer=HBoxContainer.new(); left.add_child(exploration_row)
	exploration_row.add_child(_button("Исследование","NewExplorationButton",_start_exploration.bind(false),false,true))
	exploration_row.add_child(_button("Продолжить","ContinueExplorationButton",_start_exploration.bind(true),not _exploration_store.has_slot(Sm2JourneySession.EXPLORATION_SLOT)))
	var care_row: HBoxContainer=HBoxContainer.new(); left.add_child(care_row)
	care_row.add_child(_button("Лечение и припасы","NewCareJourneyButton",_start_care.bind(false),false,true))
	care_row.add_child(_button("Продолжить","ContinueCareJourneyButton",_start_care.bind(true),not _care_store.has_slot(Sm2JourneySession.CARE_SLOT)))
	var prosthesis_row: HBoxContainer=HBoxContainer.new(); left.add_child(prosthesis_row)
	prosthesis_row.add_child(_button("Протезирование","NewProsthesisJourneyButton",_start_prosthesis.bind(false),false,true))
	prosthesis_row.add_child(_button("Продолжить","ContinueProsthesisJourneyButton",_start_prosthesis.bind(true),not _prosthesis_store.has_slot(Sm2JourneySession.PROSTHESIS_SLOT)))
	var injury_row: HBoxContainer=HBoxContainer.new(); left.add_child(injury_row)
	injury_row.add_child(_button("Травмы и лечение","NewBodyJourneyButton",_start_body.bind(false),false,true))
	injury_row.add_child(_button("Продолжить","ContinueBodyJourneyButton",_start_body.bind(true),not _body_store.has_slot(Sm2JourneySession.BODY_SLOT)))
	var growth_row: HBoxContainer=HBoxContainer.new(); left.add_child(growth_row)
	growth_row.add_child(_button("Герой и спутник","NewPartyJourneyButton",_start_party.bind(false),false,true))
	growth_row.add_child(_button("Продолжить","ContinuePartyJourneyButton",_start_party.bind(true),not _party_store.has_slot(Sm2JourneySession.PARTY_SLOT)))
	var journey_row: HBoxContainer=HBoxContainer.new(); journey_row.add_theme_constant_override("separation",8); left.add_child(journey_row)
	journey_row.add_child(_button("Путь героя","NewJourneyButton",_start_journey.bind(false),false,true))
	journey_row.add_child(_button("Продолжить путь","ContinueJourneyButton",_start_journey.bind(true),not _journey_store.has_slot(Sm2JourneySession.JOURNEY_SLOT)))
	var life_row: HBoxContainer=HBoxContainer.new(); life_row.add_theme_constant_override("separation",8); left.add_child(life_row)
	life_row.add_child(_button("Мир и воплощение","NewWorldButton",_start_life.bind(false)))
	life_row.add_child(_button("Продолжить","ContinueWorldButton",_start_life.bind(true),not _life_store.has_slot(Sm2LifeSession.SLOT)))
	if _life != null: life_row.add_child(_button("Вернуться","ResumeWorldButton",func() -> void: _page="life"; _redraw_page()))
	var development_row: HBoxContainer=HBoxContainer.new(); development_row.add_theme_constant_override("separation",8); right.add_child(development_row)
	development_row.add_child(_button("Бой с развитием","NewDevelopmentButton",_start_development.bind(false)))
	development_row.add_child(_button("Продолжить","ContinueDevelopmentButton",_start_development.bind(true),not _development_store.has_slot(Sm2BattleRunner.DEVELOPMENT_SLOT)))
	var battle_row: HBoxContainer=HBoxContainer.new(); battle_row.add_theme_constant_override("separation",8); left.add_child(battle_row)
	battle_row.add_child(_button("Начать сражение", "NewBattleButton", _new_battle, false, true))
	battle_row.add_child(_button("Продолжить бой", "ContinueBattleButton", _load_battle, not _battle_store.has_slot(Sm2BattleRunner.SLOT)))
	if _battle != null:
		left.add_child(_button("Вернуться на поле", "ResumeBattleButton", _resume_battle))
	var party_row: HBoxContainer=HBoxContainer.new(); right.add_child(party_row)
	party_row.add_child(_button("Создать отряд", "NewGameButton", _new_game, _session == null))
	party_row.add_child(_button("Продолжить отряд", "ContinueButton", _load_game, _session == null or not _session.has_save()))
	right.add_child(_label("Выбирайте позицию",23,INK))
	var hint: Label = _label("Гексы, высоты и препятствия меняют доступные цели.",16,MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)
	right.add_child(_button("Лаборатория развития", "ProgressButton", _open_progress))
	right.add_child(_button("Восемь характеристик", "AttributesButton", _open_attributes))
	right.add_child(_label("ЭФФЕКТЫ И МАГИЯ / ОТДЕЛЬНЫЕ СРАЖЕНИЯ",12,GOLD))
	var row_Effects: HBoxContainer=HBoxContainer.new(); right.add_child(row_Effects)
	row_Effects.add_child(_button("Бой с эффектами", "NewEffectsButton", _start_effects.bind(false)))
	row_Effects.add_child(_button("Продолжить", "ContinueEffectsButton", _start_effects.bind(true),not _effects_store.has_slot(Sm2BattleRunner.EFFECT_SLOT)))
	_build_current_modes(right)
	var row_Magic: HBoxContainer=HBoxContainer.new(); right.add_child(row_Magic)
	row_Magic.add_child(_button("Бой с магией", "NewMagicButton", _start_magic.bind(false)))
	row_Magic.add_child(_button("Продолжить", "ContinueMagicButton", _start_magic.bind(true),not _magic_store.has_slot(Sm2BattleRunner.MAGIC_SLOT)))
	var row_Area: HBoxContainer=HBoxContainer.new(); right.add_child(row_Area)
	row_Area.add_child(_button("Бой по области", "NewAreaButton", _start_area.bind(false)))
	row_Area.add_child(_button("Продолжить", "ContinueAreaButton", _start_area.bind(true),not _area_store.has_slot(Sm2BattleRunner.AREA_SLOT)))

func _start_survival_tissues(from_save: bool) -> void:
	var rows: Array[Dictionary]=_campaigns().inspect()
	var index: int=Sm2Campaigns.latest(rows,_campaigns().selected()) if from_save else _campaigns().selected()
	if not from_save and rows[index].occupied:
		index=-1
		for row: Dictionary in rows:
			if not row.occupied: index=row.index; break
	if index<0: _show_campaigns(); return
	_open_campaign(index,from_save)

func _start_survival_devices(from_save: bool) -> void:
	var content: Dictionary=Sm2SurvivalContentLoader.load_scenario(true)
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить протезы: "+str(content.get("errors",[])); _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_survival_devices_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_survival(from_save: bool) -> void:
	var content: Dictionary=Sm2SurvivalContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить тело и инвентарь: "+str(content.get("errors",[])); _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_survival_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_region(from_save: bool) -> void:
	var content: Dictionary=Sm2RegionContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить карту."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_region_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_hybrids(from_save: bool) -> void:
	var content: Dictionary=Sm2HybridContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить игру."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_hybrid_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_implants(from_save: bool) -> void:
	var content: Dictionary=Sm2ImplantContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить развитие псионики."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_implant_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_upgrades(from_save: bool) -> void:
	var content: Dictionary=Sm2BodyUpgradeContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить развитие псионики."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_upgrade_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_psionic_shield(from_save: bool) -> void:
	var content: Dictionary=Sm2PsionicShieldContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить развитие псионики."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_psionic_shield_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_psionic_growth(from_save: bool) -> void:
	var content: Dictionary=Sm2PsionicGrowthContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить развитие псионики."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_psionic_growth_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_psionic(from_save: bool) -> void:
	var content: Dictionary=Sm2PsionicContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить псионику."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_psionic_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_discovery(from_save: bool) -> void:
	var content: Dictionary=Sm2DiscoveryContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить исследование."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_discovery_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_search(from_save: bool) -> void:
	var content: Dictionary=Sm2SearchContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить исследование."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_search_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_exploration(from_save: bool) -> void:
	var content: Dictionary=Sm2ExplorationContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить лечение."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_exploration_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_care(from_save: bool) -> void:
	var content: Dictionary=Sm2CareContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить лечение."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_care_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_prosthesis(from_save: bool) -> void:
	var content: Dictionary=Sm2ProsthesisContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить протезирование."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_prosthesis_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_body(from_save: bool) -> void:
	var content: Dictionary=Sm2BodyContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить функции тела."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_body_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_party(from_save: bool) -> void:
	var content: Dictionary=Sm2PartyContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить развитие отряда."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_party_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_journey(from_save: bool) -> void:
	var content: Dictionary=Sm2JourneyContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить путь героя."; _redraw_page(); return
	var candidate: Sm2JourneySession=Sm2JourneySession.new(content,ai.profile,_journey_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _start_life(from_save: bool) -> void:
	var content: Dictionary=Sm2LifeContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: _notice="Не удалось подготовить мир."; _redraw_page(); return
	var candidate: Sm2LifeSession=Sm2LifeSession.new(content,ai.profile,_life_store)
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_game()
	if _handle_result(result,""): _life=candidate; _page="life"
	_redraw_page()

func _open_attributes() -> void:
	if _attributes == null:
		var content: Dictionary = Sm2ProgressContentLoader.load_catalog("res://content/p4/attributes.tres")
		if not content.ok:
			_handle_result(content,""); _redraw_page(); return
		var candidate: Sm2ProgressSession = Sm2ProgressSession.new(content.catalog,Sm2SaveStore.new("user://attributes"),"p4_attribute_lab")
		if not _handle_result(candidate.new_game(),""): _redraw_page(); return
		_attributes=candidate
	_page="attributes"; _redraw_page()

func _open_progress() -> void:
	if _progress == null:
		var content: Dictionary = Sm2ProgressContentLoader.load_catalog()
		if not content.ok:
			_handle_result(content,""); _redraw_page(); return
		var candidate: Sm2ProgressSession = Sm2ProgressSession.new(content.catalog,Sm2SaveStore.new("user://progression"))
		if not _handle_result(candidate.new_game(),""): _redraw_page(); return
		_progress=candidate
	_page="progress"; _redraw_page()

func _start_development(from_save: bool) -> void:
	var content: Dictionary=Sm2DevelopmentContentLoader.load_scenario()
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok:
		_handle_result(content if not content.ok else ai,""); _redraw_page(); return
	var candidate: Sm2BattleRunner=Sm2BattleRunner.new(content.catalog,content.combat,ai.profile,_development_store,false,null,null,content.development)
	if not from_save: content.setup.battle_id="p2:"+Crypto.new().generate_random_bytes(16).hex_encode()
	var result: Dictionary=candidate.load_game() if from_save else candidate.new_battle(content.setup)
	if _handle_result(result,""):
		_battle=candidate; _page="battle"
	_redraw_page()

func _start_area(from_save: bool) -> void:
	var content: Dictionary = Sm2AreaContentLoader.load_scenario()
	var ai: Dictionary = _expanded_ai(_area_store,Sm2BattleRunner.AREA_SLOT,true) if from_save else Sm2AiContentLoader.load_profile(Sm2AiContentLoader.AREA_PATH)
	if not content.ok or not ai.ok:
		_notice = "Не удалось загрузить бой по области."
		_is_error = true
		_redraw_page()
		return
	var candidate: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog,content.combat,ai.profile,_area_store,false,content.effects,content.magic)
	var result: Dictionary = candidate.load_game() if from_save else candidate.new_battle(content.setup)
	if _handle_result(result,""):
		_battle = candidate
		_page = "battle"
	_redraw_page()

func _start_magic(from_save: bool) -> void:
	var content: Dictionary = Sm2MagicContentLoader.load_scenario()
	var ai: Dictionary = _expanded_ai(_magic_store,Sm2BattleRunner.MAGIC_SLOT,from_save)
	if not content.ok or not ai.ok:
		_notice = "Не удалось загрузить набор магии."
		_is_error = true
		_redraw_page()
		return
	var candidate: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog,content.combat,ai.profile,_magic_store,false,content.effects,content.magic)
	var result: Dictionary = candidate.load_game() if from_save else candidate.new_battle(content.setup)
	if _handle_result(result,""):
		_battle = candidate
		_page = "battle"
	_redraw_page()

func _start_effects(from_save: bool, sequences: bool = false) -> void:
	var content: Dictionary = Sm2EffectSequenceContentLoader.load_scenario() if sequences else Sm2EffectContentLoader.load_scenario()
	var store: Sm2SaveStore = _sequence_store if sequences else _effects_store
	var ai: Dictionary = _expanded_ai(store,Sm2BattleRunner.EFFECT_SLOT,from_save)
	if not content.ok or not ai.ok:
		_notice = "Не удалось загрузить набор эффектов."
		_is_error = true
		_redraw_page()
		return
	var candidate: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog,content.combat,ai.profile,store,false,content.effects)
	var result: Dictionary = candidate.load_game() if from_save else candidate.new_battle(content.setup)
	if _handle_result(result,""):
		_battle = candidate
		_page = "battle"
	_redraw_page()

func _show_creature_page(page: int) -> void:
	_creature_page = maxi(0,page); _modes_expanded = true; _redraw_page()

func _creature_store(id: String) -> Sm2SaveStore:
	return Sm2SaveStore.new("user://creature_encounters/"+id.sha256_text())

func _start_creatures(id: String, from_save: bool) -> void:
	if _creature_content.is_empty(): _creature_content = Sm2CreatureContentLoader.load_catalog()
	if not _creature_content.ok:
		_notice = "Не удалось загрузить шаблоны существ."; _is_error = true; _redraw_page(); return
	var compiled: Dictionary = _creature_content.catalog.compile(id)
	if not compiled.ok:
		_notice = "Не удалось подготовить встречу."; _is_error = true; _redraw_page(); return
	var candidate: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(compiled,_creature_content.profile,_creature_store(id),false,_creature_content.visuals)
	var result: Dictionary = candidate.load_game() if from_save else candidate.new_battle(compiled.setup)
	if _handle_result(result,""):
		_battle = candidate; _page = "battle"
	_redraw_page()

func _expanded_ai(store: Sm2SaveStore, slot: String, from_save: bool) -> Dictionary:
	if not from_save: return Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH)
	var saved: Dictionary = store.load_slot(slot)
	if not saved.ok: return saved
	var fingerprint: Variant = saved.payload.get("profile")
	if not fingerprint is String: return {"ok":false,"errors":PackedStringArray(["saved_ai_profile_missing"])}
	return Sm2AiContentLoader.load_saved_profile(fingerprint)

func _make_battle() -> Sm2BattleRunner:
	var content: Dictionary = Sm2CombatContentLoader.load_scenario()
	var ai: Dictionary = Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok:
		_notice = "Не удалось подготовить сражение. Проверьте журнал запуска."
		_is_error = true
		return null
	return Sm2BattleRunner.new(content.catalog, content.combat, ai.profile, _battle_store, false)

func _new_battle() -> void:
	var candidate: Sm2BattleRunner = _make_battle()
	if candidate != null:
		var content: Dictionary = Sm2CombatContentLoader.load_scenario()
		if _handle_result(candidate.new_battle(content.setup), ""):
			_battle = candidate
			_page = "battle"
	_redraw_page()

func _load_battle() -> void:
	var candidate: Sm2BattleRunner = _make_battle()
	if candidate != null and _handle_result(candidate.load_game(), ""):
		_battle = candidate
		_page = "battle"
	_redraw_page()

func _resume_battle() -> void:
	_page = "battle"
	_redraw_page()

func _build_party(left: VBoxContainer, right: VBoxContainer) -> void:
	left.add_child(_label("ВАШ ОТРЯД", 12, GOLD))
	var title: Label = _label("Начало пути\nположено.", 36, INK)
	left.add_child(title)
	var description: Label = _label("Сохраните отряд, чтобы продолжить с этого места после следующего запуска.", 16, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(description)
	_spacer(left, 12)
	left.add_child(_button("Сохранить отряд", "SaveButton", _save_game, false, true))
	left.add_child(_button("Главное меню", "MenuButton", _show_menu))
	right.add_child(_button("Выйти из игры", "QuitButton", _quit_game))
	var state: Dictionary = _session.view()
	for actor: Dictionary in state.get("actors", []):
		if actor.get("side") == "company":
			_card(right, "УЧАСТНИК ОТРЯДА", str(actor.get("name", "")), "Здоровье: %s / %s\nОчки действий: %s / %s\nУсталость: %s / %s" % [actor.get("hp"), actor.get("hp_max"), actor.get("ap"), actor.get("ap_max"), actor.get("fatigue"), actor.get("fatigue_max")])
	_card(right, "СОХРАНЕНИЕ", "Один слот", "Кнопка «Сохранить отряд» обновляет текущее сохранение. Создание нового отряда само по себе его не перезаписывает.")

func _new_game() -> void:
	var result: Dictionary = _session.new_game()
	if _handle_result(result, "Отряд создан. Его можно сохранить."):
		_page = "party"
	_redraw_page()

func _load_game() -> void:
	var result: Dictionary = _session.load_game()
	if _handle_result(result, "Сохранённый отряд восстановлен."):
		_page = "party"
	_redraw_page()

func _save_game() -> void:
	_handle_result(_session.save_game(), "Отряд сохранён. Можно закрыть игру и продолжить позже.")
	_redraw_page()

func _resume_game() -> void:
	_page = "party"
	_notice = ""
	_redraw_page()

func _show_menu() -> void:
	_page = "menu"
	_notice = ""
	_redraw_page()

func _quit_game() -> void:
	get_tree().quit()

func _handle_result(result: Dictionary, success_message: String) -> bool:
	_is_error = not result.get("ok", false)
	_notice = "\n".join(result.get("errors", PackedStringArray(["Не удалось завершить действие."]))) if _is_error else success_message
	_notice = _notice.replace("Файл сохранения содержит повреждённый JSON.","Файл сохранения повреждён.")
	return not _is_error

func _card(parent: VBoxContainer, eyebrow: String, title: String, description: String) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.11, 0.16, 0.19, 0.92), Color("35464e"), 10, 18))
	parent.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	body.add_child(_label(eyebrow, 11, GOLD))
	body.add_child(_label(title, 23, INK))
	var detail: Label = _label(description, 15, MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)

func _button(text_value: String, node_name: String, action: Callable, disabled_value: bool = false, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text_value
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = disabled_value
	if _page == "menu":
		button.add_theme_stylebox_override("normal", Sm2BronzeTheme.box(Color("44331c") if primary else Sm2BronzeTheme.BUTTON,Sm2BronzeTheme.GOLD if primary else Sm2BronzeTheme.BORDER,12))
	elif primary:
		button.add_theme_stylebox_override("normal", _box(Color("ad905b"), Color("d1b478"), 8, 10))
		button.add_theme_color_override("font_color", Color("131e23"))
	button.pressed.connect(action)
	return button

static func _label(text_value: String, font_size: int, tint: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label

static func _spacer(parent: Control, height: float) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)

static func _box(fill: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
