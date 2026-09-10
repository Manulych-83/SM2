extends RefCounted
## Authoring -> validated field integration. No combat statistics or turns here.


static func run(t: Sm2TestHarness) -> void:
	_check_authored(t)
	var directory: String = "user://tests/m2_content_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	t.equal(directory_error, OK, "m2 content: isolated fixture directory created")
	if directory_error != OK:
		t.complete_suite("m2_content")
		return
	_check_valid_variants(t, directory)
	_check_rejections(t, directory)
	var own_directory: DirAccess = DirAccess.open(directory)
	if own_directory != null:
		for filename: String in own_directory.get_files():
			DirAccess.remove_absolute(directory.path_join(filename))
		DirAccess.remove_absolute(directory)
	t.complete_suite("m2_content")


static func _check_authored(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2FieldContentLoader.load_scenario()
	t.expect(loaded["ok"], "m2 content: authored skirmish field loads")
	if not loaded["ok"]:
		return
	var field: Sm2Battlefield = loaded["field"]
	t.equal(loaded["scenario_id"], "m2:scenario.skirmish_3x3", "m2 content: stable scenario ID")
	t.equal(loaded["seed"], 20260909, "m2 content: prescribed seed lives in authoring data")
	t.equal(field.id(), loaded["scenario_id"], "m2 content: field identity is scenario identity")
	t.equal(field.width(), 11, "m2 content: field width")
	t.equal(field.height(), 7, "m2 content: field height")
	t.equal(field.to_data()["surfaces"].size(), 2, "m2 content: two authored surface definitions")
	t.equal(field.to_data()["tiles"].size(), 13, "m2 content: sparse thirteen overrides retained")
	var counts: Dictionary = {"cells": 0, "passable": 0, "rough": 0, "rocks": 0, "raised": 0}
	for q: int in field.width():
		for r: int in field.height():
			var cell: Dictionary = field.cell(Vector2i(q, r))
			counts["cells"] += 1
			if cell["passable"]:
				counts["passable"] += 1
			if cell["surface_id"] == "m2:surface.rough":
				counts["rough"] += 1
			if not cell["passable"] and cell["opaque"]:
				counts["rocks"] += 1
			if cell["elevation"] == 1:
				counts["raised"] += 1
	t.equal(counts, {"cells": 77, "passable": 75, "rough": 5, "rocks": 2, "raised": 6}, "m2 content: complete prescribed terrain inventory")
	for position: Vector2i in [Vector2i(4, 2), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(6, 4)]:
		var cell: Dictionary = field.cell(position)
		t.equal(cell["surface_id"], "m2:surface.rough", "m2 content: rough cell %s" % position)
		t.equal([cell["ap_cost"], cell["fatigue_cost"]], [3, 6], "m2 content: rough destination price")
	for position: Vector2i in [Vector2i(5, 1), Vector2i(5, 5)]:
		var cell: Dictionary = field.cell(position)
		t.expect(not cell["passable"] and cell["opaque"], "m2 content: rock is blocked and opaque %s" % position)
	for position: Vector2i in [Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 1), Vector2i(8, 4), Vector2i(8, 5), Vector2i(7, 5)]:
		t.equal(field.cell(position)["elevation"], 1, "m2 content: prescribed elevated cell %s" % position)
	t.equal([field.cell(Vector2i.ZERO)["ap_cost"], field.cell(Vector2i.ZERO)["fatigue_cost"]], [2, 4], "m2 content: default ground price")
	var expected_spawns: Array[Dictionary] = []
	for actor_id: int in range(1, 7):
		var company: bool = actor_id <= 3
		var side: String = "company" if company else "opposition"
		expected_spawns.append({"actor_id": actor_id, "side": side, "owner": side,
			"controller": "player" if company else "ai", "q": 1 if company else 9,
			"r": 2 + (actor_id - 1) % 3})
	t.equal(loaded["spawns"], expected_spawns, "m2 content: exact six start markers and ownership")
	var original_fingerprint: String = field.fingerprint()
	var detached_cell: Dictionary = field.cell(Vector2i.ZERO)
	detached_cell["passable"] = false
	var detached_data: Dictionary = field.to_data()
	detached_data["surfaces"][0]["ap_cost"] = 99
	loaded["spawns"][0]["q"] = 10
	t.equal(field.fingerprint(), original_fingerprint, "m2 content: returned cell and map data are detached")
	var reloaded: Dictionary = Sm2FieldContentLoader.load_scenario()
	t.expect(reloaded["ok"], "m2 content: second independent load succeeds")
	if reloaded["ok"]:
		t.equal(reloaded["spawns"], expected_spawns, "m2 content: returned markers do not mutate authoring or later loads")
		t.equal(reloaded["field"].fingerprint(), original_fingerprint, "m2 content: repeated field load is deterministic")
	t.expect(not Sm2FieldContentLoader.load_scenario("res://content/m2/missing_field.tres")["ok"], "m2 content: missing manifest is controlled")
	t.expect(not Sm2FieldContentLoader.load_scenario("res://content/m2/surfaces/ground.tres")["ok"], "m2 content: wrong resource type is rejected")


