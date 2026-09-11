class_name Sm2RegionCatalog
extends RefCounted
## Authored geography. Commands and placements are explicit, never executable content.
const VERSION: String="sm2.region.content.1"
const TIME_LIMIT: int=1000000000
const LOCAL_COMMANDS: Array[String]=["practice","heal_hp","heal_hand","install_prosthesis","remove_prosthesis","repair_prosthesis"]
var _raw: Dictionary={}

func build(raw: Dictionary, content: Dictionary) -> PackedStringArray:
	if not Sm2Validate.fields(raw,["version","start","stash","locations","routes","bodies","encounters","sites","upgrades","services"]) or raw.version!=VERSION: return _error("region_version")
	for key: String in ["locations","routes","bodies","encounters","sites","upgrades","services"]:
		if not raw[key] is Array or raw[key].size()>1000: return _error("region_groups")
	var ids: Array[String]=[]
	for row: Variant in raw.locations:
		if not row is Dictionary or not Sm2Validate.fields(row,["id","name","description"]) or not Sm2Validate.text(row.id) or row.id in ids or not Sm2Validate.text(row.name) or not Sm2Validate.text(row.description): return _error("region_location")
		ids.append(row.id)
	if ids.is_empty() or raw.start not in ids or raw.stash not in ids: return _error("region_start")
	var routes: Array[String]=[]
	var links: Dictionary={}
	for id: String in ids: links[id]=[]
	for row: Variant in raw.routes:
		if not row is Dictionary or not Sm2Validate.fields(row,["from","to","seconds"]) or row.from not in ids or row.to not in ids or row.from==row.to or not Sm2Validate.integer(row.seconds,1,86400): return _error("region_route")
		var key: String=str(row.from)+":"+str(row.to)
		if key in routes: return _error("region_duplicate_route")
		routes.append(key); links[row.from].append(row.to)
	# Every place can reach every other place; an authored route may be directed.
	for start: String in ids:
		var reached: Array[String]=[start]; var cursor: int=0
		while cursor<reached.size():
			for target: String in links[reached[cursor]]:
				if target not in reached: reached.append(target)
			cursor+=1
		if reached.size()!=ids.size(): return _error("region_disconnected")
	var body_ids: Array[String]=[]
	for id: int in content.world_definition.ids(): body_ids.append(str(id))
	if not _mapping(raw.bodies,body_ids,ids): return _error("region_body_placement")
	var meetings: Array[String]=[]
	for i: int in content.meetings.size(): meetings.append(str(i))
	var service_places: Array[String]=ids.duplicate(); service_places.append("*")
	if not _mapping(raw.encounters,meetings,ids) or not _mapping(raw.sites,content.exploration.ids(),ids) or not _mapping(raw.services,LOCAL_COMMANDS,service_places): return _error("region_activity_placement")
	if _at(raw.bodies,"2")!=raw.start or _at(raw.bodies,"4")!=raw.start: return _error("region_party_start")
	for i: int in content.meetings.size():
		for enemy: Variant in content.meetings[i].enemies:
			if _at(raw.bodies,str(int(enemy)))!=_at(raw.encounters,str(i)): return _error("region_enemy_placement")
	var upgrades: Array[String]=[]
	for row: Variant in raw.upgrades:
		if not row is Dictionary or not Sm2Validate.fields(row,["id","collect","apply"]) or row.id not in content.development.upgrades().ids() or row.id in upgrades or row.collect not in ids or row.apply not in ids: return _error("region_upgrade_placement")
		upgrades.append(row.id)
	if upgrades.size()!=content.development.upgrades().ids().size(): return _error("region_upgrade_count")
	_raw=raw.duplicate(true)
	return PackedStringArray()

static func _mapping(rows: Array, expected: Array, places: Array[String]) -> bool:
	if rows.size()!=expected.size(): return false
	var seen: Array[String]=[]
	for row: Variant in rows:
		if not row is Dictionary or not Sm2Validate.fields(row,["id","location"]) or row.id not in expected or row.id in seen or row.location not in places: return false
		seen.append(row.id)
	return true

static func _at(rows: Array,id: String) -> String:
	for row: Dictionary in rows:
		if row.id==id: return row.location
	return ""

func to_data() -> Dictionary: return _raw.duplicate(true)
func copy() -> Sm2RegionCatalog:
	var value: Sm2RegionCatalog=Sm2RegionCatalog.new(); value._raw=to_data(); return value
func ids() -> Array[String]:
	var result: Array[String]=[]
	for row: Dictionary in _raw.locations: result.append(row.id)
	return result
func location(id: String) -> Dictionary:
	for row: Dictionary in _raw.locations:
		if row.id==id: return row.duplicate(true)
	return {}
func at(group: String,id: String) -> String: return _at(_raw[group],id)
func upgrade(id: String,action: String) -> String:
	for row: Dictionary in _raw.upgrades:
		if row.id==id: return row[action]
	return ""
func route(from: String,to: String) -> int:
	for row: Dictionary in _raw.routes:
		if row.from==from and row.to==to: return int(row.seconds)
	return 0
static func _error(code: String) -> PackedStringArray: return PackedStringArray([code])
