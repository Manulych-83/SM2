class_name Sm2WorkspaceLayout
extends RefCounted
## Responsive placement. Holds nodes, but no owning RefCounted cycle with the screen.
var owner: Sm2SurvivalWorkspace
var rail: ScrollContainer
var summary: PanelContainer
var center: Panel
var right: PanelContainer
var header: PanelContainer
var footer: Label
var figure: Sm2WorkspaceFigure
var slots: Array[Button]=[]
var settling: bool=false
var content: VBoxContainer

func build(screen: Sm2SurvivalWorkspace) -> void:
	owner=screen
	var background: ColorRect=ColorRect.new(); background.color=Color("111310"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); owner.layout.add_child(background)
	header=frame(); var nav: HBoxContainer=HBoxContainer.new(); header.add_child(nav)
	for row: Array in [["Инвентарь","WorkspaceInventoryTab",1],["Тело","WorkspaceBodyTab",0]]:
		var tab: Button=owner.button(row[0],row[1],owner.change_tab.bind(row[2])); tab.toggle_mode=true; tab.button_pressed=int(owner.ui.tab)==row[2]; nav.add_child(tab)
	nav.add_child(owner.button("Развитие","WorkspaceDevelopment",owner.open_development))
	var location: Label=owner.label(owner.view.location+" · Вне боя",13,Sm2BronzeTheme.MUTED); location.size_flags_horizontal=Control.SIZE_EXPAND_FILL; location.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; nav.add_child(location)
	nav.add_child(owner.button("В лагерь","WorkspaceBack",func() -> void: owner.closed.emit(owner.ui.duplicate(true),owner.message)))
	rail=ScrollContainer.new(); rail.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; owner.layout.add_child(rail)
	var people: VBoxContainer=VBoxContainer.new(); people.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rail.add_child(people)
	people.add_child(owner.label("ОТРЯД",12,Sm2BronzeTheme.MUTED))
	for row: Dictionary in owner.view.people:
		var card: Button=owner.button(row.name,"WorkspacePerson_"+str(row.id),owner.choose_person.bind(int(row.id))); card.custom_minimum_size=Vector2(74,110); card.add_theme_font_size_override("font_size",12); card.icon=owner.artwork.art.sprites.get("head_hair"); card.expand_icon=true; card.add_theme_constant_override("icon_max_width",42); card.tooltip_text=row.name
		card.text=""; card.toggle_mode=true; card.button_pressed=int(row.id)==int(owner.ui.body); people.add_child(card)
		var name_label: Label=owner.label(row.name if row.alive else "Тело №%s" % row.id,11,Sm2BronzeTheme.GOLD); name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; people.add_child(name_label)
	var selector: OptionButton=OptionButton.new(); selector.name="WorkspacePerson"; selector.fit_to_longest_item=false; selector.custom_minimum_size.x=74; people.add_child(selector)
	for row: Dictionary in owner.view.people:
		selector.add_item(row.name); selector.set_item_metadata(selector.item_count-1,row.id)
		if int(row.id)==int(owner.ui.body): selector.select(selector.item_count-1)
	selector.item_selected.connect(func(index: int) -> void: owner.choose_person(int(selector.get_item_metadata(index))))
	summary=frame(); var summary_column: VBoxContainer=owner.scroll_column(summary,1)
	var body: Dictionary=owner.view.body
	summary_column.add_child(owner.label(body.name,25,Sm2BronzeTheme.GOLD))
	summary_column.add_child(owner.label("Жив" if body.alive else "Мёртвое тело",15))
	summary_column.add_child(owner.label("\nСОСТОЯНИЕ ТЕЛА",12,Sm2BronzeTheme.GOLD))
	summary_column.add_child(owner.label("Кровь\n%s / %s мл" % [body.blood,body.blood_max],19))
	var blood: ProgressBar=ProgressBar.new(); blood.max_value=body.blood_max; blood.value=body.blood; blood.show_percentage=false; blood.custom_minimum_size.y=6; summary_column.add_child(blood)
	blood.add_theme_stylebox_override("fill",Sm2BronzeTheme.box(Color("833e35"),Sm2BronzeTheme.DIM_BORDER,0))
	summary_column.add_child(owner.label("Кровотечение\n%s мл/мин" % body.bleeding,16,owner.DANGER if int(body.bleeding)>0 else Sm2BronzeTheme.MUTED))
	var damaged: int=0
	for part: Dictionary in owner.view.parts:
		if part.damaged or not part.working: damaged+=1
	summary_column.add_child(owner.label("Повреждённых частей: %s" % damaged if damaged>0 else "Функции сохранены" if body.alive else "Жизнь тела завершена",14,owner.DANGER if damaged>0 else Sm2BronzeTheme.MUTED))
	summary_column.add_child(owner.label("\nСНАРЯЖЕНИЕ И ГРУЗ",12,Sm2BronzeTheme.GOLD))
	summary_column.add_child(owner.label("%.2f кг" % (body.mass/1000.0),26))
	summary_column.add_child(owner.label("Включая надетые вещи и содержимое контейнеров.\n\nУ каждого контейнера свои пределы объёма, массы и размера вещи.",13,Sm2BronzeTheme.MUTED))
	center=Panel.new(); center.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.DIM_BORDER,0)); owner.layout.add_child(center)
	figure=Sm2WorkspaceFigure.new(); figure.artwork=owner.artwork; figure.view=owner.view; figure.anatomy=int(owner.ui.tab)==0; figure.selected=str(owner.ui.part); center.add_child(figure)
	var caption: Label=owner.label("ТЕЛО · осмотр" if figure.anatomy else "НАДЕТО",13,Sm2BronzeTheme.GOLD); caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; center.add_child(caption); caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); caption.offset_top=12
	if not figure.anatomy:
		for slot: String in owner.artwork.metadata.slots:
			var found: Dictionary={}
			for item: Dictionary in owner.view.items:
				if int(item.owner)==int(owner.ui.body) and item.place=="equipped" and item.slot==slot: found=item; break
			var selected: Dictionary=found.duplicate(true)
			var button: Button=owner.button(owner.artwork.metadata.slots[slot],"WorkspaceEquipment_"+slot,func() -> void:
				if not selected.is_empty(): owner.select_equipment(str(selected.id)))
			button.disabled=found.is_empty(); button.custom_minimum_size=Vector2(68,100); button.add_theme_font_size_override("font_size",11)
			button.tooltip_text=found.name if not found.is_empty() else "Ничего не надето"
			button.text=""
			center.add_child(button); slots.append(button)
			var contents: VBoxContainer=VBoxContainer.new(); contents.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(contents); contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); contents.offset_left=4; contents.offset_right=-4; contents.offset_top=8; contents.offset_bottom=-4
			var icon: TextureRect=TextureRect.new(); icon.mouse_filter=Control.MOUSE_FILTER_IGNORE; icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size.y=56; icon.size_flags_vertical=Control.SIZE_EXPAND_FILL; contents.add_child(icon)
			if not found.is_empty(): icon.texture=owner.artwork.icon(found)
			var slot_label: Label=owner.label(owner.artwork.metadata.slots[slot],11,Sm2BronzeTheme.MUTED if found.is_empty() else Sm2BronzeTheme.GOLD); slot_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; slot_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; contents.add_child(slot_label)
	else:
		var warning: Label=owner.label("Схема тела · точное состояние частей справа",12,Sm2BronzeTheme.MUTED); warning.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; center.add_child(warning); warning.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); warning.offset_top=-58; warning.offset_bottom=-12
	right=frame(); content=VBoxContainer.new(); content.add_theme_constant_override("separation",8); right.add_child(content)
	footer=owner.label("",12,Sm2BronzeTheme.MUTED); footer.name="WorkspaceNotice"; owner.layout.add_child(footer)
	footer.text=owner.message if not owner.message.is_empty() else "Изменения происходят сразу. Сохранение — после возвращения в лагерь."
	if not owner.resized.is_connected(relayout): owner.resized.connect(relayout)
	for node: Control in [header,right,footer]: node.minimum_size_changed.connect(schedule_layout)
	relayout(); schedule_layout()

