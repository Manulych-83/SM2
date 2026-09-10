class_name Sm2ProgressBodyState
extends RefCounted
var id: int = 2
var tracks: Dictionary[String,Sm2ProgressTrackState] = {}
func to_data() -> Dictionary:
	var entries: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(tracks.keys()); ids.sort()
	for key: String in ids: entries.append(tracks[key].to_data())
	return {"id":str(id),"template_id":"p1:body.human","tracks":entries}
