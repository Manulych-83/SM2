class_name Sm2CreatureCatalog
extends RefCounted
## Definitions are indexed once. A battle compiles only the selected template set.
const VERSION: String = "sm2.creatures.1"
const TYPES_VERSION: String = "sm2.creature_types.1"
const MAX_TYPES: int = 3000
const MAX_ACTORS: int = 64
var _raw: Dictionary = {}
var _templates: Dictionary = {}
var _profiles: Dictionary = {}
var _encounters: Dictionary = {}
var _fields: Dictionary = {}
var _base: Dictionary = {}
var _hash: String = ""

func build(raw: Dictionary, turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, effects: Sm2EffectCatalog, fields: Dictionary, appearances: Array[String]) -> PackedStringArray:
	if turns == null or combat == null or effects == null or not combat.matches(turns): return _error("creature_dependencies")
	if not Sm2Validate.fields(raw,["version","profiles","templates","encounters"]) or raw.version not in [VERSION,TYPES_VERSION]: return _error("creature_catalog_shape")
	var normalized: Dictionary = {"version":raw.version}
	var indices: Dictionary = {}
	for group: String in ["profiles","templates","encounters"]:
		var types_only: bool = group=="encounters" and raw.version==TYPES_VERSION
		if not raw[group] is Array or (raw[group].is_empty() and not types_only) or (types_only and not raw[group].is_empty()) or raw[group].size() > (1000 if group == "encounters" else MAX_TYPES): return _error("creature_group:"+group)
		indices[group] = {}
		var rows: Array[Dictionary] = []
		for row: Variant in raw[group]:
			if not row is Dictionary or not Sm2Validate.text(row.get("id")) or indices[group].has(row.id): return _error("creature_identity:"+group)
			var data: Dictionary = row.duplicate(true)
			indices[group][data.id] = data; rows.append(data)
		rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
		normalized[group] = rows
	for profile: Dictionary in normalized.profiles:
		if not Sm2Validate.fields(profile,["id","turn","combat"]) or not profile.turn is Dictionary or not profile.combat is Dictionary or profile.turn.has("id") or profile.combat.has("id"): return _error("creature_profile:"+profile.id)
	for definition: Dictionary in normalized.templates:
		if not Sm2Validate.fields(definition,["id","name","profile_id","equipment_ids","actions","immunities","resistances","appearance_id","behavior_id"]): return _error("creature_template_fields:"+definition.id)
		if not Sm2Validate.text(definition.name) or not definition.profile_id is String or not indices.profiles.has(definition.profile_id): return _error("creature_profile_reference:"+definition.id)
		if not definition.appearance_id is String or definition.appearance_id not in appearances: return _error("creature_appearance:"+definition.id)
		if definition.behavior_id != Sm2AiProfile.ABILITY_POLICY: return _error("creature_behavior:"+definition.id)
		for key: String in ["equipment_ids","actions","immunities"]:
			if not Sm2Validate.string_list(definition[key]) or definition[key].size() > (64 if key == "equipment_ids" else 32): return _error("creature_list:"+definition.id)
			definition[key].sort()
		if not definition.resistances is Dictionary: return _error("creature_resistance:"+definition.id)
	var base: Dictionary = {"turns":turns.to_data(),"combat":combat.to_data(),"effects":effects.to_data()}
	# Full authoring validation once, including unused profiles and template loadouts.
	var checked: Dictionary = _assemble(indices.templates,indices.profiles,base,indices.templates.keys(),true,VERSION)
	if not checked.ok: return checked.errors
	# Preserve normalized numeric values from the existing typed catalogs.
	var checked_turns: Dictionary = {}; var checked_combat: Dictionary = {}
	for p: Dictionary in checked.catalog.to_data().profiles: checked_turns[p.id] = p
	for p: Dictionary in checked.combat.to_data().profiles: checked_combat[p.id] = p
	for p: Dictionary in normalized.profiles:
		p.turn = checked_turns[p.id].duplicate(true); p.turn.erase("id")
		p.combat = checked_combat[p.id].duplicate(true); p.combat.erase("id")
	var field_copies: Dictionary = {}
	for id: Variant in fields:
		if not Sm2Validate.text(id) or not fields[id] is Dictionary: return _error("creature_field")
		var field: Sm2Battlefield = Sm2Battlefield.new()
		if not field.build(fields[id]).is_empty(): return _error("creature_field:"+id)
		field_copies[id] = field
	for encounter: Dictionary in normalized.encounters:
		var error: String = _check_encounter(encounter,indices.templates,field_copies)
		if not error.is_empty(): return _error(error+":"+encounter.id)
	_raw = normalized; _templates = indices.templates; _profiles = indices.profiles; _encounters = indices.encounters
	_base = base; _fields = {}
	for id: String in field_copies: _fields[id] = field_copies[id].to_data()
	_hash = Sm2Canonical.hash([normalized,_fields,turns.fingerprint(),combat.fingerprint(),effects.fingerprint()])
	return PackedStringArray()

func fingerprint() -> String: return _hash
func to_data() -> Dictionary: return _raw.duplicate(true)
func definition(id: String) -> Dictionary: return _templates.get(id,{}).duplicate(true)
func profile(id: String) -> Dictionary: return _profiles.get(id,{}).duplicate(true)
func effect_definitions() -> Dictionary:
	var result: Dictionary = _base.effects.duplicate(true)
	result.profiles = []
	return result
func encounter(id: String) -> Dictionary: return _encounters.get(id,{}).duplicate(true)
func count() -> int: return _templates.size()
func encounters() -> Array[String]:
	var result: Array[String] = []; result.assign(_encounters.keys()); result.sort(); return result

