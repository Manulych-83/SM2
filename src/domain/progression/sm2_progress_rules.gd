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

static func tracks(body: Sm2ProgressBodyState, catalog: Sm2ProgressCatalog, modifiers: Array[Dictionary]=[]) -> Array[Dictionary]:
	if body is Sm2CompanionProgress: return (body as Sm2CompanionProgress).attributes(catalog)
	var rows: Array[Dictionary] = []
	var own: Dictionary[String,int] = {}
	for id: String in catalog.track_ids():
		var definition: Sm2ProgressTrackDefinition = catalog.track(id)
		var value: Sm2ProgressTrackState = body.tracks[id]
		var row: Dictionary = definition.describe(value.earned)
		var flat: int = 0
		for node: String in value.nodes: flat += catalog.node(node).bonus
		row.merge({"id":id,"name":definition.title,"kind":definition.kind,"earned":value.earned,"spent":value.spent,"available":value.earned-value.spent,"node_bonus":flat,"effective":row.level+flat,"sources":[],"nodes":value.nodes.duplicate()})
		if not modifiers.is_empty():
			row["upgrade_bonus"]=0; row["upgrade_sources"]=[]
			for modifier: Dictionary in modifiers:
				if modifier.track_id==id:
					row.upgrade_bonus+=int(modifier.amount); row.upgrade_sources.append(modifier.duplicate(true))
			row.effective+=int(row.upgrade_bonus)
		own[id] = int(row.effective)
		rows.append(row)
	for row: Dictionary in rows:
		for contribution: Dictionary in catalog.contributions():
			if contribution.target != row.id: continue
			@warning_ignore("integer_division")
			var amount: int = own[contribution.source]*int(contribution.numerator)/int(contribution.denominator)
			row.effective += amount
			row.sources.append({"name":catalog.track(contribution.source).title,"amount":amount,"source_value":own[contribution.source],"numerator":contribution.numerator,"denominator":contribution.denominator})
	return rows

static func purchase_error(body: Sm2ProgressBodyState, catalog: Sm2ProgressCatalog, node_id: String) -> String:
	if body is Sm2CompanionProgress: return "companion_automatic_growth"
	var node: Sm2ProgressNodeDefinition = catalog.node(node_id)
	if node == null: return "node_missing"
	var track: Sm2ProgressTrackState = body.tracks[node.track_id]
	if node.id in track.nodes: return "node_owned"
	for id: String in node.own_levels():
		if catalog.track(id).describe(body.tracks[id].earned).level < node.own_levels()[id]: return "level_required"
	for prerequisite: String in node.requires:
		if prerequisite not in body.tracks[catalog.node(prerequisite).track_id].nodes: return "prerequisite_required"
	for id: String in node.prices():
		if body.tracks[id].earned-body.tracks[id].spent < node.prices()[id]: return "experience_required"
	return ""

static func purchase(body: Sm2ProgressBodyState, node: Sm2ProgressNodeDefinition) -> void:
	var track: Sm2ProgressTrackState = body.tracks[node.track_id]
	for id: String in node.prices(): body.tracks[id].spent+=node.prices()[id]
	track.nodes.append(node.id)
	track.nodes.sort()

static func empty_body(id: int, catalog: Sm2ProgressCatalog) -> Sm2ProgressBodyState:
	var body: Sm2ProgressBodyState = Sm2ProgressBodyState.new()
	body.id = id
	for key: String in catalog.track_ids():
		var track: Sm2ProgressTrackState = Sm2ProgressTrackState.new()
		track.track_id = key
		body.tracks[key] = track
	return body

static func decode_body(raw: Dictionary, catalog: Sm2ProgressCatalog) -> Dictionary:
	if raw.has("growth"): return Sm2CompanionProgress.decode(raw,catalog)
	var invalid: Dictionary = {"ok":false,"errors":PackedStringArray(["progress_body_invalid"])}
	if not Sm2Validate.fields(raw,["id","template_id","tracks"]) or not Sm2Validate.decimal(raw.id,1) or raw.template_id != "p1:body.human" or not raw.tracks is Array or raw.tracks.size() != catalog.track_ids().size(): return invalid
	var body: Sm2ProgressBodyState = empty_body(int(raw.id),catalog)
	var owned: Array[String] = []
	var paid: Dictionary[String,int]={}
	for id: String in catalog.track_ids(): paid[id]=0
	for index: int in raw.tracks.size():
		var entry: Variant = raw.tracks[index]
		if not entry is Dictionary or not Sm2Validate.fields(entry,["track_id","earned_total","spent_total","owned_nodes"]): return invalid
		if entry.track_id != catalog.track_ids()[index] or not Sm2Validate.integer(entry.earned_total,0,Sm2ProgressCatalog.XP_LIMIT) or not Sm2Validate.integer(entry.spent_total,0,int(entry.earned_total)) or not Sm2Validate.string_list(entry.owned_nodes): return invalid
		var value: Sm2ProgressTrackState = body.tracks[entry.track_id]
		value.earned = int(entry.earned_total); value.spent = int(entry.spent_total); value.nodes.assign(entry.owned_nodes)
		var sorted: Array[String] = value.nodes.duplicate(); sorted.sort()
		if sorted != value.nodes: return invalid
		for id: String in value.nodes:
			var node: Sm2ProgressNodeDefinition = catalog.node(id)
			if node == null or node.track_id != value.track_id or catalog.track(value.track_id).describe(value.earned).level < node.min_level: return invalid
			for price_id: String in node.prices(): paid[price_id]+=node.prices()[price_id]
			owned.append(id)
	for id: String in catalog.track_ids():
		if paid[id]!=body.tracks[id].spent: return invalid
	for id: String in owned:
		for track_id: String in catalog.node(id).own_levels():
			if catalog.track(track_id).describe(body.tracks[track_id].earned).level<catalog.node(id).own_levels()[track_id]: return invalid
		for prerequisite: String in catalog.node(id).requires:
			if prerequisite not in owned: return invalid
	return {"ok":true,"body":body,"errors":PackedStringArray()}