func frame() -> PanelContainer:
	var panel: PanelContainer=PanelContainer.new(); panel.add_theme_stylebox_override("panel",Sm2BronzeTheme.box(Sm2BronzeTheme.PANEL,Sm2BronzeTheme.BORDER,12)); owner.layout.add_child(panel); return panel

func rect(node: Control,x: float,y: float,w: float,h: float) -> void:
	node.position=Vector2(x,y); node.size=Vector2(maxf(0,w),maxf(0,h))

func relayout() -> void:
	if not is_instance_valid(owner.layout): return
	var w: float=owner.size.x; var h: float=owner.size.y; var top: float=94; var available: float=h-140
	rect(header,116,12,w-132,66); rect(rail,12,top,90,available)
	var next: float=116
	summary.visible=w>=1400
	if summary.visible: rect(summary,next,top,218,available); next+=234
	center.visible=w>=1180
	if center.visible:
		var width: float=clampf(w*0.25,280,410); rect(center,next,top,width,available); next+=width+16
		rect(figure,16,46,width-32,available-130)
		for index: int in slots.size():
			var left: bool=index<3; var y: float=58+(index if left else index-3)*116
			if index==6: rect(slots[index],width/2-44,available-110,88,98)
			else: rect(slots[index],12 if left else width-100,y,88,100)
	rect(right,next,top,w-next-16,available); rect(footer,116,h-34,w-132,29)
	if is_instance_valid(owner.item_list): owner.item_list.fixed_column_width=138 if right.size.x>=610 else 116

func schedule_layout() -> void:
	if settling: return
	settling=true; call_deferred("settle_layout")

func settle_layout() -> void:
	settling=false
	if not is_instance_valid(header) or not header.is_inside_tree(): return
	relayout()
