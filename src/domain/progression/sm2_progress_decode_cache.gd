class_name Sm2ProgressDecodeCache
extends RefCounted
## Bounded, battle-owned certificates of fully validated values. Never game state.
const CAPACITY: int=8
var _entries: Array[Dictionary]=[]
var growth_enabled: bool=false

## Only the live command boundary requests this temporary view. File restore
## retains the default full decoder even when XP happens to increase.
func growth_copy() -> Sm2ProgressDecodeCache:
	var result: Sm2ProgressDecodeCache=Sm2ProgressDecodeCache.new()
	result._entries.assign(_entries); result.growth_enabled=true
	return result

func adopt_certificates(other: Sm2ProgressDecodeCache) -> void:
	_entries.assign(other._entries)

func find_growth(raw: Dictionary,catalog: Sm2ProgressCatalog) -> Sm2ProgressBodyState:
	if not growth_enabled or not Sm2Validate.fields(raw,["id","template_id","tracks"]) or not raw.tracks is Array: return null
	var fingerprint: String=catalog.fingerprint()
	for index: int in range(_entries.size()-1,-1,-1):
		var entry: Dictionary=_entries[index]; var prior: Dictionary=entry.raw
		if entry.fingerprint!=fingerprint or not prior.has("tracks") or typeof(raw.id)!=typeof(prior.id) or raw.id!=prior.id or typeof(raw.template_id)!=typeof(prior.template_id) or raw.template_id!=prior.template_id or raw.tracks.size()!=prior.tracks.size(): continue
		var matching: bool=true
		for i: int in raw.tracks.size():
			var row: Variant=raw.tracks[i]; var old: Dictionary=prior.tracks[i]
			if not row is Dictionary or not Sm2Validate.fields(row,["track_id","earned_total","spent_total","owned_nodes"]): matching=false; break
			if typeof(row.track_id)!=typeof(old.track_id) or row.track_id!=old.track_id or typeof(row.spent_total)!=typeof(old.spent_total) or row.spent_total!=old.spent_total: matching=false; break
			if not Sm2Validate.integer(row.earned_total,int(old.earned_total),Sm2ProgressCatalog.XP_LIMIT): matching=false; break
			if typeof(row.owned_nodes)!=typeof(old.owned_nodes) or row.owned_nodes!=old.owned_nodes or not _same_types(old.owned_nodes,row.owned_nodes): matching=false; break
		if not matching: continue
		# Same paid graph, identity and catalog; monotonic XP cannot lower any
		# own level, invalidate a prerequisite, or reduce the available balance.
		var body: Sm2ProgressBodyState=entry.body.copy()
		for row: Dictionary in raw.tracks: body.tracks[row.track_id].earned=int(row.earned_total)
		return body
	return null

func find(raw: Dictionary,catalog: Sm2ProgressCatalog) -> Sm2ProgressBodyState:
	var fingerprint: String=catalog.fingerprint()
	for entry: Dictionary in _entries:
		if entry.fingerprint==fingerprint and entry.raw==raw and _same_types(entry.raw,raw): return entry.body.copy()
	return null
## Variant equality can equate values with different types. A certificate must
## never turn e.g. boolean XP or packed arrays into valid serialized progression.
static func _same_types(left: Variant,right: Variant) -> bool:
	if typeof(left)!=typeof(right): return false
	if left is Dictionary:
		for key: Variant in left:
			if not _same_types(left[key],right[key]): return false
	elif left is Array:
		for i: int in left.size():
			if not _same_types(left[i],right[i]): return false
	return true
func remember(raw: Dictionary,catalog: Sm2ProgressCatalog,body: Sm2ProgressBodyState) -> void:
	if _entries.size()>=CAPACITY: _entries.pop_front()
	_entries.append({"fingerprint":catalog.fingerprint(),"raw":raw.duplicate(true),"body":body.copy()})
