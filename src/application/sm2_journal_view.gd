class_name Sm2JournalView
extends RefCounted
## Replay into a disposable world without a store; never apply to the live session.
static func build(session: Sm2JourneySession) -> Dictionary:
	var projected: Variant=session.checkpoint_projection("journal")
	if projected!=null: return projected
	var shadow: Sm2JourneySession=Sm2JourneySession.new(session._content,session._profile,null)
	shadow.world.start(session.world.world_id)
	var rows: Array[Dictionary]=[]
	for entry: Dictionary in session.history:
		var world: Sm2JourneyWorld=shadow.journey()
		var place: String=world.region.location_id
		var hero: int=world.hero_id(); var old_items: Array[String]=world.survival.inventory.ids()
		var kind: String="outcome"; var detail: String=""; var outcome: String=""
		if entry.kind=="camp":
			kind=entry.command.kind; detail=subject(shadow,entry.command)
			if not shadow._camp(entry.command,true).ok: return {"ok":false,"rows":[]}
		else:
			var checked: Dictionary=shadow._check_battle(entry.battle)
			if not checked.ok or not checked.state.finished: return {"ok":false,"rows":[]}
			shadow.world.revision+=checked.state.revision
			var result: Dictionary=Sm2BattleOutcome.view(checked.state)
			outcome="Победа отряда" if result.winner=="company" else "Ничья"
			if result.winner=="opposition": outcome="Отряд отступил" if result.counts.company.escaped>0 else "Отряд разбит"
			if not shadow._finish().ok: return {"ok":false,"rows":[]}
		world=shadow.journey()
		var added: int=0
		for id: String in world.survival.inventory.ids():
			if not id in old_items: added+=1
		var interrupted: bool=hero!=0 and world.hero_id()==0 and kind not in ["end_life","outcome"]
		rows.append({"number":rows.size()+1,"kind":kind,"subject":detail,"outcome":outcome,"interrupted":interrupted,"seconds":world.region.seconds,"from":world.region_catalog.location(place).name,"location":world.region_catalog.location(world.region.location_id).name,"life_ended":hero!=0 and world.hero_id()==0,"new_items":added})
	if session.world.busy():
		var checked: Dictionary=shadow._check_battle(session.runner.capture())
		if not checked.ok or checked.state.finished: return {"ok":false,"rows":[]}
		shadow.world.revision+=checked.state.revision
	if Sm2Canonical.hash(shadow.world.capture())!=Sm2Canonical.hash(session.world.capture()): return {"ok":false,"rows":[]}
	return {"ok":true,"rows":rows,"busy":session.world.busy()}

static func subject(session: Sm2JourneySession,command: Dictionary) -> String:
	var world: Sm2JourneyWorld=session.journey(); var id: String=command.content_id
	match str(command.kind):
		"travel": return world.region_catalog.location(id).name
		"practice": return world._progress.activity(id).title
		"buy_node": return world._progress.node(id).title
		"explore": return world.exploration_catalog.site(id).name
		"collect_upgrade","apply_upgrade": return world.upgrade_catalog.definition(id).name
		"incarnate": return world._definition.body(int(command.target_id)).name
		"start_battle": return world.encounters[world.completed].name
		"bandage","heal_hp","heal_hand": return world._definition.body(int(command.target_id)).name
		"store_item","wear_item","drop_item","attach_device","detach_device","repair_device":
			if world.survival.inventory.items.has(id): return world.survival.catalog.item(world.survival.inventory.items[id].definition_id).name
	return ""
