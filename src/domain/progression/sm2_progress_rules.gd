class_name Sm2ProgressRules
extends RefCounted
## Shared body progression arithmetic; no battle, scene, or persistence ownership.
static func award_error(body: Sm2ProgressBodyState, awards: Dictionary) -> String:
	if body is Sm2CompanionProgress: return "companion_automatic_growth"
	for id: Variant in awards:
		if not id is String or not body.tracks.has(id) or not Sm2Validate.integer(awards[id],1,Sm2ProgressCatalog.XP_LIMIT): return "practice_award_invalid"
		if body.tracks[id].earned>Sm2ProgressCatalog.XP_LIMIT-int(awards[id]): return "Достигнут предел опыта направления."
	return ""

## Caller checks the entire command before applying on its detached candidate.
static func award(body: Sm2ProgressBodyState, awards: Dictionary) -> void:
	for id: String in awards: body.tracks[id].earned+=int(awards[id])

static func _own(body: Sm2ProgressBodyState,catalog: Sm2ProgressCatalog,id: String,modifiers: Array[Dictionary]) -> Dictionary:
	var definition: Sm2ProgressTrackDefinition=catalog.track(id)
	var value: Sm2ProgressTrackState=body.tracks[id]
	var row: Dictionary=definition.describe(value.earned)
	var flat: int=0
	for node: String in value.nodes: flat+=catalog.node_bonus(node)
	row.merge({"id":id,"name":definition.title,"kind":definition.kind,"earned":value.earned,"spent":value.spent,"available":value.earned-value.spent,"node_bonus":flat,"effective":row.level+flat,"sources":[],"nodes":value.nodes.duplicate()})
	if not modifiers.is_empty():
		row["upgrade_bonus"]=0; row["upgrade_sources"]=[]
		for modifier: Dictionary in modifiers:
			if modifier.track_id==id:
				row.upgrade_bonus+=int(modifier.amount); row.upgrade_sources.append(modifier.duplicate(true))
		row.effective+=int(row.upgrade_bonus)
	return row

static func track(body: Sm2ProgressBodyState,catalog: Sm2ProgressCatalog,id: String,modifiers: Array[Dictionary]=[]) -> Dictionary:
	if body is Sm2CompanionProgress:
		for row: Dictionary in (body as Sm2CompanionProgress).attributes(catalog):
			if row.id==id: return row
		return {}
	var row: Dictionary=_own(body,catalog,id,modifiers)
	for contribution: Dictionary in catalog.contributions_to(id):
		var source: Dictionary=_own(body,catalog,contribution.source,modifiers)
		_add_source(row,source,contribution)
	return row

static func _add_source(row: Dictionary,source: Dictionary,contribution: Dictionary) -> void:
	@warning_ignore("integer_division")
	var amount: int=int(source.effective)*int(contribution.numerator)/int(contribution.denominator)
	row.effective+=amount
	row.sources.append({"name":source.name,"amount":amount,"source_value":source.effective,"numerator":contribution.numerator,"denominator":contribution.denominator})

static func tracks(body: Sm2ProgressBodyState, catalog: Sm2ProgressCatalog, modifiers: Array[Dictionary]=[]) -> Array[Dictionary]:
	if body is Sm2CompanionProgress: return (body as Sm2CompanionProgress).attributes(catalog)
	var rows: Array[Dictionary]=[]; var own: Dictionary={}
	for id: String in catalog.track_ids(): own[id]=_own(body,catalog,id,modifiers)
	for id: String in catalog.track_ids():
		var row: Dictionary=own[id].duplicate(true)
		for contribution: Dictionary in catalog.contributions_to(id): _add_source(row,own[contribution.source],contribution)
		rows.append(row)
	return rows

static func purchase_error(body: Sm2ProgressBodyState, catalog: Sm2ProgressCatalog, node_id: String) -> String:
	if body is Sm2CompanionProgress: return "companion_automatic_growth"
	var node: Sm2ProgressNodeDefinition = catalog.node(node_id)
	if node == null: return "node_missing"
	var track: Sm2ProgressTrackState = body.tracks[node.track_id]
	if track.owns(node.id): return "node_owned"
	for id: String in node.own_levels():
		if catalog.track(id).describe(body.tracks[id].earned).level < node.own_levels()[id]: return "level_required"
	for prerequisite: String in node.requires:
		if not body.tracks[catalog.node(prerequisite).track_id].owns(prerequisite): return "prerequisite_required"
	for id: String in node.prices():
		if body.tracks[id].earned-body.tracks[id].spent < node.prices()[id]: return "experience_required"
	return ""

