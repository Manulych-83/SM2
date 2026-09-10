class_name Sm2ProgressLabState
extends RefCounted
var world_id: String
var soul: Sm2SoulState = Sm2SoulState.new()
var body: Sm2ProgressBodyState = Sm2ProgressBodyState.new()
var incarnation: Sm2IncarnationRecord = Sm2IncarnationRecord.new()
var revision: int = 0
var practice_sequence: int = 0
var activity_counts: Dictionary[String,int] = {}

func to_data(fingerprint: String) -> Dictionary:
	var counts: Array[Dictionary] = []
	var ids: Array[String] = []; ids.assign(activity_counts.keys()); ids.sort()
	for id: String in ids: counts.append({"activity_id":id,"count":activity_counts[id]})
	return {"format":"sm2.progression_lab","schema_version":1,"ruleset":"sm2.p1.practice.1","content_fingerprint":fingerprint,"world_id":world_id,"soul":soul.to_data(),"body":body.to_data(),"incarnation":incarnation.to_data(),"source_id":"4","next_id":"5","revision":str(revision),"practice_sequence":str(practice_sequence),"activity_counts":counts}