static func _check_valid_variants(t: Sm2TestHarness, directory: String) -> void:
	var manifest: Sm2FieldManifest = _fixture()
	manifest.seed = -9007199254740993
	manifest.spawns[0].id = 9007199254740993
	manifest.spawns[1].id = Sm2FieldContentLoader.MAX_ACTOR_ID
	manifest.spawns[0].owner = "third_party_owner"
	manifest.spawns[0].controller = "independent_controller"
	var loaded: Dictionary = _load_fixture(t, manifest, directory, "int64_ids")
	t.expect(loaded["ok"], "m2 content: arbitrary two sides, owners, controllers and non-contiguous int64 IDs accepted")
	if loaded["ok"]:
		t.equal(loaded["seed"], -9007199254740993, "m2 content: authoring seed is not narrowed to int32 or JSON float")
		t.equal(loaded["spawns"][0]["actor_id"], 9007199254740993, "m2 content: first large actor ID remains exact")
		t.equal(loaded["spawns"][1]["actor_id"], Sm2FieldContentLoader.MAX_ACTOR_ID, "m2 content: largest supported actor ID remains exact")
	manifest = _fixture()
	manifest.surfaces.append(_surface("test:surface.moss", 1, 9))
	manifest.tiles.append(_tile(1, 0, "test:surface.moss"))
	loaded = _load_fixture(t, manifest, directory, "new_surface")
	t.expect(loaded["ok"], "m2 content: new surface is added through data")
	if loaded["ok"]:
		var cell: Dictionary = loaded["field"].cell(Vector2i(1, 0))
		t.equal([cell["surface_id"], cell["ap_cost"], cell["fatigue_cost"]], ["test:surface.moss", 1, 9], "m2 content: independent surface AP and fatigue are preserved")
	manifest = _fixture()
	manifest.default_elevation = 16
	manifest.surfaces[0].fatigue_cost = 0
	loaded = _load_fixture(t, manifest, directory, "allowed_bounds")
	t.expect(loaded["ok"], "m2 content: allowed default elevation and zero fatigue remain valid")
	if loaded["ok"]:
		t.equal(loaded["field"].cell(Vector2i(2, 1))["elevation"], 16, "m2 content: authored default elevation fills unlisted cells")


static func _check_rejections(t: Sm2TestHarness, directory: String) -> void:
	var manifest: Sm2FieldManifest = _fixture()
	manifest.surfaces.append(null)
	_reject(t, manifest, directory, "null_surface")
	manifest = _fixture()
	manifest.tiles.append(null)
	_reject(t, manifest, directory, "null_tile")
	manifest = _fixture()
	manifest.spawns.append(null)
	_reject(t, manifest, directory, "null_spawn")
	manifest = _fixture()
	manifest.surfaces.append(_surface("test:surface.ground", 3, 6))
	_reject(t, manifest, directory, "duplicate_surface")
	manifest = _fixture()
	manifest.surfaces.clear()
	_reject(t, manifest, directory, "no_surfaces")
	manifest = _fixture()
	manifest.default_surface_id = "test:surface.missing"
	_reject(t, manifest, directory, "unknown_default_surface")
	manifest = _fixture()
	manifest.tiles.append(_tile(1, 0, "test:surface.missing"))
	_reject(t, manifest, directory, "unknown_cell_surface")
	manifest = _fixture()
	manifest.tiles.append(_tile(1, 0))
	manifest.tiles.append(_tile(1, 0))
	_reject(t, manifest, directory, "duplicate_tile")
	manifest = _fixture()
	manifest.tiles.append(_tile(4, 0))
	_reject(t, manifest, directory, "out_of_bounds_tile")
	manifest = _fixture()
	manifest.tiles.append(_tile(1, 0, "test:surface.ground", 17))
	_reject(t, manifest, directory, "invalid_elevation")
	for invalid_width: int in [0, 65]:
		manifest = _fixture()
		manifest.width = invalid_width
		_reject(t, manifest, directory, "width_%s" % invalid_width)
	manifest = _fixture()
	manifest.version = ""
	_reject(t, manifest, directory, "empty_version")
	manifest = _fixture()
	manifest.scenario_id = ""
	_reject(t, manifest, directory, "empty_scenario_id")
	for invalid_ap: int in [0, 101]:
		manifest = _fixture()
		manifest.surfaces[0].ap_cost = invalid_ap
		_reject(t, manifest, directory, "surface_ap_%s" % invalid_ap)
	for invalid_fatigue: int in [-1, 101]:
		manifest = _fixture()
		manifest.surfaces[0].fatigue_cost = invalid_fatigue
		_reject(t, manifest, directory, "surface_fatigue_%s" % invalid_fatigue)
	manifest = _fixture()
	manifest.spawns[1].id = manifest.spawns[0].id
	_reject(t, manifest, directory, "duplicate_actor_id")
	for invalid_id: int in [0, -1, 9223372036854775807]:
		manifest = _fixture()
		manifest.spawns[0].id = invalid_id
		_reject(t, manifest, directory, "actor_id_%s" % invalid_id)
	for invalid_q: int in [-1, 4, 4294967296]:
		manifest = _fixture()
		manifest.spawns[0].q = invalid_q
		_reject(t, manifest, directory, "spawn_q_%s" % invalid_q)
	manifest = _fixture()
	manifest.spawns[1].q = manifest.spawns[0].q
	manifest.spawns[1].r = manifest.spawns[0].r
	_reject(t, manifest, directory, "occupied_spawn")
	manifest = _fixture()
	manifest.tiles.append(_tile(0, 0, "test:surface.ground", 0, false, true))
	_reject(t, manifest, directory, "blocked_spawn")
	manifest = _fixture()
	manifest.spawns[1].side = manifest.spawns[0].side
	_reject(t, manifest, directory, "one_side")
	manifest = _fixture()
	manifest.spawns.append(_marker(7, 2, 1, "third_side"))
	_reject(t, manifest, directory, "three_sides")
	manifest = _fixture()
	manifest.spawns[0].side = ""
	_reject(t, manifest, directory, "empty_side")
	manifest = _fixture()
	manifest.spawns[0].owner = " "
	_reject(t, manifest, directory, "empty_owner")
	manifest = _fixture()
	manifest.spawns[0].controller = ""
	_reject(t, manifest, directory, "empty_controller")
	manifest = _fixture()
	manifest.spawns.resize(1)
	_reject(t, manifest, directory, "single_spawn")
	manifest = _fixture()
	manifest.spawns.resize(Sm2FieldContentLoader.MAX_SPAWNS + 1)
	_reject(t, manifest, directory, "too_many_spawns")
	manifest = _fixture()
	manifest.width = 1
	manifest.height = 1
	_reject(t, manifest, directory, "spawns_exceed_cells")


