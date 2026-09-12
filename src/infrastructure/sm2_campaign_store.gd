class_name Sm2CampaignStore
extends Sm2SaveStore
## One immutable physical destination per session. Legacy stores keep their policy.
var campaign_index: int
var validate_payload: Callable
var recovered: bool=false

func _init(directory: String,index: int,validator: Callable) -> void:
	super(directory); campaign_index=index; validate_payload=validator

func _slot_path(slot: String) -> String:
	return super._slot_path(slot if campaign_index==0 else slot+"_"+str(campaign_index+1))

func _problem(slot: String) -> String:
	if campaign_index<0 or campaign_index>2 or slot!="survival_tissues": return "Неизвестная кампания."
	return _location_error(slot)

func checked(path: String) -> Dictionary:
	var result: Dictionary=_read_envelope(path)
	if result.ok:
		var check: Dictionary=validate_payload.call(result.payload)
		if not check.ok: return check
	return result

func load_slot(slot: String="survival_tissues") -> Dictionary:
	recovered=false
	if not _problem(slot).is_empty(): return _failure(_problem(slot))
	var path: String=_slot_path(slot)
	var primary: Dictionary=checked(path)
	if primary.ok: return primary
	var backup: Dictionary=checked(path+".bak")
	if backup.ok: recovered=true; return backup
	return _failure("Сохранение повреждено или несовместимо. Пригодной резервной копии нет.")

func save_slot(payload: Dictionary,slot: String="survival_tissues") -> Dictionary:
	if not _problem(slot).is_empty(): return _failure(_problem(slot))
	var budget: Array[int]=[MAX_NODES]
	var structure_error: String=_validate_value(payload,0,budget)
	if not structure_error.is_empty(): return _failure("Некорректные данные сохранения: "+structure_error)
	var validation: Dictionary=validate_payload.call(payload)
	if not validation.ok: return validation
	var path: String=_slot_path(slot)
	for suffix: String in ["",".tmp",".bak"]:
		if DirAccess.dir_exists_absolute(path+suffix): return _failure("Вместо файла сохранения обнаружена папка. Запись отменена.")
	if not FileAccess.file_exists(path) or checked(path).ok:
		var result: Dictionary=super.save_slot(payload,slot)
		if result.ok: recovered=false
		return result
	# A recovered session may replace an invalid primary, preserving its valid backup.
	if not checked(path+".bak").ok: return _failure("Повреждённое сохранение оставлено без изменений. Выберите пустую кампанию или удалите повреждённую.")
	var serialized: String=Sm2Canonical.stringify({"format":FORMAT,"schema_version":SCHEMA_VERSION,"payload":payload,"checksum":Sm2Canonical.hash(payload)})
	if serialized.to_utf8_buffer().size()>MAX_FILE_BYTES: return _failure("Размер сохранения превышает лимит 8 МиБ.")
	var temp_path: String=path+".tmp"
	var file: FileAccess=FileAccess.open(temp_path,FileAccess.WRITE)
	if file==null: return _failure("Не удалось записать временное сохранение.")
	file.store_string(serialized); file.flush(); var error: Error=file.get_error(); file.close()
	var verify: Dictionary=checked(temp_path)
	if error!=OK or not verify.ok or Sm2Canonical.hash(verify.payload)!=Sm2Canonical.hash(payload):
		_remove_if_present(temp_path); return _failure("Проверка записи не пройдена. Резервная копия сохранена.")
	if DirAccess.remove_absolute(path)!=OK:
		_remove_if_present(temp_path); return _failure("Не удалось заменить повреждённый файл. Резервная копия сохранена.")
	if DirAccess.rename_absolute(temp_path,path)!=OK:
		return _failure("Не удалось опубликовать сохранение. Загрузите сохранившуюся резервную копию.")
	recovered=false
	return {"ok":true,"errors":PackedStringArray()}
