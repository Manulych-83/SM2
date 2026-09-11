class_name Sm2ProgressLabState
extends RefCounted
var world_id: String
var soul: Sm2SoulState = Sm2SoulState.new()
var body: Sm2ProgressBodyState = Sm2ProgressBodyState.new()
var incarnation: Sm2IncarnationRecord = Sm2IncarnationRecord.new()
var revision: int = 0
var practice_sequence: int = 0
var activity_counts: Dictionary[String,int] = {}

func to_data(fingerprint: String, format_name: String = "sm2.progression_lab", rules: String = "sm2.p1.practice.1") -> Dictionary:
	var counts: Array[Dictionary] = []
	var ids: Array[String] = []; ids.assign(activity_counts.keys()); ids.sort()
	for id: String in ids: counts.append({"activity_id":id,"count":activity_counts[id]})
	return {"format":format_name,"schema_version":1,"ruleset":rules,"content_fingerprint":fingerprint,"world_id":world_id,"soul":soul.to_data(),"body":body.to_data(),"incarnation":incarnation.to_data(),"source_id":"4","next_id":"5","revision":str(revision),"practice_sequence":str(practice_sequence),"activity_counts":counts}
