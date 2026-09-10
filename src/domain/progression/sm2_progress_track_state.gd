class_name Sm2ProgressTrackState
extends RefCounted
var track_id: String
var earned: int = 0
var spent: int = 0
var nodes: Array[String] = []

func to_data() -> Dictionary:
	return {"track_id":track_id,"earned_total":earned,"spent_total":spent,"owned_nodes":nodes.duplicate()}

func copy() -> Sm2ProgressTrackState:
	var value: Sm2ProgressTrackState = Sm2ProgressTrackState.new()
	value.track_id=track_id; value.earned=earned; value.spent=spent; value.nodes=nodes.duplicate()
	return value
