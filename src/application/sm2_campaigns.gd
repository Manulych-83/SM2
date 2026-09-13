class_name Sm2Campaigns
extends RefCounted
## Three independent worlds; incarnation remains a lifecycle inside each world.
var directory: String
var content: Dictionary
var legacy_content: Dictionary
var legacy_profile: Sm2AiProfile
var profile: Sm2AiProfile
var error: String=""
var history_repository: Sm2HistoryRepository

func _init(base_directory: String="user://survival_tissues") -> void:
	directory=ProjectSettings.globalize_path(base_directory)
	history_repository=Sm2HistoryRepository.new(directory)
	legacy_content=Sm2SurvivalContentLoader.load_scenario(true,true)
	content=Sm2WorldCreatureContentLoader.load_scenario(legacy_content)
	var ai: Dictionary=Sm2AiContentLoader.load_profile()
	var ability_ai: Dictionary=Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH)
	if not content.ok or not ai.ok or not ability_ai.ok: error="Не удалось подготовить кампании."; return
	legacy_profile=ai.profile
	profile=ability_ai.profile

func _content_for(payload: Dictionary) -> Dictionary:
	if payload.get("fingerprint")==content.journey_fingerprint: return content
	if payload.get("fingerprint")==legacy_content.journey_fingerprint: return legacy_content
	return {}

func _profile_for(definitions: Dictionary) -> Sm2AiProfile:
	return profile if definitions.has("world_creatures") else legacy_profile

func store(index: int) -> Sm2CampaignStore:
	var result: Sm2CampaignStore=Sm2CampaignStore.new(directory,index,_validate)
	result.large_profile=content.ok and content.development._shared_progression().is_large()
	history_repository.store.large_profile=result.large_profile
	return result

func _validate(payload: Dictionary) -> Dictionary:
	if not error.is_empty(): return {"ok":false,"errors":PackedStringArray([error])}
	var definitions: Dictionary=_content_for(payload)
	if definitions.is_empty(): return {"ok":false,"errors":PackedStringArray(["campaign_content_version"])}
	var session: Sm2CheckpointSession=Sm2CheckpointSession.new(definitions,_profile_for(definitions),null,history_repository)
	var result: Dictionary=session.restore(payload)
	if result.ok: result["validated_session"]=session
	return result

func open(index: int,from_save: bool) -> Dictionary:
	if not error.is_empty() or index<0 or index>2: return {"ok":false,"errors":PackedStringArray([error if not error.is_empty() else "Неизвестная кампания."])}
	var destination: Sm2CampaignStore=store(index)
	if not from_save and occupied(index): return {"ok":false,"errors":PackedStringArray(["Выберите пустую кампанию. Старое сохранение не изменено."])}
	var session: Sm2CheckpointSession
	var result: Dictionary
	if from_save:
		result=destination.load_slot("survival_tissues")
		if not result.ok: return result
		session=result.validated_session
		session._store=destination
	else:
		session=Sm2CheckpointSession.new(content,_profile_for(content),destination,history_repository)
		result=session.new_game()
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
			var path: String=store(index)._slot_path("survival_tissues")
			var result: Dictionary=_preview(path)
			var recovered: bool=false
			if not result.ok:
				result=_preview(path+".bak"); recovered=result.ok
			if result.ok:
				row.ok=true; row.recovered=recovered
				var world: Sm2JourneyWorld=result.world
				row.location=world.region_catalog.location(world.region.location_id).name
				row.state="В сражении" if world.busy() else ("Душа без тела" if world.hero_id()==0 else "Герой жив")
				row.modified=FileAccess.get_modified_time(path+(".bak" if recovered else ""))
				row.date=Time.get_datetime_string_from_unix_time(row.modified).replace("T"," ")+" UTC"
		rows.append(row)
	return rows

func _preview(path: String) -> Dictionary:
	# A slot card verifies the envelope and current world, without opening its archive.
	# Full archive/battle validation and backup selection happen on actual loading.
	var read: Dictionary=Sm2SaveStore._read_envelope(path,content.development._shared_progression().is_large())
	if not read.ok: return read
	var raw: Dictionary=read.payload
	var definitions: Dictionary=_content_for(raw)
	if raw.get("format") not in [Sm2CheckpointSession.CHECKPOINT_FORMAT,"sm2.survival_journey_session.3"] or definitions.is_empty(): return {"ok":false}
	var fresh: Sm2CheckpointSession=Sm2CheckpointSession.new(definitions,_profile_for(definitions))
	return Sm2CheckpointWorld.decode(raw.get("world"),fresh.journey())

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
