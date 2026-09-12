class_name Sm2CombatHud
extends RefCounted
const GOLD: Color = Sm2BronzeTheme.GOLD
const MUTED: Color = Sm2BronzeTheme.MUTED
var screen: Sm2BattleScreen
var art: Sm2BattleArt
var queue_row: HBoxContainer
var portrait: TextureRect
var person: Label
var status: Label
var resources: GridContainer
var tabs: TabContainer
var controls: VBoxContainer
var metadata: Dictionary = {}
var painted_icons: Dictionary = {}
var accents: Dictionary = {}
var action_rows: Array[Dictionary] = []

var layout: Sm2CombatLayout
var party_column: VBoxContainer
var context_panel: Control
var category: String = "main"
var groups: Dictionary = {}
var shortcuts: Array[Button] = []
var target_hint: PanelContainer
var hint_text: Label

func build(owner: Sm2BattleScreen) -> void:
	screen=owner; owner.theme=Sm2BronzeTheme.create()
	metadata=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/combat_hud.json"))
	groups=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/combat_action_groups.json"))
	load_painted_icons()
	layout=Sm2CombatLayout.new(); layout.build(self)
	target_hint=PanelContainer.new(); target_hint.name="HudTargetHint"; target_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE; target_hint.add_theme_stylebox_override("panel",box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.PSI)); screen.add_child(target_hint)
	hint_text=label("",12,Sm2BronzeTheme.PSI); hint_text.mouse_filter=Control.MOUSE_FILTER_IGNORE; target_hint.add_child(hint_text); target_hint.hide()

func open_tab(index: int) -> void:
	screen._close_results()
	context_panel.show(); tabs.current_tab=index; layout.relayout()
	if index==2: screen._inspect(screen._inspected)

func close_context() -> void:
	context_panel.hide(); tabs.current_tab=0; target_hint.hide()

func set_category(value: String) -> void:
	category=value; actions()
	layout.action_scroll.scroll_horizontal=0

func accepts(row: Dictionary) -> bool:
	if category=="all": return true
	if category=="help": return row.kind=="bandage"
	if category=="main": return not row.id in groups.get("aimed",[])
	return row.id in groups.get(category,[])

func hotkey(event: InputEventKey) -> bool:
	var id: String=Sm2Controls.action(event)
	if id in ["end_turn","wait"]:
		return Sm2Controls.press(screen,"EndTurnButton" if id=="end_turn" else "WaitButton")
	if not id.begins_with("slot_"): return false
	var index: int=int(id.trim_prefix("slot_"))-1
	if index<0 or index>=shortcuts.size(): return false
	var value: Button=shortcuts[index]
	if is_instance_valid(value) and not value.disabled: value.pressed.emit()
	return true

func refresh() -> void:
	clear(queue_row); clear(party_column); target_hint.hide()
	var active: Dictionary=screen._actor(screen._active)
	layout.refresh_active(active)
	screen._queue.text="Бой завершён" if screen.state.finished else ("Ваш ход · " if screen._player_turn() else "Ход противника · ")+Sm2BattleText.actor(active)
	for entry: Dictionary in Sm2CombatHudView.queue(screen.state):
		var choice: Button=actor_choice(int(entry.id),"HudTurn_%s" % entry.id,Vector2(78,104),"Сейчас" if entry.current else "Ожидает" if entry.deferred else "Далее")
		queue_row.add_child(choice)
	for actor: Dictionary in screen.state.get("actors",[]):
		if actor.side!="company": continue
		var choice: Button=actor_choice(int(actor.actor_id),"HudParty_%s" % actor.actor_id,Vector2(68,111),"Погиб" if not actor.alive else "Вышел" if not actor.on_field else "Кровотечение" if Sm2CombatHudView.card(actor).bleeding>0 else "В строю")
		party_column.add_child(choice)