static func _reject(t: Sm2TestHarness, manifest: Sm2FieldManifest, directory: String, label: String) -> void:
	var result: Dictionary = _load_fixture(t, manifest, directory, label)
	t.expect(not result["ok"], "m2 content: reject " + label)
	t.equal(result["field"], null, "m2 content: no field published for " + label)
	t.equal(result["spawns"].size(), 0, "m2 content: no partial spawn list for " + label)
	t.expect(not result["errors"].is_empty(), "m2 content: refusal has diagnostics for " + label)


static func _load_fixture(t: Sm2TestHarness, manifest: Sm2FieldManifest, directory: String, label: String) -> Dictionary:
	var path: String = directory.path_join(label + ".tres")
	var write_error: Error = ResourceSaver.save(manifest, path)
	t.equal(write_error, OK, "m2 content: resource fixture written " + label)
	if write_error != OK:
		return {"ok": false, "field": null, "spawns": [], "errors": PackedStringArray(["fixture_write_failed"])}
	return Sm2FieldContentLoader.load_scenario(path)


static func _fixture() -> Sm2FieldManifest:
	var manifest: Sm2FieldManifest = Sm2FieldManifest.new()
	manifest.version = "test.m2.field.1"
	manifest.scenario_id = "test:scenario.field"
	manifest.seed = 901
	manifest.width = 4
	manifest.height = 3
	manifest.default_surface_id = "test:surface.ground"
	manifest.surfaces.append(_surface("test:surface.ground", 2, 4))
	manifest.surfaces.append(_surface("test:surface.rough", 3, 6))
	manifest.spawns.append(_marker(11, 0, 0, "left"))
	manifest.spawns.append(_marker(99, 3, 2, "right"))
	return manifest


static func _surface(id: String, ap: int, fatigue: int) -> Sm2SurfaceContent:
	var surface: Sm2SurfaceContent = Sm2SurfaceContent.new()
	surface.id = id
	surface.ap_cost = ap
	surface.fatigue_cost = fatigue
	return surface


static func _tile(q: int, r: int, surface_id: String = "test:surface.ground", elevation: int = 0,
		passable: bool = true, opaque: bool = false) -> Sm2CellOverrideContent:
	var tile: Sm2CellOverrideContent = Sm2CellOverrideContent.new()
	tile.q = q
	tile.r = r
	tile.surface_id = surface_id
	tile.elevation = elevation
	tile.passable = passable
	tile.opaque = opaque
	return tile


static func _marker(id: int, q: int, r: int, side: String) -> Sm2SpawnMarkerContent:
	var marker: Sm2SpawnMarkerContent = Sm2SpawnMarkerContent.new()
	marker.id = id
	marker.q = q
	marker.r = r
	marker.side = side
	marker.owner = side
	marker.controller = "ai"
	return marker