func compile(encounter_id: String) -> Dictionary:
	if not _encounters.has(encounter_id): return {"ok":false,"errors":_error("creature_encounter_missing")}
	var meeting: Dictionary = _encounters[encounter_id]
	var selected: Dictionary = {}
	for spawn: Dictionary in meeting.actors: selected[spawn.template_id] = true
	var compiled: Dictionary = _assemble(_templates,_profiles,_base,selected.keys(),false,VERSION+"."+Sm2Canonical.hash([_hash,encounter_id]))
	if not compiled.ok: return compiled
	var actors: Array[Dictionary] = []
	var bindings: Dictionary = {}
	for spawn: Dictionary in meeting.actors:
		var definition: Dictionary = _templates[spawn.template_id]
		actors.append({"actor_id":spawn.actor_id,"loadout_id":_loadout(spawn.template_id),"side":spawn.side,"owner":spawn.side,"controller":spawn.controller,"creator":0,"q":spawn.q,"r":spawn.r,"fatigue":0,"alive":true,"on_field":true,"morale":"steady"})
		bindings[spawn.actor_id] = {"template_id":definition.id,"display_name":definition.name,"appearance_id":definition.appearance_id,"behavior_id":definition.behavior_id}
	compiled["setup"] = {"battle_id":"creatures:battle."+encounter_id.sha256_text(),"scenario_id":encounter_id,"seed":meeting.seed,"round_limit":meeting.round_limit,"field":_fields[meeting.field_id].duplicate(true),"actors":actors}
	compiled["bindings"] = bindings
	compiled["encounter_name"] = meeting.name
	compiled["creature_fingerprint"] = _hash
	return compiled

static func _assemble(templates: Dictionary, profiles: Dictionary, base: Dictionary, selected: Array, all_profiles: bool, version: String) -> Dictionary:
	var turns: Dictionary = base.turns.duplicate(true)
	var combat: Dictionary = base.combat.duplicate(true)
	var effects: Dictionary = base.effects.duplicate(true)
	turns.version = version; turns.profiles = []; turns.loadouts = []; combat.profiles = []; effects.profiles = []
	var profile_ids: Dictionary = {}
	if all_profiles:
		for id: String in profiles: profile_ids[id] = true
	var ids: Array = selected.duplicate(); ids.sort()
	for id: String in ids:
		var definition: Dictionary = templates[id]
		profile_ids[definition.profile_id] = true
		turns.loadouts.append({"id":_loadout(id),"profile_id":definition.profile_id,"equipment_ids":definition.equipment_ids.duplicate()})
		effects.profiles.append({"id":_loadout(id),"actions":definition.actions.duplicate(),"immunities":definition.immunities.duplicate(),"resistances":definition.resistances.duplicate(true)})
	var ordered: Array = profile_ids.keys(); ordered.sort()
	for id: String in ordered:
		var turn: Dictionary = profiles[id].turn.duplicate(true); turn.id = id; turns.profiles.append(turn)
		var profile: Dictionary = profiles[id].combat.duplicate(true); profile.id = id; combat.profiles.append(profile)
	var turn_catalog: Sm2TurnCatalog = Sm2TurnCatalog.new()
	var errors: PackedStringArray = turn_catalog.build(turns)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var combat_catalog: Sm2CombatCatalog = Sm2CombatCatalog.new()
	errors = combat_catalog.build(combat,turn_catalog)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var effect_catalog: Sm2EffectCatalog = Sm2EffectCatalog.new()
	errors = effect_catalog.build(effects,combat_catalog)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	return {"ok":true,"catalog":turn_catalog,"combat":combat_catalog,"effects":effect_catalog,"errors":PackedStringArray()}

static func _check_encounter(data: Dictionary, templates: Dictionary, fields: Dictionary) -> String:
	if not Sm2Validate.fields(data,["id","name","field_id","seed","round_limit","actors"]) or not Sm2Validate.text(data.name) or not data.field_id is String or not fields.has(data.field_id): return "creature_encounter_field"
	if not Sm2Validate.integer(data.seed,1,2147483646) or not Sm2Validate.integer(data.round_limit,1,1000) or not data.actors is Array or data.actors.size() < 2 or data.actors.size() > MAX_ACTORS: return "creature_encounter_bounds"
	var ids: Dictionary = {}; var occupied: Dictionary = {}; var sides: Dictionary = {}
	var field: Sm2Battlefield = fields[data.field_id]
	for spawn: Variant in data.actors:
		if not spawn is Dictionary or not Sm2Validate.fields(spawn,["actor_id","template_id","side","controller","q","r"]): return "creature_spawn_shape"
		if not Sm2Validate.integer(spawn.actor_id,1,4096) or ids.has(int(spawn.actor_id)) or not spawn.template_id is String or not templates.has(spawn.template_id): return "creature_spawn_identity"
		if spawn.side not in ["company","opposition"] or spawn.controller != ("player" if spawn.side == "company" else "ai"): return "creature_spawn_side"
		if not Sm2Validate.integer(spawn.q,0,63) or not Sm2Validate.integer(spawn.r,0,63): return "creature_spawn_position"
		var cell: Vector2i = Vector2i(int(spawn.q),int(spawn.r))
		if not field.in_bounds(cell) or not field.cell(cell).passable or occupied.has(cell): return "creature_spawn_position"
		ids[int(spawn.actor_id)] = true; occupied[cell] = true; sides[spawn.side] = true
		for key: String in ["actor_id","q","r"]: spawn[key] = int(spawn[key])
	if sides.size() != 2: return "creature_encounter_sides"
	data.actors.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.actor_id < b.actor_id)
	data.seed = int(data.seed); data.round_limit = int(data.round_limit)
	return ""

static func _loadout(id: String) -> String: return "creatures:loadout."+id.sha256_text()
static func _error(reason: String) -> PackedStringArray: return PackedStringArray([reason])
