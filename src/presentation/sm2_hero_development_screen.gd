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
var _sources: Dictionary={}
var _kind: String=""
var _companion: bool=false
var _node_filter: int=0
var _node_list: VBoxContainer
var _node_page: int=0
var _node_query: String=""
var _track_page: int=0
var _link_page: int=0
var _link_offsets: Dictionary={}
var back_text: String="В лагерь"
const INK: Color=Sm2BronzeTheme.TEXT
const GOLD: Color=Sm2BronzeTheme.GOLD
const MUTED: Color=Sm2BronzeTheme.MUTED

static func control_id(prefix: String,id: String) -> String: return prefix+"_"+id.sha256_text().substr(0,16)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=Sm2BronzeTheme.create()
	theme.set_stylebox("background","ProgressBar",Sm2BronzeTheme.box(Sm2BronzeTheme.BACKGROUND,Sm2BronzeTheme.DIM_BORDER,0))
	theme.set_stylebox("fill","ProgressBar",Sm2BronzeTheme.box(Color("927347"),GOLD,0))
	resized.connect(_schedule_layout); redraw()

var _pending_layout: bool=false
func _schedule_layout() -> void:
	if _pending_layout: return
	_pending_layout=true; call_deferred("_resize_layout")
func _resize_layout() -> void:
	_pending_layout=false
	if is_inside_tree(): redraw()

