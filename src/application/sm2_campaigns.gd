class_name Sm2Campaigns
extends RefCounted
## Three independent worlds; incarnation remains a lifecycle inside each world.
var directory: String
var content: Dictionary
var profile: Sm2AiProfile
var error: String=""

func _init(base_directory: String="user://survival_tissues") -> void:
	directory=ProjectSettings.globalize_path(base_directory)
	content=Sm2SurvivalContentLoader.load_scenario(true,true)
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	if not content.ok or not ai.ok: error="Не удалось подготовить кампании."; return
	profile=ai.profile

func store(index: int) -> Sm2CampaignStore:
	return Sm2CampaignStore.new(directory,index,_validate)

func _validate(payload: Dictionary) -> Dictionary:
	if not error.is_empty(): return {"ok":false,"errors":PackedStringArray([error])}
	return Sm2JourneySession.new(content,profile).restore(payload)

func open(index: int,from_save: bool) -> Dictionary:
	if not error.is_empty() or index<0 or index>2: return {"ok":false,"errors":PackedStringArray([error if not error.is_empty() else "Неизвестная кампания."])}
	var destination: Sm2CampaignStore=store(index)
	if not from_save and occupied(index): return {"ok":false,"errors":PackedStringArray(["Выберите пустую кампанию. Старое сохранение не изменено."])}
	var session: Sm2JourneySession=Sm2JourneySession.new(content,profile,destination)
	var result: Dictionary=session.load_game() if from_save else session.new_game()
	if result.ok: result["session"]=session; result["recovered"]=destination.recovered
	return result

func occupied(index: int) -> bool:
	var path: String=store(index)._slot_path("survival_tissues")
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix) or DirAccess.dir_exists_absolute(path+suffix): return true
	return false

func inspect() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for index: int in 3:
		var row: Dictionary={"index":index,"title":"Кампания "+str(index+1),"occupied":occupied(index),"ok":false,"recovered":false,"date":"","location":"","state":"","modified":0,"token":token(index)}
		if row.occupied:
			var result: Dictionary=open(index,true)
			if result.ok:
				row.ok=true; row.recovered=result.recovered
				var session: Sm2JourneySession=result.session
				var region: Sm2RegionState=session.journey().region
				row.location=session.journey().region_catalog.location(region.location_id).name
				row.state="В сражении" if session.journey().busy() else ("Душа без тела" if session.world.hero_id()==0 else "Герой жив")
				var path: String=store(index)._slot_path("survival_tissues")+(".bak" if row.recovered else "")
				row.modified=FileAccess.get_modified_time(path)
				row.date=Time.get_datetime_string_from_unix_time(row.modified).replace("T"," ")+" UTC"
		rows.append(row)
	return rows

static func latest(rows: Array[Dictionary],preferred: int=-1) -> int:
	var found: int=-1; var modified: int=-1
	for row: Dictionary in rows:
		if row.ok and (int(row.modified)>modified or (int(row.modified)==modified and row.index==preferred)): found=row.index; modified=row.modified
	return found

func selected() -> int:
	var config: ConfigFile=ConfigFile.new()
	if config.load(directory.path_join("selected_campaign.cfg"))!=OK: return 0
	var value: Variant=config.get_value("menu","campaign",0)
	return int(value) if value is int and value>=0 and value<3 else 0

func select(index: int) -> bool:
	if index<0 or index>2: return false
	if store(0)._ensure_directory()!=OK: return false
	var config: ConfigFile=ConfigFile.new(); config.set_value("menu","campaign",index)
	return config.save(directory.path_join("selected_campaign.cfg"))==OK

func token(index: int) -> String:
	var path: String=store(index)._slot_path("survival_tissues"); var values: Array=[]
	for suffix: String in ["",".bak",".tmp"]:
		var item: String=path+suffix
		values.append([suffix,FileAccess.get_sha256(item) if FileAccess.file_exists(item) else "directory" if DirAccess.dir_exists_absolute(item) else "missing"])
	return Sm2Canonical.hash(values)

func delete(index: int,expected: String) -> Dictionary:
	if index<0 or index>2 or token(index)!=expected: return {"ok":false,"errors":PackedStringArray(["Сохранение изменилось. Выберите его заново."])}
	var path: String=store(index)._slot_path("survival_tissues")
	for suffix: String in ["",".bak",".tmp"]:
		if DirAccess.dir_exists_absolute(path+suffix): return {"ok":false,"errors":PackedStringArray(["Вместо файла обнаружена папка. Удаление отменено."])}
	for suffix: String in [".tmp",".bak",""]:
		if FileAccess.file_exists(path+suffix) and DirAccess.remove_absolute(path+suffix)!=OK:
			return {"ok":false,"errors":PackedStringArray(["Не удалось удалить все файлы кампании. Проверьте список снова."])}
	return {"ok":true,"errors":PackedStringArray()}
