class_name Sm2LifeDefinition
extends RefCounted
## Authored carriers for one location; supports adding more eligible bodies as data.
var _raw: Dictionary={}
var _bodies: Dictionary[int,Dictionary]={}
func build(raw: Dictionary) -> PackedStringArray:
	var failure: PackedStringArray=PackedStringArray(["world_definition_invalid"])
	if not Sm2Validate.fields(raw,["version","bodies"]) or raw.version!="sm2.p3.content.1" or not raw.bodies is Array or raw.bodies.size()<4 or raw.bodies.size()>1000: return failure
	var candidate: Dictionary[int,Dictionary]={}; var previous: int=0
	for entry: Variant in raw.bodies:
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","name","human","enhanced","prepared","alive"]) or not Sm2Validate.integer(entry.id,1,1000000) or int(entry.id)<=previous or int(entry.id) in [1,3,5,6,7,12] or not Sm2Validate.text(entry.name): return failure
		for flag: String in ["human","enhanced","prepared","alive"]:
			if not entry[flag] is bool: return failure
		if entry.prepared and entry.alive: return failure
		previous=int(entry.id); candidate[previous]=entry.duplicate(true)
	for id: int in [2,4,10,11]:
		if not candidate.has(id) or not candidate[id].alive or not candidate[id].human or candidate[id].enhanced: return failure
	_raw=raw.duplicate(true); _bodies=candidate
	return PackedStringArray()
func to_data() -> Dictionary: return _raw.duplicate(true)
func fingerprint() -> String: return Sm2Canonical.hash(_raw)
func ids() -> Array[int]:
	var result: Array[int]=[]; result.assign(_bodies.keys()); result.sort(); return result
func body(id: int) -> Dictionary: return _bodies.get(id,{}).duplicate(true)
func first_free_id() -> int: return maxi(12,ids().back())+1