func redraw() -> void:
	if is_instance_valid(_content): remove_child(_content); _content.queue_free()
	_model=Sm2HeroDevelopmentView.build(session,selected_id,{"compact_tracks":true,"page":_node_page,"filter":_node_filter,"query":_node_query,"focus":_focused,"link_offsets":_link_offsets,"link_page":_link_page})
	_node_page=_model.node_page
	if not _model.selected.is_empty(): selected_id=_model.selected.id
	_sources=Sm2DevelopmentSources.build(session,selected_id)
	var surface: Panel=Panel.new(); _content=surface; surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); surface.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.BACKGROUND,Sm2BronzeTheme.BACKGROUND,0)); add_child(surface)
	var margin: MarginContainer=MarginContainer.new(); surface.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	var column: VBoxContainer=VBoxContainer.new(); column.add_theme_constant_override("separation",12); margin.add_child(column)
	var header: HBoxContainer=HBoxContainer.new(); _frame(column).add_child(header)
	var title: Label=_label("РАЗВИТИЕ",24,GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.add_theme_font_override("font",Sm2BronzeTheme.SERIF); header.add_child(title)
	for entry: Array in [["Герой","HeroDevelopmentHero",false],["Спутник","HeroDevelopmentCompanion",true]]:
		var choice: Button=_button(entry[0],entry[1],func() -> void: _companion=entry[2]; redraw(),bool(entry[2]) and _sources.companion.is_empty())
		choice.toggle_mode=true; choice.button_pressed=_companion==bool(entry[2]); header.add_child(choice)
	header.add_child(_button("Сохранить","HeroDevelopmentSave",_save))
	header.add_child(_button("Загрузить","HeroDevelopmentLoad",_load))
	header.add_child(_button(back_text,"HeroDevelopmentBack",func() -> void: camp_requested.emit()))
	var notice: Label=_label(_notice if not _notice.is_empty() else "Практика и узлы принадлежат телу. Знания Души сохраняются при новом воплощении.",14,GOLD if not _notice.is_empty() else MUTED); notice.name="HeroDevelopmentNotice"; column.add_child(notice)
	if _companion: _show_companion(column); return
	if not _model.message.is_empty(): column.add_child(_label(_model.message,16,GOLD))
	if _model.selected.is_empty(): return
	var panes: HBoxContainer=HBoxContainer.new(); panes.size_flags_vertical=Control.SIZE_EXPAND_FILL; panes.add_theme_constant_override("separation",12); column.add_child(panes)
	var left: VBoxContainer=VBoxContainer.new(); left.custom_minimum_size.x=224; _frame(panes).add_child(left)
	left.add_child(_label("НАПРАВЛЕНИЯ",15,GOLD))
	var filter: LineEdit=LineEdit.new(); filter.name="HeroTrackFilter"; filter.placeholder_text="Найти направление"; filter.text=_query; left.add_child(filter)
	filter.text_changed.connect(func(value: String) -> void: _query=value; _track_page=0; _populate_tracks())
	var kinds: HBoxContainer=HBoxContainer.new(); left.add_child(kinds)
	for entry: Array in [["Все",""],["Хар-ки","attribute"],["Навыки","skill"]]:
		var button: Button=_button(entry[0],"HeroKind_"+entry[1],func() -> void: _kind=entry[1]; _track_page=0; _populate_tracks()); button.toggle_mode=true; button.custom_minimum_size.x=66; button.add_theme_font_size_override("font_size",12); kinds.add_child(button)
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(scroll)
	_track_list=VBoxContainer.new(); _track_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(_track_list); _populate_tracks()
	var center: VBoxContainer
	if size.x>=1200:
		var panel: PanelContainer=_frame(panes); panel.custom_minimum_size.x=340; center=_scroll(panel)
		_summary(center)
	var node_panel: PanelContainer=_frame(panes); node_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_details=ScrollContainer.new(); _details.name="HeroDevelopmentDetails"; _details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _details.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; node_panel.add_child(_details)
	var right: VBoxContainer=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _details.add_child(right)
	if size.x<1200: _summary(right)
	var node_header: HBoxContainer=HBoxContainer.new(); right.add_child(node_header)
	var node_title: Label=_label("УЗЛЫ НАПРАВЛЕНИЯ",17,GOLD); node_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; node_header.add_child(node_title)
	var state_filter: OptionButton=OptionButton.new(); state_filter.name="HeroNodeFilter"; state_filter.fit_to_longest_item=false; state_filter.custom_minimum_size.x=145; node_header.add_child(state_filter)
	for title_text: String in ["Все узлы","Доступные","Изученные"]: state_filter.add_item(title_text)
	state_filter.select(_node_filter); state_filter.item_selected.connect(func(index: int) -> void: _node_filter=index; _node_page=0; _focused=""; redraw())
	var search: LineEdit=LineEdit.new(); search.name="HeroNodeSearch"; search.placeholder_text="Название узла · Enter для поиска"; search.text=_node_query; right.add_child(search)
	search.text_submitted.connect(func(value: String) -> void: _node_query=value; _node_page=0; _focused=""; redraw())
	if int(_model.node_pages)>1:
		_pager(right,"HeroNodes",_node_page,int(_model.node_pages),int(_model.node_count),func(page: int) -> void: _node_page=page; _focused=""; redraw())
	_node_list=VBoxContainer.new(); _node_list.add_theme_constant_override("separation",12); right.add_child(_node_list); _populate_nodes()

func _summary(right: VBoxContainer) -> void:
	var track: Dictionary=_model.selected
	var heading: Label=_label(track.name,28,GOLD); heading.add_theme_font_override("font",Sm2BronzeTheme.SERIF); right.add_child(heading)
	var summary: Label=_label("Собственный уровень: %s · с прибавками: %s\nОпыт: заработано %s · потрачено %s · доступно %s" % [track.level,track.effective,track.earned,track.spent,track.available],16,INK)
	summary.name="HeroTrackSummary"; right.add_child(summary)
	var bar: ProgressBar=ProgressBar.new(); bar.name="HeroTrackProgress"; bar.max_value=track.needed; bar.value=track.progress; bar.show_percentage=false; bar.custom_minimum_size.y=16; right.add_child(bar)
	right.add_child(_label("Продвижение: %s / %s XP\nДо следующего уровня: %s XP. Покупка узлов не уменьшает уровень или продвижение." % [track.progress,track.needed,int(track.needed)-int(track.progress)],14,MUTED))
	if int(track.node_bonus)>0: right.add_child(_label("Изученные узлы: +%s к значению." % track.node_bonus,14,GOLD))
	for source: Dictionary in track.get("upgrade_sources",[]): right.add_child(_label("%s: +%s к эффективному значению. Собственная практика не меняется." % [source.name,source.amount],14,GOLD))
	for source: Dictionary in track.sources: right.add_child(_label("Вклад «%s»: +%s. Этот вклад не выдаёт собственный опыт." % [source.name,source.amount],14,MUTED))
	for link: Dictionary in _model.links:
		var destination: String=link.target if selected_id==link.source else link.source
		right.add_child(_button("%s → %s (%s/%s)" % [link.source_name,link.target_name,link.numerator,link.denominator],control_id("HeroContribution",destination),_select.bind(destination,"")))
	if int(_model.link_pages)>1:
		_pager(right,"HeroContributions",int(_model.link_page),int(_model.link_pages),int(_model.link_count),func(page: int) -> void: _link_page=page; redraw())
	right.add_child(_label("КАК ПОЛУЧАТЬ ОПЫТ",16,GOLD))
	if _sources.practice.is_empty(): right.add_child(_label("Для этого направления в текущем примере ещё нет источников практики.",14,MUTED))
	for source: Dictionary in _sources.practice:
		var title: String=source.name if not str(source.name).is_empty() else Sm2BattleText.ability(source.id)
		var kind: String={"combat":"Бой","practice":"Упражнение","explore":"Осмотр"}[source.kind]
		right.add_child(_label("%s · %s\n+%s XP%s" % [kind,title,int(source.xp)," · %s сек" % int(source.seconds) if int(source.seconds)>0 else ""],14,INK))
		right.add_child(_label(source.reason if not str(source.reason).is_empty() else "Сейчас доступно в лагере.",12,MUTED))

func _populate_nodes() -> void:
	Sm2SurvivalWorkspace.clear(_node_list)
	var count: int=0
	for node: Dictionary in _model.nodes:
		if _node_filter==1 and not node.allowed: continue
		if _node_filter==2 and not node.owned: continue
		_node(_node_list,node); count+=1
	if count==0: _node_list.add_child(_label("Нет узлов для этого фильтра." if _node_filter>0 or not _node_query.strip_edges().is_empty() else "Для этого направления узлы пока не добавлены.",16,MUTED))

func _frame(parent: Node) -> PanelContainer:
	var panel: PanelContainer=PanelContainer.new(); panel.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.BORDER,14)); parent.add_child(panel); return panel

