class_name Sm2InventoryCards
extends RefCounted
## Read-only grouping of exact item IDs. Never merges inventory objects or commands.
static func build(view: Dictionary,ui: Dictionary) -> Dictionary:
	var rows: Array[Dictionary]=[]
	for row: Dictionary in view.items:
		if not str(ui.query).strip_edges().is_empty() and not str(row.name).to_lower().contains(str(ui.query).strip_edges().to_lower()): continue
		if int(ui.scope)==1 and int(row.owner)!=int(ui.body): continue
		if int(ui.scope)==2 and row.place!="ground": continue
		if int(ui.scope)==3 and not row.stash: continue
		if not str(ui.get("storage","")).is_empty() and (row.place!="container" or row.holder!=ui.storage): continue
		var kind: int=int(ui.get("kind",0))
		if kind==1 and (str(row.slot).is_empty() or int(row.capacity)>0): continue
		if kind==2 and (not str(row.slot).is_empty() or row.device or int(row.capacity)>0): continue
		if kind==3 and int(row.capacity)<=0: continue
		if kind==4 and not row.device: continue
		rows.append(row.duplicate(true))
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var mode: int=int(ui.get("sort",0))
		if mode==1 and int(a.mass)!=int(b.mass): return int(a.mass)>int(b.mass)
		if mode==2 and int(a.volume)!=int(b.volume): return int(a.volume)>int(b.volume)
		if a.name!=b.name: return str(a.name).naturalnocasecmp_to(str(b.name))<0
		return int(a.id)<int(b.id))
	var grouped: Array[Dictionary]=[]; var keys: Dictionary={}
	for row: Dictionary in rows:
		var key: String=str(row.id)
		if not row.device and str(row.slot).is_empty() and int(row.capacity)==0:
			key=JSON.stringify([row.definition_id,row.place,row.holder,row.current])
		if not keys.has(key): keys[key]=grouped.size(); grouped.append({"row":row.duplicate(true),"ids":[]})
		grouped[int(keys[key])].ids.append(str(row.id))
	return {"rows":rows,"groups":grouped}
