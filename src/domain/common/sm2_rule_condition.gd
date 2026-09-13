class_name Sm2RuleCondition
extends RefCounted
## Bounded, read-only predicates over an explicit context. No world traversal or callbacks.
const MAX_NODES: int = 128
const MAX_DEPTH: int = 8
const MAX_NUMBER: int = 8000000000000

static func evaluate(rule: Variant, facts: Dictionary) -> Dictionary:
	return _visit(rule, facts, 0, [0])

static func _visit(rule: Variant, facts: Dictionary, depth: int, budget: Array) -> Dictionary:
	budget[0] += 1
	if depth > MAX_DEPTH or int(budget[0]) > MAX_NODES: return _error("condition_budget")
	if not rule is Dictionary: return _error("condition_shape")
	var kind: String = str(rule.get("kind", ""))
	if kind in ["all", "any"]:
		if not Sm2Validate.fields(rule,["kind","children"]) or not rule.children is Array or rule.children.is_empty() or rule.children.size() > MAX_NODES: return _error("condition_children")
		var matches: bool = kind == "all"
		var reason: String = ""
		for child: Variant in rule.children:
			# Validate every branch, including those which cannot affect the boolean result.
			var checked: Dictionary = _visit(child,facts,depth+1,budget)
			if not checked.valid: return checked
			matches = (matches and checked.matches) if kind == "all" else (matches or checked.matches)
			if not checked.matches and reason.is_empty(): reason = checked.reason
		return _result(matches,reason)
	if kind == "not":
		if not Sm2Validate.fields(rule,["kind","child","reason"]) or not Sm2Validate.text(rule.reason): return _error("condition_not")
		var checked: Dictionary = _visit(rule.child,facts,depth+1,budget)
		return _result(not checked.matches,rule.reason) if checked.valid else checked
	if kind not in ["compare","tag"]: return _error("condition_kind")
	var fields: Array[String] = []
	fields.assign(["kind","fact","op","value","reason"] if kind == "compare" else ["kind","fact","tag","reason"])
	if not Sm2Validate.fields(rule,fields) or not Sm2Validate.text(rule.fact) or not Sm2Validate.text(rule.reason): return _error("condition_fields")
	if not facts.has(rule.fact): return _error("condition_fact_missing")
	var actual: Variant = facts[rule.fact]
	if kind == "tag":
		if not _tag(rule.tag) or not actual is Array or actual.size() > 1000: return _error("condition_tag")
		var found: bool = false
		for tag: Variant in actual:
			if not _tag(tag): return _error("condition_tag")
			found = found or tag == rule.tag or tag.begins_with(rule.tag+".")
		return _result(found,rule.reason)
	if rule.op not in ["eq","ne","lt","lte","gt","gte"]: return _error("condition_operator")
	var expected: Variant = rule.value
	var numeric: bool = Sm2Validate.integer(actual,-MAX_NUMBER,MAX_NUMBER) and Sm2Validate.integer(expected,-MAX_NUMBER,MAX_NUMBER)
	if not numeric:
		if rule.op not in ["eq","ne"]: return _error("condition_value_type")
		if not ((actual is bool and expected is bool) or (Sm2Validate.text(actual,true) and Sm2Validate.text(expected,true))): return _error("condition_value_type")
	var matches: bool = false
	match rule.op:
		"eq": matches = int(actual) == int(expected) if numeric else actual == expected
		"ne": matches = int(actual) != int(expected) if numeric else actual != expected
		"lt": matches = int(actual) < int(expected)
		"lte": matches = int(actual) <= int(expected)
		"gt": matches = int(actual) > int(expected)
		"gte": matches = int(actual) >= int(expected)
	return _result(matches,rule.reason)

static func _tag(value: Variant) -> bool:
	if not Sm2Validate.text(value): return false
	for segment: String in value.split("."):
		if segment.is_empty() or segment != segment.strip_edges(): return false
	return true

static func _result(matches: bool, reason: String) -> Dictionary:
	return {"valid":true,"matches":matches,"reason":"" if matches else reason}

static func _error(reason: String) -> Dictionary:
	return {"valid":false,"matches":false,"reason":reason}
