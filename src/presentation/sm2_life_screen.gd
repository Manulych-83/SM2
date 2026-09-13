class_name Sm2LifeScreen
extends Control
signal menu_requested
signal battle_requested
signal development_requested
signal settings_requested
var session: Sm2LifeSession
var expedition: Sm2ExpeditionView=Sm2ExpeditionView.new()
var expedition_seen: Dictionary={}
var _workspace_state: Dictionary={}
var _content: Control
var _notice: String=""
var _selected: int=0
var _exercise: String=""
var _map_selection: String=""
var _camp_page: String="home"
var _camp_resize_pending: bool=false
const INK: Color=Color("e9e8de")
const GOLD: Color=Color("d1b478")
const MUTED: Color=Color("a3b0b4")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); resized.connect(_resize_camp); redraw()

func _resize_camp() -> void:
	if _camp_resize_pending or not session is Sm2JourneySession: return
	var world: Sm2JourneyWorld=(session as Sm2JourneySession).journey()
	if world.survival==null or not world.survival.catalog.has_layers(): return
	_camp_resize_pending=true; call_deferred("_reflow_camp")

func _reflow_camp() -> void:
	_camp_resize_pending=false
	if is_inside_tree() and is_instance_valid(_content) and _content.visible: redraw()

func redraw() -> void:
	if is_instance_valid(_content): remove_child(_content); _content.queue_free()
	if session is Sm2JourneySession:
		var world: Sm2JourneyWorld=(session as Sm2JourneySession).journey()
		if world.survival!=null and world.survival.catalog.has_layers():
			Sm2CampScreen.new().build(self); call_deferred("_expedition_completed"); return
	var margin: MarginContainer=MarginContainer.new(); _content=margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var outer: VBoxContainer=VBoxContainer.new(); margin.add_child(outer)
	var header: HBoxContainer=HBoxContainer.new(); outer.add_child(header)
	var title: Label=_label("ПОЛЯНА У РУИН",24,GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	if session is Sm2JourneySession and session.world._progress.is_party(): header.add_child(_button("Развитие","WorldDevelopment",func() -> void: development_requested.emit()))
	header.add_child(_button("Сохранить","WorldSave",_save))
	header.add_child(_button("Загрузить","WorldLoad",_load))
	header.add_child(_button("Меню","WorldMenu",func() -> void: menu_requested.emit()))
	var v: Dictionary=session.view()
	var workspace_profile: bool=v.has("survival") and (session as Sm2JourneySession).journey().survival.catalog.has_layers()
	if v.has("region"):
		title.text=(session as Sm2JourneySession).journey().region_catalog.location(v.region.location_id).name.to_upper()
		_region(outer,v)
	outer.add_child(_label("Душа без тела · выберите нового носителя" if v.hero_id==0 else "Воплощение %s · %s" % [v.history.size(),v.hero_name],21,INK))
	outer.add_child(_label("Знания Души: "+", ".join(v.knowledge),15,MUTED))
	if not _notice.is_empty(): outer.add_child(_label(_notice,14,GOLD))
	var scroll: ScrollContainer=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(scroll)
	var page: VBoxContainer=VBoxContainer.new(); page.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(page)
	if workspace_profile: Sm2JourneyGuide.build(self,page)
	var rows: HBoxContainer=HBoxContainer.new(); rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page.add_child(rows)
	var left: VBoxContainer=VBoxContainer.new(); left.size_flags_horizontal=Control.SIZE_EXPAND_FILL; left.size_flags_stretch_ratio=1.15; rows.add_child(left)
	var right: VBoxContainer=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rows.add_child(right)
	if workspace_profile:
		right.add_child(_label("Тело и инвентарь",21,GOLD))
		for person: int in [v.hero_id,4]:
			if person==0: continue
			var body: Sm2Anatomy=(session as Sm2JourneySession).journey().survival.bodies[str(person)]
			right.add_child(_label(("Герой" if person==v.hero_id else "Спутник")+": кровь %s мл · кровотечение %s мл/мин" % [body.blood,body.rate()],16,INK))
		right.add_child(_button("Открыть тело и инвентарь","WorldBodyInventory",_open_workspace))
	elif v.has("survival"):
		var panel: Sm2SurvivalPanel=Sm2SurvivalPanel.new(); panel.name="SurvivalPanel"
		panel.session=session as Sm2JourneySession
		panel.changed=func(message: String) -> void: _notice=message; redraw()
		right.add_child(panel)
	if session is Sm2JourneySession:
		left.add_child(_label(v.encounter_name,21,GOLD))
		left.add_child(_label("Завершено встреч: %s/%s. Здоровье, опыт и состояние вещей переходят в следующий бой." % [v.completed,v.encounter_count],15,MUTED))
		var reason: String=session.world.check(session.command("start_battle"))
		left.add_child(_button("Вернуться в сражение" if v.busy else "Войти в сражение","WorldBattle",_battle,not v.busy and not reason.is_empty()))
		if v.has("region") and not reason.is_empty() and not v.busy: left.add_child(_label(reason,14,MUTED))
	elif not v.battle_applied:
		left.add_child(_label("Сражение на поляне",21,GOLD))
		left.add_child(_label("Герой и спутник против двух противников. Результат останется частью этого мира.",15,MUTED))
		left.add_child(_button("Вернуться в сражение" if v.busy else "Войти в сражение","WorldBattle",_battle))
	else:
		left.add_child(_label("Сражение завершено",20,GOLD))
		left.add_child(_label("Погибшие и уцелевшие остались в мире. Эта встреча не создаётся заново.",14,MUTED))
	if session._content.development.has_psionics() and v.hero_id!=0:
		left.add_child(_label("Пси-импульс",20,GOLD))
		left.add_child(_label("Начните с четырёх упражнений, затем изучите узел в разделе «Развитие» → «Псионика». Концентрация восстанавливается перед новым боем.",14,MUTED))
		left.add_child(_button("Практика Псионики · +25 опыта","PsiTrain",_act.bind("practice",v.hero_id,"p5:activity.psionics"),not session.world.check(session.command("practice",v.hero_id,"p5:activity.psionics")).is_empty()))
	if v.has("exploration") and (not v.has("region") or v.hero_id!=0): _exploration(left,v)
	if v.hero_id!=0:
		if _selected not in [v.hero_id,4]: _selected=v.hero_id
		var selectors: HBoxContainer=HBoxContainer.new(); left.add_child(selectors)
		selectors.add_child(_button("Герой","WorldHero",func() -> void: _selected=v.hero_id; redraw()))
		selectors.add_child(_button("Спутник","WorldCompanion",func() -> void: _selected=4; redraw()))
		for body: Dictionary in v.bodies:
			if body.id!=_selected: continue
			left.add_child(_label(body.name+" · "+("здоровье %s/%s" % [body.hp,body.hp_max] if body.alive else "погиб"),18,INK))
			if v.has("care") and not workspace_profile:
				var care_catalog: Sm2CareCatalog=(session as Sm2JourneySession).journey().care_catalog
				var hp_reason: String=session.world.check(session.command("heal_hp",body.id))
				var treatment: Button=_button("Обработать раны · до %s HP" % int(care_catalog.service("heal_hp").heal_hp),"HealHpButton",_act.bind("heal_hp",body.id,""),not hp_reason.is_empty())
				treatment.tooltip_text=hp_reason; left.add_child(treatment)
				left.add_child(_label(care_catalog.description("heal_hp"),13,MUTED))
			if body.has("functions") and not workspace_profile:
				left.add_child(_label("Функции тела",18,GOLD))
				for part: Dictionary in body.functions:
					left.add_child(_label(part.name+": "+Sm2BattleText.function_status(part),14,INK))
					if not part.working:
						var heal_reason: String=session.world.check(session.command("heal_hand",body.id,part.id))
						var heal: Button=_button("Лечить: "+part.name,"Heal_"+part.id,_act.bind("heal_hand",body.id,part.id),not heal_reason.is_empty())
						heal.tooltip_text=heal_reason; left.add_child(heal)
						if v.has("care"): left.add_child(_label((session as Sm2JourneySession).journey().care_catalog.description("heal_hand"),13,MUTED))
				left.add_child(_label("Лечение руки — вне боя. HP и опыт не меняются. Предметы остаются при теле.",13,MUTED))
			if body.has("growth"):
				left.add_child(_label("Уровень %s · общий опыт %s" % [body.growth.level,body.growth.earned],18,GOLD))
				left.add_child(_label("До следующего уровня: %s / %s. Характеристики растут автоматически." % [body.growth.progress,body.growth.needed],14,MUTED))
				for track: Dictionary in body.tracks: left.add_child(_label("%s: %s" % [track.name,track.effective],14,INK))
				continue
			for track: Dictionary in body.tracks:
				left.add_child(_label("%s: уровень %s · опыт %s · доступно %s" % [track.name,track.level,track.earned,track.available],14,MUTED))
			var practice: Sm2WorldCommand=session.command("practice",body.id)
			left.add_child(_button("Упражнение с мечом","WorldPractice",_act.bind("practice",body.id,""),not session.world.check(practice).is_empty()))
			var catalog: Sm2ProgressCatalog=session.world._progress
			if catalog.is_party():
				var choices: OptionButton=OptionButton.new(); choices.name="HeroExercise"
				var ids: Array[String]=catalog.activity_ids()
				for id: String in ids: choices.add_item(catalog.activity(id).title)
				if _exercise not in ids: _exercise=ids[0]
				choices.select(ids.find(_exercise)); choices.item_selected.connect(func(index: int) -> void: _exercise=ids[index]; redraw())
				left.add_child(choices)
				left.add_child(_button("Выполнить упражнение","HeroTrain",_act.bind("practice",body.id,_exercise),not session.world.check(session.command("practice",body.id,_exercise)).is_empty()))
			for node_id: String in catalog.node_ids():
				if session is Sm2JourneySession and v.has("exploration") and node_id in (session as Sm2JourneySession).journey().exploration_catalog.required_node_ids(): continue
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
			if v.has("region") and body.location_id!=v.region.location_id: continue
			left.add_child(_label(body.name,17,INK))
			left.add_child(_label("Подготовленный свежий труп · без улучшений" if body.eligible_reason.is_empty() else body.eligible_reason,14,MUTED))
			left.add_child(_button("Вселиться","WorldIncarnate%s" % body.id,_act.bind("incarnate",body.id,""),not body.eligible_reason.is_empty()))
		left.add_child(_label("Вселение мгновенное. Знания сохранятся; опыт и узлы нового тела начнутся с нуля.",14,MUTED))
	if session is Sm2JourneySession and (session as Sm2JourneySession).journey().upgrade_catalog!=null: _upgrades(right)
	right.add_child(_label("Тайник · Лагерь" if v.has("region") else "Тайник у камня",21,GOLD))
	var owner: String="в тайнике" if v.item_owner==6 else "при теле: "+v.item_owner_name
	right.add_child(_label("Памятный камень — "+owner,17,INK))
	right.add_child(_button("Положить в тайник","WorldDeposit",_act.bind("deposit",0,""),not session.world.check(session.command("deposit")).is_empty()))
	right.add_child(_button("Забрать камень","WorldTake",_act.bind("take",0,""),not session.world.check(session.command("take")).is_empty()))
	right.add_child(_label("Вещи принадлежат миру: Душа не переносит их между телами.",14,MUTED))
	if session is Sm2JourneySession and not v.has("survival"):
		if v.has("care"): _care(right,v)
		if v.has("prostheses"): _prostheses(right,v)
		_equipment(right,v)
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
		if v.has("region") and body.location_id!=v.region.location_id: continue
		if not body.alive and body.death_cause!="": right.add_child(_label("Здесь осталось тело: "+body.name,14,MUTED))
	outer.add_child(_label("Снаряжение меняется вне боя · пустая рука позволяет бить кулаком" if session is Sm2JourneySession else "Первый пример · одна локация и одно сражение · подробная анатомия появится позже",12,MUTED))

func _upgrades(parent: VBoxContainer) -> void:
	var world: Sm2JourneyWorld=(session as Sm2JourneySession).journey()
	parent.add_child(_label("Улучшения тела",21,GOLD))
	for id: String in world.upgrade_catalog.ids():
		var a: Dictionary=world.upgrade_catalog.definition(id)
		parent.add_child(_label(a.name,18,INK))
		for m: Dictionary in a.modifiers:
			parent.add_child(_label(("+%s к эффективной характеристике «%s»" % [int(m.amount),session.world._progress.track(m.track_id).title]) if m.kind=="track_bonus" else "+%s концентрации за псионическое применение" % int(m.amount) if m.kind=="psionic_focus_cost" else "+%s усталости за физическую атаку, включая ответный удар" % int(m.amount),14,MUTED))
		var active: bool=world.hero_id()!=0 and id in world.bodies[world.hero_id()].upgrades.installed
		var status: Label=_label("Действует в этом теле" if active else "Не установлено в текущем теле",14,GOLD); status.name="UpgradeStatus_"+id.get_slice(".",1); parent.add_child(status)
		parent.add_child(_label(a.cache_name+" · "+("собран" if id in world.upgrade_supply.collected else "не собран")+(" · комплектов: %s" if a.path=="cybernetics" else " · доз в запасе: %s") % int(world.upgrade_supply.remaining[id]),14,MUTED))
		if world.survival!=null and world.survival.catalog.has_layers():
			var definition: String=world.survival.catalog.to_data().supplies.upgrades[id]
			parent.add_child(_label("Физических предметов доступно здесь: %s. Находку для дороги нужно положить в контейнер." % Sm2PhysicalSupplies.matching(world.survival,definition,world).size(),14,MUTED))
		for entry: Array in [["collect_upgrade",0,"Забрать комплект" if a.path=="cybernetics" else "Забрать препарат","UpgradeCollect_"],["apply_upgrade",world.hero_id(),"Установить имплант" if a.path=="cybernetics" else "Применить препарат","UpgradeApply_"]]:
			var reason: String=world.check(session.command(entry[0],entry[1],id))
			var button: Button=_button(entry[2],entry[3]+id.get_slice(".",1),_act.bind(entry[0],entry[1],id),not reason.is_empty()); button.tooltip_text=reason; parent.add_child(button)
	parent.add_child(_label("Только вне боя. Расходники тратятся; улучшения остаются в этом теле. Новое воплощение начинает без них.",13,MUTED))

func _exploration(parent: VBoxContainer,v: Dictionary) -> void:
	var world: Sm2JourneyWorld=(session as Sm2JourneySession).journey()
	parent.add_child(_label("Места для осмотра",21,GOLD))
	parent.add_child(_label("На осмотр затрачено: %s мин. Каждое место можно собрать один раз." % v.exploration.minutes,14,MUTED))
	var progress: Sm2ProgressCatalog=session.world._progress
	if world.exploration_catalog.has_practice():
		parent.add_child(_label("Узлы открывают новые места. Практика и узлы принадлежат телу и изучаются заново при воплощении." if world.exploration_catalog.has_requirements() else "Практику получает герой. В новом теле она начинается заново. Уровень пока не меняет находки.",14,MUTED))
		if world.hero_id()!=0:
			var awarded: Dictionary={}
			for site_id: String in world.exploration_catalog.ids(): awarded.merge(world.exploration_catalog.site(site_id).practice,true)
			for track: Dictionary in Sm2ProgressRules.tracks(world.bodies[world.hero_id()].progress,progress):
				if not awarded.has(track.id): continue
				var summary: Label=_label("%s: уровень %s · опыт %s · до следующего %s/%s" % [track.name,track.level,track.earned,track.progress,track.needed],14,GOLD)
				summary.name="SearchProgress_"+str(track.id).get_slice(".",1); parent.add_child(summary)
	if world.exploration_catalog.has_requirements(): _discovery_nodes(parent,world,progress)
	for id: String in world.exploration_catalog.ids():
		if world.region!=null and world.region_catalog.at("sites",id)!=world.region.location_id: continue
		var site: Dictionary=world.exploration_catalog.site(id)
		parent.add_child(_label(site.name,18,INK)); parent.add_child(_label(site.description,14,MUTED))
		var rewards: PackedStringArray=[]
		for resource_id: String in world.care_catalog.resource_ids():
			if site.rewards.has(resource_id): rewards.append("%s +%s" % [world.care_catalog.resource(resource_id).name,int(site.rewards[resource_id])])
		parent.add_child(_label(", ".join(rewards)+" · %s мин." % int(site.minutes),14,GOLD))
		if world.exploration_catalog.has_practice():
			var awards: PackedStringArray=[]
			for track_id: String in site.practice: awards.append("%s +%s" % [progress.track(track_id).title,int(site.practice[track_id])])
			var practice_label: Label=_label("Опыт героя: "+", ".join(awards),14,GOLD)
			practice_label.name="ExplorePractice_"+id; parent.add_child(practice_label)
		var reason: String=session.world.check(session.command("explore",0,id))
		var status: Label=_label("Собрано" if id in v.exploration.collected else reason if not reason.is_empty() else "Доступно",13,MUTED)
		status.name="ExploreStatus_"+id; parent.add_child(status)
		var button: Button=_button("Осмотреть и забрать","Explore_"+id,_act.bind("explore",0,id),not reason.is_empty())
		button.tooltip_text=reason; parent.add_child(button)

func _discovery_nodes(parent: VBoxContainer,world: Sm2JourneyWorld,progress: Sm2ProgressCatalog) -> void:
	parent.add_child(_label("Узлы исследования",18,GOLD))
	for id: String in world.exploration_catalog.required_node_ids():
		var node: Sm2ProgressNodeDefinition=progress.node(id)
		parent.add_child(_label(node.title,17,INK))
		var places: PackedStringArray=[]
		for site_id: String in world.exploration_catalog.ids():
			var site: Dictionary=world.exploration_catalog.site(site_id)
			if id in site.required_nodes: places.append(site.name)
		parent.add_child(_label("Открывает: "+", ".join(places),14,MUTED))
		parent.add_child(_label("Нужен собственный уровень %s (%s). Цена: %s опыта этого направления." % [node.min_level,progress.track(node.track_id).title,node.cost],14,MUTED))
		var owned: bool=false
		if world.hero_id()!=0:
			var track: Sm2ProgressTrackState=world.bodies[world.hero_id()].progress.tracks[node.track_id]
			owned=id in track.nodes
			var balance: Label=_label("Заработано %s · потрачено %s · доступно %s. Покупка не снижает уровень." % [track.earned,track.spent,track.earned-track.spent],14,GOLD)
			balance.name="DiscoveryBalance_"+id.get_slice(".",1); parent.add_child(balance)
		var reason: String=session.world.check(session.command("buy_node",world.hero_id(),id))
		var status: String="Изучено этим телом" if owned else {"level_required":"Нужно больше собственной практики.","experience_required":"Недостаточно свободного опыта.","prerequisite_required":"Сначала изучите предыдущие узлы."}.get(reason,reason)
		var label: Label=_label(status if not status.is_empty() else "Можно изучить",14,MUTED)
		label.name="DiscoveryNodeStatus_"+id.get_slice(".",1); parent.add_child(label)
		var button: Button=_button("Изучено" if owned else "Изучить узел","DiscoveryLearn_"+id.get_slice(".",1),_act.bind("buy_node",world.hero_id(),id),not reason.is_empty())
		button.tooltip_text=status; parent.add_child(button)

func _care(parent: VBoxContainer,v: Dictionary) -> void:
	var catalog: Sm2CareCatalog=(session as Sm2JourneySession).journey().care_catalog
	parent.add_child(_label("Припасы и процедуры",21,GOLD))
	for row: Dictionary in v.care.supplies:
		var label: Label=_label("%s: %s" % [catalog.resource(row.id).name,row.amount],16,INK)
		if v.has("exploration"): label.text+=" / %s" % catalog.capacity(row.id)
		label.name="CareSupply_"+row.id; parent.add_child(label)
	var elapsed: Label=_label("Затрачено на процедуры: %s мин." % v.care.minutes,15,MUTED)
	elapsed.name="CareElapsed"; parent.add_child(elapsed)
	parent.add_child(_label("Походный запас перемещается с отрядом; при гибели остаётся в этом месте и доступен новому воплощению. Процедуры — в лагере." if v.has("region") else "Общий запас в тайнике сохраняется между жизнями. Цена фиксирована за процедуру. Время учитывается сразу; ожидать у экрана не нужно.",13,MUTED))
	for kind: String in Sm2CareCatalog.COMMANDS:
		parent.add_child(_label(catalog.service(kind).name+": "+catalog.description(kind),13,MUTED))

func _prostheses(parent: VBoxContainer,v: Dictionary) -> void:
	parent.add_child(_label("Протезы",21,GOLD))
	parent.add_child(_label("Протез заменяет утраченную руку. Установка, снятие и ремонт — вне боя."+(" Расход и время указаны выше." if v.has("care") else " В этом примере операция бесплатна и мгновенна."),14,MUTED))
	var catalog: Sm2BodyFunctionCatalog=(session as Sm2JourneySession).journey().body_catalog
	for entry: Dictionary in v.prostheses:
		if v.has("region") and not (session as Sm2JourneySession).journey().region.local_owner(int(entry.owner_id),(session as Sm2JourneySession).journey().region_catalog): continue
		var owner: String="тайник"
		for body: Dictionary in v.bodies:
			if str(body.id)==entry.owner_id: owner=body.name
		parent.add_child(_label(catalog.prosthesis(entry.definition_id).name+" · "+owner,16,INK))
		parent.add_child(_label(("Установлен · " if not entry.installed_part.is_empty() else "Снят · ")+("исправен" if entry.working else "повреждён"),14,MUTED))
		var row: HFlowContainer=HFlowContainer.new(); parent.add_child(row)
		row.add_child(_item_button("Установить герою","install_prosthesis",int(v.hero_id),entry.id))
		row.add_child(_item_button("Установить спутнику","install_prosthesis",4,entry.id))
		row.add_child(_item_button("Снять","remove_prosthesis",0,entry.id))
		row.add_child(_item_button("Ремонт","repair_prosthesis",0,entry.id))
		row.add_child(_item_button("Герою","transfer_prosthesis",int(v.hero_id),entry.id))
		row.add_child(_item_button("Спутнику","transfer_prosthesis",4,entry.id))
		row.add_child(_item_button("В тайник","transfer_prosthesis",6,entry.id))

func _equipment(parent: VBoxContainer,v: Dictionary) -> void:
	parent.add_child(_label("Снаряжение и вещи",21,GOLD))
	var names: Dictionary={"sword":"Меч","shield":"Щит","padded":"Стёганая броня","helmet":"Шлем","bow":"Лук","axe":"Топор","mail":"Кольчуга","spear":"Копьё"}
	for item: Dictionary in v.items:
		var owner_id: int=int(item.owner_id)
		if v.has("region") and not (session as Sm2JourneySession).journey().region.local_owner(owner_id,(session as Sm2JourneySession).journey().region_catalog): continue
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
	if session is Sm2JourneySession and (session as Sm2JourneySession).journey().care_catalog!=null:
		result.tooltip_text+="\n"+(session as Sm2JourneySession).journey().care_catalog.description(kind)
	return result

func _act(kind: String, target: int, content_id: String) -> void:
	_act_captured(session.command(kind,target,content_id))

func _act_captured(command: Sm2WorldCommand) -> void:
	var before: Dictionary=session.view()
	var result: Dictionary=session.act(command)
	_notice="Действие выполнено." if result.ok else str(result.errors[0])
	if result.ok and before.has("survival") and (session as Sm2JourneySession).journey().survival.catalog.has_layers():
		_notice=Sm2JourneyGuideView.feedback(command.kind,before,session.view())
	redraw()

func _region(parent: VBoxContainer,v: Dictionary) -> void:
	var world: Sm2JourneyWorld=(session as Sm2JourneySession).journey()
	var compact: bool=world.survival!=null and world.survival.catalog.has_layers()
	var seconds: int=int(v.region.seconds)
	var clock_label: Label=_label("МАЛАЯ КАРТА · День %s · %02d:%02d:%02d" % [1+seconds/86400,(seconds/3600)%24,(seconds/60)%60,seconds%60],17,GOLD)
	clock_label.name="RegionClock"; parent.add_child(clock_label)
	var places: HBoxContainer=HBoxContainer.new(); places.name="RegionMap"; places.add_theme_constant_override("separation",12); parent.add_child(places)
	for id: String in world.region_catalog.ids():
		var definition: Dictionary=world.region_catalog.location(id)
		var panel: PanelContainer=PanelContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; places.add_child(panel)
		var column: VBoxContainer=VBoxContainer.new(); panel.add_child(column)
		var here: bool=id==v.region.location_id
		var caption: Label=_label(definition.name+" · "+("Вы здесь" if here else "Посещено" if id in v.region.visited else "Не посещено"),16,GOLD if here else INK)
		caption.custom_minimum_size.y=40 if compact else 52; caption.tooltip_text=definition.description; column.add_child(caption)
		var time: int=world.region_catalog.route(v.region.location_id,id)
		var reason: String=world.check(session.command("travel",0,id))
		var button: Button=_button("Вы здесь" if here else "Перейти · %s мин" % (time/60) if time>0 else "Нет прямого пути","Travel_"+id,_act.bind("travel",0,id),here or not reason.is_empty())
		button.tooltip_text=reason; column.add_child(button)
	if not compact:
		parent.add_child(_label(world.region_catalog.location(v.region.location_id).description,14,MUTED))
		parent.add_child(_label("Безопасные переходы · время действий учитывается сразу · спутник и переносимые вещи идут с героем",12,MUTED))

func _battle() -> void:
	if not session.view().busy:
		var result: Dictionary=session.act(session.command("start_battle"))
		if not result.ok: _notice=str(result.errors[0]); redraw(); return
	battle_requested.emit()

func _confirm_end() -> void:
	var command: Sm2WorldCommand=session.command("end_life")
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
	buttons.add_child(_button("Завершить жизнь","WorldConfirmDeath",func() -> void: dialog.queue_free(); _act_captured(command)))

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

func _open_soul() -> void:
	var page: Sm2SoulScreen=Sm2SoulScreen.new(); page.name="SoulScreen"; page.session=session as Sm2JourneySession
	_content.hide()
	page.closed.connect(func(message: String) -> void:
		_notice=message; remove_child(page); page.queue_free(); redraw())
	add_child(page)

func _open_journal() -> void:
	var page: Sm2JournalScreen=Sm2JournalScreen.new(); page.name="JournalScreen"; page.session=session as Sm2JourneySession
	_content.hide()
	page.closed.connect(func() -> void: remove_child(page); page.queue_free(); redraw())
	add_child(page)

func _open_workspace() -> void:
	var workspace: Sm2SurvivalWorkspace=Sm2SurvivalWorkspace.new(); workspace.name="SurvivalWorkspace"; workspace.session=session as Sm2JourneySession
	if not _workspace_state.is_empty(): workspace.ui=_workspace_state.duplicate(true)
	_content.hide()
	workspace.closed.connect(func(state: Dictionary,message: String) -> void:
		_workspace_state=state; _notice=message; remove_child(workspace); workspace.queue_free(); redraw())
	add_child(workspace)

func _expedition_completed() -> void:
	if not is_inside_tree() or not is_instance_valid(_content) or not _content.visible: return
	var view: Dictionary=expedition.build(session as Sm2JourneySession)
	if not view.ok or not view.complete: return
	var key: String=str(view.world_id)+":"+Sm2Canonical.hash(view.summary)
	if not expedition_seen.has(key): _open_expedition()

func _open_expedition() -> void:
	var view: Dictionary=expedition.build(session as Sm2JourneySession)
	if not view.ok: _notice="Не удалось восстановить сведения о походе."; return
	if view.complete: expedition_seen[str(view.world_id)+":"+Sm2Canonical.hash(view.summary)]=true
	var page: Sm2ExpeditionScreen=Sm2ExpeditionScreen.new(); page.name="ExpeditionScreen"; page.owner_screen=self; page.model=view
	_content.hide(); page.closed.connect(func() -> void: remove_child(page); page.queue_free(); redraw()); add_child(page)

func _unhandled_key_input(event: InputEvent) -> void:
	if Sm2Controls.back(event) and _camp_page!="home" and is_instance_valid(_content) and _content.is_visible_in_tree():
		get_viewport().set_input_as_handled(); _camp_page="home"; redraw(); return
	if not is_instance_valid(_content) or not _content.is_visible_in_tree() or Sm2Controls.text_focused(self): return
	if find_child("WorldDeathDialog",true,false)!=null: return
	if not session is Sm2JourneySession: return
	var world: Sm2JourneyWorld=(session as Sm2JourneySession).journey()
	if world.survival==null or not world.survival.catalog.has_layers(): return
	var targets: Dictionary={"inventory":"CampInventory","body":"WorldBodyInventory","development":"WorldDevelopment","journal":"CampJournal","soul":"CampSoul","settings":"CampSettings"}
	var id: String=Sm2Controls.action(event)
	if targets.has(id):
		get_viewport().set_input_as_handled()
		if not Sm2Controls.press(_content,targets[id]) and _camp_page!="home":
			_camp_page="home"; redraw(); Sm2Controls.press(_content,targets[id])
