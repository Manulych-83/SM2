extends RefCounted
const TRACK: String="scale:skill.000"
static func node_id(index: int) -> String: return "scale:node.%05d" % index

static func raw(count: int,base: Dictionary,keep_nodes: bool=true) -> Dictionary:
	var data: Dictionary=base.duplicate(true)
	data.version=Sm2ProgressCatalog.LARGE_VERSION
	for index: int in range(data.tracks.size(),200):
		data.tracks.append({"id":"scale:skill.%03d" % (index-base.tracks.size()),"name":"Направление %03d" % (index-base.tracks.size()),"kind":"skill","base_level":1,"step":100,"growth":0})
	if not keep_nodes: data.nodes=[]
	var generated: int=count-data.nodes.size()
	for index: int in generated:
		# Reverse chain with a branching root exercises both long dependencies and fan-out.
		var needs: Array=[]
		if index+1<generated: needs=[node_id(generated-1 if index<40 else index+1)]
		data.nodes.append({"id":node_id(index),"name":"Узел %05d" % index,"track_id":TRACK,"min_level":1,"cost":1,"bonus":1,"requires":needs,"extra_requirements":[],"extra_costs":[]})
	return data

static func content(count: int=10000) -> Dictionary:
	var result: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true)
	if not result.ok: return result
	var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	var errors: PackedStringArray=catalog.build(raw(count,result.development.progression().to_data()))
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=development.build(result.development.to_data(),catalog,result.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	result.development=development
	result.journey_fingerprint=Sm2Canonical.hash([result.journey_fingerprint,development.fingerprint(),"scale-fixture"])
	return result

static func session(count: int=10000) -> Sm2CheckpointSession:
	return Sm2CheckpointSession.new(content(count),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://development-scale"))
