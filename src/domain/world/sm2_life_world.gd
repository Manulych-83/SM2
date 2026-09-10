class_name Sm2LifeWorld
extends RefCounted
## A bounded location fixture. No clocks, files, scenes, or autonomous rewards.
const FORMAT: String = "sm2.world.p3.1"
const DRILL: String = "p1:activity.sword_drill"
const BINDING: Dictionary = {1:2,2:4,3:10,4:11}
var world_id: String = ""
var revision: int = 0
var next_id: int = 13
var soul: Sm2SoulState = Sm2SoulState.new()
var incarnations: Array[Dictionary] = []
var bodies: Dictionary[int,Sm2WorldBody] = {}
var item_owner: int = 2
var battle_started: bool = false
var receipt: String = ""
var _progress: Sm2ProgressCatalog
var _definition: Sm2LifeDefinition

func _init(progress: Sm2ProgressCatalog, definition: Sm2LifeDefinition) -> void:
	_progress=Sm2ProgressCatalog.new(); _progress.build(progress.to_data())
	_definition=Sm2LifeDefinition.new(); _definition.build(definition.to_data())

func start(id: String) -> void:
	world_id=id; soul.knowledge=_progress.knowledge_ids(); next_id=_definition.first_free_id()
	incarnations=[{"id":"3","body_id":"2","ended":false}]
	for body_id: int in _definition.ids():
		var body: Sm2WorldBody=Sm2WorldBody.new()
		body.id=body_id; body.progress=Sm2ProgressRules.empty_body(body_id,_progress)
		body.alive=_definition.body(body_id).alive; body.hp=60 if body.alive else 0
		bodies[body_id]=body

func hero_id() -> int:
	return int(incarnations.back().body_id) if soul.incarnation_id != 0 else 0

func busy() -> bool: return battle_started and receipt.is_empty()

func capture() -> Dictionary:
	var entries: Array[Dictionary]=[]
	for id: int in _definition.ids(): entries.append(bodies[id].to_data())
	return {"format":FORMAT,"world_id":world_id,"revision":str(revision),"next_id":str(next_id),"soul":soul.to_data(),"incarnations":incarnations.duplicate(true),"bodies":entries,
		"location_id":"5","stash_id":"6","item":{"id":"7","definition_id":"p3:item.memory_stone","owner_id":str(item_owner)},
		"battle_id":world_id+":12","binding":[{"actor_id":"1","body_id":"2","incarnation_id":"3"},{"actor_id":"2","body_id":"4","incarnation_id":"0"},{"actor_id":"3","body_id":"10","incarnation_id":"0"},{"actor_id":"4","body_id":"11","incarnation_id":"0"}],
		"battle_started":battle_started,"receipt":receipt,"progress_fingerprint":_progress.fingerprint(),"world_fingerprint":_definition.fingerprint()}

func eligible(id: int) -> String:
	if not bodies.has(id): return "Тела нет в этой локации."
	if bodies[id].alive: return "Это живой человек."
	var definition: Dictionary=_definition.body(id)
	if not definition.human: return "Душе нужно человеческое тело."
	if definition.enhanced: return "Импланты: Душа не может вселиться в улучшенное тело."
	for record: Dictionary in incarnations:
		if int(record.body_id)==id: return "Повторное вселение в прежнее тело пока недоступно."
	if not definition.prepared: return "Этот носитель не подготовлен для первого примера."
	return ""

func check(command: Sm2WorldCommand) -> String:
	if command == null or command.world_id!=world_id or command.expected_revision!=revision or command.incarnation_id!=soul.incarnation_id or command.body_id!=hero_id(): return "Устаревшая команда или другой мир."
	if revision>=1000000: return "Достигнут предел действий примера."
	if busy(): return "Сначала завершите сражение."
	if command.kind=="incarnate":
		if hero_id()!=0: return "Душа уже воплощена."
		return eligible(command.target_id)
	if hero_id()==0: return "Сначала выберите новое тело."
	match command.kind:
		"start_battle": return "Эта встреча уже завершена." if battle_started else ""
		"deposit": return "Камень уже в тайнике или остался при другом теле." if item_owner!=hero_id() else ""
		"take": return "Камень уже у героя." if item_owner==hero_id() else ""
		"end_life": return "Сначала завершите сражение первого примера." if receipt.is_empty() else ""
		"practice", "buy_node":
			if receipt.is_empty(): return "Развитие в локации доступно после сражения."
			if command.target_id not in [hero_id(),4] or not bodies[command.target_id].alive: return "Этот участник недоступен."
			var body: Sm2WorldBody=bodies[command.target_id]
			if command.kind=="buy_node": return Sm2ProgressRules.purchase_error(body.progress,_progress,command.content_id)
			var activity: Sm2PracticeDefinition=_progress.activity(DRILL)
			for id: String in activity.awards:
				if body.progress.tracks[id].earned>Sm2ProgressCatalog.XP_LIMIT-activity.awards[id]: return "Достигнут предел опыта примера."
			return ""
	return "Неизвестное действие."

