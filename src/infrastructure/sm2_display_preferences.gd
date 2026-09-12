class_name Sm2DisplayPreferences
extends RefCounted
const DEFAULT: Dictionary={"mode":"fullscreen","resolution":"2560x1440","vsync":true}
const RESOLUTIONS: Array[String]=["2560x1440","1920x1080","1280x720"]
var path: String="user://display_settings.cfg"

static func valid(value: Dictionary) -> bool:
	return value.size()==3 and value.get("mode") in ["fullscreen","windowed"] and value.get("resolution") in RESOLUTIONS and value.get("vsync") is bool

func read() -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":true,"exists":false,"value":DEFAULT.duplicate()}
	var file: ConfigFile=ConfigFile.new()
	if file.load(path)!=OK or file.get_value("display","version",0)!=1: return {"ok":false,"exists":true,"value":DEFAULT.duplicate()}
	for key: String in DEFAULT:
		if not file.has_section_key("display",key): return {"ok":false,"exists":true,"value":DEFAULT.duplicate()}
	var value: Dictionary={"mode":file.get_value("display","mode"),"resolution":file.get_value("display","resolution"),"vsync":file.get_value("display","vsync")}
	return {"ok":valid(value),"exists":true,"value":value if valid(value) else DEFAULT.duplicate()}

func write(value: Dictionary) -> bool:
	if not valid(value): return false
	var file: ConfigFile=ConfigFile.new(); file.set_value("display","version",1)
	for key: String in value: file.set_value("display",key,value[key])
	return file.save(path)==OK
