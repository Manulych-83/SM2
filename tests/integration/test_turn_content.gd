extends RefCounted
## Authored round data -> catalog -> exact coordinator setup; no tactical engine dependency.
const LOADOUTS: Array[String] = ["m2:loadout.spear_guard", "m2:loadout.sword_fighter",
	"m2:loadout.bow_archer", "m2:loadout.axe_fighter", "m2:loadout.spear_guard", "m2:loadout.bow_archer"]

static func run(t: Sm2TestHarness) -> void:
	_authored(t)
	_catalog_contract(t)
	_catalog_rejections(t)
	var directory: String = "user://tests/turn_content_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	t.equal(error, OK, "turn content: isolated fixture directory")
	if error == OK:
		_scenario_variants(t, directory)
	t.complete_suite("turn_content")

static func _authored(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2TurnContentLoader.load_scenario()
	t.expect(loaded.ok, "turn content: authored scenario loads")
	if not loaded.ok:
		return
	t.expect(loaded.errors.is_empty(), "turn content: successful load has no errors")
	var catalog: Sm2TurnCatalog = loaded.catalog
	t.equal(catalog.version(), "sm2.m2.turn_content.1", "turn content: authored catalog version")
	var raw: Dictionary = catalog.to_data()
	t.equal([raw.profiles.size(), raw.equipment.size(), raw.loadouts.size()], [3, 8, 4], "turn content: source profile/equipment/loadout inventory")
	var setup: Dictionary = loaded.setup
	t.expect(Sm2Validate.fields(setup, ["battle_id", "scenario_id", "seed", "field", "round_limit", "actors"]), "turn content: exact setup fields")
	t.equal([setup.battle_id, setup.scenario_id, setup.seed, setup.round_limit],
		["m2:battle.skirmish_3x3", "m2:scenario.skirmish_3x3", 20260909, 100], "turn content: prescribed setup metadata")
	t.equal(setup.actors.size(), 6, "turn content: six actors")
	var load_oracle: Array[int] = [35, 27, 16, 36, 35, 16]
	var fatigue_oracle: Array[int] = [65, 73, 74, 64, 65, 74]
	var initiative_oracle: Array[int] = [75, 88, 104, 79, 75, 104]
	for index: int in setup.actors.size():
		var actor: Dictionary = setup.actors[index]
		var company: bool = index < 3
		var side: String = "company" if company else "opposition"
		t.equal(actor, {"actor_id": index + 1, "loadout_id": LOADOUTS[index], "side": side,
			"owner": side, "controller": "player" if company else "ai", "creator": 0,
			"q": 1 if company else 9, "r": 2 + index % 3, "fatigue": 0,
			"alive": true, "on_field": true, "morale": "steady"}, "turn content: complete actor setup %d" % (index + 1))
		var definition: Sm2TurnDefinition = catalog.definition(actor.loadout_id)
		t.expect(definition != null, "turn content: assigned definition exists")
		if definition != null:
			t.equal(definition.load_penalty, load_oracle[index], "turn content: independent equipment sum")
			t.equal(definition.fatigue_max, fatigue_oracle[index], "turn content: derived fatigue capacity")
			t.equal(definition.initiative_base - definition.load_penalty, initiative_oracle[index], "turn content: zero fatigue steady initiative inputs")
			t.equal(definition.ap_max, 9, "turn content: profile action points")
	var field_result: Dictionary = Sm2FieldContentLoader.load_scenario()
	t.equal(setup.field, field_result.field.to_data(), "turn content: existing authored field reused")
	var before: String = catalog.fingerprint()
	setup.actors[0].q = 60
	setup.field.surfaces.clear()
	var copy: Dictionary = catalog.to_data()
	copy.equipment.clear()
	var mutable: Sm2TurnDefinition = catalog.definition(LOADOUTS[0])
	mutable.fatigue_max = 1
	t.equal(catalog.fingerprint(), before, "turn content: returned values are detached")
	var again: Dictionary = Sm2TurnContentLoader.load_scenario()
	t.expect(again.ok, "turn content: repeated authored load")
	if again.ok:
		t.equal(again.catalog.fingerprint(), before, "turn content: stable authored fingerprint")
		t.equal(again.setup.actors[0].q, 1, "turn content: setup mutation cannot alter later load")
		t.equal(catalog.definition(LOADOUTS[0]).fatigue_max, 65, "turn content: definition mutation cannot alter catalog")
	t.expect(not Sm2TurnContentLoader.load_scenario("res://content/m2/missing_turn_scenario.tres").ok, "turn content: missing scenario rejected")
	t.expect(not Sm2TurnContentLoader.load_scenario("res://content/m2/skirmish_field.tres").ok, "turn content: wrong scenario resource type rejected")
	t.expect(not Sm2TurnContentLoader.load_catalog("res://content/m2/missing_turn_catalog.tres").ok, "turn content: missing catalog rejected")
	t.expect(not Sm2TurnContentLoader.load_catalog("res://content/m2/skirmish_field.tres").ok, "turn content: wrong catalog resource type rejected")

static func _raw() -> Dictionary:
	return {"version": "test:turns.1", "profiles": [{"id": "profile", "ap_max": 9, "fatigue_base": 100, "initiative_base": 115}],
		"equipment": [{"id": "light", "load_penalty": 5}, {"id": "heavy", "load_penalty": 15}],
		"loadouts": [{"id": "kit", "profile_id": "profile", "equipment_ids": ["light", "heavy"]}]}

static func _catalog_contract(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = Sm2TurnCatalog.new()
	t.expect(not catalog.has_loadout("kit") and catalog.definition("kit") == null, "turn catalog: empty accessors")
	var raw: Dictionary = _raw()
	t.expect(catalog.build(raw).is_empty(), "turn catalog: complete candidate builds")
	t.equal([catalog.definition("kit").load_penalty, catalog.definition("kit").fatigue_max], [20, 80], "turn catalog: independent sum and subtraction")
	var before: String = catalog.fingerprint()
	raw.equipment[0].load_penalty = 99
	t.equal(catalog.fingerprint(), before, "turn catalog: input detached")
	var permuted: Dictionary = _raw()
	permuted.equipment.reverse()
	permuted.loadouts[0].equipment_ids.reverse()
	t.expect(catalog.build(permuted).is_empty(), "turn catalog: equivalent permutations build")
	t.equal(catalog.fingerprint(), before, "turn catalog: normalization ignores authoring array order")
	permuted.equipment[0].load_penalty = 16
	t.expect(catalog.build(permuted).is_empty(), "turn catalog: changed equipment is valid data")
	t.equal([catalog.definition("kit").load_penalty, catalog.definition("kit").fatigue_max], [21, 79], "turn catalog: changed gear recomputes derived capacity")
	t.expect(catalog.fingerprint() != before, "turn catalog: changed gear changes fingerprint")
	var boundary: Dictionary = _raw()
	boundary.profiles[0].fatigue_base = 35
	t.expect(catalog.build(boundary).is_empty(), "turn catalog: exact minimum capacity accepted")
	t.equal(catalog.definition("kit").fatigue_max, 15, "turn catalog: minimum derived capacity")
	boundary = _raw()
	boundary.loadouts[0].equipment_ids = []
	t.expect(catalog.build(boundary).is_empty(), "turn catalog: empty loadout accepted")
	t.equal(catalog.definition("kit").fatigue_max, 100, "turn catalog: no gear keeps base capacity")
	boundary = _raw()
	boundary.profiles[0].ap_max = 1000.0
	boundary.profiles[0].fatigue_base = 10000.0
	boundary.profiles[0].initiative_base = 0.0
	boundary.equipment[0].load_penalty = 0.0
	t.expect(catalog.build(boundary).is_empty(), "turn catalog: safe integral JSON numbers and bounds accepted")
	t.expect(catalog.to_data().profiles[0].ap_max is int, "turn catalog: JSON numbers normalized to int")
	t.equal(catalog.definition("kit").initiative_base, 0, "turn catalog: zero initiative remains valid")

static func _catalog_rejections(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = Sm2TurnCatalog.new()
	catalog.build(_raw())
	var bad: Dictionary = _raw()
	bad.extra = true
	_reject_raw(t, catalog, bad, "extra root field")
	bad = _raw()
	bad.erase("version")
	_reject_raw(t, catalog, bad, "missing root field")
	bad = _raw()
	bad.version = " "
	_reject_raw(t, catalog, bad, "blank version")
	for group: String in Sm2TurnCatalog.GROUPS:
		bad = _raw()
		bad[group] = "not an array"
		_reject_raw(t, catalog, bad, "invalid collection " + group)
		bad = _raw()
		bad[group].append(null)
		_reject_raw(t, catalog, bad, "null definition " + group)
		bad = _raw()
		bad[group].append(bad[group][0].duplicate(true))
		_reject_raw(t, catalog, bad, "duplicate ID " + group)
		bad = _raw()
		bad[group][0].unexpected = 1
		_reject_raw(t, catalog, bad, "extra definition field " + group)
		bad = _raw()
		bad[group].resize(10001)
		_reject_raw(t, catalog, bad, "collection exceeds 10000 " + group)
	for invalid_ap: Variant in [0, 1001, 9.5, true, "9", NAN, INF]:
		bad = _raw()
		bad.profiles[0].ap_max = invalid_ap
		_reject_raw(t, catalog, bad, "invalid AP")
	for invalid_base: int in [14, 10001]:
		bad = _raw()
		bad.profiles[0].fatigue_base = invalid_base
		_reject_raw(t, catalog, bad, "invalid base fatigue")
	for invalid_initiative: int in [-1, 10001]:
		bad = _raw()
		bad.profiles[0].initiative_base = invalid_initiative
		_reject_raw(t, catalog, bad, "invalid initiative")
	for invalid_load: int in [-1, 10001]:
		bad = _raw()
		bad.equipment[0].load_penalty = invalid_load
		_reject_raw(t, catalog, bad, "invalid equipment load")
	bad = _raw()
	bad.profiles[0].fatigue_base = 34
	_reject_raw(t, catalog, bad, "summed load leaves only 14 capacity")
	bad = _raw()
	bad.loadouts[0].profile_id = "light"
	_reject_raw(t, catalog, bad, "equipment ID cannot resolve a profile")
	bad = _raw()
	bad.loadouts[0].equipment_ids = ["profile"]
	_reject_raw(t, catalog, bad, "profile ID cannot resolve equipment")
	bad = _raw()
	bad.loadouts[0].equipment_ids = ["light", "light"]
	_reject_raw(t, catalog, bad, "same equipment listed twice")
	bad = _raw()
	bad.loadouts[0].equipment_ids = [17]
	_reject_raw(t, catalog, bad, "non-string equipment ID")
	bad = _raw()
	bad.equipment.clear()
	bad.loadouts[0].equipment_ids.clear()
	for index: int in 65:
		var id: String = "gear_%d" % index
		bad.equipment.append({"id": id, "load_penalty": 0})
		bad.loadouts[0].equipment_ids.append(id)
	_reject_raw(t, catalog, bad, "loadout exceeds 64 equipment definitions")
	bad.equipment.pop_back()
	bad.loadouts[0].equipment_ids.pop_back()
	var boundary: Sm2TurnCatalog = Sm2TurnCatalog.new()
	t.expect(boundary.build(bad).is_empty(), "turn catalog: exactly 64 equipment definitions accepted")
	t.equal(boundary.definition("kit").load_penalty, 0, "turn catalog: zero load gear remains zero at limit")

static func _reject_raw(t: Sm2TestHarness, catalog: Sm2TurnCatalog, raw: Dictionary, label: String) -> void:
	var before: String = catalog.fingerprint()
	var errors: PackedStringArray = catalog.build(raw)
	t.expect(not errors.is_empty(), "turn catalog rejected: " + label)
	t.equal(catalog.fingerprint(), before, "turn catalog rejection keeps prior catalog: " + label)
	t.equal(catalog.definition("kit").fatigue_max, 80, "turn catalog rejection keeps resolved definition")

static func _scenario() -> Sm2TurnScenarioContent:
	var scenario: Sm2TurnScenarioContent = Sm2TurnScenarioContent.new()
	scenario.battle_id = "test:turn_battle"
	scenario.field_manifest = ResourceLoader.load("res://content/m2/skirmish_field.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Sm2FieldManifest
	scenario.catalog_manifest = _manifest()
	for index: int in 6:
		var assignment: Sm2TurnAssignmentContent = Sm2TurnAssignmentContent.new()
		assignment.actor_id = index + 1
		assignment.loadout_id = "kit"
		scenario.assignments.append(assignment)
	return scenario

static func _manifest() -> Sm2TurnContentManifest:
	var manifest: Sm2TurnContentManifest = Sm2TurnContentManifest.new()
	manifest.version = "test:turn_manifest.1"
	var profile: Sm2TurnProfileContent = Sm2TurnProfileContent.new()
	profile.id = "profile"
	profile.ap_max = 7
	profile.fatigue_base = 90
	profile.initiative_base = 123
	manifest.profiles.append(profile)
	var equipment: Sm2TurnEquipmentContent = Sm2TurnEquipmentContent.new()
	equipment.id = "gear"
	equipment.load_penalty = 20
	manifest.equipment.append(equipment)
	var loadout: Sm2TurnLoadoutContent = Sm2TurnLoadoutContent.new()
	loadout.id = "kit"
	loadout.profile_id = "profile"
	loadout.equipment_ids.assign(["gear"])
	manifest.loadouts.append(loadout)
	return manifest

static func _scenario_variants(t: Sm2TestHarness, directory: String) -> void:
	var valid: Sm2TurnScenarioContent = _scenario()
	valid.round_limit = 1
	valid.assignments.reverse()
	var loaded: Dictionary = _load_fixture(t, valid, directory, "custom")
	t.expect(loaded.ok, "turn scenario: custom profile, loadout and reordered assignments")
	if loaded.ok:
		t.equal(loaded.setup.round_limit, 1, "turn scenario: authored round limit retained")
		t.equal(loaded.catalog.definition("kit").fatigue_max, 70, "turn scenario: custom equipment derived")
		t.equal(loaded.catalog.definition("kit").ap_max, 7, "turn scenario: custom AP retained")
		t.equal(loaded.setup.actors[0].actor_id, 1, "turn scenario: stable numerical actor order")
	for reason: String in ["missing_assignment", "extra_assignment", "duplicate_assignment", "foreign_actor",
		"unknown_loadout", "null_assignment", "null_field", "null_catalog", "null_profile", "null_equipment",
		"null_loadout", "overloaded", "invalid_battle", "round_zero", "round_over_limit", "actor_zero", "actor_above_limit"]:
		var candidate: Sm2TurnScenarioContent = _scenario()
		match reason:
			"missing_assignment": candidate.assignments.pop_back()
			"extra_assignment": candidate.assignments.append(candidate.assignments[0])
			"duplicate_assignment": candidate.assignments[1].actor_id = 1
			"foreign_actor": candidate.assignments[0].actor_id = 100
			"unknown_loadout": candidate.assignments[0].loadout_id = "missing"
			"null_assignment": candidate.assignments[0] = null
			"null_field": candidate.field_manifest = null
			"null_catalog": candidate.catalog_manifest = null
			"null_profile": candidate.catalog_manifest.profiles[0] = null
			"null_equipment": candidate.catalog_manifest.equipment[0] = null
			"null_loadout": candidate.catalog_manifest.loadouts[0] = null
			"overloaded": candidate.catalog_manifest.equipment[0].load_penalty = 76
			"invalid_battle": candidate.battle_id = " "
			"round_zero": candidate.round_limit = 0
			"round_over_limit": candidate.round_limit = 1001
			"actor_zero": candidate.assignments[0].actor_id = 0
			"actor_above_limit": candidate.assignments[0].actor_id = 9223372036854775806
		loaded = _load_fixture(t, candidate, directory, reason)
		t.expect(not loaded.ok and not loaded.errors.is_empty(), "turn scenario rejects: " + reason)
		t.expect(loaded.catalog == null and loaded.setup.is_empty(), "turn scenario failure publishes no partial result")
	# A new saved field proves setup values come from the referenced field rather than six hard-coded actors.
	var altered: Sm2TurnScenarioContent = _scenario()
	var field: Sm2FieldManifest = altered.field_manifest.duplicate(true) as Sm2FieldManifest
	field.seed = -9007199254740993
	field.scenario_id = "test:other_field"
	field.spawns[0].id = 9007199254740993
	field.spawns[0].owner = "different_owner"
	field.spawns[0].controller = "different_controller"
	field.spawns[0].q = 0
	altered.assignments[0].actor_id = 9007199254740993
	var field_path: String = directory.path_join("alternate_field.tres")
	var saved: Error = ResourceSaver.save(field, field_path)
	t.equal(saved, OK, "turn scenario: altered field saved")
	if saved == OK:
		altered.field_manifest = ResourceLoader.load(field_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Sm2FieldManifest
		loaded = _load_fixture(t, altered, directory, "alternate_field_scenario")
		t.expect(loaded.ok, "turn scenario: arbitrary exact ID and field metadata accepted")
		if loaded.ok:
			t.equal(loaded.setup.seed, -9007199254740993, "turn scenario: seed retained as int64")
			t.equal(loaded.setup.scenario_id, "test:other_field", "turn scenario: field scenario identity retained")
			var actor: Dictionary = loaded.setup.actors[5]
			t.equal([actor.actor_id, actor.owner, actor.controller, actor.q],
				[9007199254740993, "different_owner", "different_controller", 0], "turn scenario: marker ownership/position/int64 ID retained")

static func _load_fixture(t: Sm2TestHarness, scenario: Sm2TurnScenarioContent, directory: String, label: String) -> Dictionary:
	var path: String = directory.path_join(label + ".tres")
	var error: Error = ResourceSaver.save(scenario, path)
	t.equal(error, OK, "turn scenario fixture saved: " + label)
	if error != OK:
		return {"ok": false, "catalog": null, "setup": {}, "errors": PackedStringArray(["fixture save failed"])}
	return Sm2TurnContentLoader.load_scenario(path)