## Only called on the session's detached candidate, after check().
func apply(command: Sm2WorldCommand) -> void:
	match command.kind:
		"start_battle": battle_started=true
		"deposit": item_owner=6
		"take": item_owner=hero_id()
		"end_life":
			var body: Sm2WorldBody=bodies[hero_id()]
			body.alive=false; body.hp=0; body.death_cause="fixture"; _end_incarnation()
		"incarnate":
			var body: Sm2WorldBody=bodies[command.target_id]
			body.progress=Sm2ProgressRules.empty_body(body.id,_progress); body.drills=0
			body.hp=60; body.alive=true; body.death_cause=""
			soul.incarnation_id=next_id; next_id+=1
			incarnations.append({"id":str(soul.incarnation_id),"body_id":str(body.id),"ended":false})
		"practice":
			var body: Sm2WorldBody=bodies[command.target_id]
			var activity: Sm2PracticeDefinition=_progress.activity(DRILL)
			for id: String in activity.awards: body.progress.tracks[id].earned+=activity.awards[id]
			body.drills+=1
		"buy_node": Sm2ProgressRules.purchase(bodies[command.target_id].progress,_progress.node(command.content_id))
	revision+=1

func apply_battle(state: Sm2TacticalState, result_hash: String) -> String:
	if not receipt.is_empty(): return "" if receipt==result_hash else "outcome_conflict"
	if not battle_started or not state.finished or state.battle_id!=world_id+":12" or soul.incarnation_id!=3: return "outcome_context"
	for actor_id: int in BINDING:
		var body: Sm2WorldBody=bodies[BINDING[actor_id]]
		var actor: Sm2TacticalActor=state.actor(actor_id)
		body.hp=actor.combat.hp; body.alive=actor.spatial.alive
		body.death_cause="" if body.alive else "battle"
		if state.development.bodies.has(actor_id):
			var raw: Dictionary=state.development.bodies[actor_id].to_data(); raw.id=str(body.id)
			body.progress=Sm2ProgressRules.decode_body(raw,_progress).body
	if not bodies[2].alive: _end_incarnation()
	receipt=result_hash
	return ""

func _end_incarnation() -> void:
	incarnations.back().ended=true; soul.incarnation_id=0

func view() -> Dictionary:
	var rows: Array[Dictionary]=[]
	for id: int in _definition.ids():
		var body: Sm2WorldBody=bodies[id]
		var name: String=_definition.body(id).name
		rows.append({"id":id,"name":name,"hp":body.hp,"hp_max":60,"alive":body.alive,"death_cause":body.death_cause,"drills":body.drills,"tracks":Sm2ProgressRules.tracks(body.progress,_progress),"eligible_reason":eligible(id)})
	var knowledge: Array[String]=[]
	for id: String in soul.knowledge: knowledge.append(_progress.knowledge_name(id))
	return {"world_id":world_id,"revision":revision,"hero_id":hero_id(),"hero_name":_definition.body(hero_id()).get("name",""),"incarnation_id":soul.incarnation_id,"knowledge":knowledge,"bodies":rows,"item_owner":item_owner,"item_owner_name":_definition.body(item_owner).get("name","тайник"),"history":incarnations.duplicate(true),"busy":busy(),"battle_started":battle_started,"battle_applied":not receipt.is_empty()}

