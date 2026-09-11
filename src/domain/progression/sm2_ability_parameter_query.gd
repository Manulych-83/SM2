class_name Sm2AbilityParameterQuery
extends RefCounted
## Positive growth above authored baselines; no execution of content scripts.
static func validate(raw: Variant, progress: Sm2ProgressCatalog, base: int) -> String:
	if progress==null or not progress.is_ready() or base<0 or base>1000000: return "parameter_dependencies"
	if not raw is Dictionary or not Sm2Validate.fields(raw,["maximum","terms"]) or not Sm2Validate.integer(raw.maximum,base,1000000): return "parameter_shape"
	if not raw.terms is Array or raw.terms.is_empty() or raw.terms.size()>64: return "parameter_terms"
	var seen: Array[String]=[]
	for term: Variant in raw.terms:
		if not term is Dictionary or not Sm2Validate.fields(term,["track_id","baseline","numerator","denominator"]): return "parameter_term"
		if not term.track_id is String or progress.track(term.track_id)==null or term.track_id in seen: return "parameter_track"
		if not Sm2Validate.integer(term.baseline,0,1000000) or not Sm2Validate.integer(term.numerator,1,100) or not Sm2Validate.integer(term.denominator,1,10000): return "parameter_ratio"
		seen.append(term.track_id)
	return ""

static func resolve(base: int, raw: Dictionary, body: Sm2ProgressBodyState, progress: Sm2ProgressCatalog, modifiers: Array[Dictionary]=[]) -> Dictionary:
	var result: Dictionary={"base":base,"bonus":0,"unclamped":base,"total":base,"maximum":int(raw.maximum),"terms":[]}
	var tracks: Dictionary={}
	for row: Dictionary in Sm2ProgressRules.tracks(body,progress,modifiers): tracks[row.id]=row
	for rule: Dictionary in raw.terms:
		var track: Dictionary=tracks[rule.track_id]
		var delta: int=maxi(0,int(track.effective)-int(rule.baseline))
		@warning_ignore("integer_division")
		var amount: int=delta*int(rule.numerator)/int(rule.denominator)
		result.bonus+=amount
		result.terms.append({"track_id":track.id,"name":track.name,"own":track.level,"nodes":track.node_bonus,"effective":track.effective,"sources":track.sources.duplicate(true),"baseline":int(rule.baseline),"numerator":int(rule.numerator),"denominator":int(rule.denominator),"amount":amount})
		if track.has("upgrade_bonus"):
			result.terms.back()["upgrade_bonus"]=track.upgrade_bonus; result.terms.back()["upgrade_sources"]=track.upgrade_sources.duplicate(true)
	result.unclamped=base+int(result.bonus); result.total=mini(int(raw.maximum),int(result.unclamped))
	return result
