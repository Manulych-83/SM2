class_name Sm2Anatomy
extends RefCounted
## Small data-defined body. Health is a read model, never a spendable life pool.
const FORMAT: String = "sm2.anatomy.1"
var tissues: Dictionary = {}
var wounds: Array[Dictionary] = []
var blood: int = 5000
var remainder: int = 0
var next_wound: int = 1
var death: String = ""

static func fresh(rules: Dictionary) -> Sm2Anatomy:
	var body: Sm2Anatomy = Sm2Anatomy.new()
	body.blood = int(rules.blood_max)
	for part: Dictionary in rules.parts:
		body.tissues[part.id] = int(part.capacity)
	return body

func copy() -> Sm2Anatomy:
	var body: Sm2Anatomy = Sm2Anatomy.new()
	body.tissues = tissues.duplicate(true)
	body.wounds.assign(wounds.duplicate(true))
	body.blood = blood; body.remainder = remainder; body.next_wound = next_wound; body.death = death
	return body

func to_data() -> Dictionary:
	return {"format":FORMAT,"tissues":tissues.duplicate(true),"wounds":wounds.duplicate(true),"blood":blood,"remainder":remainder,"next_wound":next_wound,"death":death}

func cause(rules: Dictionary) -> String:
	if not death.is_empty(): return death
	for part: Dictionary in rules.parts:
		if part.critical and int(tissues[part.id]) == 0: return "organ:" + str(part.id)
	return "blood_loss" if blood <= int(rules.blood_fatal) else ""

func rate() -> int:
	var total: int = 0
	for wound: Dictionary in wounds: total += int(wound.rate)
	return total

func summary(rules: Dictionary) -> int:
	var current: int = 0; var capacity: int = 0
	for part: Dictionary in rules.parts:
		current += int(tissues[part.id]); capacity += int(part.capacity)
	return int(60.0 * current / capacity)

func working(part: String) -> bool:
	return int(tissues.get(part,0)) > 0

func injure(part: String, amount: int, cut: bool, rules: Dictionary) -> String:
	if not tissues.has(part) or amount < 0: return "anatomy_damage_target"
	if amount == 0 or not death.is_empty(): return ""
	if wounds.size() >= 256 or next_wound >= 1000000: return "anatomy_wound_limit"
	var loss: int = mini(int(tissues[part]), amount)
	tissues[part] -= loss
	wounds.append({"id":str(next_wound),"part":part,"loss":loss,"rate":loss*int(rules.bleeding_per_damage) if cut else 0,"initial_rate":loss*int(rules.bleeding_per_damage) if cut else 0})
	next_wound += 1
	death = cause(rules)
	return ""

func wound(id: String) -> Dictionary:
	for entry: Dictionary in wounds:
		if entry.id == id: return entry.duplicate(true)
	return {}

func bandage(id: String) -> String:
	for entry: Dictionary in wounds:
		if entry.id == id:
			if int(entry.rate) == 0: return "Рана уже не кровоточит."
			entry.rate = 0
			return ""
	return "Рана не найдена."

func until_death(rules: Dictionary) -> int:
	if not cause(rules).is_empty(): return 0
	if rate() == 0: return 1000000000
	var numerator: int = (blood-int(rules.blood_fatal))*60-remainder
	@warning_ignore("integer_division")
	var seconds: int = (numerator+rate()-1)/rate()
	return seconds

func advance(seconds: int, rules: Dictionary) -> void:
	if seconds <= 0 or not death.is_empty(): return
	var duration: int = mini(seconds,until_death(rules))
	var amount: int = rate()*duration+remainder
	@warning_ignore("integer_division")
	var loss: int = amount/60
	blood = maxi(0,blood-loss); remainder = amount%60
	death = cause(rules)

static func decode(raw: Variant, rules: Dictionary) -> Dictionary:
	var fail: Dictionary = {"ok":false,"errors":PackedStringArray(["anatomy_invalid"])}
	if not raw is Dictionary or not Sm2Validate.fields(raw,["format","tissues","wounds","blood","remainder","next_wound","death"]) or raw.format != FORMAT: return fail
	if not raw.tissues is Dictionary or raw.tissues.size()!=rules.parts.size() or not raw.wounds is Array or raw.wounds.size()>256 or not raw.death is String: return fail
	if not Sm2Validate.integer(raw.blood,0,int(rules.blood_max)) or not Sm2Validate.integer(raw.remainder,0,59) or not Sm2Validate.integer(raw.next_wound,1,1000000): return fail
	var body: Sm2Anatomy = fresh(rules)
	var losses: Dictionary = {}
	for part: Dictionary in rules.parts:
		if not Sm2Validate.integer(raw.tissues.get(part.id),0,int(part.capacity)): return fail
		body.tissues[part.id] = int(raw.tissues[part.id]); losses[part.id] = 0
	var previous: int = 0
	for entry: Variant in raw.wounds:
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","part","loss","rate","initial_rate"]) or not Sm2Validate.decimal(entry.id,previous+1,int(raw.next_wound)-1) or not entry.part is String or not body.tissues.has(entry.part): return fail
		if not Sm2Validate.integer(entry.loss,0,10000) or not Sm2Validate.integer(entry.initial_rate,0,int(entry.loss)*int(rules.bleeding_per_damage)) or not Sm2Validate.integer(entry.rate,0,int(entry.initial_rate)): return fail
		if int(entry.initial_rate) not in [0,int(entry.loss)*int(rules.bleeding_per_damage)] or int(entry.rate) not in [0,int(entry.initial_rate)]: return fail
		previous = int(entry.id); losses[entry.part] += int(entry.loss)
		body.wounds.append(entry.duplicate(true))
	for part: Dictionary in rules.parts:
		if int(part.capacity)-int(body.tissues[part.id])!=int(losses[part.id]): return fail
	if int(raw.next_wound)!=raw.wounds.size()+1: return fail
	body.blood = int(raw.blood); body.remainder = int(raw.remainder); body.next_wound = int(raw.next_wound)
	if raw.death != body.cause(rules) and raw.death != "prepared_carrier": return fail
	body.death = raw.death
	return {"ok":true,"body":body}