func _scroll(parent: Node) -> VBoxContainer:
	return Sm2SurvivalWorkspace.scroll_column(parent,1)

func _show_companion(parent: VBoxContainer) -> void:
	if _sources.companion.is_empty(): parent.add_child(_label(_sources.message if not _sources.message.is_empty() else "Нет спутника с автоматическим развитием.",18,MUTED)); return
	var data: Dictionary=_sources.companion
	var panel: PanelContainer=_frame(parent); panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var column: VBoxContainer=_scroll(panel)
	column.add_child(_label("СПУТНИК · УРОВЕНЬ %s" % data.level,28,GOLD))
	column.add_child(_label("Жив · развивается автоматически" if data.alive else "Погиб · развитие сохранено у прежнего тела",16,MUTED))
	column.add_child(_label("Всего опыта: %s · до следующего уровня: %s XP" % [data.earned,int(data.needed)-int(data.progress)],19,INK))
	var bar: ProgressBar=ProgressBar.new(); bar.name="CompanionProgress"; bar.max_value=data.needed; bar.value=data.progress; bar.show_percentage=false; bar.custom_minimum_size.y=10; column.add_child(bar)
	column.add_child(_label("За личную выполненную атаку: +%s XP, включая промах и ответный удар. За каждый уровень — автоматические прибавки ниже." % int(data.attack_xp),16,MUTED))
	var grid: GridContainer=GridContainer.new(); grid.columns=2; grid.add_theme_constant_override("h_separation",14); grid.add_theme_constant_override("v_separation",12); column.add_child(grid)
	for row: Dictionary in data.attributes:
		var card: PanelContainer=_frame(grid); card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var value: Label=_label("%s · %s\n+%s за каждый полученный уровень" % [row.name,row.level,int(row.per_level)],19,INK); value.name=control_id("CompanionAttribute",row.id); card.add_child(value)
	column.add_child(_label("Ближний бой: +%s за каждый полученный уровень." % int(data.melee_per_level),16,GOLD))
	column.add_child(_label("Спутник не тратит отдельную практику и не покупает узлы героя.",16,MUTED))

