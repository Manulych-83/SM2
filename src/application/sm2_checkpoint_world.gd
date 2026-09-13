class_name Sm2CheckpointWorld
extends RefCounted
## Strict state decoding for the current layered campaign; no history execution.
static func decode(raw: Variant, fresh: Sm2JourneyWorld) -> Dictionary:
	var bad: Dictionary={"ok":false,"errors":PackedStringArray(["checkpoint_world_invalid"])}
	if not raw is Dictionary or not Sm2Validate.text(raw.get("world_id")) or str(raw.world_id).length()>100: return bad
	fresh.start(raw.world_id)
	var baseline: Dictionary=fresh.capture(); var fields: Array[String]=[]; fields.assign(baseline.keys())
	if not Sm2Validate.fields(raw,fields): return bad
	for key: String in ["format","stash_id","progress_fingerprint","world_fingerprint"]:
		if raw[key]!=baseline[key]: return bad
	if baseline.format not in ["sm2.world.survival.3",Sm2WorldCreatureCatalog.WORLD_FORMAT] or not Sm2Validate.decimal(raw.revision,0,1000000) or not Sm2Validate.decimal(raw.next_id,fresh.next_id,1000000): return bad
	if fresh.world_creatures!=null and Sm2Canonical.hash(raw.creatures)!=Sm2Canonical.hash(baseline.creatures): return bad
	if not raw.battle_started is bool or not raw.receipt is String or (not raw.receipt.is_empty() and not digest(raw.receipt)): return bad
	if not Sm2Validate.integer(raw.completed,0,fresh.encounters.size()): return bad
	fresh.revision=int(raw.revision); fresh.next_id=int(raw.next_id); fresh.battle_started=raw.battle_started; fresh.receipt=raw.receipt; fresh.completed=int(raw.completed)
	if not raw.incarnations is Array or raw.incarnations.is_empty() or raw.incarnations.size()>fresh.bodies.size(): return bad
	var used: Array[int]=[]; var expected_next: int=int(baseline.next_id)
	for index: int in raw.incarnations.size():
		var life: Variant=raw.incarnations[index]
		if not life is Dictionary or not Sm2Validate.fields(life,["id","body_id","ended"]) or not life.ended is bool or not Sm2Validate.decimal(life.body_id,1): return bad
		if index==0 and (life.id!="3" or life.body_id!="2"): return bad
		if index>0 and (not Sm2Validate.decimal(life.id,expected_next,fresh.next_id-1) or int(life.id)<=int(raw.incarnations[index-1].id)): return bad
		var id: int=int(life.body_id)
		if not fresh.bodies.has(id) or id in used: return bad
		var definition: Dictionary=fresh._definition.body(id)
		if index>0 and (fresh.bodies[id].alive or not definition.human or definition.enhanced or not definition.prepared): return bad
		if index<raw.incarnations.size()-1 and not life.ended: return bad
		used.append(id)
	fresh.incarnations.assign(raw.incarnations.duplicate(true))
	fresh.soul.incarnation_id=0 if fresh.incarnations.back().ended else int(fresh.incarnations.back().id)
	if raw.soul!=fresh.soul.to_data(): return bad
	if not raw.item is Dictionary or not Sm2Validate.fields(raw.item,["id","definition_id","owner_id"]) or raw.item.id!=baseline.item.id or raw.item.definition_id!=baseline.item.definition_id or not Sm2Validate.decimal(raw.item.owner_id,1): return bad
	fresh.item_owner=int(raw.item.owner_id)
	if fresh.item_owner!=6 and fresh.item_owner not in used: return bad
	if not raw.bodies is Array or raw.bodies.size()!=fresh.bodies.size(): return bad
	for index: int in raw.bodies.size():
		var entry: Variant=raw.bodies[index]; var id: int=fresh._definition.ids()[index]
		fields.assign(fresh.bodies[id].to_data().keys())
		if not entry is Dictionary or not Sm2Validate.fields(entry,fields) or entry.id!=str(id) or not entry.alive is bool or not Sm2Validate.integer(entry.hp,0,60) or not Sm2Validate.integer(entry.drills,0,1000000) or not Sm2Validate.text(entry.death_cause,true) or not entry.progress is Dictionary: return bad
		var progress: Dictionary=Sm2ProgressRules.decode_body(entry.progress,fresh._progress)
		var functions: Dictionary=Sm2BodyFunctionState.decode(entry.body_functions,fresh.body_catalog)
		var upgrades: Dictionary=Sm2BodyUpgradeState.decode(entry.upgrades,fresh.upgrade_catalog)
		if not progress.ok or not functions.ok or not upgrades.ok: return bad
		var body: Sm2WorldBody=fresh.bodies[id]
		body.hp=int(entry.hp); body.alive=entry.alive; body.drills=int(entry.drills); body.death_cause=entry.death_cause
		body.progress=progress.body; body.functions=functions.state; body.upgrades=upgrades.state
		if id in used and id!=fresh.hero_id() and body.alive: return bad
	if not _collections(raw,fresh,baseline): return bad
	var survival: Dictionary=Sm2SurvivalState.decode(raw.survival,fresh.survival)
	if not survival.ok: return survival
	fresh.survival=survival.state
	var reason: String=fresh.validate()
	if not reason.is_empty(): return {"ok":false,"errors":PackedStringArray([reason])}
	# Items and new incarnations share one allocation sequence; finds may interleave lives.
	expected_next+=fresh.incarnations.size()-1
	for site: String in fresh.exploration.collected:
		for amount: int in fresh.exploration_catalog.site(site).rewards.values(): expected_next+=amount
	for id: String in fresh.upgrade_supply.collected: expected_next+=int(fresh.upgrade_catalog.definition(id).doses)
	if fresh.next_id!=expected_next: return bad
	for id: String in fresh.survival.inventory.ids():
		if not Sm2Validate.decimal(id,1,fresh.next_id-1): return bad
		for life: Dictionary in fresh.incarnations:
			if life.id==id: return bad
	if Sm2Canonical.hash(fresh.capture())!=Sm2Canonical.hash(raw): return bad
	return {"ok":true,"world":fresh}

