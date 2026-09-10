class_name Sm2ProgressSession
extends RefCounted
const SLOT: String = "p1_lab"
var lab: Sm2ProgressLab
var _store: Sm2SaveStore
var _catalog: Sm2ProgressCatalog
func _init(catalog: Sm2ProgressCatalog, store: Sm2SaveStore) -> void:
	_catalog=Sm2ProgressCatalog.new(); _catalog.build(catalog.to_data())
	_store=store; lab=Sm2ProgressLab.new(_catalog)
func new_game() -> Dictionary:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16: return {"ok":false,"errors":PackedStringArray(["world_id_failed"])}
	return lab.start("p1:"+bytes.hex_encode())
func view() -> Dictionary: return lab.view()
func act(kind: String, target_id: String) -> Dictionary:
	var state: Dictionary = lab.view()
	if state.is_empty(): return {"ok":false,"errors":PackedStringArray(["no_lab"])}
	var command: Sm2ProgressCommand = Sm2ProgressCommand.new()
	command.kind=kind; command.target_id=target_id; command.world_id=state.world_id
	command.body_id=state.body_id; command.incarnation_id=state.incarnation_id; command.expected_revision=state.revision
	command.practice_sequence=int(state.practice_sequence)+1 if kind == "practice" else 0
	return lab.execute(command)
func has_save() -> bool: return _store != null and _store.has_slot(SLOT)
func save_game() -> Dictionary:
	if _store == null: return {"ok":false,"errors":PackedStringArray(["no_store"])}
	var checked: Dictionary = Sm2ProgressSnapshot.decode(lab.capture(),_catalog)
	if not checked.ok: return checked
	return _store.save_slot(lab.capture(),SLOT)
func load_game() -> Dictionary:
	if _store == null: return {"ok":false,"errors":PackedStringArray(["no_store"])}
	var saved: Dictionary = _store.load_slot(SLOT)
	if not saved.ok: return saved
	return lab.restore(saved.payload)