func _populate_tracks() -> void:
	for kind: String in ["","attribute","skill"]:
		var tab: Button=find_child("HeroKind_"+kind,true,false) as Button
		if tab!=null: tab.button_pressed=kind==_kind
	for child: Node in _track_list.get_children(): _track_list.remove_child(child); child.queue_free()
	var count: int=0
	var query: String=_query.strip_edges().to_lower()
	var matches: Array[Dictionary]=[]
	for kind: String in ["attribute","skill"]:
		for track: Dictionary in _model.tracks:
			if track.kind!=kind or (not _kind.is_empty() and track.kind!=_kind) or (not query.is_empty() and not str(track.name).to_lower().contains(query)): continue
			matches.append(track)
	var pages: int=maxi(1,ceili(float(matches.size())/Sm2HeroDevelopmentView.PAGE_SIZE))
	_track_page=clampi(_track_page,0,pages-1)
	if pages>1: _pager(_track_list,"HeroTracks",_track_page,pages,matches.size(),func(page: int) -> void: _track_page=page; _populate_tracks())
	for kind: String in ["attribute","skill"]:
		var shown: bool=false
		for track: Dictionary in matches.slice(_track_page*Sm2HeroDevelopmentView.PAGE_SIZE,(_track_page+1)*Sm2HeroDevelopmentView.PAGE_SIZE):
			if track.kind!=kind: continue
			track=Sm2HeroDevelopmentView.track_details(session,track.id)
			if not shown: _track_list.add_child(_label("Характеристики" if kind=="attribute" else "Навыки",16,GOLD)); shown=true
			var button: Button=_button("%s · %s" % [track.name,track.level],control_id("HeroTrack",track.id),_select.bind(track.id,"")); button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.tooltip_text="Свой уровень: %s · итоговое значение: %s · доступно %s XP" % [track.level,track.effective,track.available]
			button.toggle_mode=true; button.button_pressed=track.id==selected_id; _track_list.add_child(button); count+=1
	if count==0: _track_list.add_child(_label("Нет совпадений.",14,MUTED))

