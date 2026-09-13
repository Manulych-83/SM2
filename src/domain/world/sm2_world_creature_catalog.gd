class_name Sm2WorldCreatureCatalog
extends RefCounted
## Immutable template bindings for persistent human bodies. Anatomy owns health.
const VERSION: String = "sm2.world_creatures.1"
const WORLD_FORMAT: String = "sm2.world.creatures.1"
var _raw: Dictionary = {}
var _actors: Dictionary = {}
var _effects: Dictionary = {}
var _hash: String = ""

func build(raw: Dictionary, templates: Sm2CreatureCatalog, world: Sm2LifeDefinition, meetings: Array, survival: Sm2SurvivalCatalog, combat: Sm2CombatCatalog) -> PackedStringArray:
	if not Sm2Validate.fields(raw,["version","bindings"]) or raw.version != VERSION or not raw.bindings is Array or raw.bindings.is_empty() or raw.bindings.size()>1000 or templates==null or world==null or combat==null or survival==null or not survival.has_layers(): return _error("world_creatures_shape")
	var expected: Dictionary = {}
	for meeting: Dictionary in meetings:
		for id: Variant in meeting.enemies: expected[int(id)] = true
	var profile_ids: Dictionary = {}
	for p: Dictionary in combat.to_data().profiles: profile_ids[p.id]=true
	var actors: Dictionary = {}; var bindings: Array[Dictionary] = []
	for row: Variant in raw.bindings:
		if not row is Dictionary or not Sm2Validate.fields(row,["id","template_id","anatomy_id"]) or not Sm2Validate.decimal(row.id,1,1000000) or actors.has(int(row.id)) or not expected.has(int(row.id)) or not row.template_id is String: return _error("world_creatures_binding")
		var carrier: Dictionary = world.body(int(row.id))
		var definition: Dictionary = templates.definition(row.template_id)
		if carrier.is_empty() or not carrier.human or carrier.enhanced or not carrier.alive or carrier.prepared or definition.is_empty(): return _error("world_creatures_carrier")
		var parameters: Dictionary = templates.profile(definition.profile_id)
		# The current tissue model projects health to 0..60. Do not introduce a second health source.
		if row.anatomy_id != "m2:body.human" or parameters.combat.body_id != row.anatomy_id or int(parameters.combat.hp_max)!=60: return _error("world_creatures_anatomy")
		for gear_id: String in definition.equipment_ids:
			if combat.gear(gear_id)==null or survival.item(gear_id).is_empty(): return _error("world_creatures_physical_gear")
		if profile_ids.has(parameters.id): return _error("world_creatures_profile_collision")
		var binding: Dictionary = {"id":str(row.id),"template_id":row.template_id,"anatomy_id":row.anatomy_id}
		bindings.append(binding)
		actors[int(row.id)] = {"binding":binding,"definition":definition,"profile":parameters}
	if actors.size()!=expected.size(): return _error("world_creatures_missing_binding")
	bindings.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.id)<int(b.id))
	_raw = {"version":VERSION,"bindings":bindings}; _actors = actors
	_effects = templates.effect_definitions()
	_hash = Sm2Canonical.hash([_raw,templates.fingerprint(),survival.to_data()])
	return PackedStringArray()

func fingerprint() -> String: return _hash
func to_data() -> Dictionary: return _raw.duplicate(true)
func snapshot() -> Dictionary: return {"version":VERSION,"fingerprint":_hash,"bindings":_raw.bindings.duplicate(true)}
func actor(id: int) -> Dictionary: return _actors.get(id,{}).duplicate(true)
func effects() -> Dictionary: return _effects.duplicate(true)
func copy() -> Sm2WorldCreatureCatalog:
	var result: Sm2WorldCreatureCatalog = Sm2WorldCreatureCatalog.new()
	result._raw=_raw.duplicate(true); result._actors=_actors.duplicate(true); result._effects=_effects.duplicate(true); result._hash=_hash
	return result
static func _error(value: String) -> PackedStringArray: return PackedStringArray([value])
