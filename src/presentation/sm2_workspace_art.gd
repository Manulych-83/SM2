class_name Sm2WorkspaceArt
extends RefCounted
var art: Sm2BattleArt=Sm2BattleArt.new()
var metadata: Dictionary={}
var icons: Dictionary={}

func prepare() -> void:
	art.load_assets()
	metadata=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/inventory_ui.json"))
	for id: String in metadata.icons: icons[id]=load(metadata.icons[id])

func caption(row: Dictionary) -> String:
	return metadata.captions.get(row.name,row.name)

func icon(row: Dictionary) -> Texture2D:
	var definition: String=row.get("definition_id","")
	if art.equipment.has(definition): return art.sprites.get(art.equipment[definition])
	if row.get("device",false): return art.sprites.get("prosthesis")
	return icons.get(definition,icons.get("parts"))

func actor(view: Dictionary,anatomy: bool) -> Dictionary:
	var value: Dictionary={"side":"company","combat":{"items":[]},"body_functions":{"parts":[]}}
	for part: Dictionary in view.parts:
		value.body_functions.parts.append({"id":part.id,"working":part.working,"prosthesis_id":part.get("device_id","")})
	if not anatomy:
		for row: Dictionary in view.items:
			if int(row.owner)==int(view.body.id) and row.place=="equipped": value.combat.items.append({"slot":row.slot,"definition_id":row.definition_id,"current":row.current})
	return value
