extends RefCounted


static func run(t: Sm2TestHarness) -> void:
	var directory: String = "user://tests/storage_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	var payload: Dictionary = {"session_id": "9223372036854775807", "revision": "0",
		"nested": {"actors": [{"id": "1", "hp": 12, "alive": true}], "none": null},
		"fraction": 1.23456789012345, "negative": -7, "integer_float": 2.0}
	t.expect(not store.has_slot(), "storage: missing slot is absent")
	t.expect(not store.load_slot()["ok"], "storage: missing slot is controlled error")
	var input_hash: String = Sm2Canonical.hash(payload)
	t.expect(store.save_slot(payload)["ok"], "storage: first save succeeds")
	t.equal(Sm2Canonical.hash(payload), input_hash, "storage: save does not mutate payload")
	t.expect(store.has_slot(), "storage: saved slot exists")
	var first: Dictionary = store.load_slot()
	t.expect(first["ok"], "storage: saved payload reloads")
	t.equal(Sm2Canonical.hash(first["payload"]), input_hash, "storage: exact canonical roundtrip including large IDs and fractions")
	first["payload"]["nested"]["actors"][0]["hp"] = 0
	t.equal(store.load_slot()["payload"]["nested"]["actors"][0]["hp"], 12, "storage: load returns detached payload")
	var original_file: String = _read_text(directory.path_join("session.json"))
	var second_payload: Dictionary = payload.duplicate(true)
	second_payload["revision"] = "1"
	t.expect(store.save_slot(second_payload)["ok"], "storage: second save succeeds")
	t.equal(_read_text(directory.path_join("session.json.bak")), original_file, "storage: backup preserves previous slot")
	t.expect(not FileAccess.file_exists(directory.path_join("session.json.tmp")), "storage: successful publication leaves no temp")
	t.equal(store.load_slot()["payload"]["revision"], "1", "storage: second snapshot is current")
	var current_file: String = _read_text(directory.path_join("session.json"))
	var rejected_payloads: Array[Dictionary] = [
		{"object": RefCounted.new()}, {"vector": Vector2i(1, 2)},
		{3: "non_string_key"}, {"not_finite": INF}, {"not_finite": NAN},
		{"large_int": 9223372036854775807}, {"packed_array": PackedInt32Array([1])}]
	for invalid: Dictionary in rejected_payloads:
		t.expect(not store.save_slot(invalid)["ok"], "storage: rejects non-JSON or lossy value %s" % str(invalid.keys()))
		t.equal(_read_text(directory.path_join("session.json")), current_file, "storage: validation failure preserves current slot")
	t.equal(_read_text(directory.path_join("session.json.bak")), original_file, "storage: validation failure preserves backup")
	var deep: Dictionary = {}
	for index: int in Sm2SaveStore.MAX_DEPTH + 1:
		deep = {"child": deep}
	t.expect(not store.save_slot(deep)["ok"], "storage: rejects excessive nesting")
	var excessive: Array = []
	excessive.resize(Sm2SaveStore.MAX_COLLECTION_SIZE + 1)
	t.expect(not store.save_slot({"items": excessive})["ok"], "storage: rejects excessive collection")
	t.expect(not store.save_slot({"text": "x".repeat(Sm2SaveStore.MAX_STRING_LENGTH + 1)})["ok"], "storage: rejects excessive string")
	var too_many_nodes: Array = []
	for index: int in 6:
		var child: Array = []
		child.resize(9000)
		too_many_nodes.append(child)
	t.expect(not store.save_slot({"items": too_many_nodes})["ok"], "storage: rejects total node limit")
	var oversized: Array[String] = []
	for index: int in 9:
		oversized.append("x".repeat(Sm2SaveStore.MAX_STRING_LENGTH))
	t.expect(not store.save_slot({"strings": oversized})["ok"], "storage: rejects oversized encoded file")
	t.equal(_read_text(directory.path_join("session.json")), current_file, "storage: size/depth failures preserve current slot")
	for invalid_slot: String in ["", "../escape", "a/b", "a\\b", "session.json", "C:escape", "CON", "LPT1", "a".repeat(65)]:
		t.expect(not store.save_slot(payload, invalid_slot)["ok"], "storage: rejects slot name " + invalid_slot)
		t.expect(not store.load_slot(invalid_slot)["ok"], "storage: rejects invalid load name " + invalid_slot)
		t.expect(not store.has_slot(invalid_slot), "storage: invalid names never report a slot")
	for invalid_directory: String in ["", "relative/path", "user://tests/../saves", "res://content", "user://"]:
		var invalid_store: Sm2SaveStore = Sm2SaveStore.new(invalid_directory)
		t.expect(not invalid_store.save_slot(payload)["ok"], "storage: invalid base directory is controlled")
		t.expect(not invalid_store.load_slot()["ok"], "storage: invalid base read is controlled")
	_write_text(directory.path_join("occupied"), "regular file")
	var occupied_store: Sm2SaveStore = Sm2SaveStore.new(directory.path_join("occupied/child"))
	t.expect(not occupied_store.save_slot(payload)["ok"], "storage: filesystem rejects unusable location without exception")
	_write_text(directory.path_join("corrupt.json"), "{this is broken")
	t.expect(not store.load_slot("corrupt")["ok"], "storage: corrupt JSON is rejected")
	t.expect(not store.save_slot(payload, "corrupt")["ok"], "storage: corrupted previous slot is retained for recovery")
	t.equal(_read_text(directory.path_join("corrupt.json")), "{this is broken", "storage: corrupted previous file remains intact")
	_write_text(directory.path_join("badroot.json"), "[]")
	t.expect(not store.load_slot("badroot")["ok"], "storage: array root is rejected")
	_write_text(directory.path_join("deep.json"), "[".repeat(100) + "0" + "]".repeat(100))
	t.expect(not store.load_slot("deep")["ok"], "storage: excessive JSON nesting rejected before parsing")
	_write_text(directory.path_join("oversized.json"), " ".repeat(Sm2SaveStore.MAX_FILE_BYTES + 1))
	t.expect(not store.load_slot("oversized")["ok"], "storage: oversized file rejected before parsing")
	var envelope: Dictionary = {"format": "sm2.save", "schema_version": 2,
		"payload": payload, "checksum": Sm2Canonical.hash(payload)}
	var bad_envelopes: Array[Dictionary] = []
	var future: Dictionary = envelope.duplicate(true)
	future["schema_version"] = 3
	bad_envelopes.append(future)
	for bad_version: Variant in ["2", true, 1.5, 0, -1]:
		var wrong_version: Dictionary = envelope.duplicate(true)
		wrong_version["schema_version"] = bad_version
		bad_envelopes.append(wrong_version)
	var checksum_failure: Dictionary = envelope.duplicate(true)
	checksum_failure["checksum"] = "0".repeat(64)
	bad_envelopes.append(checksum_failure)
	var checksum_type: Dictionary = envelope.duplicate(true)
	checksum_type["checksum"] = 12
	bad_envelopes.append(checksum_type)
	var checksum_format: Dictionary = envelope.duplicate(true)
	checksum_format["checksum"] = "g".repeat(64)
	bad_envelopes.append(checksum_format)
	var wrong_payload: Dictionary = envelope.duplicate(true)
	wrong_payload["payload"] = []
	bad_envelopes.append(wrong_payload)
	var wrong_format: Dictionary = envelope.duplicate(true)
	wrong_format["format"] = "another.save"
	bad_envelopes.append(wrong_format)
	var missing_field: Dictionary = envelope.duplicate(true)
	missing_field.erase("checksum")
	bad_envelopes.append(missing_field)
	var extra_field: Dictionary = envelope.duplicate(true)
	extra_field["surprise"] = 1
	bad_envelopes.append(extra_field)
	for index: int in bad_envelopes.size():
		_write_json(directory.path_join("invalid_%s.json" % index), bad_envelopes[index])
		t.expect(not store.load_slot("invalid_%s" % index)["ok"], "storage: malformed envelope %s rejected" % index)
	var migrated: Dictionary = {"format": "sm2.save", "schema_version": 1,
		"state": payload, "checksum": Sm2Canonical.hash(payload)}
	_write_json(directory.path_join("legacy.json"), migrated)
	var legacy_file: String = _read_text(directory.path_join("legacy.json"))
	var legacy_load: Dictionary = store.load_slot("legacy")
	t.expect(legacy_load["ok"], "storage: schema 1 fixture migrates in memory")
	t.equal(Sm2Canonical.hash(legacy_load["payload"]), input_hash, "storage: migration retains payload")
	t.equal(_read_text(directory.path_join("legacy.json")), legacy_file, "storage: reading migration never overwrites file")
	migrated["state"]["revision"] = "tampered"
	_write_json(directory.path_join("legacy_bad.json"), migrated)
	t.expect(not store.load_slot("legacy_bad")["ok"], "storage: schema 1 checksum is checked before migration")
	var rollback_payload: Dictionary = {"revision": "before_blocked_backup"}
	t.expect(store.save_slot(rollback_payload, "blocked")["ok"], "storage: rollback fixture is published")
	DirAccess.make_dir_recursive_absolute(directory.path_join("blocked.json.bak"))
	t.expect(not store.save_slot({"revision": "after"}, "blocked")["ok"], "storage: blocked backup publication is controlled")
	t.equal(store.load_slot("blocked")["payload"]["revision"], "before_blocked_backup", "storage: backup failure keeps previous slot readable")
	t.expect(not FileAccess.file_exists(directory.path_join("blocked.json.tmp")), "storage: failed backup removes temporary file")
	DirAccess.remove_absolute(directory.path_join("blocked.json.bak"))
	DirAccess.make_dir_recursive_absolute(directory.path_join("blocked_publish.json"))
	t.expect(not store.save_slot({"revision": "new"}, "blocked_publish")["ok"], "storage: blocked final publication returns controlled error")
	t.expect(not store.has_slot("blocked_publish"), "storage: failed publication leaves no valid partial slot")
	t.expect(not FileAccess.file_exists(directory.path_join("blocked_publish.json.tmp")), "storage: failed publication removes temp file")
	DirAccess.remove_absolute(directory.path_join("blocked_publish.json"))
	_check_content(t, directory)
	# Cleanup is limited to this run's flat, uniquely named test directory.
	var test_directory: DirAccess = DirAccess.open(directory)
	if test_directory != null:
		for filename: String in test_directory.get_files():
			DirAccess.remove_absolute(directory.path_join(filename))
		DirAccess.remove_absolute(directory)
	t.complete_suite("integration")