func actor_choice(id: int, node_name: String, dimensions: Vector2, phase: String) -> Button:
	var actor: Dictionary=screen._actor(id)
	var current: bool=id==screen._active
	var choice: Button=button("",node_name,inspect.bind(id)); choice.custom_minimum_size=dimensions
	choice.add_theme_stylebox_override("normal",box(Color("273033") if current else Sm2BronzeTheme.PANEL,Sm2BronzeTheme.PSI if current else Color("56848b") if actor.side=="company" else Color("a65d4d")))
	var face: TextureRect=TextureRect.new(); face.texture=portrait_texture(); face.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; face.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; face.mouse_filter=Control.MOUSE_FILTER_IGNORE; choice.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); face.offset_left=-21; face.offset_right=21; face.offset_top=5; face.offset_bottom=50
	var line: int=0
	for item: Array in [[actor.get("display_name","Боец"),12],[phase,10]]:
		var text: Label=label(item[0],item[1],Sm2BronzeTheme.GOLD if current else MUTED); text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; text.clip_text=true; text.mouse_filter=Control.MOUSE_FILTER_IGNORE; choice.add_child(text)
		text.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); text.offset_left=3; text.offset_right=-3; text.offset_top=54+line*22; text.offset_bottom=76+line*22; line+=1
	var data: Dictionary=Sm2CombatHudView.card(actor)
	var meter: ProgressBar=ProgressBar.new(); meter.show_percentage=false; meter.max_value=maxi(1,int(data.condition[1])); meter.value=data.condition[0]; meter.mouse_filter=Control.MOUSE_FILTER_IGNORE; choice.add_child(meter)
	meter.add_theme_stylebox_override("background",Sm2BronzeTheme.box(Color("302d23"),Color("302d23"),0)); meter.add_theme_stylebox_override("fill",Sm2BronzeTheme.box(Color("93ad7d") if actor.side=="company" else Color("bd7969"),Color.TRANSPARENT,0))
	meter.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); meter.offset_left=5; meter.offset_right=-5; meter.offset_top=98; meter.offset_bottom=101
	choice.tooltip_text="%s №%s · Состояние %s/%s · ОД %s/%s\nКровотечение %s мл/мин. Нажмите для осмотра; ход не изменится." % [data.name,id,data.condition[0],data.condition[1],data.ap[0],data.ap[1],data.bleeding]
	return choice

func inspect(id: int) -> void:
	screen._inspected = id; screen._inspect(id); screen.board.inspected = id; screen.board.queue_redraw(); open_tab(2)

func show_actor(actor: Dictionary) -> void:
	var data: Dictionary = Sm2CombatHudView.card(actor)
	if data.is_empty(): return
	portrait.texture = portrait_texture()
	person.text = "%s №%s" % [data.name,data.id]
	status.text = ("Ваш отряд" if data.side == "company" else "Противник") + " · " + Sm2BattleText.MORALE.get(data.morale,data.morale)
	if not data.alive: status.text = "Погиб"
	elif not data.on_field: status.text = "Покинул поле"
	clear(resources)
	for row: Array in [["ОД",data.ap,Color("e3bf7b")],["Усталость",data.fatigue,Color("c09570")],["Концентрация",data.focus,Color("83c4df")],["Состояние",data.condition,Color("96ba99")]]:
		var cell: VBoxContainer = VBoxContainer.new(); cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cell.add_theme_constant_override("separation",1); resources.add_child(cell)
		var value: Label = label("%s %s/%s" % [row[0],row[1][0],row[1][1]],12,Sm2BronzeTheme.TEXT); cell.add_child(value)
		var bar: ProgressBar = ProgressBar.new(); bar.name = "HudMeter_"+str(row[0]); bar.show_percentage = false; bar.custom_minimum_size.y = 4; bar.max_value = maxf(1,float(row[1][1])); bar.value = row[1][0]
		bar.add_theme_stylebox_override("fill",Sm2BronzeTheme.box(row[2],row[2],0)); bar.add_theme_stylebox_override("background",Sm2BronzeTheme.box(Color("100d09"),Sm2BronzeTheme.DIM_BORDER,0)); cell.add_child(bar)
	var blood: Label = label("Кровь %s мл" % data.blood,12,MUTED); resources.add_child(blood)
	var bleeding: Label = label("Кровотечение %s" % data.bleeding,12,Sm2HexBoard.RED if int(data.bleeding)>0 else MUTED); resources.add_child(bleeding); bleeding.tooltip_text = "мл/мин"
	resources.add_child(label("Пси-щит %s" % data.barrier,12,Color("a8deec")))
	var detail: Label = label("Ткани → «Детали»",12,MUTED); detail.tooltip_text = "Состояние — сводный индикатор. Жизнеспособность определяют анатомия и кровь."; resources.add_child(detail)

