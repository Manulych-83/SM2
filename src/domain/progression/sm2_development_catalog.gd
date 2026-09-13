class_name Sm2DevelopmentCatalog
extends RefCounted
const HYBRID_VERSION: String="sm2.p5.hybrid.development.1"
var _hybrids: Sm2HybridCatalog=null
const IMPLANT_VERSION: String="sm2.p5.implant.development.1"
const UPGRADE_VERSION: String="sm2.p5.upgrade.development.1"
var _upgrades: Sm2BodyUpgradeCatalog=null
const PSIONIC_SHIELD_VERSION: String="sm2.p5.psionic.development.3"
const PSIONIC_GROWTH_VERSION: String="sm2.p5.psionic.development.2"
const PSIONIC_VERSION: String="sm2.p5.psionic.development.1"
var _psionics: Sm2PsionicCatalog=null
const PROSTHESIS_VERSION: String="sm2.p4.prosthesis.development.1"
const BODY_VERSION: String="sm2.p4.body.development.1"
var _body: Sm2BodyFunctionCatalog=null
const PARTY_VERSION: String = "sm2.p4.party.development.1"
const VERSION: String = "sm2.p2.content.1"
var _raw: Dictionary = {}
var _fingerprint: String=""
var _progress: Sm2ProgressCatalog

func build(raw: Dictionary, progress: Sm2ProgressCatalog, combat: Sm2CombatCatalog, shared_progression: bool=false) -> PackedStringArray:
	if progress == null or not progress.is_ready() or combat == null: return PackedStringArray(["development_dependencies"])
	var fields: Array[String]=["version","hero_actor_id","companion_actor_id","awards","mappings"]
	if raw.get("version")==HYBRID_VERSION: fields.append("hybrids")
	if raw.get("version") in [UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]: fields.append("body_upgrades")
	if raw.get("version") in [BODY_VERSION,PROSTHESIS_VERSION,PSIONIC_VERSION,PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]: fields.append("body_functions")
	if raw.get("version") in [PSIONIC_VERSION,PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]: fields.append("psionics")
	if not Sm2Validate.fields(raw,fields) or raw.version != (str(raw.version) if raw.get("version") in [BODY_VERSION,PROSTHESIS_VERSION,PSIONIC_VERSION,PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION] and progress.is_party() else PARTY_VERSION if progress.is_party() else VERSION): return PackedStringArray(["development_version"])
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
	var functions: Sm2BodyFunctionCatalog=null
	if raw.version in [BODY_VERSION,PROSTHESIS_VERSION,PSIONIC_VERSION,PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]:
		if not raw.body_functions is Dictionary: return PackedStringArray(["body_content_type"])
		functions=Sm2BodyFunctionCatalog.new()
		var errors: PackedStringArray=functions.build(raw.body_functions,combat,progress)
		if not errors.is_empty(): return errors
		if functions.supports_prostheses()!=(raw.version in [PROSTHESIS_VERSION,PSIONIC_VERSION,PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]): return PackedStringArray(["body_profile_version"])
	var psi: Sm2PsionicCatalog=null
	if raw.version in [PSIONIC_VERSION,PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]:
		if not raw.psionics is Dictionary: return PackedStringArray(["psionic_content_type"])
		psi=Sm2PsionicCatalog.new()
		var errors: PackedStringArray=psi.build(raw.psionics,progress,combat)
		if not errors.is_empty(): return errors
		if psi.grows()!=(raw.version in [PSIONIC_GROWTH_VERSION,PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]) or psi.shields()!=(raw.version in [PSIONIC_SHIELD_VERSION,UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]): return PackedStringArray(["psionic_profile_version"])
	var upgrades: Sm2BodyUpgradeCatalog=null
	if raw.version in [UPGRADE_VERSION,IMPLANT_VERSION,HYBRID_VERSION]:
		if not raw.body_upgrades is Dictionary: return PackedStringArray(["upgrade_catalog_type"])
		upgrades=Sm2BodyUpgradeCatalog.new()
		var errors: PackedStringArray=upgrades.build(raw.body_upgrades,progress)
		if not errors.is_empty(): return errors
		if upgrades.supports_implants()!=(raw.version in [IMPLANT_VERSION,HYBRID_VERSION]): return PackedStringArray(["upgrade_profile_version"])
	var hybrid: Sm2HybridCatalog=null
	if raw.version==HYBRID_VERSION:
		if not raw.hybrids is Dictionary: return PackedStringArray(["hybrid_content_type"])
		hybrid=Sm2HybridCatalog.new()
		var errors: PackedStringArray=hybrid.build(raw.hybrids,progress,combat)
		if not errors.is_empty(): return errors
		for id: String in hybrid.ids():
			if raw.awards.has(id) or not psi.ability(id).is_empty(): return PackedStringArray(["hybrid_duplicate_award"])
	_hybrids=hybrid
	_upgrades=upgrades
	_psionics=psi
	_body=functions
	# Internal encounter compilation may share an already built immutable catalog.
	# All mappings and dependencies above still validate against the new combat.
	var copy: Sm2ProgressCatalog = progress if shared_progression else Sm2ProgressCatalog.new()
	if not shared_progression: copy.build(progress.to_data())
	_progress = copy; _raw = raw.duplicate(true); _fingerprint=""
	return PackedStringArray()

func has_hybrids() -> bool: return _hybrids!=null
func hybrids() -> Sm2HybridCatalog: return _hybrids
func has_implants() -> bool: return _upgrades!=null and _upgrades.supports_implants()
func has_upgrades() -> bool: return _upgrades!=null
func upgrades() -> Sm2BodyUpgradeCatalog: return _upgrades
func ready() -> bool: return not _raw.is_empty()
func to_data() -> Dictionary: return _raw.duplicate(true)
func fingerprint() -> String:
	if not ready(): return ""
	if _fingerprint.is_empty(): _fingerprint=Sm2Canonical.hash([_raw,_progress.to_data()])
	return _fingerprint
func progression() -> Sm2ProgressCatalog:
	var copy: Sm2ProgressCatalog = Sm2ProgressCatalog.new()
	if _progress != null: copy.build(_progress.to_data())
	return copy
## Internal session composition only. Treat the built catalog as immutable.
## Public progression() retains its defensive-copy contract.
func _shared_progression() -> Sm2ProgressCatalog: return _progress
func hero() -> int: return int(_raw.hero_actor_id)
func companion() -> int: return int(_raw.companion_actor_id)
func awards(ability_id: String) -> Dictionary:
	if _hybrids!=null and not _hybrids.ability(ability_id).is_empty(): return _hybrids.awards(ability_id)
	return _psionics.awards(ability_id) if _psionics!=null and not _psionics.ability(ability_id).is_empty() else _raw.awards.get(ability_id,{}).duplicate(true)
func ability_ids() -> Array[String]:
	var ids: Array[String] = []; ids.assign(_raw.awards.keys())
	if _psionics!=null: ids.append_array(_psionics.ids())
	if _hybrids!=null: ids.append_array(_hybrids.ids())
	ids.sort(); return ids
func mappings() -> Array:
	return _raw.mappings.duplicate(true)

func body_functions() -> Sm2BodyFunctionCatalog: return _body
func has_body_functions() -> bool: return _body!=null

func has_prostheses() -> bool: return _body!=null and _body.supports_prostheses()
func has_psionic_shields() -> bool: return _psionics!=null and _psionics.shields()
func has_psionic_growth() -> bool: return _psionics!=null and _psionics.grows()
func has_psionics() -> bool: return _psionics!=null
func psionics() -> Sm2PsionicCatalog: return _psionics
