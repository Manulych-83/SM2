class_name Sm2HeroDevelopmentScreen
extends Control
signal camp_requested
var session: Sm2LifeSession
var selected_id: String=""
var _query: String=""
var _focused: String=""
var _notice: String=""
var _content: Control
var _track_list: VBoxContainer
var _details: ScrollContainer
var _model: Dictionary={}
const INK: Color=Color("e9e8de")
const GOLD: Color=Color("d1b478")
const MUTED: Color=Color("a3b0b4")

static func control_id(prefix: String,id: String) -> String: return prefix+"_"+id.sha256_text().substr(0,16)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); redraw()

func redraw() -> void:
	if is_instance_valid(_content): remove_child(_content); _content.queue_free()
	_model=Sm2HeroDevelopmentView.build(session,selected_id)
	if not _model.selected.is_empty(): selected_id=_model.selected.id
	var margin: MarginContainer=MarginContainer.new(); _content=margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var column: VBoxContainer=VBoxContainer.new(); margin.add_child(column)
	var header: HBoxContainer=HBoxContainer.new(); column.add_child(header)
	var title: Label=_label("РАЗВИТИЕ ГЕРОЯ",24,GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(_button("Сохранить","HeroDevelopmentSave",_save))
	header.add_child(_button("Загрузить","HeroDevelopmentLoad",_load))
	header.add_child(_button("В лагерь","HeroDevelopmentBack",func() -> void: camp_requested.emit()))
	column.add_child(_label("Практика принадлежит текущему телу. Спутник растёт автоматически. Знания Души сохраняются отдельно.",14,MUTED))
	if not _notice.is_empty(): column.add_child(_label(_notice,14,GOLD))
	if not _model.message.is_empty(): column.add_child(_label(_model.message,16,GOLD))
	if _model.selected.is_empty(): return
	var panes: HBoxContainer=HBoxContainer.new(); panes.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(panes)
	var left: VBoxContainer=VBoxContainer.new(); left.custom_minimum_size.x=245; panes.add_child(left)
	var filter: LineEdit=LineEdit.new(); filter.name="HeroTrackFilter"; filter.placeholder_text="Найти направление"; filter.text=_query; left.add_child(filter)
	filter.text_changed.connect(func(value: String) -> void: _query=value; _populate_tracks())
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(scroll)
	_track_list=VBoxContainer.new(); _track_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(_track_list); _populate_tracks()
	_details=ScrollContainer.new(); _details.name="HeroDevelopmentDetails"; _details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _details.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panes.add_child(_details)
	var right: VBoxContainer=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _details.add_child(right)
	var track: Dictionary=_model.selected
	right.add_child(_label(track.name,24,GOLD))
	var summary: Label=_label("Собственный уровень: %s · с прибавками: %s\nОпыт: заработано %s · потрачено %s · доступно %s" % [track.level,track.effective,track.earned,track.spent,track.available],16,INK)
	summary.name="HeroTrackSummary"; right.add_child(summary)
	var bar: ProgressBar=ProgressBar.new(); bar.name="HeroTrackProgress"; bar.max_value=track.needed; bar.value=track.progress; bar.show_percentage=false; bar.custom_minimum_size.y=16; right.add_child(bar)
	right.add_child(_label("До следующего уровня: %s / %s. Покупка узлов не уменьшает уровень или это продвижение." % [track.progress,track.needed],14,MUTED))
	for source: Dictionary in track.get("upgrade_sources",[]): right.add_child(_label("%s: +%s к эффективному значению. Собственная практика не меняется." % [source.name,source.amount],14,GOLD))
	for source: Dictionary in track.sources: right.add_child(_label("Вклад «%s»: +%s. Этот вклад не выдаёт собственный опыт." % [source.name,source.amount],14,MUTED))
	for link: Dictionary in _model.links:
		var destination: String=link.target if selected_id==link.source else link.source
		right.add_child(_button("%s → %s (%s/%s)" % [link.source_name,link.target_name,link.numerator,link.denominator],control_id("HeroContribution",destination),_select.bind(destination,"")))
	right.add_child(_label("Узлы направления",20,GOLD))
	if _model.nodes.is_empty(): right.add_child(_label("Для этого направления узлы пока не добавлены.",16,MUTED))
	for node: Dictionary in _model.nodes: _node(right,node)

func _populate_tracks() -> void:
	for child: Node in _track_list.get_children(): _track_list.remove_child(child); child.queue_free()
	var count: int=0
	var query: String=_query.strip_edges().to_lower()
	for kind: String in ["attribute","skill"]:
		var shown: bool=false
		for track: Dictionary in _model.tracks:
			if track.kind!=kind or (not query.is_empty() and not str(track.name).to_lower().contains(query)): continue
			if not shown: _track_list.add_child(_label("Характеристики" if kind=="attribute" else "Навыки",16,GOLD)); shown=true
			var button: Button=_button("%s · %s" % [track.name,track.level],control_id("HeroTrack",track.id),_select.bind(track.id,""))
			button.toggle_mode=true; button.button_pressed=track.id==selected_id; _track_list.add_child(button); count+=1
	if count==0: _track_list.add_child(_label("Нет совпадений.",14,MUTED))

func _node(parent: VBoxContainer,node: Dictionary) -> void:
	var panel: PanelContainer=PanelContainer.new(); panel.name=control_id("HeroNode",node.id); parent.add_child(panel)
	var style: StyleBoxFlat=StyleBoxFlat.new(); style.bg_color=Color("17272f"); style.border_color=GOLD if node.owned or node.id==_focused else Color("40525b")
	style.set_border_width_all(1); style.set_content_margin_all(12); panel.add_theme_stylebox_override("panel",style)
	var box: VBoxContainer=VBoxContainer.new(); panel.add_child(box)
	box.add_child(_label(node.name,19,GOLD if node.owned else INK))
	for effect: String in node.effects: box.add_child(_label(effect,14,INK))
	box.add_child(_label("Собственный уровень: %s / требуется %s\nЦена: %s · доступно: %s опыта «%s»" % [_model.selected.level,node.min_level,node.cost,_model.selected.available,_model.selected.name],14,MUTED))
	for requirement: Dictionary in node.get("extra_requirements",[]):
		box.add_child(_button("%s: свой %s / требуется %s" % [requirement.name,requirement.level,requirement.min_level],control_id("HeroCrossRequirement",node.id+requirement.track_id),_select.bind(requirement.track_id,"")))
	for price: Dictionary in node.get("extra_costs",[]):
		box.add_child(_label("Дополнительно: %s опыта «%s» · доступно %s" % [price.cost,price.name,price.available],14,MUTED))
	for needed: Dictionary in node.requires:
		box.add_child(_button("← Требуется: "+needed.name+(" · изучено" if needed.owned else " · не изучено"),control_id("HeroRequires",node.id+needed.id),_select.bind(needed.track_id,needed.id)))
	for next: Dictionary in node.unlocks:
		box.add_child(_button("→ Следующий узел: "+next.name,control_id("HeroNext",node.id+next.id),_select.bind(next.track_id,next.id)))
	var state: Label=_label("Изучено этим телом" if node.owned else "Можно изучить" if node.allowed else node.reason,14,GOLD if node.allowed or node.owned else MUTED)
	state.name=control_id("HeroNodeStatus",node.id); box.add_child(state)
	box.add_child(_button("Изучено" if node.owned else "Изучить",control_id("HeroBuy",node.id),_buy.bind(node.id,_model.context.duplicate(true)),not node.allowed))

func _select(id: String,node: String) -> void:
	selected_id=id; _focused=node; redraw()
	if not node.is_empty(): _focus_node.call_deferred(node)

func _focus_node(id: String) -> void:
	await get_tree().process_frame
	var card: Control=find_child(control_id("HeroNode",id),true,false) as Control
	if card!=null and is_instance_valid(_details): _details.ensure_control_visible(card)

func _buy(id: String,context: Dictionary) -> void:
	var command: Sm2WorldCommand=session.command("buy_node",int(context.body_id),id)
	command.world_id=context.world_id; command.expected_revision=int(context.revision); command.incarnation_id=int(context.incarnation_id); command.body_id=int(context.body_id)
	var result: Dictionary=session.act(command)
	_notice="Узел изучен. Уровень и заработанный опыт сохранены." if result.ok else Sm2HeroDevelopmentView.reason_text(str(result.errors[0])); redraw()

func _save() -> void:
	var result: Dictionary=session.save_game(); _notice="Мир сохранён." if result.ok else str(result.errors); redraw()
func _load() -> void:
	var result: Dictionary=session.load_game(); _notice="Мир восстановлен." if result.ok else str(result.errors); redraw()
static func _label(value: String,size: int,color: Color) -> Label: return Sm2LifeScreen._label(value,size,color)
static func _button(value: String,id: String,action: Callable,disabled: bool=false) -> Button:
	var button: Button=Sm2LifeScreen._button(value,id,action,disabled); button.custom_minimum_size.y=40; return button
