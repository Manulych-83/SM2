class_name Sm2ProgressBodyState
extends RefCounted
var id: int = 2
const SPARSE_LAYOUT: String="sm2.body_tracks.sparse.1"
var sparse: bool=false
var tracks: Dictionary[String,Sm2ProgressTrackState] = {}
## In-memory transaction copy; untrusted snapshots still go through decode_body.
func copy() -> Sm2ProgressBodyState:
	var result: Sm2ProgressBodyState=Sm2ProgressBodyState.new(); result.id=id
	result.sparse=sparse
	for key: String in tracks:
		var value: Sm2ProgressTrackState=Sm2ProgressTrackState.new()
		value.track_id=key; value.earned=tracks[key].earned; value.spent=tracks[key].spent; value.nodes=tracks[key].nodes.duplicate()
		result.tracks[key]=value
	return result
func to_data() -> Dictionary:
	var entries: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(tracks.keys()); ids.sort()
	for key: String in ids:
		if sparse and tracks[key].earned==0 and tracks[key].spent==0 and tracks[key].nodes.is_empty(): continue
		entries.append(tracks[key].to_data())
	var result: Dictionary={"id":str(id),"template_id":"p1:body.human","tracks":entries}
	if sparse: result["track_layout"]=SPARSE_LAYOUT
	return result
