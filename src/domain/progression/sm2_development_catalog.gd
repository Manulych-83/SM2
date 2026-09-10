class_name Sm2DevelopmentCatalog
extends RefCounted
const VERSION: String = "sm2.p2.content.1"
var _raw: Dictionary = {}
var _progress: Sm2ProgressCatalog

func build(raw: Dictionary, progress: Sm2ProgressCatalog, combat: Sm2CombatCatalog) -> PackedStringArray:
	if progress == null or not progress.is_ready() or combat == null: return PackedStringArray(["development_dependencies"])
	if not Sm2Validate.fields(raw,["version","hero_actor_id","companion_actor_id","awards","mappings"]) or raw.version != VERSION: return PackedStringArray(["development_version"])
	if not Sm2Validate.integer(raw.hero_actor_id,1,4096) or not Sm2Validate.integer(raw.companion_actor_id,1,4096) or raw.hero_actor_id == raw.companion_actor_id: return PackedStringArray(["development_participants"])
	if not raw.awards is Dictionary or raw.awards.is_empty() or raw.awards.size() > 1000 or not raw.mappings is Array or raw.mappings.is_empty() or raw.mappings.size() > 64: return PackedStringArray(["development_rules"])
	for ability_id: Variant in raw.awards:
		if not ability_id is String: return PackedStringArray(["development_ability"])
		var ability: Sm2CombatAbility = combat.ability(ability_id)
		if ability == null or ability.mode != "melee" or ability.operation != "damage" or not raw.awards[ability_id] is Dictionary or raw.awards[ability_id].is_empty(): return PackedStringArray(["development_ability"])
		for track: Variant in raw.awards[ability_id]:
			if not track is String or progress.track(track) == null or not Sm2Validate.integer(raw.awards[ability_id][track],1,10000): return PackedStringArray(["development_award"])
	var targets: Array[String] = []
	for mapping: Variant in raw.mappings:
		if not mapping is Dictionary or not Sm2Validate.fields(mapping,["stat","track_id","scale","baseline"]): return PackedStringArray(["development_mapping"])
		if mapping.stat != "melee_skill" or mapping.stat in targets or not mapping.track_id is String or progress.track(mapping.track_id) == null or not Sm2Validate.integer(mapping.scale,1,10) or not Sm2Validate.integer(mapping.baseline,0,10000): return PackedStringArray(["development_mapping"])
		targets.append(mapping.stat)
	var copy: Sm2ProgressCatalog = Sm2ProgressCatalog.new()
	copy.build(progress.to_data())
	_progress = copy; _raw = raw.duplicate(true)
	return PackedStringArray()

func ready() -> bool: return not _raw.is_empty()
func to_data() -> Dictionary: return _raw.duplicate(true)
func fingerprint() -> String: return Sm2Canonical.hash([_raw,_progress.to_data()]) if ready() else ""
func progression() -> Sm2ProgressCatalog:
	var copy: Sm2ProgressCatalog = Sm2ProgressCatalog.new()
	if _progress != null: copy.build(_progress.to_data())
	return copy
func hero() -> int: return int(_raw.hero_actor_id)
func companion() -> int: return int(_raw.companion_actor_id)
func awards(ability_id: String) -> Dictionary: return _raw.awards.get(ability_id,{}).duplicate(true)
func ability_ids() -> Array[String]:
	var ids: Array[String] = []; ids.assign(_raw.awards.keys()); ids.sort(); return ids
func mappings() -> Array:
	return _raw.mappings.duplicate(true)