func _node(parent: VBoxContainer,node: Dictionary) -> void:
	var panel: PanelContainer=PanelContainer.new(); panel.name=control_id("HeroNode",node.id); parent.add_child(panel)
	var style: StyleBoxFlat=StyleBoxFlat.new(); style.bg_color=Color("241d14"); style.border_color=GOLD if node.owned or node.id==_focused else Sm2BronzeTheme.DIM_BORDER
	style.set_border_width_all(1); style.set_content_margin_all(12); panel.add_theme_stylebox_override("panel",style)
	var box: VBoxContainer=VBoxContainer.new(); panel.add_child(box)
	box.add_child(_label(node.name,19,GOLD if node.owned else INK))
	for effect: String in node.effects: box.add_child(_label(effect,14,INK))
	box.add_child(_label("Собственный уровень: %s / требуется %s\nЦена: %s · доступно: %s опыта «%s»" % [_model.selected.level,node.min_level,node.cost,_model.selected.available,_model.selected.name],14,MUTED))
	if not node.owned and int(_model.selected.level)<int(node.min_level): box.add_child(_label("Недостаток собственного уровня: %s." % (int(node.min_level)-int(_model.selected.level)),14,Sm2SurvivalWorkspace.DANGER))
	if not node.owned and int(_model.selected.available)<int(node.cost): box.add_child(_label("Не хватает %s XP направления «%s»." % [int(node.cost)-int(_model.selected.available),_model.selected.name],14,Sm2SurvivalWorkspace.DANGER))
	for requirement: Dictionary in node.get("extra_requirements",[]):
		box.add_child(_button("%s: свой %s / требуется %s" % [requirement.name,requirement.level,requirement.min_level],control_id("HeroCrossRequirement",node.id+requirement.track_id),_select.bind(requirement.track_id,"")))
		if not node.owned and int(requirement.level)<int(requirement.min_level): box.add_child(_label("Не хватает %s уровней «%s»." % [int(requirement.min_level)-int(requirement.level),requirement.name],14,Sm2SurvivalWorkspace.DANGER))
	for price: Dictionary in node.get("extra_costs",[]):
		box.add_child(_label("Дополнительно: %s опыта «%s» · доступно %s" % [price.cost,price.name,price.available],14,MUTED))
		if not node.owned and int(price.available)<int(price.cost): box.add_child(_label("Не хватает %s XP направления «%s»." % [int(price.cost)-int(price.available),price.name],14,Sm2SurvivalWorkspace.DANGER))
	for needed: Dictionary in node.requires:
		box.add_child(_button("← Требуется: "+needed.name+(" · изучено" if needed.owned else " · не изучено"),control_id("HeroRequires",node.id+needed.id),_select.bind(needed.track_id,needed.id)))
	for next: Dictionary in node.unlocks:
		box.add_child(_button("→ Следующий узел: "+next.name,control_id("HeroNext",node.id+next.id),_select.bind(next.track_id,next.id)))
	for kind: String in ["requires","unlocks"]:
		if int(node[kind+"_pages"])>1:
			box.add_child(_label("Предпосылки" if kind=="requires" else "Следующие узлы",14,MUTED))
			_pager(box,control_id("HeroLinks",node.id+kind),int(node[kind+"_page"]),int(node[kind+"_pages"]),int(node[kind+"_count"]),func(page: int) -> void: _link_offsets[node.id+"/"+kind]=page; redraw(); _focus_node.call_deferred(node.id))
	var state: Label=_label("Изучено этим телом" if node.owned else "Можно изучить" if node.allowed else node.reason,14,GOLD if node.allowed or node.owned else MUTED)
	state.name=control_id("HeroNodeStatus",node.id); box.add_child(state)
	box.add_child(_button("Изучено" if node.owned else "Изучить",control_id("HeroBuy",node.id),_buy.bind(node.id,_model.context.duplicate(true)),not node.allowed))

func _select(id: String,node: String) -> void:
	selected_id=id; _focused=node
	_node_page=0; _link_page=0; _link_offsets.clear()
	if not node.is_empty(): _node_filter=0; _node_query=""
	redraw()
	if not node.is_empty(): _focus_node.call_deferred(node)

func _pager(parent: Node,prefix: String,page: int,pages: int,count: int,action: Callable) -> void:
	var row: HBoxContainer=HBoxContainer.new(); parent.add_child(row)
	var previous: Button=_button("‹",prefix+"Previous",action.bind(page-1),page==0); previous.custom_minimum_size.x=32; row.add_child(previous)
	var label: Label=_label("%s / %s · %s" % [page+1,pages,count],12,MUTED); label.name=prefix+"Page"; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.tooltip_text="Страница %s из %s. Всего: %s." % [page+1,pages,count]; row.add_child(label)
	var next: Button=_button("›",prefix+"Next",action.bind(page+1),page>=pages-1); next.custom_minimum_size.x=32; row.add_child(next)

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
static func _label(value: String,size: int,color: Color) -> Label: return Sm2SurvivalWorkspace.label(value,size,color)
static func _button(value: String,id: String,action: Callable,disabled: bool=false) -> Button:
	var button: Button=Sm2SurvivalWorkspace.button(value,id,action); button.disabled=disabled; button.custom_minimum_size.y=40; return button

func _unhandled_input(event: InputEvent) -> void:
	if Sm2Controls.back(event):
		get_viewport().set_input_as_handled(); camp_requested.emit()
