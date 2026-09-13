class_name Sm2CombatGrowthProfile
extends RefCounted
## Private immutable encounter inputs. Never accepted from a file or a command.
const LIVE_FORMAT: String="sm2.internal.combat_growth.1"
var _base: Sm2BattleDevelopment
var _raw: Dictionary
var _key: String
var _stats: Dictionary={}
var _available: Dictionary={}
var _parameters: Dictionary={}
var _costs: Dictionary={}
var _views: Dictionary={}
var _fatigue: Dictionary={}

static func build(state: Sm2TacticalState) -> Sm2CombatGrowthProfile:
	var dev: Sm2BattleDevelopment=state.development
	var result: Sm2CombatGrowthProfile=Sm2CombatGrowthProfile.new()
	result._base=dev.copy(); result._raw=dev.to_data(); result._key=Sm2Canonical.hash(result._raw)
	for actor: int in dev.bodies:
		result._stats[actor]={}
		for mapping: Dictionary in dev.catalog.mappings(): result._stats[actor][mapping.stat]=dev.stat_bonus(actor,mapping.stat)
		# Companion automatic melee growth also exists without a hero mapping.
		result._stats[actor]["melee_skill"]=dev.stat_bonus(actor,"melee_skill")
		result._views[actor]=dev.view(state,actor)
	for actor: int in state.sorted_ids():
		result._fatigue[actor]=dev.extra_attack_fatigue(actor)
		result._available[actor]={}; result._parameters[actor]={}; result._costs[actor]={}
		if dev.catalog.has_psionics():
			for id: String in dev.catalog.psionics().ids():
				var definition: Dictionary=dev.catalog.psionics().ability(id)
				result._available[actor][id]=dev.psionic_available(actor,id)
				result._costs[actor][id]=dev.concentration_cost(actor,int(definition.concentration_cost))
				if dev.bodies.has(actor) and actor==dev.catalog.hero():
					result._parameters[actor][id]=dev.psionic_parameter(actor,id,definition.get("operation")=="self_barrier")
		if dev.catalog.has_hybrids():
			for id: String in dev.catalog.hybrids().ids():
				result._available[actor][id]=dev.hybrid_available(actor,id)
				result._costs[actor][id]=dev.concentration_cost(actor,int(dev.catalog.hybrids().ability(id).concentration_cost))
				if dev.bodies.has(actor) and actor==dev.catalog.hero(): result._parameters[actor][id]=dev.hybrid_parameter(actor,id)
	for value: Dictionary in [result._raw,result._stats,result._available,result._parameters,result._costs,result._views,result._fatigue]: _freeze(value)
	return result

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()

func has_actor(id: int) -> bool: return _base._bodies.has(id)
func body_id(id: int) -> int: return _base._bodies[id].id
func simple(id: int) -> bool: return _base._bodies[id] is Sm2CompanionProgress
func earned(id: int,track: String) -> int:
	return (_base._bodies[id] as Sm2CompanionProgress).earned if simple(id) else _base._bodies[id].tracks[track].earned
func origin_version() -> String: return str(_raw.origin.version)
func actors() -> Array: return _raw.origin.actors
func available(actor: int,id: String) -> bool: return bool(_available.get(actor,{}).get(id,false))
func parameter(actor: int,id: String) -> Dictionary: return _parameters.get(actor,{}).get(id,{}).duplicate(true)
func cost(actor: int,id: String) -> Dictionary: return _costs.get(actor,{}).get(id,{}).duplicate(true)
func stat(actor: int,id: String) -> int: return int(_stats.get(actor,{}).get(id,0))
func fatigue(actor: int) -> int: return int(_fatigue.get(actor,0))

func materialize_into(dev: Sm2BattleDevelopment) -> void:
	dev._origin=_base._origin.duplicate(true)
	for id: int in _base._bodies: dev._bodies[id]=_base._bodies[id].copy()
	for id: int in _base._upgrades: dev._upgrades[id]=_base._upgrades[id].copy()

func instance() -> Sm2BattleDevelopment:
	var dev: Sm2BattleDevelopment=Sm2BattleDevelopment.new()
	dev.catalog=_base.catalog; dev.progress=_base.progress; dev.world_id=_base.world_id; dev.deferred_growth=true
	dev.soul.incarnation_id=_base.soul.incarnation_id; dev.soul.knowledge=_base.soul.knowledge.duplicate()
	dev.incarnation.id=_base.incarnation.id; dev.incarnation.body_id=_base.incarnation.body_id
	dev._profile=self
	for actor: int in _base.counts:
		dev.counts[actor]={}
		for id: String in _base.counts[actor]: dev.counts[actor][id]=0
	return dev

func snapshot(dev: Sm2BattleDevelopment,compact: bool) -> Dictionary:
	var data: Dictionary={"format":LIVE_FORMAT,"profile":_key,"sequence":str(dev.sequence),"members":[]} if compact else _raw.duplicate(true)
	data.sequence=str(dev.sequence)
	var rows: Array=[]
	for actor: int in [_base.catalog.hero(),_base.catalog.companion()]:
		var attacks: Array=[]
		for id: String in _base.catalog.ability_ids(): attacks.append({"ability_id":id,"count":dev.counts[actor][id]})
		var row: Dictionary={"actor_id":str(actor),"attacks":attacks}
		if not compact: row["body"]=data.members[rows.size()].body
		rows.append(row)
	data.members=rows
	return data

func view(dev: Sm2BattleDevelopment,actor: int) -> Dictionary:
	var result: Dictionary=_views.get(actor,{}).duplicate(true)
	if not result.is_empty():
		result.pending_practice=dev.pending_view(actor); result.attacks=dev.counts[actor].duplicate(true)
	return result
