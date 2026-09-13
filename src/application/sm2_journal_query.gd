class_name Sm2JournalQuery
extends RefCounted
## One screen query. Default paging only requests intersecting archive blocks.
var session: Sm2JourneySession
var definitions: Dictionary
var _selection: Array[Dictionary]=[]
var _key: String=""
var _legacy: Dictionary={}
func _init(value: Sm2JourneySession,labels: Dictionary) -> void:
	session=value; definitions=labels
	if not session is Sm2CheckpointSession: _legacy=Sm2JournalView.build(session)
func page(query: String,group: String,index: int,size: int=30) -> Dictionary:
	var checkpoint: Sm2CheckpointSession=session as Sm2CheckpointSession
	var total: int=checkpoint.archive.count if checkpoint!=null else _legacy.rows.size()
	var text: String=query.strip_edges().to_lower()
	if checkpoint!=null and text.is_empty() and group=="Все":
		index=clampi(index,0,maxi(0,(total-1)/size))
		var read: Dictionary=checkpoint.archive.page(index*size,size)
		return {"ok":read.ok,"rows":read.rows,"count":total,"total":total,"page":index,"busy":session.world.busy()}
	var key: String=JSON.stringify([text,group,session.world.world_id,session.world.revision])
	if key!=_key:
		_selection.clear(); _key=key
		var all_rows: Array=[]
		if checkpoint!=null:
			# Filter scans bounded pages once per filter/revision; only matching rows persist.
			for offset: int in range(0,total,100):
				var read: Dictionary=checkpoint.archive.page(offset,100)
				if not read.ok: _key=""; return {"ok":false,"rows":[],"count":0,"total":total,"page":0,"busy":session.world.busy()}
				_select(read.rows,text,group)
		else:
			all_rows=_legacy.rows.duplicate(); all_rows.reverse(); _select(all_rows,text,group)
	index=clampi(index,0,maxi(0,(_selection.size()-1)/size))
	return {"ok":true if checkpoint!=null else _legacy.ok,"rows":_selection.slice(index*size,(index+1)*size).duplicate(true),"count":_selection.size(),"total":total,"page":index,"busy":session.world.busy()}
func _select(rows: Array,text: String,group: String) -> void:
	for row: Dictionary in rows:
		var definition: Dictionary=definitions.get(row.kind,{"title":"Действие мира","group":"Прочее"})
		if group!="Все" and group!=definition.group: continue
		var searchable: String=definition.title+" "+row.subject+" "+row.location+" "+row.from+" "+row.outcome
		if not text.is_empty() and not searchable.to_lower().contains(text): continue
		_selection.append(row)
