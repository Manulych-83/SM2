class_name Sm2ExpeditionScreen
extends Control
signal closed
var owner_screen: Sm2LifeScreen
var model: Dictionary
const UI: GDScript=preload("res://src/presentation/sm2_camp_screen.gd")
const B: GDScript=preload("res://src/presentation/sm2_bronze_theme.gd")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme=B.create()
	var panel: Panel=Panel.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_stylebox_override("panel",B.box(B.BACKGROUND,B.BACKGROUND,0)); add_child(panel)
	var margin: MarginContainer=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	var page: VBoxContainer=VBoxContainer.new(); page.add_theme_constant_override("separation",16); margin.add_child(page)
	var header: HBoxContainer=HBoxContainer.new(); page.add_child(header)
	var title: Label=UI.label("ПОХОД ЗАВЕРШЁН" if model.complete else "ПЕРВЫЙ ПОХОД",26,B.GOLD); title.name="ExpeditionTitle"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(UI.button("В лагерь","ExpeditionBack",func() -> void: closed.emit()))
	var content: VBoxContainer=UI.scroll(page)
	content.add_child(UI.label(model.brief.title,23,B.GOLD)); content.add_child(UI.label(model.brief.brief,18,B.TEXT))
	for row: Dictionary in model.steps: content.add_child(UI.label(("✓ " if row.done else "○ ")+str(row.text),18,B.PSI if row.done else B.TEXT))
	var texts: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/expedition.json"))
	content.add_child(UI.label(texts.get(model.stage,""),18,B.GOLD))
	for fact: String in model.facts: content.add_child(UI.label(fact,16,B.MUTED))
	if model.complete: summary(content)
	else:
		for row: Dictionary in model.actions:
			var command: Sm2WorldCommand=owner_screen.session.command(row.kind,int(row.target),row.content) if row.has("kind") else null
			var captured: Dictionary=row.duplicate(true)
			var button: Button=UI.button(row.title,"ExpeditionAction_"+(str(row.kind) if row.has("kind") else str(row.link)),func() -> void:
				closed.emit(); Sm2JourneyGuide.activate(owner_screen,captured,command))
			button.disabled=not row.reason.is_empty()
			button.tooltip_text=row.reason; content.add_child(button)
		content.add_child(UI.label("Перевязка останавливает кровотечение, но не восстанавливает ткани и кровь. При тяжёлой травме можно вернуться раньше; начатый поход останется в мире.",16,B.MUTED))
	if not model.ids.is_empty():
		content.add_child(UI.label("Медикаменты из санитарной сумки · текущее местоположение",18,B.GOLD))
		for row: Dictionary in model.finds: content.add_child(UI.label("№%s · %s%s" % [row.id,row.where," · в сундуке" if row.delivered else ""],16,B.MUTED))

func summary(parent: VBoxContainer) -> void:
	var data: Dictionary=model.summary
	parent.add_child(UI.label("ИТОГ НА МОМЕНТ ДОСТАВКИ",21,B.GOLD))
	parent.add_child(UI.label("%s · Доставлено: %s медикамента\nОт первого выхода до завершения: %s мин · Воплощение %s" % [data.battle.title,model.brief.quantity,int(data.elapsed)/60,data.incarnation],18,B.TEXT))
	for row: Dictionary in data.party:
		parent.add_child(UI.label("%s: %s · Кровь %s/%s мл · Неработающих частей: %s" % [row.name,"жив" if row.alive else "погиб",row.blood,row.blood_max,row.lost_functions],17,B.TEXT))
	parent.add_child(UI.label("Практика героя за подготовку и путь",20,B.GOLD))
	for row: Dictionary in data.practice: parent.add_child(UI.label("%s: +%s XP" % [row.title,row.xp],17,B.TEXT))
	parent.add_child(UI.label("Спутник: +%s общего опыта. Все награды уже получены во время действий." % data.companion_xp,17,B.MUTED))
	var notice: Label=UI.label("",16,B.GOLD); notice.name="ExpeditionSaveNotice"
	parent.add_child(UI.button("Сохранить игру","ExpeditionSave",func() -> void:
		var result: Dictionary=owner_screen.session.save_game(); notice.text="Игра сохранена." if result.ok else "Не удалось сохранить игру: "+str(result.get("errors",[]))))
	parent.add_child(notice)

func _unhandled_input(event: InputEvent) -> void:
	if Sm2Controls.back(event): get_viewport().set_input_as_handled(); closed.emit()

static func card(screen: Sm2LifeScreen,parent: VBoxContainer) -> void:
	var view: Dictionary=screen.expedition.build(screen.session as Sm2JourneySession)
	if not view.ok: return
	var panel: PanelContainer=UI.frame(parent); panel.name="ExpeditionCard"
	var body: VBoxContainer=VBoxContainer.new(); body.add_theme_constant_override("separation",6); panel.add_child(body)
	body.add_child(UI.label("Первый поход завершён" if view.complete else "ЦЕЛЬ · медикаменты для лагеря",19,B.GOLD))
	for row: Dictionary in view.steps: body.add_child(UI.label(("✓ " if row.done else "○ ")+str(row.text),14,B.PSI if row.done else B.TEXT))
	body.add_child(UI.button("Итоги похода" if view.complete else "План первого похода","CampExpedition",screen._open_expedition))
