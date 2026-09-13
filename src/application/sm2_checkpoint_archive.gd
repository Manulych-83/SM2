class_name Sm2CheckpointArchive
extends RefCounted
const FORMAT: String="sm2.history_block.1"
const BLOCK_SIZE: int=64
const MAX_RECORDS: int=65536
var refs: Array[Dictionary]=[]
var tail: Array[Dictionary]=[]
var blocks: Dictionary={}
var repository: Sm2HistoryRepository
var count: int=0
var revision: int=0
var world_id: String=""
var fingerprint: String=""
var large_profile: bool=false

func copy() -> Sm2CheckpointArchive:
	var value: Sm2CheckpointArchive=Sm2CheckpointArchive.new()
	value.refs.assign(refs); value.tail.assign(tail); value.blocks=blocks.duplicate()
	value.repository=repository
	value.large_profile=large_profile
	value.count=count; value.revision=revision; value.world_id=world_id; value.fingerprint=fingerprint
	return value

func append(entry: Dictionary,row: Dictionary,end_revision: int) -> bool:
	if count>=MAX_RECORDS or end_revision<=revision: return false
	var record: Dictionary={"number":count+1,"before":revision,"after":end_revision,"entry":entry.duplicate(true),"row":row.duplicate(true)}
	# Bound each published file by the same tree budget as ordinary saves.
	var check: Array=tail.duplicate(); check.append(record)
	var limit: int=Sm2SaveStore.LARGE_MAX_NODES if large_profile else Sm2SaveStore.MAX_NODES
	var budget: Array[int]=[limit-128]
	if not Sm2SaveStore.new("user://unused")._validate_value(check,0,budget).is_empty():
		seal(); budget=[limit-128]
		if not Sm2SaveStore.new("user://unused")._validate_value([record],0,budget).is_empty(): return false
	tail.append(record); count+=1; revision=end_revision
	if tail.size()>=BLOCK_SIZE: seal()
	return true

func seal() -> void:
	if tail.is_empty(): return
	var block: Dictionary={"format":FORMAT,"world_id":world_id,"fingerprint":fingerprint,"previous":refs.back().hash if not refs.is_empty() else "","first":tail.front().number,"last":tail.back().number,"before":tail.front().before,"after":tail.back().after,"records":tail.duplicate(true)}
	var hash_value: String=Sm2Canonical.hash(block)
	blocks[hash_value]=block
	refs.append({"hash":hash_value,"first":block.first,"last":block.last,"before":block.before,"after":block.after})
	tail=[]

func to_data() -> Dictionary:
	return {"refs":refs.duplicate(true),"tail":tail.duplicate(true),"count":count,"revision":revision}

func rows() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for reference: Dictionary in refs:
		var block: Dictionary=_block(reference.hash)
		if block.is_empty(): return []
		for record: Dictionary in block.records: result.append(_row(record.row))
	for record: Dictionary in tail: result.append(_row(record.row))
	return result

static func _row(value: Dictionary) -> Dictionary:
	var row: Dictionary=value.duplicate(true)
	for key: String in ["number","seconds","new_items"]: row[key]=int(row[key])
	return row

func all_entries() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for reference: Dictionary in refs:
		var block: Dictionary=_block(reference.hash)
		if block.is_empty(): return []
		for record: Dictionary in block.records: result.append(record.entry.duplicate(true))
	for record: Dictionary in tail: result.append(record.entry.duplicate(true))
	return result

func _block(hash_value: String) -> Dictionary:
	if blocks.has(hash_value): return blocks[hash_value]
	var read: Dictionary=repository.read(hash_value) if repository!=null else {"ok":false}
	return read.payload if read.ok else {}

