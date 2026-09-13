extends RefCounted
const TRACK: String="wide:skill.04999"
const NODE: String="wide:node.04999"
const ACTIVITY: String="wide:practice.04999"

static func extension(base: Dictionary) -> Dictionary:
	var groups: Dictionary={"tracks":[],"nodes":[],"activities":[],"contributions":[],"profile":[{"id":"progression","version":Sm2ProgressCatalog.LARGE_VERSION}]}
	var existing: int=0
	for track: Dictionary in base.tracks:
		if track.kind=="skill": existing+=1
	for i: int in range(existing,5000):
		var id: String="wide:skill.%05d" % i
		groups.tracks.append({"id":id,"name":"Навык %05d" % i,"kind":"skill","base_level":1,"step":10,"growth":0})
		groups.nodes.append({"id":"wide:node.%05d" % i,"name":"Приём %05d" % i,"track_id":id,"min_level":2,"cost":5,"bonus":1,"requires":[],"extra_requirements":[],"extra_costs":[]})
		groups.activities.append({"id":"wide:practice.%05d" % i,"name":"Практика %05d" % i,"operation":"attribute_exercise","seconds":1,"capability":{},"awards":[{"track_id":id,"amount":10}]})
		groups.contributions.append({"id":"wide:link.%05d" % i,"source":"p1:stat.strength","target":id,"numerator":1,"denominator":10})
	# Actual cross-skill requirements and separate payment, no shared pool.
	groups.nodes[-1].extra_requirements=[{"track_id":"wide:skill.04998","min_level":2}]
	groups.nodes[-1].extra_costs=[{"track_id":"wide:skill.04998","amount":5}]
	var sources: Array=[]; var docs: Dictionary={}
	for group: String in groups:
		var path: String="res://content/wide/"+group+".json"
		sources.append({"group":group,"path":path,"field":""}); docs[path]=groups[group]
	var manifest: Dictionary={"format":Sm2ContentPackages.VERSION,"packages":[{"id":"progression.main","requires":[],"sources":sources}]}
	return {"manifest":manifest,"documents":docs}

static func content() -> Dictionary:
	var c: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true)
	if not c.ok: return c
	var raw: Dictionary=c.development.progression().to_data()
	var e: Dictionary=extension(raw)
	var assembled: Dictionary=Sm2ContentPackages.compile(e.manifest,["progression.main"],e.documents,40000)
	var merged: Dictionary=Sm2ProgressPackageLoader.merge(raw,assembled)
	if not merged.ok: return merged
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	var errors: PackedStringArray=development.build(c.development.to_data(),merged.catalog,c.combat,true)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.development=development
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,development.fingerprint(),"wide-skill-fixture"])
	return c

static func session() -> Sm2CheckpointSession:
	return Sm2CheckpointSession.new(content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://skill-scale"))