func actions() -> void:
	clear(screen._actions); clear(controls); shortcuts.clear()
	var player: bool = screen._player_turn() and screen._path.is_empty()
	var movement: Button = button("Движение\nЦена по пути","MoveButton",func() -> void: screen._selected=""; screen._refresh(),not player)
	decorate(movement,"move",screen._selected.is_empty()); screen._actions.add_child(movement); movement.visible=category in ["main","all"]; register_shortcut(movement)
	action_rows = Sm2CombatHudView.actions(screen.runner,screen.state,player)
	for row: Dictionary in action_rows:
		var captured: Dictionary = row.duplicate(true)
		var title: String = row.get("label",screen._ability_name(row.id))
		var caption: String = groups.get("labels",{}).get(row.id,title)
		var choice: Button = button(caption+"\n"+price(row.cost),row.button,activate.bind(captured),not row.allowed)
		decorate(choice,"bandage" if row.kind == "bandage" else row.id,screen._selected == row.id)
		choice.tooltip_text = title+"\n"+price(row.cost)+( "\n"+reason(row.reason) if not row.allowed else "")
		choice.mouse_entered.connect(hover_action.bind(captured,title)); screen._actions.add_child(choice); choice.visible=accepts(row); register_shortcut(choice)
	for row: Array in [["end_turn","Завершить ход","EndTurnButton"],["wait","Ждать","WaitButton"],["escape","Уйти с поля","EscapeButton"]]:
		var request: Sm2Command = screen._command(row[0]); var check: Dictionary = screen.runner.preview(request)
		var choice: Button = button(row[1],row[2],screen._execute.bind(request),not player or not check.allowed)
		if row[0] in ["end_turn","wait"]: choice.text=Sm2Controls.caption(row[0],row[1])
		choice.icon = icon(row[0]); choice.expand_icon = true; choice.add_theme_constant_override("icon_max_width",18)
		choice.tooltip_text = "" if player and check.allowed else reason(check.reason if player else "not_player_turn")
		choice.mouse_entered.connect(func() -> void: open_tab(0); screen._preview.text=row[1]+"\n"+("Доступно" if player and check.allowed else choice.tooltip_text))
		controls.add_child(choice)

	for control: Node in layout.categories.get_children():
		var choice: Button=control as Button
		choice.add_theme_stylebox_override("normal",box(Color("39301c") if str(choice.name)=="HudCategory_"+category else Sm2BronzeTheme.PANEL))
	if shortcuts.is_empty():
		var empty: Label=label("Нет доступных действий этой группы",13,MUTED); screen._actions.add_child(empty)

func register_shortcut(value: Button) -> void:
	if not value.visible or shortcuts.size()>=9: return
	shortcuts.append(value)
	var key: String=Sm2Controls.label_for("slot_%s" % shortcuts.size())
	value.text=key+" · "+value.text; value.tooltip_text+="\nКлавиша: "+key

func activate(row: Dictionary) -> void:
	var live_runner: Sm2BattleRunner = screen.life_session.runner if screen.life_session != null else screen.runner
	var current: Dictionary = live_runner.view()
	if int(row.revision) != int(current.revision) or row.battle_id != current.battle_id or int(row.actor_id) != int(current.active_actor_id):
		screen._refresh(); screen._notice.text = "Состояние боя изменилось. Выберите действие заново."; return
	if row.self: screen._execute(Sm2CombatHudView.command(screen.state,row.kind,row.id,int(row.target)))
	else: screen._ability_clicked(row.id,false)

func hover_action(row: Dictionary, title: String) -> void:
	open_tab(0); screen._inspected=screen._active; screen._inspect(screen._active); target_hint.hide()
	screen._preview.text = title+"\n"+price(row.cost)+"\n\n"
	if not row.allowed: screen._preview.text += reason(row.reason); return
	if row.kind == "bandage": screen._preview.text += "Остановить кровотечение выбранной раны.\nРасход: один доступный перевязочный материал."; return
	if row.self: screen._preview.text += describe(row.check,false); return
	screen._preview.text += "Выберите действие, затем наведите на противника для точного прогноза."