static func purchase(body: Sm2ProgressBodyState, node: Sm2ProgressNodeDefinition) -> void:
	var track: Sm2ProgressTrackState = body.tracks[node.track_id]
	for id: String in node.prices(): body.tracks[id].spent+=node.prices()[id]
	track.nodes.insert(track.nodes.bsearch(node.id),node.id)

static func empty_body(id: int, catalog: Sm2ProgressCatalog) -> Sm2ProgressBodyState:
	var body: Sm2ProgressBodyState = Sm2ProgressBodyState.new()
	body.id = id
	body.sparse=catalog.uses_sparse_bodies()
	for key: String in catalog.track_ids():
		var track: Sm2ProgressTrackState = Sm2ProgressTrackState.new()
		track.track_id = key
		body.tracks[key] = track
	return body

static func decode_body(raw: Dictionary, catalog: Sm2ProgressCatalog,cache: Sm2ProgressDecodeCache=null) -> Dictionary:
	if cache!=null:
		var known: Sm2ProgressBodyState=cache.find(raw,catalog)
		if known!=null: return {"ok":true,"body":known,"errors":PackedStringArray()}
		known=cache.find_growth(raw,catalog)
		if known!=null:
			cache.remember(raw,catalog,known)
			return {"ok":true,"body":known,"errors":PackedStringArray()}
	var result: Dictionary=_decode_body(raw,catalog)
	if result.ok and cache!=null: cache.remember(raw,catalog,result.body)
	return result

static func _decode_body(raw: Dictionary, catalog: Sm2ProgressCatalog) -> Dictionary:
	if raw.has("growth"): return Sm2CompanionProgress.decode(raw,catalog)
	var invalid: Dictionary = {"ok":false,"errors":PackedStringArray(["progress_body_invalid"])}
	var sparse: bool=raw.has("track_layout")
	var fields: Array[String]=["id","template_id","tracks"]
	if sparse: fields.append("track_layout")
	if not Sm2Validate.fields(raw,fields) or not Sm2Validate.decimal(raw.id,1) or not raw.template_id is String or raw.template_id != "p1:body.human" or not raw.tracks is Array: return invalid
	if sparse and (not catalog.uses_sparse_bodies() or not raw.track_layout is String or raw.track_layout!=Sm2ProgressBodyState.SPARSE_LAYOUT): return invalid
	if raw.tracks.size()>catalog.track_ids().size() or (not sparse and raw.tracks.size()!=catalog.track_ids().size()): return invalid
	var body: Sm2ProgressBodyState = empty_body(int(raw.id),catalog)
	body.sparse=sparse
	var owned: Dictionary = {}
	var paid: Dictionary[String,int]={}
	var levels: Dictionary={}; var definitions: Dictionary={}
	var track_ids: Array[String]=catalog.track_ids()
	for id: String in track_ids:
		paid[id]=0
		levels[id]=catalog.track(id).base_level
	var previous: String=""
	for index: int in raw.tracks.size():
		var entry: Variant = raw.tracks[index]
		if not entry is Dictionary or not Sm2Validate.fields(entry,["track_id","earned_total","spent_total","owned_nodes"]): return invalid
		if not entry.track_id is String or not body.tracks.has(entry.track_id) or entry.track_id<=previous or (not sparse and entry.track_id != track_ids[index]) or not Sm2Validate.integer(entry.earned_total,0,Sm2ProgressCatalog.XP_LIMIT) or not Sm2Validate.integer(entry.spent_total,0,int(entry.earned_total)) or not catalog.owned_list_valid(entry.owned_nodes): return invalid
		if sparse and int(entry.earned_total)==0 and int(entry.spent_total)==0 and entry.owned_nodes.is_empty(): return invalid
		previous=entry.track_id
		var value: Sm2ProgressTrackState = body.tracks[entry.track_id]
		value.earned = int(entry.earned_total); value.spent = int(entry.spent_total); value.nodes.assign(entry.owned_nodes)
		levels[value.track_id]=catalog.track(value.track_id).describe(value.earned).level
		var sorted: Array[String] = value.nodes.duplicate(); sorted.sort()
		if sorted != value.nodes: return invalid
		for id: String in value.nodes:
			var node: Sm2ProgressNodeDefinition = catalog.node(id)
			if node == null or node.track_id != value.track_id or levels[value.track_id] < node.min_level: return invalid
			for price_id: String in node.prices(): paid[price_id]+=node.prices()[price_id]
			owned[id]=true; definitions[id]=node
	for id: String in catalog.track_ids():
		if paid[id]!=body.tracks[id].spent: return invalid
	for id: String in owned:
		for track_id: String in definitions[id].own_levels():
			if levels[track_id]<definitions[id].own_levels()[track_id]: return invalid
		for prerequisite: String in definitions[id].requires:
			if prerequisite not in owned: return invalid
	return {"ok":true,"body":body,"errors":PackedStringArray()}
