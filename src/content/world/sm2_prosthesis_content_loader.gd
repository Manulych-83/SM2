class_name Sm2ProsthesisContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2BodyContentLoader.load_scenario()
	if not base.ok: return base
	var functions: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/prosthesis_functions.json"))
	var attacks: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/prosthesis_attacks.json"))
	if not functions is Dictionary or not attacks is Array: return {"ok":false,"errors":PackedStringArray(["body_content_file"])}
	var raw: Dictionary=base.combat.to_data()
	var rules: Dictionary=base.development.to_data()
	for attack: Variant in attacks:
		if not attack is Dictionary or not attack.get("id") is String: return {"ok":false,"errors":PackedStringArray(["body_attack_entry"])}
		raw.abilities.append(attack.duplicate(true))
		for gear: Dictionary in raw.equipment:
			if gear.id=="m2:equipment.sword": gear.abilities.append(attack.id)
		rules.awards[attack.id]=rules.awards["m2:ability.sword_strike"].duplicate(true)
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new()
	var errors: PackedStringArray=combat.build(raw,base.catalog)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	rules.version=Sm2DevelopmentCatalog.PROSTHESIS_VERSION; rules["body_functions"]=functions
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=development.build(rules,base.development.progression(),combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.combat=combat; base.development=development
	base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,development.fingerprint(),combat.fingerprint()])
	return base
