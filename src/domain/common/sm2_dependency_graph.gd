class_name Sm2DependencyGraph
extends RefCounted
## Iterative O(V+E) traversal. Input order resolves independent ties deterministically.
## blocked contains cycle members AND nodes dependent on cycles, not only the cycle.
static func inspect(ids: Array[String], dependencies: Dictionary) -> Dictionary:
	var degree: Dictionary={}; var children: Dictionary={}; var errors: Array[Dictionary]=[]
	for id: String in ids:
		if degree.has(id):
			errors.append({"code":"duplicate_id","id":id}); continue
		degree[id]=0; children[id]=[]
	for id: String in degree:
		var seen: Dictionary={}
		for needed: String in dependencies.get(id,[]):
			if not degree.has(needed):
				errors.append({"code":"missing_reference","id":id,"requires":needed}); continue
			if seen.has(needed):
				errors.append({"code":"duplicate_reference","id":id,"requires":needed}); continue
			seen[needed]=true; degree[id]+=1; children[needed].append(id)
	var ready: Array[String]=[]; var order: Array[String]=[]
	for id: String in degree:
		if degree[id]==0: ready.append(id)
	var cursor: int=0
	while cursor<ready.size():
		var id: String=ready[cursor]; cursor+=1; order.append(id)
		for child: String in children[id]:
			degree[child]-=1
			if degree[child]==0: ready.append(child)
	var blocked: Array[String]=[]
	for id: String in degree:
		if degree[id]>0: blocked.append(id)
	if not blocked.is_empty(): errors.append({"code":"cycle_or_dependent","ids":blocked.duplicate()})
	return {"ok":errors.is_empty(),"order":order,"blocked":blocked,"errors":errors}
