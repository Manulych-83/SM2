class_name Sm2SurvivalPanel
extends VBoxContainer
var session: Sm2JourneySession
var changed: Callable
var notice: Label
var selector: OptionButton
var destination: OptionButton
var operations: VBoxContainer

func _ready() -> void:
	var world: Sm2JourneyWorld=session.journey()
	var survival: Sm2SurvivalState=world.survival
	add_child(label("ТЕЛО И ФИЗИЧЕСКИЙ ИНВЕНТАРЬ"))
	if world.busy():
		add_child(label("Состояние тела и повязки сейчас изменяются в бою. Размещение вещей доступно после его завершения.")); return
	for body_id: int in [world.hero_id(),4]:
		if body_id==0: continue
		var body: Sm2Anatomy=survival.bodies[str(body_id)]
		add_child(label(("Герой" if body_id==world.hero_id() else "Спутник")+" · кровь %s / %s мл\nКровотечение %s мл/мин" % [body.blood,int(survival.catalog.to_data().blood_max),body.rate()]))
		add_child(label("Переносимая масса: %.2f кг" % (survival.inventory.carried_mass(body_id,survival.catalog)/1000.0)))
		if survival.catalog.has_devices():
			for part: String in survival.catalog.devices().interfaces:
				if not survival.missing[str(body_id)].has(part): continue
				var device: String=Sm2SurvivalDevices.installed(survival,str(body_id),part)
				add_child(label(survival.catalog.part_name(part)+": "+("отсутствует" if device.is_empty() else "протез №%s · прочность %s" % [device,survival.inventory.items[device].current])))
		if survival.catalog.has_layers():
			for part: String in body.layers:
				var details: PackedStringArray=[]
				for tissue: Dictionary in body.layer_rules[part]: details.append("%s %s/%s" % [tissue.name,body.layers[part][tissue.id],int(tissue.capacity)])
				var row: Label=label(survival.catalog.part_name(part)+": "+", ".join(details)+(" · естественная функция утрачена" if not body.working(part) else ""))
				row.name="Tissue_"+str(body_id)+"_"+part; add_child(row)
		for wound: Dictionary in body.wounds:
			add_child(label("%s · рана №%s · %s" % [survival.catalog.part_name(wound.part),wound.id,"перевязана / не кровоточит" if int(wound.rate)==0 else "%s мл/мин" % wound.rate]))
			if int(wound.rate)>0: add_child(action("Перевязать · %s сек" % int(survival.catalog.to_data().bandage_seconds),session.command("bandage",body_id,wound.id)))
	if survival.catalog.has_layers():
		for resource: String in world.care_catalog.resource_ids():
			var definition: String=survival.catalog.to_data().supplies.care[resource]
			add_child(label("%s: доступно здесь %s · всего в мире %s" % [world.care_catalog.resource(resource).name,Sm2PhysicalSupplies.matching(survival,definition,world).size(),Sm2PhysicalSupplies.matching(survival,definition).size()]))
	if survival.catalog.has_layers(): add_child(label("Находки появляются на земле здесь. Перед дорогой положите их в контейнер. Медикаменты хранятся для будущих лечебных процедур; перевязка использует отдельный материал."))
	selector=OptionButton.new(); selector.name="PhysicalItemSelect"; selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL; add_child(selector)
	selector.fit_to_longest_item=false
	for id: String in survival.inventory.ids():
		if survival.inventory.location(id,world.region.bodies)!=world.region.location_id: continue
		var entry: Dictionary=survival.inventory.items[id]
		selector.add_item("%s №%s" % [survival.catalog.item(entry.definition_id).name,id]); selector.set_item_metadata(selector.item_count-1,id)
	destination=OptionButton.new(); destination.name="PhysicalDestination"; add_child(destination)
	destination.fit_to_longest_item=false
	for id: String in survival.inventory.ids():
		var definition: Dictionary=survival.catalog.item(survival.inventory.items[id].definition_id)
		if int(definition.capacity)==0 or survival.inventory.location(id,world.region.bodies)!=world.region.location_id: continue
		var used: Dictionary=survival.inventory.usage(id,survival.catalog)
		destination.add_item("%s №%s · %s/%s объём · %s/%s г" % [definition.name,id,used.volume,definition.capacity,used.mass,definition.max_mass])
		destination.set_item_metadata(destination.item_count-1,id)
	operations=VBoxContainer.new(); add_child(operations)
	selector.item_selected.connect(func(_index: int) -> void: refresh_actions())
	destination.item_selected.connect(func(_index: int) -> void: refresh_actions())
	refresh_actions()

func refresh_actions() -> void:
	for node: Node in operations.get_children(): operations.remove_child(node); node.queue_free()
	if selector.selected<0: return
	var id: String=str(selector.get_item_metadata(selector.selected))
	var world: Sm2JourneyWorld=session.journey()
	var entry: Dictionary=world.survival.inventory.items[id]
	var definition: Dictionary=world.survival.catalog.item(entry.definition_id)
	operations.add_child(label("Масса %s г · объём %s · размер %s\nРазмещение: %s, %s" % [definition.mass,definition.volume,definition.size,{"equipped":"на теле","container":"в контейнере","ground":"на земле","installed":"установлен"}.get(entry.place,entry.place),entry.holder]))
	if world.survival.catalog.has_devices() and not world.survival.catalog.device(entry.definition_id).is_empty():
		operations.add_child(label("Прочность %s / %s. Установка не лечит рану и не восполняет кровь." % [int(entry.current),int(world.survival.catalog.device(entry.definition_id).capacity)]))
		for action_data: Array in [["attach_device","Установить герою",world.hero_id()],["attach_device","Установить спутнику",4],["detach_device","Снять на землю",0],["repair_device","Отремонтировать",0]]:
			var price: Dictionary=world.survival.catalog.devices().procedures[action_data[0]]
			operations.add_child(action("%s · %s сек · %s компл." % [action_data[1],int(price.seconds),int(price.parts)],session.command(action_data[0],action_data[2],id)))
	if destination.selected>=0: operations.add_child(action("Положить в выбранный контейнер",session.command("store_item",int(destination.get_item_metadata(destination.selected)),id)))
	operations.add_child(action("Надеть герою",session.command("wear_item",world.hero_id(),id)))
	operations.add_child(action("Надеть спутнику",session.command("wear_item",4,id)))
	operations.add_child(action("Оставить здесь на земле",session.command("drop_item",0,id)))

func action(title: String,command: Sm2WorldCommand) -> Button:
	var button: Button=Button.new(); button.text=title; button.name="Physical_"+command.kind
	var reason: String=session.world.check(command)
	button.disabled=not reason.is_empty(); button.tooltip_text=reason
	button.pressed.connect(func() -> void:
		var result: Dictionary=session.act(command)
		changed.call("Действие выполнено." if result.ok else str(result.errors[0])))
	return button

static func label(text: String) -> Label:
	var node: Label=Label.new(); node.text=text; node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size.x=280
	return node
