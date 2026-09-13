extends "res://tools/check_combat_runtime.gd"
class FullPublisher extends Sm2CheckpointSession:
	func _fresh() -> Sm2CheckpointSession: return FullPublisher.new(_content,_profile,_store,repository,true)
	func restore(raw: Dictionary) -> Dictionary:
		var candidate: Sm2CheckpointSession=_fresh()
		var result: Dictionary=candidate._restore_checkpoint(raw) if raw.get("format")==CHECKPOINT_FORMAT else candidate._import_legacy(raw)
		return _publish(candidate) if result.ok else result
func configure(s: Sm2CheckpointSession) -> void:
	var owner: WeakRef=weakref(s)
	s._store=Sm2CampaignStore.new("user://combat-io",0,func(raw: Dictionary):
		var candidate: Sm2CheckpointSession=(owner.get_ref() as Sm2CheckpointSession)._fresh()
		var result: Dictionary=candidate.restore(raw)
		if result.ok: result["validated_session"]=candidate
		return result)
	s._store.large_profile=true; s.repository=Sm2HistoryRepository.new(s._store._base_directory); s.repository.store.large_profile=true
func run() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://outputs/validation-1/final-large/final.json"))
	var fast: Sm2CheckpointSession=FIXTURE.session(); configure(fast)
	var full: FullPublisher=FullPublisher.new(fast._content,fast._profile,null,null,true); configure(full)
	check(fast.restore(raw).ok and full.restore(raw).ok,"same completed state restored in both policies")
	var hash_value: String=fast.state_hash(); check(full.state_hash()==hash_value,"same initial state")
	for repeat: int in 3:
		var order: Array=[fast,full] if repeat%2==0 else [full,fast]
		for s: Sm2CheckpointSession in order:
			var name: String="full" if s is FullPublisher else "single"
			check(measure("%s_save_%s" % [name,repeat],func(): return s.save_game()).ok,"save "+name)
			check(s.state_hash()==hash_value,"save preserved state "+name)
			check(measure("%s_load_%s" % [name,repeat],func(): return s.load_game()).ok,"load "+name)
			check(s.state_hash()==hash_value,"load preserved state "+name)
	write("res://outputs/validation-1/paired-save.json",report)
	quit(0 if report.passed else 1)