func preview_cell(cell: Vector2i, target: Dictionary) -> void:
	target_hint.hide()
	if screen.state.finished: return
	if not screen.board.field.in_bounds(cell):
		if tabs.current_tab==0 and not context_panel.get_global_rect().has_point(screen.get_global_mouse_position()): context_panel.hide()
		return
	open_tab(0)
	screen._inspected=int(target.actor_id) if not target.is_empty() else screen._active
	screen._inspect(screen._inspected)
	if not screen._player_turn() or not screen._path.is_empty():
		screen._preview.text = "Отряд движется по маршруту…" if not screen._path.is_empty() else "Сейчас ход противника."; return
	tabs.current_tab = 0
	if not target.is_empty() and target.side != screen._actor(screen._active).side:
		var id: String = screen._attack_id(); var check: Dictionary = screen.runner.preview(screen._command("use_ability",id,int(target.actor_id)))
		screen._preview.text = "%s → %s\n%s\n\n" % [screen._ability_name(id),Sm2BattleText.actor(target),price(screen.runner.ability_cost(screen._active,id))]
		screen._preview.text += describe(check,target.has("anatomy"))
		show_hint(cell,check); return
	if screen._reachable.has(cell) and screen._selected.is_empty():
		var path: Dictionary = screen._reachable[cell]; screen.board.route.assign(path.path)
		screen._preview.text = "Перемещение → (%s, %s)\n%s\nШагов: %s\n\nПопадание ответного удара остановит путь." % [cell.x,cell.y,price(path),path.path.size()]; screen.board.queue_redraw(); return
	if not target.is_empty(): screen._preview.text = "Осмотр: "+Sm2BattleText.actor(target)+"\nДействует только боец, чей ход наступил."
	else: screen._preview.text = "Выберите действие и наведите на цель.\nНа свободной клетке показаны путь и его цена."

func show_hint(cell: Vector2i, check: Dictionary) -> void:
	if not check.get("allowed",false): return
	hint_text.text="Без промаха\nПовреждение тканей: %s" % check.hp_loss if check.get("kind","")=="spell" else "Попадание: %s%%" % check.get("hit_chance",100)
	target_hint.reset_size()
	var point: Vector2=screen.board.position+screen.board.center(cell)+Vector2(42,-66)
	point.x=clampf(point.x,screen.board.position.x,screen.board.position.x+screen.board.size.x-target_hint.size.x)
	point.y=clampf(point.y,screen.board.position.y,screen.board.position.y+screen.board.size.y-target_hint.size.y)
	target_hint.position=point; target_hint.show()

func describe(check: Dictionary, anatomy: bool) -> String:
	if not check.get("allowed",false): return reason(check.get("reason",""))
	if check.get("kind","") == "barrier": return "Защита: %s\nДо начала следующего хода.\nПоглощает атаки после брони; яд проходит.\nПовтор заменит остаток защиты: %s." % [check.capacity,check.previous]
	if check.get("kind","") == "spell":
		return "Без промаха\n%s: %s\nПси-щит поглотит: %s\nОбходит броню и предметный щит.%s" % ["Повреждение тканей" if anatomy else "Потеря здоровья",check.hp_loss,check.get("absorbed",0),"\nСмертельное повреждение." if check.get("lethal",false) else ""]
	if check.has("shield_loss"): return "Без промаха\nЩит потеряет %s прочности." % check.shield_loss
	var result: String = "Попадание: %s%%\n" % check.get("hit_chance",0)
	for zone: Dictionary in check.get("zones",[]):
		result += "%s (%s%%): %s %s–%s\nБроня: %s–%s\n" % [check.get("function_trauma","Голова" if zone.id=="head" else "Тело"),zone.chance,"повреждение" if anatomy else "здоровье",zone.hp_min,zone.hp_max,zone.armor_min,zone.armor_max]
	result += "При попадании; защита учтена."
	if anatomy: result += "\nПовреждение затем распределяется по тканям."
	if check.has("hybrid"): result += "\nПси-часть включена. Промах тоже расходует ресурсы."
	return result

func decorate(value: Button, id: String, selected: bool) -> void:
	value.custom_minimum_size = Vector2(132,82); value.clip_text = true; value.add_theme_font_size_override("font_size",12)
	value.icon=null
	var glyph: TextureRect=TextureRect.new(); glyph.texture=icon(id); glyph.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; glyph.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter=Control.MOUSE_FILTER_IGNORE; glyph.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); glyph.position=Vector2(48,5); glyph.size=Vector2(36,32); value.add_child(glyph)
	if value.disabled: glyph.modulate=Color("77776a")
	var psychic: bool=accents.get(id,"")=="psi"
	if psychic:
		value.add_theme_stylebox_override("normal",box(Color("172329"),Color("456d7a")))
		value.add_theme_stylebox_override("hover",box(Color("243740"),Sm2BronzeTheme.PSI))
	if selected: value.add_theme_stylebox_override("normal",box(Color("283e46") if psychic else Color("41321d"),Sm2BronzeTheme.PSI if psychic else GOLD))

	for state: String in ["normal","hover","pressed","disabled"]:
		var style: StyleBox=(value.get_theme_stylebox(state) if value.has_theme_stylebox_override(state) else screen.theme.get_stylebox(state,"Button")).duplicate() as StyleBox
		style.content_margin_top=40; style.content_margin_bottom=4
		value.add_theme_stylebox_override(state,style)

