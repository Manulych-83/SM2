class_name Sm2JournalScreen
extends Control
signal closed
const UI: GDScript=preload("res://src/presentation/sm2_camp_screen.gd")
const B: GDScript=preload("res://src/presentation/sm2_bronze_theme.gd")
const PAGE_SIZE: int=30
var session: Sm2JourneySession
var reader: Sm2JournalQuery
var model: Dictionary
var definitions: Dictionary
var filtered: Array[Dictionary]=[]
var query: String=""
var group: String="Все"
var page_index: int=0
var list: VBoxContainer
var counter: Label
var previous: Button
var next: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme=B.create()
	definitions=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/journal.json"))
	reader=Sm2JournalQuery.new(session,definitions)
	var panel: Panel=Panel.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_stylebox_override("panel",B.box(B.BACKGROUND,B.BACKGROUND,0)); add_child(panel)
	var margin: MarginContainer=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	var column: VBoxContainer=VBoxContainer.new(); column.add_theme_constant_override("separation",16); margin.add_child(column)
	var header: HBoxContainer=HBoxContainer.new(); column.add_child(header)
	var title: Label=UI.label("ЖУРНАЛ ПУТЕШЕСТВИЯ",26,B.GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(UI.button("В локацию","JournalBack",func() -> void: closed.emit()))
	column.add_child(UI.label("Сначала новые записи. Время — игровой календарь на момент события. Подробные действия боя доступны в боевом журнале.",15,B.MUTED))
	var filters: HBoxContainer=HBoxContainer.new(); filters.add_theme_constant_override("separation",12); column.add_child(filters)
	var search: LineEdit=LineEdit.new(); search.name="JournalSearch"; search.placeholder_text="Поиск по названию и месту"; search.size_flags_horizontal=Control.SIZE_EXPAND_FILL; filters.add_child(search)
	search.text_changed.connect(func(value: String) -> void: query=value; page_index=0; refresh())
	var groups: OptionButton=OptionButton.new(); groups.name="JournalGroup"; filters.add_child(groups)
	var names: Array[String]=["Все"]
	for entry: Dictionary in definitions.values():
		if not entry.group in names: names.append(entry.group)
	for name_value: String in names: groups.add_item(name_value)
	groups.item_selected.connect(func(index: int) -> void: group=groups.get_item_text(index); page_index=0; refresh())
	var body: PanelContainer=UI.frame(column); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; list=UI.scroll(body)
	var footer: HBoxContainer=HBoxContainer.new(); column.add_child(footer)
	previous=UI.button("Новее","JournalPrevious",func() -> void: page_index-=1; refresh()); footer.add_child(previous)
	counter=UI.label("",15,B.MUTED); counter.name="JournalCount"; counter.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(counter)
	next=UI.button("Старее","JournalNext",func() -> void: page_index+=1; refresh()); footer.add_child(next)
	refresh()

func refresh() -> void:
	for child: Node in list.get_children(): list.remove_child(child); child.queue_free()
	model=reader.page(query,group,page_index,PAGE_SIZE)
	page_index=int(model.page); filtered.assign(model.rows)
	var start: int=page_index*PAGE_SIZE; var end: int=mini(start+PAGE_SIZE,int(model.count))
	for row: Dictionary in filtered:
		var definition: Dictionary=definitions.get(row.kind,{"title":"Действие мира","group":"Прочее"})
		var card: VBoxContainer=VBoxContainer.new(); UI.frame(list).add_child(card)
		var title: String=row.outcome if not row.outcome.is_empty() else definition.title+(": "+row.subject if not row.subject.is_empty() else "")
		if row.interrupted: title="Действие прервано: "+title
		card.add_child(UI.label(title,19,B.GOLD))
		@warning_ignore("integer_division")
		var time: String="День %s · %02d:%02d:%02d" % [1+row.seconds/86400,(row.seconds/3600)%24,(row.seconds/60)%60,row.seconds%60]
		card.add_child(UI.label("№%s · %s · %s · %s" % [row.number,time,row.from+" → "+row.location if row.from!=row.location else row.location,definition.group],14,B.MUTED))
		if row.life_ended: card.add_child(UI.label("Жизнь тела завершена. Душа остаётся в мире.",15,B.PSI))
		if row.new_items>0: card.add_child(UI.label("Появилось предметов: %s. Это не означает, что они уже собраны в инвентарь." % row.new_items,15,B.PSI))
	if not model.ok: list.add_child(UI.label("Не удалось восстановить журнал. Мир не изменён.",18,B.TEXT))
	elif filtered.is_empty(): list.add_child(UI.label("Записей по этому запросу нет." if int(model.total)>0 else "История начнётся с первого действия в мире.",18,B.MUTED))
	counter.text="%s–%s из %s · Всего событий: %s%s" % [start+1 if not filtered.is_empty() else 0,end,model.count,model.total," · Сражение продолжается" if model.get("busy",false) else ""]
	previous.disabled=page_index==0; next.disabled=end>=int(model.count)
	(list.get_parent() as ScrollContainer).scroll_vertical=0

func _unhandled_input(event: InputEvent) -> void:
	if Sm2Controls.back(event):
		get_viewport().set_input_as_handled(); closed.emit()
