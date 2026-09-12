class_name Sm2TissueLayers
extends RefCounted
## Layer state is authoritative; the old part totals are a checked read projection.

static func validate(raw: Variant,parts: Array) -> String:
	if not raw is Dictionary or raw.size()!=parts.size(): return "tissue_parts"
	for part: Dictionary in parts:
		var rows: Variant=raw.get(part.id)
		if not rows is Array or rows.is_empty() or rows.size()>8: return "tissue_layers"
		var ids: Array[String]=[]; var orders: Array[int]=[]; var total: int=0
		for row: Variant in rows:
			if not row is Dictionary or not Sm2Validate.fields(row,["id","name","capacity","bleeding","function_min","blunt_order"]): return "tissue_definition"
			if not Sm2Validate.text(row.id) or row.id in ids or not Sm2Validate.text(row.name): return "tissue_identity"
			if not Sm2Validate.integer(row.capacity,1,10000) or not Sm2Validate.integer(row.bleeding,0,100) or not Sm2Validate.integer(row.function_min,0,int(row.capacity)) or not Sm2Validate.integer(row.blunt_order,0,7): return "tissue_bounds"
			if int(row.blunt_order) in orders: return "tissue_order"
			orders.append(int(row.blunt_order))
			ids.append(row.id); total+=int(row.capacity)
		if total!=int(part.capacity): return "tissue_capacity"
	return ""

static func initialize(body: Sm2Anatomy,rules: Dictionary) -> void:
	body.layer_rules=rules.tissue_layers.duplicate(true)
	for part: String in body.layer_rules:
		body.layers[part]={}
		for row: Dictionary in body.layer_rules[part]: body.layers[part][row.id]=int(row.capacity)
	project(body)

static func project(body: Sm2Anatomy) -> void:
	for part: String in body.layers:
		var total: int=0
		for value: int in body.layers[part].values(): total+=value
		body.tissues[part]=total

static func working(body: Sm2Anatomy,part: String) -> bool:
	if not body.layers.has(part) or int(body.tissues[part])==0: return false
	for row: Dictionary in body.layer_rules[part]:
		if int(body.layers[part][row.id])<int(row.function_min): return false
	return true

static func injure(body: Sm2Anatomy,part: String,amount: int,cut: bool,rules: Dictionary) -> String:
	var ordered: Array=body.layer_rules[part].duplicate(true)
	if not cut: ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.blunt_order)<int(b.blunt_order))
	var losses: Dictionary={}; var total: int=0; var bleeding: int=0
	for row: Dictionary in ordered:
		var loss: int=mini(amount,int(body.layers[part][row.id]))
		body.layers[part][row.id]-=loss; amount-=loss; total+=loss
		losses[row.id]=loss
		if cut: bleeding+=loss*int(row.bleeding)
	body.wounds.append({"id":str(body.next_wound),"part":part,"loss":total,"rate":bleeding,"initial_rate":bleeding,"cut":cut,"layer_losses":losses})
	body.next_wound+=1; project(body); body.death=body.cause(rules)
	return ""

static func decode(raw: Variant,rules: Dictionary) -> Dictionary:
	var fail: Dictionary={"ok":false,"errors":PackedStringArray(["tissue_state_invalid"])}
	if not raw is Dictionary or not Sm2Validate.fields(raw,["format","tissues","layers","wounds","blood","remainder","next_wound","death"]) or raw.format!="sm2.anatomy.2": return fail
	if not raw.layers is Dictionary or not raw.tissues is Dictionary or not raw.wounds is Array or raw.wounds.size()>256 or not raw.death is String: return fail
	if not Sm2Validate.integer(raw.blood,0,int(rules.blood_max)) or not Sm2Validate.integer(raw.remainder,0,59) or not Sm2Validate.integer(raw.next_wound,1,1000000): return fail
	var body: Sm2Anatomy=Sm2Anatomy.fresh(rules)
	for entry: Variant in raw.wounds:
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","part","loss","rate","initial_rate","cut","layer_losses"]): return fail
		if entry.get("id")!=str(body.next_wound) or not entry.part is String or not body.layers.has(entry.part) or not entry.cut is bool or not Sm2Validate.integer(entry.loss,0,10000): return fail
		# Reconstruct every wound in order, including its actual tissue distribution.
		if not body.death.is_empty(): return fail
		injure(body,entry.part,int(entry.loss),entry.cut,rules)
		var expected: Dictionary=body.wounds.back().duplicate(true)
		if not Sm2Validate.integer(entry.rate,0,int(expected.initial_rate)) or int(entry.rate) not in [0,int(expected.initial_rate)]: return fail
		expected.rate=int(entry.rate)
		if Sm2Canonical.hash(expected)!=Sm2Canonical.hash(entry): return fail
		body.wounds.back().rate=int(entry.rate)
	if int(raw.next_wound)!=body.next_wound or Sm2Canonical.hash(raw.layers)!=Sm2Canonical.hash(body.layers) or Sm2Canonical.hash(raw.tissues)!=Sm2Canonical.hash(body.tissues): return fail
	body.blood=int(raw.blood); body.remainder=int(raw.remainder)
	if raw.death!=body.cause(rules) and raw.death!="prepared_carrier": return fail
	body.death=raw.death
	return {"ok":true,"body":body}
