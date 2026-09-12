class_name Sm2SoulScreen
extends Control
signal closed(message: String)
var session: Sm2JourneySession
var model: Dictionary={}
var message: String=""
var layout: Control
const B: GDScript=preload("res://src/presentation/sm2_bronze_theme.gd")
const UI: GDScript=preload("res://src/presentation/sm2_camp_screen.gd")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme=B.create(); refresh()

func refresh() -> void:
	model=Sm2SoulView.build(session)
	if is_instance_valid(layout): remove_child(layout); layout.queue_free()
	var panel: Panel=Panel.new(); layout=panel; panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_stylebox_override("panel",B.box(B.BACKGROUND,B.BACKGROUND,0)); add_child(panel)
	var margin: MarginContainer=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	var page: VBoxContainer=VBoxContainer.new(); page.add_theme_constant_override("separation",18); margin.add_child(page)
	var header: HBoxContainer=HBoxContainer.new(); page.add_child(header)
	var title: Label=UI.label("ДУША И ВОПЛОЩЕНИЯ",26,B.GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(UI.button("Сохранить","SoulSave",save)); header.add_child(UI.button("Загрузить","SoulLoad",restore)); header.add_child(UI.button("В локацию · Esc","SoulBack",func() -> void: closed.emit(message)))
	page.add_child(UI.label(("Душа без тела" if model.hero==0 else "Воплощение %s" % model.history.size())+" · "+model.location,20,B.PSI))
	var columns: HBoxContainer=HBoxContainer.new(); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; columns.add_theme_constant_override("separation",18); page.add_child(columns)
	var soul: VBoxContainer=column(columns)
	soul.add_child(UI.label("СОХРАНЯЕТСЯ С ДУШОЙ",18,B.GOLD))
	soul.add_child(UI.label("Изученные знания",20,B.TEXT))
	for knowledge: String in model.knowledge: soul.add_child(UI.label(knowledge,17,B.PSI))
	if model.knowledge.is_empty(): soul.add_child(UI.label("Изученных знаний пока нет.",17,B.MUTED))
	soul.add_child(UI.label("Новое воплощение",20,B.GOLD))
	soul.add_child(UI.label("Характеристики, практика и изученные узлы тела начинают развитие заново. Генетические изменения и импланты остаются с прежним телом.",17,B.TEXT))
	soul.add_child(UI.label("Вещи и последствия прежних жизней остаются в мире. Душа не переносит снаряжение.",17,B.MUTED))
	soul.add_child(UI.label(model.companion,17,B.PSI))
	var history: VBoxContainer=column(columns)
	history.add_child(UI.label("ИСТОРИЯ ВОПЛОЩЕНИЙ",18,B.GOLD))
	for row: Dictionary in model.history:
		var card: VBoxContainer=VBoxContainer.new(); UI.frame(history).add_child(card)
		card.add_child(UI.label("Воплощение %s · %s" % [row.number,row.name],20,B.GOLD))
		card.add_child(UI.label("Жизнь завершена" if row.ended else "Текущее тело",17,B.MUTED if row.ended else B.PSI))
		card.add_child(UI.label("Местонахождение тела: "+row.location,15,B.MUTED))
	var carriers: VBoxContainer=column(columns)
	carriers.add_child(UI.label("МЕСТНЫЕ НОСИТЕЛИ",18,B.GOLD))
	if model.busy: carriers.add_child(UI.label("Выбор тела доступен после завершения сражения.",17,B.MUTED))
	elif model.hero!=0: carriers.add_child(UI.label("Душа уже воплощена. Здесь можно заранее осмотреть известные местные тела.",17,B.MUTED))
	else: carriers.add_child(UI.label("Доступно для вселения: %s" % model.available,18,B.PSI))
	for row: Dictionary in model.carriers:
		var card: VBoxContainer=VBoxContainer.new(); card.add_theme_constant_override("separation",8); UI.frame(carriers).add_child(card)
		card.add_child(UI.label(row.name,20,B.GOLD))
		card.add_child(UI.label(row.eligibility if not row.eligibility.is_empty() else "Подготовленный носитель. Обычное человеческое тело без улучшений.",16,B.MUTED))
		var command: Sm2WorldCommand=session.command("incarnate",int(row.id))
		var button: Button=UI.button("Вселиться","SoulIncarnate"+str(row.id),incarnate.bind(command)); button.disabled=not row.reason.is_empty(); button.tooltip_text=row.reason; card.add_child(button)
		if not row.reason.is_empty() and row.reason!=row.eligibility: card.add_child(UI.label(row.reason,14,B.MUTED))
	if not model.busy and model.carriers.is_empty(): carriers.add_child(UI.label("Известных мёртвых носителей здесь нет.",17,B.MUTED))
	if not model.busy and model.hero==0 and model.available==0: carriers.add_child(UI.label("Подходящие местные тела исчерпаны или недоступны. Новых носителей этот экран не создаёт.",16,B.MUTED))
	var notice: Label=UI.label(message if not message.is_empty() else "Осмотр не тратит время. Вселение происходит сразу по выбранной кнопке.",15,B.GOLD); notice.name="SoulNotice"; page.add_child(notice)

func column(parent: HBoxContainer) -> VBoxContainer:
	var frame: PanelContainer=UI.frame(parent); frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var value: VBoxContainer=UI.scroll(frame); value.add_theme_constant_override("separation",18); return value

func incarnate(command: Sm2WorldCommand) -> void:
	var result: Dictionary=session.act(command)
	message="Новое воплощение началось. Знания сохранены; развитие тела начинается заново." if result.ok else str(result.errors[0]); refresh()

func save() -> void:
	var result: Dictionary=session.save_game(); message="Кампания сохранена." if result.ok else str(result.errors[0]); refresh()

func restore() -> void:
	var result: Dictionary=session.load_game(); message="Кампания загружена." if result.ok else str(result.errors[0])
	if result.ok and session._store is Sm2CampaignStore and (session._store as Sm2CampaignStore).recovered: message="Загружена резервная копия кампании."
	refresh()

func _unhandled_input(event: InputEvent) -> void:
	if Sm2Controls.back(event): get_viewport().set_input_as_handled(); closed.emit(message)
