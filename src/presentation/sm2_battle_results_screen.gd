class_name Sm2BattleResultsScreen
extends Control
var screen: Sm2BattleScreen
var view: Dictionary
const B: GDScript=preload("res://src/presentation/sm2_bronze_theme.gd")

func _ready() -> void:
	name="BattleResultsScreen"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bg: ColorRect=ColorRect.new(); bg.mouse_filter=Control.MOUSE_FILTER_IGNORE; bg.color=B.BACKGROUND; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var margin: MarginContainer=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(margin)
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for side: String in ["left","right","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	margin.add_theme_constant_override("margin_top",112)
	var column: VBoxContainer=VBoxContainer.new(); column.add_theme_constant_override("separation",14); margin.add_child(column)
	column.add_child(label("ИТОГИ СРАЖЕНИЯ",26,B.GOLD))
	column.add_child(label(view.title+" · Состояние участников на конец боя · Раунд "+str(view.round),16,B.MUTED))
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	var cards: HBoxContainer=HBoxContainer.new(); cards.size_flags_horizontal=Control.SIZE_EXPAND_FILL; cards.add_theme_constant_override("separation",20); scroll.add_child(cards)
	for row: Dictionary in view.party:
		var panel: PanelContainer=PanelContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_theme_stylebox_override("panel",B.box(B.PANEL,B.BORDER,18)); cards.add_child(panel)
		var body: VBoxContainer=VBoxContainer.new(); body.add_theme_constant_override("separation",12); panel.add_child(body)
		body.add_child(label(row.name+" · "+row.status,24,B.GOLD if row.alive else Color("ef9a83")))
		body.add_child(label("Кровь: %s / %s мл\nКровотечение: %s мл/мин\nРан: %s" % [row.blood,row.max_blood,row.bleeding,row.wounds],18,B.TEXT))
		body.add_child(label("Неработающие части: "+(", ".join(row.lost) if not row.lost.is_empty() else "нет"),16,B.MUTED))
		body.add_child(label("Практика за сражение" if row.name=="Герой" else "Опыт за сражение",20,B.GOLD))
		if row.practice.is_empty(): body.add_child(label("Опыт не получен.",17,B.MUTED))
		for practice: Dictionary in row.practice:
			body.add_child(label("%s: +%s XP · уровень %s%s" % [practice.title,practice.xp,practice.before," → "+str(practice.after) if practice.after!=practice.before else ""],17,B.PSI))
		if not row.alive: body.add_child(label("Практика принадлежит этому телу. Она не переносится в новое воплощение." if row.name=="Герой" else "Погибший спутник не возвращается в отряд.",16,Color("ef9a83")))
	var counts: Dictionary=view.counts.opposition
	column.add_child(label("Противник: на поле %s · погибло %s · ушло %s" % [counts.on_field,counts.dead,counts.escaped],16,B.MUTED))
	column.add_child(label("Сейчас: %s · предметов на земле рядом: %s.\nВещи не собираются автоматически. Осмотр мест и новые находки доступны в занятиях локации." % [view.location,view.ground],16,B.TEXT))
	var buttons: HBoxContainer=HBoxContainer.new(); buttons.add_theme_constant_override("separation",12); column.add_child(buttons)
	buttons.add_child(Sm2CombatHud.button("Тело и перевязка","ResultsBody",func() -> void: navigate(0)))
	buttons.add_child(Sm2CombatHud.button("Осмотреть вещи","ResultsLoot",func() -> void: navigate(1)))
	buttons.add_child(Sm2CombatHud.button("Осмотреть поле боя","ResultsField",screen._close_results))
	column.add_child(label("Опыт уже учтён. Открытие итогов ничего не начисляет и не расходует.",13,B.MUTED))

func navigate(tab: int) -> void:
	var session: Sm2JourneySession=screen.life_session as Sm2JourneySession
	if session.world.world_id!=view.world_id or session.world.revision!=view.revision or session.world.busy():
		screen._close_results(); return
	screen.aftermath_requested.emit(tab,int(view.body))

static func label(text: String,size: int,color: Color) -> Label:
	var result: Label=Label.new(); result.text=text; result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size",size); result.add_theme_color_override("font_color",color); return result
