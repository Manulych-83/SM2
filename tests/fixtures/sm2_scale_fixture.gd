extends RefCounted

static func catalog(count: int) -> Dictionary:
	var raw: Dictionary={"version":Sm2ProgressCatalog.VERSION,"tracks":[{"id":"scale:skill","name":"Scale fixture","kind":"skill","base_level":1,"step":1,"growth":0}],"nodes":[],"activities":[{"id":"scale:practice","name":"Fixture practice","operation":"sword_exercise","seconds":1,"awards":[{"track_id":"scale:skill","amount":1}]}],"contributions":[],"knowledge":[]}
	for index: int in count:
		raw.nodes.append({"id":"scale:node.%05d" % index,"name":"Fixture %s" % index,"track_id":"scale:skill","min_level":1,"cost":1,"bonus":1,"requires":["scale:node.%05d" % (index+1)] if index+1<count else []})
	return raw

static func graph(count: int) -> Dictionary:
	var ids: Array[String]=[]; var dependencies: Dictionary={}
	for index: int in count:
		var id: String="node.%05d" % index
		ids.append(id); dependencies[id]=["node.%05d" % (index+1)] if index+1<count else []
	return {"ids":ids,"dependencies":dependencies}
