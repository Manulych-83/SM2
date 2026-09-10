class_name Sm2BattleProgressPanel
extends PanelContainer
signal close_requested
signal changed(events: Array[Dictionary])
var runner: Sm2BattleRunner
var selected_actor: int = 0
var _content: VBoxContainer
var _message: String = ""
const REASONS: Dictionary = {"nodes_after_battle":"Узлы доступны после боя","development_owner":"Развитие недоступно этому участнику","node_owned":"Изучен","level_required":"Нужен более высокий уровень","prerequisite_required":"Нужен предыдущий узел","experience_required":"Недостаточно опыта"}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style: StyleBoxFlat=StyleBoxFlat.new()
	style.bg_color=Color("101c20"); style.border_color=Color("b39760")
	style.set_border_width_all(2)
	for side: String in ["left","right","top","bottom"]: style.set("content_margin_"+side,22.0)
	add_theme_stylebox_override("panel",style)
	refresh()

func refresh() -> void:
	if is_instance_valid(_content): remove_child(_content); _content.queue_free()
	_content=VBoxContainer.new(); _content.add_theme_constant_override("separation",12); add_child(_content)
	var state: Dictionary=runner.view()
	var members: Array[Dictionary]=[]
	for actor: Dictionary in state.actors:
		if actor.has("development"): members.append(actor)
	if selected_actor == 0: selected_actor=int(members[0].actor_id)
	_content.add_child(_label("РАЗВИТИЕ В БОЮ",24,Color("e3bf7b")))
	_content.add_child(_label("Удар мечом развивает силу и ближний бой, включая промах и ответный удар. Числа пока пробные.",14))
	var selectors: HBoxContainer=HBoxContainer.new(); selectors.add_theme_constant_override("separation",10); _content.add_child(selectors)
	var selected: Dictionary={}
	for actor: Dictionary in members:
		var button: Button=_button(Sm2BattleText.actor(actor),"DevelopActor"+str(actor.actor_id),func() -> void: selected_actor=int(actor.actor_id); refresh())
		button.toggle_mode=true; button.button_pressed=int(actor.actor_id) == selected_actor; selectors.add_child(button)
		if int(actor.actor_id) == selected_actor: selected=actor
	var data: Dictionary=selected.development
	var status: String="Герой · Душа помнит: "+", ".join(data.knowledge) if data.role == "hero" else "Спутник · Собственное тело и собственный опыт"
	if not selected.alive: status += " · Погиб"
	_content.add_child(_label(status,16))
	var cards: HBoxContainer=HBoxContainer.new(); cards.add_theme_constant_override("separation",18); _content.add_child(cards)
	for track: Dictionary in data.tracks:
		var box: VBoxContainer=VBoxContainer.new(); box.size_flags_horizontal=SIZE_EXPAND_FILL; cards.add_child(box)
		box.add_child(_label("%s · уровень %s" % [track.name,track.level],18,Color("e3bf7b")))
		var progress: ProgressBar=ProgressBar.new(); progress.max_value=track.needed; progress.value=track.progress; progress.show_percentage=false; progress.custom_minimum_size.y=10; box.add_child(progress)
		box.add_child(_label("До следующего: %s / %s\nЗаработано: %s · потрачено: %s\nДля узлов: %s\nИтоговое значение: %s" % [track.progress,track.needed,track.earned,track.spent,track.available,track.effective],14))
		for source: Dictionary in track.sources: box.add_child(_label("%s: +%s" % [source.name,source.amount],14))
	_content.add_child(_label("Навык попадания: %s · основа %s · развитие %+d · мораль %s%%" % [selected.melee_stat.value,selected.melee_stat.base,data.melee_bonus,selected.melee_stat.morale_percent],16))
	_content.add_child(_label("Узлы можно изучить сейчас. Уровни и продвижение сохраняются." if state.finished else "Новые уровни уже влияют на следующие действия. Узлы — после завершения боя.",14,Color("e3bf7b")))
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.name="DevelopmentNodes"; scroll.size_flags_vertical=SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _content.add_child(scroll)
	var nodes: VBoxContainer=VBoxContainer.new(); nodes.size_flags_horizontal=SIZE_EXPAND_FILL; nodes.add_theme_constant_override("separation",10); scroll.add_child(nodes)
	for node: Dictionary in data.nodes:
		var row: HBoxContainer=HBoxContainer.new(); nodes.add_child(row)
		var label: Label=_label("%s · %s +%s\nУровень %s · цена %s · %s" % [node.name,node.track_name,node.bonus,node.min_level,node.cost,"Доступен" if node.allowed else REASONS.get(node.reason,node.reason)],14)
		label.size_flags_horizontal=SIZE_EXPAND_FILL; row.add_child(label)
		var buy: Button=_button("Изучен" if node.owned else "Изучить","DevBuy_"+node.id.get_slice(".",1),_purchase.bind(node.id)); buy.disabled=not node.allowed; row.add_child(buy)
	_content.add_child(_label(_message,14,Color("e3bf7b")))
	var footer: HBoxContainer=HBoxContainer.new(); footer.add_theme_constant_override("separation",12); _content.add_child(footer)
	footer.add_child(_button("Сохранить","SaveDevelopmentButton",_save))
	footer.add_child(_button("Назад к бою","CloseDevelopmentButton",func() -> void: close_requested.emit()))

func _purchase(id: String) -> void:
	var command: Sm2Command=Sm2Command.new()
	command.battle_id=runner.view().battle_id
	command.kind="buy_node"; command.actor_id=selected_actor; command.target_actor_id=selected_actor; command.ability_id=id; command.expected_revision=runner.view().revision
	var result: Sm2CommandResult=runner.execute_player(command)
	_message="Узел изучен. Уровень и продвижение сохранены." if result.accepted else REASONS.get(result.code,result.code)
	if result.accepted: changed.emit(result.events)
	refresh()

func _save() -> void:
	var result: Dictionary=runner.save_game()
	_message="Бой и развитие сохранены вместе." if result.ok else "Ошибка сохранения: "+str(result.errors)
	refresh()

static func _label(text_value: String, size_value: int, color_value: Color=Color("dce6dc")) -> Label:
	var label: Label=Label.new(); label.text=text_value; label.add_theme_font_size_override("font_size",size_value); label.add_theme_color_override("font_color",color_value); label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

static func _button(text_value: String, id: String, action: Callable) -> Button:
	var button: Button=Button.new(); button.text=text_value; button.name=id; button.custom_minimum_size=Vector2(120,40); button.pressed.connect(action)
	return button
