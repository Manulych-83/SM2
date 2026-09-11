class_name Sm2AbilityParameterText
extends RefCounted
## Shared explanation of an already calculated parameter; no combat rules here.
static func describe(value: Dictionary, title: String="Урон", unit: String="HP", gain: String="урона") -> String:
	var lines: Array[String]=["%s: %s (основа) + %s (развитие) = %s %s." % [title,value.base,value.bonus,value.total,unit]]
	for term: Dictionary in value.terms:
		var contributions: Array[String]=[]
		for source: Dictionary in term.sources: contributions.append("%s %s → +%s" % [source.name,source.source_value,source.amount])
		lines.append("%s: свой %s, узлы +%s, с прибавками %s." % [term.name,term.own,term.nodes,term.effective])
		for source: Dictionary in term.get("upgrade_sources",[]): lines.append("%s: +%s (улучшение тела)." % [source.name,source.amount])
		if not contributions.is_empty(): lines.append("; ".join(contributions)+".")
		lines.append("Рост выше %s: ×%s/%s, вниз → +%s %s." % [term.baseline,term.numerator,term.denominator,term.amount,gain])
	if value.unclamped!=value.total: lines.append("Действует предел параметра: %s." % value.maximum)
	return "\n".join(lines)
