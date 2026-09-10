class_name Sm2ProgressScreen
extends Control
signal menu_requested
var session: Sm2ProgressSession
var state: Dictionary = {}
var _notice: String = ""
var _content: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background: ColorRect = ColorRect.new()
	background.color=Color("111d24"); background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margins.add_theme_constant_override("margin_"+side,20)
	add_child(margins)
	_content=VBoxContainer.new(); _content.add_theme_constant_override("separation",10); margins.add_child(_content)
	refresh()

func refresh() -> void:
	for child: Node in _content.get_children(): _content.remove_child(child); child.queue_free()
	state=session.view()
	_content.add_child(_label("ЛАБОРАТОРИЯ РАЗВИТИЯ",25,Color("dfbf7e")))
	_content.add_child(_label("Учебный пример · Тело уже получено · Числа пока пробные",14,Color("a5b9c2")))
	var identity: Label = _label("Душа помнит: "+str(state.knowledge[0].name if not state.knowledge.is_empty() else "—")+"  |  Тело: обычный человек",16)
	identity.name="ProgressIdentity"; _content.add_child(identity)
	var cards: HBoxContainer = HBoxContainer.new(); cards.add_theme_constant_override("separation",12); _content.add_child(cards)
	for track: Dictionary in state.tracks:
		var panel: PanelContainer = PanelContainer.new()
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var style: StyleBoxFlat = StyleBoxFlat.new(); style.bg_color=Color("1b2b34")
		style.content_margin_left=12; style.content_margin_right=12; style.content_margin_top=10; style.content_margin_bottom=10
		panel.add_theme_stylebox_override("panel",style); cards.add_child(panel)
		var column: VBoxContainer = VBoxContainer.new(); column.add_theme_constant_override("separation",5); panel.add_child(column)
		column.add_child(_label(track.name+" · уровень "+str(track.level),20,Color("dfbf7e")))
		var progress: ProgressBar = ProgressBar.new(); progress.max_value=track.needed; progress.value=track.progress; progress.show_percentage=false; progress.custom_minimum_size.y=9; column.add_child(progress)
		column.add_child(_label("До следующего: %s / %s" % [track.progress,track.needed],14))
		column.add_child(_label("Опыт: %s · потрачено: %s" % [track.earned,track.spent],14))
		var available: Label = _label("Для узлов: %s" % track.available,18)
		available.name="Balance_"+track.id.get_slice(".",1); column.add_child(available)
		column.add_child(_label("Итоговое значение: %s" % track.effective,16))
		var parts: PackedStringArray = ["Уровень %s + узлы %s" % [track.level,track.node_bonus]]
		for source: Dictionary in track.sources: parts.append("%s: +%s" % [source.name,source.amount])
		column.add_child(_label(" · ".join(parts),12,Color("a5b9c2")))
	var training: HBoxContainer = HBoxContainer.new(); training.add_theme_constant_override("separation",12); _content.add_child(training)
	for activity: Dictionary in state.activities:
		training.add_child(_button(activity.name,"PracticeButton",_act.bind("practice",activity.id),not activity.preview.ok))
	var hint: Label = _label("",14)
	var award_text: PackedStringArray = []
	if not state.activities.is_empty() and state.activities[0].preview.ok:
		for award: Dictionary in state.activities[0].preview.awards: award_text.append("%s +%s" % [award.name,award.amount])
	hint.text="Упражнений: %s · учебное время: %s с\n%s" % [state.practice_sequence,state.elapsed,", ".join(award_text) if not award_text.is_empty() else "Достигнут предел учебного опыта."]
	hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL; hint.name="PracticeHint"; training.add_child(hint)
	_content.add_child(_label("УЗЛЫ · покупка сохраняет уровень и продвижение",16,Color("dfbf7e")))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name="ProgressNodesScroll"; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var nodes: VBoxContainer = VBoxContainer.new(); nodes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	nodes.add_theme_constant_override("separation",7); scroll.add_child(nodes)
	for node: Dictionary in state.nodes:
		var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation",12); nodes.add_child(row)
		var detail: Label = _label("%s · %s +%s\nУровень %s · цена %s опыта · %s" % [node.name,node.track_name,node.bonus,node.min_level,node.cost,"Изучен" if node.owned else reason(node.reason)],14)
		detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(detail)
		var buy: Button = _button("Изучен" if node.owned else "Изучить","Buy_"+node.id.get_slice(".",1),_act.bind("buy_node",node.id),not node.allowed)
		buy.custom_minimum_size.x=125; row.add_child(buy)
	var status: Label = _label(_notice,14,Color("dfbf7e")); status.name="ProgressNotice"; status.custom_minimum_size.y=22; _content.add_child(status)
	var navigation: HBoxContainer = HBoxContainer.new(); navigation.add_theme_constant_override("separation",12); _content.add_child(navigation)
	navigation.add_child(_button("Новый пример","NewProgressButton",_new_game))
	navigation.add_child(_button("Сохранить","SaveProgressButton",_save))
	navigation.add_child(_button("Загрузить","LoadProgressButton",_load,not session.has_save()))
	navigation.add_child(_button("Главное меню","ProgressMenuButton",func() -> void: menu_requested.emit()))
	_content.add_child(_label("Душа и её знания сохранены отдельно от практики тела. Вселение и настоящий бой подключим позже.",12,Color("a5b9c2")))

func _act(kind: String, target: String) -> void:
	var result: Dictionary = session.act(kind,target)
	_notice=reason(result.errors[0]) if not result.ok else ("Упражнение выполнено. Опыт начислен своим направлениям." if kind == "practice" else "Узел изучен. Уровень и продвижение сохранены.")
	refresh()
func _new_game() -> void:
	var result: Dictionary = session.new_game()
	_notice="Новый учебный пример. Сохранение на диске не изменено." if result.ok else "Не удалось создать пример."
	refresh()
func _save() -> void:
	var result: Dictionary = session.save_game()
	_notice="Развитие сохранено." if result.ok else "Не удалось сохранить развитие: "+str(result.errors[0])
	refresh()
func _load() -> void:
	var result: Dictionary = session.load_game()
	_notice="Развитие восстановлено. Повторного начисления опыта нет." if result.ok else "Сохранение не загружено. Текущий пример сохранён."
	refresh()
static func reason(code: String) -> String:
	return {"":"Доступен","level_required":"Нужен более высокий уровень","prerequisite_required":"Сначала изучите предыдущий узел","experience_required":"Не хватает опыта этого направления","node_owned":"Уже изучен","experience_limit":"Предел учебного опыта","practice_sequence":"Повтор упражнения отклонён","stale_revision":"Состояние изменилось"}.get(code,"Действие недоступно")
static func _label(text_value: String, size_value: int, color: Color = Color("e9e8de")) -> Label:
	var value: Label = Label.new(); value.text=text_value
	value.add_theme_font_size_override("font_size",size_value); value.add_theme_color_override("font_color",color)
	value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return value
static func _button(text_value: String, id: String, callback: Callable, disabled_value: bool = false) -> Button:
	var value: Button = Button.new(); value.text=text_value; value.name=id
	value.custom_minimum_size.y=38; value.disabled=disabled_value; value.pressed.connect(callback)
	return value