static func _collections(raw: Dictionary,w: Sm2JourneyWorld,baseline: Dictionary) -> bool:
	if not raw.region is Dictionary or not Sm2Validate.fields(raw.region,["format","location_id","seconds","visited","bodies"]) or raw.region.format!=baseline.region.format or raw.location_id!=raw.region.location_id: return false
	if not Sm2Validate.integer(raw.region.seconds,0,Sm2RegionCatalog.TIME_LIMIT) or not Sm2Validate.string_list(raw.region.visited) or not raw.region.bodies is Dictionary: return false
	if not raw.region.location_id is String: return false
	w.region.location_id=raw.region.location_id; w.region.seconds=int(raw.region.seconds); w.region.visited.assign(raw.region.visited)
	w.region.bodies.clear()
	for id: Variant in raw.region.bodies:
		if not id is String or not raw.region.bodies[id] is String: return false
		w.region.bodies[id]=raw.region.bodies[id]
	if not raw.care is Dictionary or not Sm2Validate.fields(raw.care,["format","supplies","minutes"]) or raw.care.format!=baseline.care.format or not raw.care.supplies is Array or not Sm2Validate.integer(raw.care.minutes,0,1000000000): return false
	w.care.minutes=int(raw.care.minutes); w.care.supplies.clear()
	for row: Variant in raw.care.supplies:
		if not row is Dictionary or not Sm2Validate.fields(row,["id","amount"]) or not row.id is String or w.care.supplies.has(row.id) or not Sm2Validate.integer(row.amount,0,1000000): return false
		w.care.supplies[row.id]=int(row.amount)
	if not raw.exploration is Dictionary or not Sm2Validate.fields(raw.exploration,["format","collected","minutes"]) or raw.exploration.format!=baseline.exploration.format or not Sm2Validate.string_list(raw.exploration.collected) or not Sm2Validate.integer(raw.exploration.minutes,0,1000000000): return false
	w.exploration.collected.assign(raw.exploration.collected); w.exploration.minutes=int(raw.exploration.minutes)
	if not raw.upgrade_supply is Dictionary or not Sm2Validate.fields(raw.upgrade_supply,["collected","remaining"]) or not Sm2Validate.string_list(raw.upgrade_supply.collected) or not raw.upgrade_supply.remaining is Dictionary: return false
	w.upgrade_supply.collected.assign(raw.upgrade_supply.collected); w.upgrade_supply.remaining=raw.upgrade_supply.remaining.duplicate(true)
	if not raw.items is Array or raw.items.size()!=baseline.items.size() or not raw.prostheses is Array: return false
	for index: int in raw.items.size():
		var entry: Variant=raw.items[index]; var initial: Dictionary=baseline.items[index]
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","definition_id","owner_id","equipped","slot","current","ammo"]) or not entry.equipped is bool or not Sm2Validate.decimal(entry.owner_id,1): return false
		for key: String in ["id","definition_id","slot"]:
			if entry[key]!=initial[key]: return false
	w.items.assign(raw.items.duplicate(true))
	# Prosthesis validation expects shaped rows; start with immutable identities.
	if raw.prostheses.size()!=baseline.prostheses.size(): return false
	for index: int in raw.prostheses.size():
		var row: Variant=raw.prostheses[index]; var initial: Dictionary=baseline.prostheses[index]
		var keys: Array[String]=[]; keys.assign(initial.keys())
		if not row is Dictionary or not Sm2Validate.fields(row,keys): return false
		for key: String in ["id","definition_id"]:
			if row[key]!=initial[key]: return false
		for key: String in initial:
			if typeof(row[key])!=typeof(initial[key]) and not (typeof(initial[key])==TYPE_INT and Sm2Validate.integer(row[key],0,1000000)): return false
	w.prostheses.items.assign(raw.prostheses.duplicate(true))
	return true

static func digest(value: Variant) -> bool:
	if not value is String or value.length()!=64: return false
	for c: String in value:
		if not c in "0123456789abcdef": return false
	return true
