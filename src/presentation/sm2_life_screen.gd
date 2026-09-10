class_name Sm2LifeScreen
extends Control
signal menu_requested
signal battle_requested
var session: Sm2LifeSession
var _content: Control
var _notice: String=""
var _selected: int=0
const INK: Color=Color("e9e8de")
const GOLD: Color=Color("d1b478")
const MUTED: Color=Color("a3b0b4")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); redraw()

func redraw() -> void:
	if is_instance_valid(_content): remove_child(_content); _content.queue_free()
	var margin: MarginContainer=MarginContainer.new(); _content=margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var outer: VBoxContainer=VBoxContainer.new(); margin.add_child(outer)
	var header: HBoxContainer=HBoxContainer.new(); outer.add_child(header)
	var title: Label=_label("ПОЛЯНА У РУИН",24,GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(_button("Сохранить","WorldSave",_save))
	header.add_child(_button("Загрузить","WorldLoad",_load))
	header.add_child(_button("Меню","WorldMenu",func() -> void: menu_requested.emit()))
	var v: Dictionary=session.view()
	outer.add_child(_label("Душа без тела · выберите нового носителя" if v.hero_id==0 else "Воплощение %s · %s" % [v.history.size(),v.hero_name],21,INK))
	outer.add_child(_label("Знания Души: "+", ".join(v.knowledge),15,MUTED))
	if not _notice.is_empty(): outer.add_child(_label(_notice,14,GOLD))
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(scroll)
	var rows: HBoxContainer=HBoxContainer.new(); rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(rows)
	var left: VBoxContainer=VBoxContainer.new(); left.size_flags_horizontal=Control.SIZE_EXPAND_FILL; left.size_flags_stretch_ratio=1.15; rows.add_child(left)
	var right: VBoxContainer=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rows.add_child(right)
	if session is Sm2JourneySession:
		left.add_child(_label(v.encounter_name,21,GOLD))
		left.add_child(_label("Завершено встреч: %s/%s. Здоровье, опыт и состояние вещей переходят в следующий бой." % [v.completed,v.encounter_count],15,MUTED))
		var reason: String=session.world.check(session.command("start_battle"))
		left.add_child(_button("Вернуться в сражение" if v.busy else "Войти в сражение","WorldBattle",_battle,not v.busy and not reason.is_empty()))
	elif not v.battle_applied:
		left.add_child(_label("Сражение на поляне",21,GOLD))
		left.add_child(_label("Герой и спутник против двух противников. Результат останется частью этого мира.",15,MUTED))
		left.add_child(_button("Вернуться в сражение" if v.busy else "Войти в сражение","WorldBattle",_battle))
	else:
		left.add_child(_label("Сражение завершено",20,GOLD))
		left.add_child(_label("Погибшие и уцелевшие остались в мире. Эта встреча не создаётся заново.",14,MUTED))
	if v.hero_id!=0:
		if _selected not in [v.hero_id,4]: _selected=v.hero_id
		var selectors: HBoxContainer=HBoxContainer.new(); left.add_child(selectors)
		selectors.add_child(_button("Герой","WorldHero",func() -> void: _selected=v.hero_id; redraw()))
		selectors.add_child(_button("Спутник","WorldCompanion",func() -> void: _selected=4; redraw()))
		for body: Dictionary in v.bodies:
			if body.id!=_selected: continue
			left.add_child(_label(body.name+" · "+("здоровье %s/%s" % [body.hp,body.hp_max] if body.alive else "погиб"),18,INK))
			for track: Dictionary in body.tracks:
				left.add_child(_label("%s: уровень %s · опыт %s · доступно %s" % [track.name,track.level,track.earned,track.available],14,MUTED))
			var practice: Sm2WorldCommand=session.command("practice",body.id)
			left.add_child(_button("Упражнение с мечом","WorldPractice",_act.bind("practice",body.id,""),not session.world.check(practice).is_empty()))
			var catalog: Sm2ProgressCatalog=session._content.development.progression()
			for node_id: String in catalog.node_ids():
				var node: Sm2ProgressNodeDefinition=catalog.node(node_id)
				var reason: String=session.world.check(session.command("buy_node",body.id,node_id))
				var buy: Button=_button("%s · %s опыта" % [node.title,node.cost],"WorldBuy_"+node_id.get_slice(".",1),_act.bind("buy_node",body.id,node_id),not reason.is_empty())
				buy.tooltip_text=reason; left.add_child(buy)
		var end_button: Button=_button("Завершить жизнь тела…","WorldEndLife",_confirm_end,not session.world.check(session.command("end_life")).is_empty())
		left.add_child(end_button)
	else:
		left.add_child(_label("Доступные носители",21,GOLD))
		for body: Dictionary in v.bodies:
			if body.alive: continue
			left.add_child(_label(body.name,17,INK))
			left.add_child(_label("Подготовленный свежий труп · без улучшений" if body.eligible_reason.is_empty() else body.eligible_reason,14,MUTED))
			left.add_child(_button("Вселиться","WorldIncarnate%s" % body.id,_act.bind("incarnate",body.id,""),not body.eligible_reason.is_empty()))
		left.add_child(_label("Вселение мгновенное. Знания сохранятся; опыт и узлы нового тела начнутся с нуля.",14,MUTED))
	right.add_child(_label("Тайник у камня",21,GOLD))
	var owner: String="в тайнике" if v.item_owner==6 else "при теле: "+v.item_owner_name
	right.add_child(_label("Памятный камень — "+owner,17,INK))
	right.add_child(_button("Положить в тайник","WorldDeposit",_act.bind("deposit",0,""),not session.world.check(session.command("deposit")).is_empty()))
	right.add_child(_button("Забрать камень","WorldTake",_act.bind("take",0,""),not session.world.check(session.command("take")).is_empty()))
	right.add_child(_label("Вещи принадлежат миру: Душа не переносит их между телами.",14,MUTED))
	if session is Sm2JourneySession: _equipment(right,v)
	right.add_child(_label("Спутник",21,GOLD))
	for body: Dictionary in v.bodies:
		if body.id==4: right.add_child(_label("Погиб. Новое воплощение его не вернёт." if not body.alive else "Ждёт возвращения героя. Его опыт сохранён." if v.hero_id==0 else "В отряде. Его развитие независимо.",15,MUTED))
	right.add_child(_label("История места",21,GOLD))
	for index: int in v.history.size():
		var record: Dictionary=v.history[index]; var body_name: String=""
		for body: Dictionary in v.bodies:
			if body.id==int(record.body_id): body_name=body.name
		right.add_child(_label("Жизнь %s · %s · %s" % [index+1,body_name,"завершена" if record.ended else "текущая жизнь"],14,MUTED))
	for body: Dictionary in v.bodies:
		if body.id in [2,4,10,11] and not body.alive: right.add_child(_label("Здесь осталось тело: "+body.name,14,MUTED))
	outer.add_child(_label("Снаряжение меняется вне боя · пустая рука позволяет бить кулаком" if session is Sm2JourneySession else "Первый пример · одна локация и одно сражение · подробная анатомия появится позже",12,MUTED))

func _equipment(parent: VBoxContainer,v: Dictionary) -> void:
	parent.add_child(_label("Снаряжение и вещи",21,GOLD))
	var names: Dictionary={"sword":"Меч","shield":"Щит","padded":"Стёганая броня","helmet":"Шлем","bow":"Лук","axe":"Топор","mail":"Кольчуга","spear":"Копьё"}
	for item: Dictionary in v.items:
		var owner_id: int=int(item.owner_id)
		var owner_name: String="тайник"
		var available: bool=owner_id==6
		for body: Dictionary in v.bodies:
			if body.id==owner_id:
				owner_name=body.name
				available=not body.alive or owner_id in [v.hero_id,4]
		if not available: continue
		parent.add_child(_label("%s · %s%s" % [names.get(str(item.definition_id).get_slice(".",1),"Предмет"),owner_name," · надето" if item.equipped else ""],16,INK))
		if item.slot!="weapon": parent.add_child(_label("Прочность: %s" % item.current,14,MUTED))
		var row: HBoxContainer=HBoxContainer.new(); parent.add_child(row)
		var kind: String="unequip" if item.equipped else "equip"
		row.add_child(_item_button("Снять" if item.equipped else "Надеть",kind,0,item.id))
		row.add_child(_item_button("Герою","transfer",int(v.hero_id),item.id))
		row.add_child(_item_button("Спутнику","transfer",4,item.id))
		row.add_child(_item_button("В тайник","transfer",6,item.id))

func _item_button(title: String,kind: String,target: int,id: String) -> Button:
	var reason: String=session.world.check(session.command(kind,target,id))
	var result: Button=_button(title,"JourneyItem%s_%s_%s" % [id,kind,target],_act.bind(kind,target,id),not reason.is_empty())
	result.tooltip_text=reason
	return result

func _act(kind: String, target: int, content_id: String) -> void:
	var result: Dictionary=session.act(session.command(kind,target,content_id))
	_notice="Действие выполнено." if result.ok else str(result.errors[0]); redraw()

func _battle() -> void:
	if not session.view().busy:
		var result: Dictionary=session.act(session.command("start_battle"))
		if not result.ok: _notice=str(result.errors[0]); redraw(); return
	battle_requested.emit()

func _confirm_end() -> void:
	var dialog: ColorRect=ColorRect.new(); dialog.name="WorldDeathDialog"
	dialog.color=Color(0,0,0,0.8); dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(dialog)
	var panel: PanelContainer=PanelContainer.new(); dialog.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-310; panel.offset_right=310; panel.offset_top=-110; panel.offset_bottom=110
	var margin: MarginContainer=MarginContainer.new(); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	var column: VBoxContainer=VBoxContainer.new(); margin.add_child(column)
	column.add_child(_label("Завершить жизнь тела?",23,GOLD))
	column.add_child(_label("Тело и вещи останутся здесь. Душа сможет выбрать нового носителя. Это завершение жизни в первом примере.",16,INK))
	var buttons: HBoxContainer=HBoxContainer.new(); column.add_child(buttons)
	buttons.add_child(_button("Продолжить жизнь","WorldCancelDeath",func() -> void: dialog.queue_free()))
	buttons.add_child(_button("Завершить жизнь","WorldConfirmDeath",func() -> void: dialog.queue_free(); _act("end_life",0,"")))

func _save() -> void:
	var result: Dictionary=session.save_game(); _notice="Мир сохранён." if result.ok else str(result.errors); redraw()
func _load() -> void:
	var result: Dictionary=session.load_game(); _notice="Мир восстановлен." if result.ok else str(result.errors); redraw()
static func _label(value: String, size: int, color: Color) -> Label:
	var label: Label=Label.new(); label.text=value; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size); label.add_theme_color_override("font_color",color); return label
static func _button(value: String, id: String, action: Callable, disabled_value: bool=false) -> Button:
	var button: Button=Button.new(); button.text=value; button.name=id; button.disabled=disabled_value
	button.pressed.connect(action); return button