func page(offset: int,limit: int) -> Dictionary:
	if offset<0 or limit<1 or limit>100: return {"ok":false,"rows":[]}
	var first: int=maxi(1,count-offset-limit+1); var last_number: int=count-offset
	var result: Array[Dictionary]=[]
	if last_number<1: return {"ok":true,"rows":result}
	for reference: Dictionary in refs:
		if int(reference.last)<first or int(reference.first)>last_number: continue
		var block: Dictionary=_block(reference.hash)
		if block.is_empty(): return {"ok":false,"rows":[]}
		for record: Dictionary in block.records:
			if int(record.number)>=first and int(record.number)<=last_number: result.append(_row(record.row))
	for record: Dictionary in tail:
		if int(record.number)>=first and int(record.number)<=last_number: result.append(_row(record.row))
	result.reverse()
	return {"ok":true,"rows":result}

func restore(raw: Variant,reader: Sm2HistoryRepository) -> bool:
	repository=reader
	if not raw is Dictionary or not Sm2Validate.fields(raw,["refs","tail","count","revision"]) or not raw.refs is Array or raw.refs.size()>MAX_RECORDS or not raw.tail is Array or raw.tail.size()>=BLOCK_SIZE: return false
	if not Sm2Validate.integer(raw.count,0,MAX_RECORDS) or not Sm2Validate.integer(raw.revision,0,1000000): return false
	var prior: String=""; var number: int=0; var last_revision: int=0
	for reference: Variant in raw.refs:
		if not reference is Dictionary or not Sm2Validate.fields(reference,["hash","first","last","before","after"]) or not Sm2CheckpointWorld.digest(reference.hash): return false
		var loaded: Dictionary=repository.read(reference.hash) if repository!=null else {"ok":false}
		if not loaded.ok: return false
		var block: Dictionary=loaded.payload
		if not Sm2Validate.fields(block,["format","world_id","fingerprint","previous","first","last","before","after","records"]) or block.format!=FORMAT or block.world_id!=world_id or block.fingerprint!=fingerprint or block.previous!=prior: return false
		if not block.records is Array or block.records.is_empty() or block.records.size()>BLOCK_SIZE: return false
		for record: Variant in block.records:
			if not valid_record(record,number,last_revision): return false
			number+=1; last_revision=int(record.after)
		for key: String in ["first","last","before","after"]:
			if reference[key]!=block[key]: return false
		if block.first!=block.records.front().number or block.last!=number or block.before!=block.records.front().before or block.after!=last_revision: return false
		prior=reference.hash
	for record: Variant in raw.tail:
		if not valid_record(record,number,last_revision): return false
		number+=1; last_revision=int(record.after)
	if number!=int(raw.count) or last_revision!=int(raw.revision): return false
	refs.assign(raw.refs.duplicate(true)); tail.assign(raw.tail.duplicate(true)); count=number; revision=last_revision
	return true

static func valid_record(record: Variant,number: int,revision: int) -> bool:
	if not record is Dictionary or not Sm2Validate.fields(record,["number","before","after","entry","row"]) or record.number!=number+1 or record.before!=revision or not Sm2Validate.integer(record.after,revision+1,1000000): return false
	if not record.entry is Dictionary or record.entry.get("kind") not in ["camp","outcome"] or not record.row is Dictionary: return false
	var row: Dictionary=record.row
	if not Sm2Validate.fields(row,["number","kind","subject","outcome","interrupted","seconds","from","location","life_ended","new_items"]) or row.number!=record.number: return false
	for key: String in ["kind","subject","outcome","from","location"]:
		if not Sm2Validate.text(row[key],true): return false
	if not row.interrupted is bool or not row.life_ended is bool or not Sm2Validate.integer(row.seconds,0,1000000000) or not Sm2Validate.integer(row.new_items,0,1000000): return false
	if record.entry.kind=="camp":
		if not Sm2Validate.fields(record.entry,["kind","command"]) or not record.entry.command is Dictionary or not Sm2Validate.fields(record.entry.command,["kind","world_id","revision","incarnation_id","body_id","target_id","content_id"]): return false
		if record.entry.command.kind!=row.kind: return false
	else:
		if not Sm2Validate.fields(record.entry,["kind","battle"]) or not record.entry.battle is Dictionary or row.kind!="outcome": return false
	return true