## The session supplies an already decoded battle; cross-check the entire boundary.
static func decode(raw: Dictionary, progress: Sm2ProgressCatalog, definition: Sm2LifeDefinition, battle: Sm2TacticalState, battle_hash: String) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["world_snapshot_invalid"])}
	var w: Sm2LifeWorld=Sm2LifeWorld.new(progress,definition)
	if not Sm2Validate.text(raw.get("world_id")) or str(raw.world_id).length()>100: return failure
	w.start(raw.world_id)
	var fields: Array[String]=[]; fields.assign(w.capture().keys())
	if not Sm2Validate.fields(raw,fields): return failure
	for key: String in ["format","location_id","stash_id","battle_id","binding","progress_fingerprint","world_fingerprint"]:
		if raw[key]!=w.capture()[key]: return failure
	if battle.battle_id!=raw.battle_id or battle.development==null: return failure
	var first_id: int=definition.first_free_id()
	if not Sm2Validate.decimal(raw.revision,0,1000000) or not Sm2Validate.decimal(raw.next_id,first_id,first_id+1000) or not raw.battle_started is bool or not raw.receipt is String: return failure
	w.revision=int(raw.revision); w.next_id=int(raw.next_id); w.battle_started=raw.battle_started; w.receipt=raw.receipt
	if (not w.battle_started and battle.revision!=0) or (battle.finished!=not w.receipt.is_empty()) or (not w.receipt.is_empty() and (not w.battle_started or w.receipt!=battle_hash)): return failure
	if not raw.incarnations is Array or raw.incarnations.size()<1 or raw.incarnations.size()>definition.ids().size() or w.next_id!=first_id+raw.incarnations.size()-1: return failure
	w.incarnations.clear()
	var used: Array[int]=[]
	for index: int in raw.incarnations.size():
		var entry: Variant=raw.incarnations[index]
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","body_id","ended"]) or entry.id!=("3" if index==0 else str(first_id+index-1)) or not Sm2Validate.decimal(entry.body_id,1) or not entry.ended is bool: return failure
		var carrier: int=int(entry.body_id)
		if not w.bodies.has(carrier) or carrier in used: return failure
		if index==0:
			if carrier!=2: return failure
		elif not w.eligible(carrier).is_empty(): return failure
		used.append(carrier)
		if index<raw.incarnations.size()-1 and not entry.ended: return failure
		w.incarnations.append(entry.duplicate(true))
	w.soul.incarnation_id=0 if w.incarnations.back().ended else int(w.incarnations.back().id)
	if not raw.soul is Dictionary or raw.soul!=w.soul.to_data(): return failure
	if w.receipt.is_empty() and w.incarnations!=[{"id":"3","body_id":"2","ended":false}]: return failure
	if not raw.item is Dictionary or not Sm2Validate.fields(raw.item,["id","definition_id","owner_id"]) or raw.item.id!="7" or raw.item.definition_id!="p3:item.memory_stone" or not Sm2Validate.decimal(raw.item.owner_id,1): return failure
	w.item_owner=int(raw.item.owner_id)
	if w.item_owner!=6 and w.item_owner not in used: return failure
	if not raw.bodies is Array or raw.bodies.size()!=definition.ids().size(): return failure
	var operations: int=0
	for index: int in definition.ids().size():
		var entry: Variant=raw.bodies[index]
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","hp","alive","death_cause","drills","progress"]) or entry.id!=str(definition.ids()[index]) or not entry.alive is bool or not Sm2Validate.integer(entry.hp,0,60) or entry.alive!=(entry.hp>0) or entry.death_cause not in ["","battle","fixture"] or not Sm2Validate.integer(entry.drills,0,1000000) or not entry.progress is Dictionary or entry.progress.get("id")!=entry.id: return failure
		var decoded: Dictionary=Sm2ProgressRules.decode_body(entry.progress,progress)
		if not decoded.ok: return failure
		var body: Sm2WorldBody=w.bodies[definition.ids()[index]]
		body.hp=int(entry.hp); body.alive=entry.alive; body.death_cause=entry.death_cause; body.drills=int(entry.drills); body.progress=decoded.body
		var baseline: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(body.id,progress)
		var expected_hp: int=60 if definition.body(body.id).alive else 0
		var expected_cause: String=""
		if not w.receipt.is_empty() and body.id in BINDING.values():
			var actor_id: int=BINDING.find_key(body.id)
			expected_hp=battle.actor(actor_id).combat.hp
			expected_cause="battle" if expected_hp==0 else ""
			if battle.development.bodies.has(actor_id): baseline=battle.development.bodies[actor_id]
		if body.id in used and body.id!=2: expected_hp=60
		for record: Dictionary in w.incarnations:
			if int(record.body_id)==body.id and record.ended:
				if expected_hp>0: expected_cause="fixture"
				expected_hp=0
		if body.hp!=expected_hp or body.death_cause!=expected_cause: return failure
		if body.id==2 and not body.alive and not w.incarnations[0].ended: return failure
		if (body.id not in used and body.id!=4) and body.drills!=0: return failure
		if w.receipt.is_empty() and body.drills!=0: return failure
		for track_id: String in progress.track_ids():
			var actual: Sm2ProgressTrackState=body.progress.tracks[track_id]
			var expected: int=baseline.tracks[track_id].earned+body.drills*progress.activity(DRILL).awards.get(track_id,0)
			if actual.earned!=expected: return failure
			if body.death_cause=="battle" and (body.drills!=0 or actual.nodes!=baseline.tracks[track_id].nodes): return failure
			operations+=actual.nodes.size()
		operations+=body.drills
	if w.revision<operations+battle.revision+(1 if w.battle_started else 0)+w.incarnations.size()-1: return failure
	return {"ok":true,"world":w,"errors":PackedStringArray()}
