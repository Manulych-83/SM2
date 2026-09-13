class_name Sm2HistoryRepository
extends RefCounted
## Immutable, content-addressed blocks. Orphans are retained on failed publication.
var store: Sm2SaveStore
var _verified: Dictionary={}
func _init(directory: String) -> void: store=Sm2SaveStore.new(directory.path_join("history_blocks"))

func read(hash_value: String) -> Dictionary:
	if not Sm2CheckpointWorld.digest(hash_value): return {"ok":false,"errors":PackedStringArray(["archive_hash"])}
	if not store._location_error(hash_value).is_empty(): return {"ok":false,"errors":PackedStringArray(["archive_directory"])}
	var path: String=store._slot_path(hash_value)
	var file_hash: String=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if not file_hash.is_empty() and _verified.has(hash_value) and _verified[hash_value].file_hash==file_hash and _verified[hash_value].budget==store.node_budget():
		return {"ok":true,"payload":_verified[hash_value].payload.duplicate(true)}
	var result: Dictionary=store.load_slot(hash_value)
	if result.ok and Sm2Canonical.hash(result.payload)!=hash_value: return {"ok":false,"errors":PackedStringArray(["archive_content_hash"])}
	if result.ok:
		if file_hash.is_empty() or file_hash!=FileAccess.get_sha256(path): return {"ok":false,"errors":PackedStringArray(["archive_changed_during_read"])}
		_verified[hash_value]={"file_hash":file_hash,"payload":result.payload.duplicate(true),"budget":store.node_budget()}
	return result

func publish(blocks: Dictionary) -> Dictionary:
	for hash_value: String in blocks:
		if Sm2Canonical.hash(blocks[hash_value])!=hash_value: return {"ok":false,"errors":PackedStringArray(["archive_content_hash"])}
		if store.has_slot(hash_value):
			var previous: Dictionary=read(hash_value)
			if not previous.ok: return previous
		else:
			var saved: Dictionary=_write_new(blocks[hash_value],hash_value)
			if not saved.ok: return saved
	return {"ok":true}

func _write_new(payload: Dictionary,hash_value: String) -> Dictionary:
	# Unlike a replaceable slot, an immutable block has no previous version or backup.
	# Validate once, then verify the exact serialized bytes before publishing.
	if not store._location_error(hash_value).is_empty(): return {"ok":false,"errors":PackedStringArray(["archive_directory"])}
	var budget: Array[int]=[store.node_budget()]
	if not Sm2SaveStore._validate_value(payload,0,budget).is_empty(): return {"ok":false,"errors":PackedStringArray(["archive_payload"])}
	var serialized: String=Sm2Canonical.stringify({"format":Sm2SaveStore.FORMAT,"schema_version":Sm2SaveStore.SCHEMA_VERSION,"payload":payload,"checksum":hash_value})
	if serialized.to_utf8_buffer().size()>Sm2SaveStore.MAX_FILE_BYTES: return {"ok":false,"errors":PackedStringArray(["archive_size"])}
	if store._ensure_directory()!=OK: return {"ok":false,"errors":PackedStringArray(["archive_directory"])}
	var path: String=store._slot_path(hash_value)
	var temporary: String=path+".tmp"
	var file: FileAccess=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return {"ok":false,"errors":PackedStringArray(["archive_temporary"])}
	file.store_string(serialized); file.flush()
	var written: Error=file.get_error(); file.close()
	var expected: String=serialized.sha256_text()
	if written!=OK or FileAccess.get_sha256(temporary)!=expected:
		Sm2SaveStore._remove_if_present(temporary)
		return {"ok":false,"errors":PackedStringArray(["archive_write_verify"])}
	# Never overwrite an existing content-addressed block, including a damaged one.
	if FileAccess.file_exists(path) or DirAccess.rename_absolute(temporary,path)!=OK:
		Sm2SaveStore._remove_if_present(temporary)
		return {"ok":false,"errors":PackedStringArray(["archive_publish"])}
	if FileAccess.get_sha256(path)!=expected: return {"ok":false,"errors":PackedStringArray(["archive_publish_verify"])}
	_verified[hash_value]={"file_hash":expected,"payload":payload.duplicate(true),"budget":store.node_budget()}
	return {"ok":true}
