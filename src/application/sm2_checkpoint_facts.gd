class_name Sm2CheckpointFacts
extends RefCounted

static func empty() -> Dictionary:
	return {"ids":[],"old_ids":[],"old_hero":0,"old_xp":{},"old_companion":0,"gained":{},"companion_xp":0,"battle":{},"summary":{},"started":-1}

static func detached_numbers(value: Variant) -> Variant:
	# JSON parses every number as a float. Restore whole-number presentation values
	# so saved reports do not show "incarnation 1.0" or "+50.0 XP" after loading.
	if value is Dictionary:
		var result: Dictionary={}
		for key: String in value: result[key]=detached_numbers(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for row: Variant in value: result.append(detached_numbers(row))
		return result
	if value is float and is_finite(value) and value==floor(value): return int(value)
	return value

static func like(value: Variant,shape: Variant) -> bool:
	if shape is Dictionary:
		if not value is Dictionary or value.size()!=shape.size(): return false
		for key: String in shape:
			if not value.has(key) or not like(value[key],shape[key]): return false
		return true
	if shape is Array:
		if not value is Array or value.size()>1000: return false
		for row: Variant in value:
			if not like(row,shape[0]): return false
		return true
	if shape is bool: return value is bool
	if shape is String: return Sm2Validate.text(value,true)
	if shape is float: return (value is float or value is int) and is_finite(float(value)) and float(value)>=0 and float(value)<=1000000000
	return Sm2Validate.integer(value,0,1000000000)

static func battle_shape() -> Dictionary:
	return {"title":"","battle_id":"","round":0,"counts":{"company":{"dead":0,"escaped":0,"on_field":0},"opposition":{"dead":0,"escaped":0,"on_field":0}},"party":[{"name":"","body_id":0,"alive":true,"status":"","blood":0,"max_blood":0,"bleeding":0,"wounds":0,"lost":[""],"practice":[{"title":"","xp":0,"before":0,"after":0}]}],"location":"","ground":0,"body":0,"world_id":"","revision":0}

static func valid(raw: Variant,w: Sm2JourneyWorld,count: int) -> bool:
	var keys: Array[String]=[]; keys.assign(empty().keys())
	if not raw is Dictionary or not Sm2Validate.fields(raw,keys): return false
	for key: String in ["ids","old_ids"]:
		if not Sm2Validate.string_list(raw[key]): return false
		for id: String in raw[key]:
			if not Sm2Validate.decimal(id,1): return false
	for key: String in ["old_xp","gained"]:
		if not raw[key] is Dictionary: return false
		for id: Variant in raw[key]:
			if not id is String or w._progress.track(id)==null or not Sm2Validate.integer(raw[key][id],0,1000000000): return false
	for key: String in ["old_hero","old_companion","companion_xp"]:
		if not Sm2Validate.integer(raw[key],0,1000000000): return false
	if not Sm2Validate.integer(raw.started,-1,w.region.seconds) or not raw.battle is Dictionary or not raw.summary is Dictionary: return false
	if not raw.battle.is_empty() and (not like(raw.battle,battle_shape()) or raw.battle.world_id!=w.world_id or raw.battle.party.size()!=2): return false
	if not raw.summary.is_empty():
		var shape: Dictionary={"event":0,"seconds":0,"elapsed":0,"battle":battle_shape(),"party":[{"id":0,"name":"","alive":true,"blood":0,"blood_max":0,"bleeding":0,"lost_functions":0,"local":true,"location":"","mass":0.0}],"practice":[{"title":"","xp":0}],"companion_xp":0,"incarnation":0,"items":[""]}
		if not like(raw.summary,shape) or raw.summary.event>=count or raw.summary.seconds>w.region.seconds or raw.summary.elapsed>raw.summary.seconds or raw.summary.incarnation<1 or raw.summary.incarnation>w.incarnations.size(): return false
		if raw.summary.items!=raw.ids or raw.summary.battle!=raw.battle or raw.ids.size()!=4 or raw.summary.party.size()!=2: return false
	return raw.ids.is_empty() or (raw.ids.size()==4 and "first_aid" in w.exploration.collected)
