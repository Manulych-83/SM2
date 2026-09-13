extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c: Dictionary = Sm2EffectSequenceContentLoader.load_scenario()
	if not c.ok: quit(1); return
	var raw: Dictionary = c.effects.to_data()
	while raw.effects.size() < 2000:
		var definition: Dictionary = c.effects.definition("m4:effect.cover").to_data()
		definition.id = "measure:effect.%s" % raw.effects.size()
		raw.effects.append(definition)
	var large: Sm2EffectCatalog = Sm2EffectCatalog.new()
	if not large.build(raw,c.combat).is_empty(): quit(2); return
	var rows: Array[Dictionary] = []
	var battles: Array[Sm2TacticalBattle] = []
	for catalog: Sm2EffectCatalog in [c.effects,large]:
		var battle: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,catalog)
		if not battle.start(Sm2CombatFixtures.setup(c,[2,4],1231)).ok: quit(3); return
		battles.append(battle)
		rows.append({"definitions":catalog.to_data().effects.size(),"previews":1000,"samples_ms":[]})
	var command: Sm2Command = Sm2Command.new()
	command.kind = "use_ability"; command.actor_id = 2; command.target_actor_id = 4
	command.ability_id = "sequences:ability.exhaustion"
	command.expected_revision = battles[0].view().revision
	# Both catalogs/actors resident before sampling, with counterbalanced order.
	for battle: Sm2TacticalBattle in battles:
		for i: int in 100: battle.preview(command)
	for round_index: int in 5:
		for index: int in ([0,1] if round_index%2 == 0 else [1,0]):
			var start: int = Time.get_ticks_usec()
			for i: int in 1000:
				var check: Dictionary = battles[index].preview(command)
				if not check.allowed or check.sequence.size() != 2: quit(4); return
			rows[index].samples_ms.append((Time.get_ticks_usec()-start)/1000.0)
	for row: Dictionary in rows:
		var ordered: Array = row.samples_ms.duplicate(); ordered.sort()
		row["median_ms"] = ordered[2]
	var report: Dictionary = {"scope":"Two-step tactical preview; 2 actors, zero initial active effects. Both catalogs resident, warmed, alternating order. Construction excluded. Not full battle/save/UI or simultaneous-catalog acceptance.","rows":rows}
	var file: FileAccess = FileAccess.open("res://outputs/sequences-1/measure.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print(JSON.stringify(report)); quit(0)
