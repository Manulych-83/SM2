class_name Sm2ControlPreferences
extends RefCounted
## Keyboard preferences are independent of campaign saves and game commands.
const DEFAULT: Dictionary={"slot_1":KEY_1,"slot_2":KEY_2,"slot_3":KEY_3,"slot_4":KEY_4,"slot_5":KEY_5,"slot_6":KEY_6,"slot_7":KEY_7,"slot_8":KEY_8,"slot_9":KEY_9,"end_turn":KEY_E,"wait":KEY_W,"inventory":KEY_I,"body":KEY_B,"development":KEY_C,"journal":KEY_J,"soul":KEY_H,"settings":KEY_F10}
var path: String="user://controls.cfg"

static func allowed_key(code: int) -> bool:
	return (code>=KEY_A and code<=KEY_Z) or (code>=KEY_0 and code<=KEY_9) or (code>=KEY_F1 and code<=KEY_F12)

static func valid(value: Dictionary) -> bool:
	if value.size()!=DEFAULT.size(): return false
	var used: Dictionary={}
	for id: String in DEFAULT:
		if not value.get(id) is int or not allowed_key(value[id]) or used.has(value[id]): return false
		used[value[id]]=true
	return true

func read() -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":true,"value":DEFAULT.duplicate()}
	var file: ConfigFile=ConfigFile.new()
	if file.load(path)!=OK or file.get_value("controls","version",0)!=1: return {"ok":false,"value":DEFAULT.duplicate()}
	var value: Variant=file.get_value("controls","bindings",{})
	var ok: bool=value is Dictionary and valid(value)
	return {"ok":ok,"value":value if ok else DEFAULT.duplicate()}

func write(value: Dictionary) -> bool:
	if not valid(value): return false
	var file: ConfigFile=ConfigFile.new()
	file.set_value("controls","version",1); file.set_value("controls","bindings",value)
	return file.save(path)==OK