static func _check_content(t: Sm2TestHarness, directory: String) -> void:
	var loaded: Dictionary = Sm2ContentLoader.load_catalog()
	t.expect(loaded["ok"], "content: authored manifest loads")
	if loaded["ok"]:
		var catalog: Sm2Catalog = loaded["catalog"]
		var data: Dictionary = catalog.to_data()
		t.equal(data["actors"].size(), 3, "content: three authored actors")
		t.equal(data["weapons"].size(), 2, "content: two authored weapons")
		t.equal(data["abilities"].size(), 3, "content: three authored abilities")
		t.equal(data["statuses"].size(), 1, "content: one authored status")
		t.expect(catalog.has_actor("core:actor.wisp"), "content: summon target exists")
		t.expect(catalog.has_weapon("core:weapon.heavy_practice_blade"), "content: second weapon added in data")
		t.equal(catalog.version(), "core.m1.1", "content: authored content version retained")
	t.expect(not Sm2ContentLoader.load_catalog("res://content/core/not_found.tres")["ok"], "content: missing manifest is controlled")
	t.expect(not Sm2ContentLoader.load_catalog("res://content/core/weapons/practice_blade.tres")["ok"], "content: wrong resource type is rejected")
	var invalid_manifest: Sm2ContentManifest = Sm2ContentManifest.new()
	invalid_manifest.version = "invalid.fixture"
	invalid_manifest.actors.append(null)
	var manifest_path: String = directory.path_join("invalid_manifest.tres")
	t.equal(ResourceSaver.save(invalid_manifest, manifest_path), OK, "content: invalid manifest fixture written")
	var invalid_load: Dictionary = Sm2ContentLoader.load_catalog(manifest_path)
	t.expect(not invalid_load["ok"], "content: null authoring reference is rejected")
	t.equal(invalid_load["catalog"], null, "content: bad manifest never publishes partial catalog")


static func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value, "", true, true))


static func _write_text(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()


static func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var result: String = file.get_as_text()
	file.close()
	return result
