class_name Sm2AttributeScreen
extends Control
signal menu_requested
var session: Sm2ProgressSession
var state: Dictionary = {}
var selected: String = "p4a:stat.power"
var _content: VBoxContainer
var _notice: String = ""
const ORDER: Array[String] = ["power","motorics","resilience","intellect","perception","will","resonance","synchronization"]
const DESCRIPTIONS: Dictionary = {
	"power":"Физическое усилие. Учебный стенд помогает только в своём упражнении.",
	"motorics":"Координация и точность исполнения движений.",
	"resilience":"Переносимость нагрузки. Здесь обучение не требует получения травм.",
	"intellect":"Анализ и решение задач. Знания Души хранятся отдельно.",
	"perception":"Обнаружение и различение сигналов.",
	"will":"Удержание концентрации и контроля.",
	"resonance":"Псионическая практика. Доступ в кампании ещё предстоит определить.",
	"synchronization":"Интеграция подключённых систем. Используется учебный интерфейс, не имплант кампании."
}

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
	_content.add_child(Sm2ProgressScreen._label("ВОСЕМЬ ХАРАКТЕРИСТИК",25,Color("dfbf7e")))
	_content.add_child(Sm2ProgressScreen._label("Учебная лаборатория · Все числа пробные · Развитие принадлежит текущему телу",14))
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; columns.add_theme_constant_override("separation",24); _content.add_child(columns)
	var list: VBoxContainer = VBoxContainer.new(); list.custom_minimum_size.x=255; list.add_theme_constant_override("separation",7); columns.add_child(list)
	for suffix: String in ORDER:
		var track: Dictionary = _track("p4a:stat."+suffix)
		var button: Button = Sm2ProgressScreen._button("%s  ·  %s" % [track.name,track.level],"Select_"+suffix,_select.bind(track.id))
		button.toggle_mode=true; button.button_pressed=selected == track.id; list.add_child(button)
	list.add_child(Sm2ProgressScreen._label("Душа помнит: Основы перевязки\nЗнание не выдаёт опыт телу.",14,Color("a5b9c2")))
	var panel: VBoxContainer = VBoxContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_theme_constant_override("separation",8); columns.add_child(panel)
	var chosen: Dictionary = _track(selected)
	var title: Label = Sm2ProgressScreen._label("%s · собственный уровень %s" % [chosen.name,chosen.level],23,Color("dfbf7e"))
	title.name="AttributeTitle"; panel.add_child(title)
	panel.add_child(Sm2ProgressScreen._label(DESCRIPTIONS.get(selected.get_slice(".",1),""),14))
	var bar: ProgressBar = ProgressBar.new(); bar.max_value=chosen.needed; bar.value=chosen.progress; bar.show_percentage=false; bar.custom_minimum_size.y=10; panel.add_child(bar)
	panel.add_child(Sm2ProgressScreen._label("Продвижение: %s / %s  ·  заработано %s" % [chosen.progress,chosen.needed,chosen.earned],15))
	panel.add_child(Sm2ProgressScreen._label("Для узлов: %s  ·  потрачено: %s" % [chosen.available,chosen.spent],17))
	panel.add_child(Sm2ProgressScreen._label("Без учебной помощи: %s = уровень %s + узлы %s" % [chosen.effective,chosen.level,chosen.node_bonus],15))
	panel.add_child(Sm2ProgressScreen._label("ПРАКТИКА",15,Color("dfbf7e")))
	for activity: Dictionary in state.activities:
		var related: bool = false
		for award: Dictionary in activity.awards:
			if award.track_id == selected: related=true
		if not related: continue
		var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation",12); panel.add_child(row)
		var suffix: String = activity.id.get_slice(".",1)
		var button: Button = Sm2ProgressScreen._button(activity.name,"AttributePractice_"+suffix,_act.bind("practice",activity.id),not activity.preview.ok)
		button.custom_minimum_size.x=265; row.add_child(button)
		var description: String = ""
		for award: Dictionary in activity.awards: description += "%s +%s опыта\n" % [award.name,award.amount]
		var capability: Dictionary = activity.preview.get("capability",{})
		if capability.has("minimum"):
			description += "%s / нужно %s" % [capability.effective,capability.minimum]
			if int(capability.assistance) > 0: description += "\n%s: +%s" % [capability.source,capability.assistance]
			if not activity.preview.ok: description += "\nНедостаточно возможности"
		var detail: Label = Sm2ProgressScreen._label(description.strip_edges(),13,Color("a5b9c2"))
		detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(detail)
	panel.add_child(Sm2ProgressScreen._label("УЗЕЛ · усиление не заменяет обучение",15,Color("dfbf7e")))
	for node: Dictionary in state.nodes:
		if node.track_id != selected: continue
		var text_value: String = "%s: +%s\nСобственный уровень %s · цена %s опыта · %s" % [node.name,node.bonus,node.min_level,node.cost,"Изучен" if node.owned else Sm2ProgressScreen.reason(node.reason)]
		panel.add_child(Sm2ProgressScreen._label(text_value,14))
		panel.add_child(Sm2ProgressScreen._button("Изучен" if node.owned else "Изучить","AttributeBuy_"+node.id.get_slice(".",1),_act.bind("buy_node",node.id),not node.allowed))
	var notice: Label = Sm2ProgressScreen._label(_notice,14,Color("dfbf7e")); notice.name="AttributeNotice"; notice.custom_minimum_size.y=36; _content.add_child(notice)
	var navigation: HBoxContainer = HBoxContainer.new(); navigation.add_theme_constant_override("separation",12); _content.add_child(navigation)
	navigation.add_child(Sm2ProgressScreen._button("Новый пример","NewAttributeButton",_new_game))
	navigation.add_child(Sm2ProgressScreen._button("Сохранить","SaveAttributeButton",_save))
	navigation.add_child(Sm2ProgressScreen._button("Загрузить","LoadAttributeButton",_load,not session.has_save()))
	navigation.add_child(Sm2ProgressScreen._button("Главное меню","AttributeMenuButton",func() -> void: menu_requested.emit()))

func _track(id: String) -> Dictionary:
	for track: Dictionary in state.tracks:
		if track.id == id: return track
	return {}
func _select(id: String) -> void:
	selected=id; _notice=""; refresh()
func _act(kind: String, target: String) -> void:
	var result: Dictionary = session.act(kind,target)
	_notice=Sm2ProgressScreen.reason(result.errors[0]) if not result.ok else ("Упражнение выполнено. Начислен опыт указанной характеристики." if kind == "practice" else "Узел изучен. Собственный уровень и продвижение сохранены.")
	refresh()
func _new_game() -> void:
	var result: Dictionary = session.new_game()
	_notice="Новый учебный пример. Сохранение на диске сохранено." if result.ok else "Не удалось создать пример."
	refresh()
func _save() -> void:
	var result: Dictionary = session.save_game()
	_notice="Восемь характеристик сохранены." if result.ok else "Не удалось сохранить пример."
	refresh()
func _load() -> void:
	var result: Dictionary = session.load_game()
	_notice="Пример восстановлен без повторного начисления опыта." if result.ok else "Сохранение не загружено. Текущий пример сохранён."
	refresh()