func icon(id: String) -> Texture2D:
	var resource: String = str(metadata.get(id,metadata.get("default","")))
	if resource.begins_with("painted:"): return painted_icons.get(resource.trim_prefix("painted:"))
	if resource.begins_with("atlas:"): return art.sprites.get(resource.trim_prefix("atlas:")) if art != null else null
	return load(resource) as Texture2D if not resource.is_empty() else null

func portrait_texture() -> Texture2D:
	return art.sprites.get("head_hair") if art != null else null

func page(title: String, node_name: String, font_size: int, parchment: bool=false) -> RichTextLabel:
	var panel: MarginContainer = MarginContainer.new(); panel.name = title
	for side: String in ["left","right","top","bottom"]: panel.add_theme_constant_override("margin_"+side,8)
	tabs.add_child(panel)
	var surface: PanelContainer=PanelContainer.new(); surface.name=node_name+"Surface"; panel.add_child(surface)
	surface.add_theme_stylebox_override("panel",Sm2BronzeTheme.paper(10) if parchment else Sm2BronzeTheme.box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.PANEL,0))
	var value: RichTextLabel = RichTextLabel.new(); value.name = node_name; value.selection_enabled = true; value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("normal_font_size",font_size); value.add_theme_color_override("default_color",Sm2BronzeTheme.INK if parchment else Sm2BronzeTheme.TEXT)
	if parchment: value.add_theme_font_override("normal_font",Sm2BronzeTheme.SERIF)
	surface.add_child(value); return value

func load_painted_icons() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/bronze_icons.json"))
	accents=data.get("accents",{}).duplicate(true)
	var texture: Texture2D=load(data.texture) as Texture2D
	var cell: Vector2=texture.get_size()/Vector2(int(data.columns),int(data.rows))
	for id: String in data.regions:
		var index: int=int(data.regions[id]); var atlas: AtlasTexture=AtlasTexture.new(); atlas.atlas=texture
		atlas.region=Rect2(Vector2(index%int(data.columns),index/int(data.columns))*cell,cell)
		atlas.filter_clip=true; painted_icons[id]=atlas

static func price(cost: Dictionary) -> String:
	if cost.is_empty(): return "Цена недоступна"
	var parts: PackedStringArray = ["%s ОД" % cost.get("ap_cost",0)]
	if int(cost.get("fatigue_cost",0))>0: parts.append("%s уст." % cost.fatigue_cost)
	if int(cost.get("mana_cost",0))>0: parts.append("%s конц." % cost.mana_cost)
	if int(cost.get("ammo_cost",0))>0: parts.append("%s стр." % cost.ammo_cost)
	return " · ".join(parts)

static func reason(code: String) -> String:
	if code == "not_player_turn": return "Дождитесь своего хода или завершения движения."
	if code == "target_unavailable": return "Нет доступной цели."
	if code == "ability_unavailable": return "Способность недоступна этому бойцу."
	if code.contains(" "): return code
	return Sm2BattleText.reason(code)

static func clear(parent: Node) -> void:
	for child: Node in parent.get_children(): parent.remove_child(child); child.queue_free()

static func label(text: String, font_size: int, tint: Color) -> Label:
	var value: Label = Label.new(); value.text = text; value.add_theme_font_size_override("font_size",font_size); value.add_theme_color_override("font_color",tint); return value

static func button(text: String, id: String, action: Callable, disabled: bool = false) -> Button:
	var value: Button = Button.new(); value.text = text; value.name = id; value.disabled = disabled; value.custom_minimum_size.y = 38
	value.add_theme_font_size_override("font_size",13)
	value.pressed.connect(action); return value

static func box(fill: Color=Sm2BronzeTheme.PANEL, border: Color=Sm2BronzeTheme.BORDER) -> StyleBoxFlat:
	return Sm2BronzeTheme.box(fill,border)
