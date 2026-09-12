class_name Sm2BattleArt
extends RefCounted
## Presentation-only atlas and attachment data. Never enters a save or a rules fingerprint.
const MANIFEST: String = "res://content/presentation/battle_art.json"
var sprites: Dictionary = {}
var ground: Texture2D
var attachments: Dictionary = {}
var equipment: Dictionary = {}
var error: String = ""

func load_assets() -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not raw is Dictionary or raw.get("version") != "sm2.battle_art.1": return _fail("manifest")
	var atlas: Texture2D = load(str(raw.get("atlas", ""))) as Texture2D
	ground = load(str(raw.get("ground", ""))) as Texture2D
	if atlas == null or ground == null: return _fail("texture")
	var prepared: Dictionary = {}
	for id: String in raw.get("sprites", {}):
		var values: Variant = raw.sprites[id]
		if not values is Array or values.size() != 4: return _fail("region")
		for value: Variant in values:
			if not value is float and not value is int: return _fail("region_number")
		var region: Rect2 = Rect2(values[0], values[1], values[2], values[3])
		if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region): return _fail("region_bounds")
		var texture: AtlasTexture = AtlasTexture.new()
		texture.atlas = atlas; texture.region = region; texture.filter_clip = true
		prepared[id] = texture
	for id: String in ["human", "mutant", "head_hair", "head_beard", "pillar", "rocks", "grass", "prosthesis", "grip"]:
		if not prepared.has(id): return _fail("missing_sprite")
	for id: String in raw.get("attachments", {}):
		var entry: Variant = raw.attachments[id]
		if not prepared.has(id) or not entry is Dictionary: return _fail("attachment")
		if not entry.get("height") is float or entry.height <= 0.0 or entry.height > 2.0: return _fail("height")
		for key: String in ["point", "anchor"]:
			if not entry.get(key) is Array or entry[key].size() != 2: return _fail("anchor")
			for number: Variant in entry[key]:
				if not number is float and not number is int: return _fail("anchor_number")
	for id: String in raw.get("equipment", {}):
		if not raw.attachments.has(raw.equipment[id]): return _fail("equipment")
	sprites = prepared; attachments = raw.attachments.duplicate(true); equipment = raw.equipment.duplicate(true)
	return true

func _fail(reason: String) -> bool:
	error = reason; sprites.clear(); return false

func part(actor: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in actor.get("body_functions", {}).get("parts", []):
		if entry.id == id: return entry
	return {}

func layers(actor: Dictionary) -> Array[String]:
	var result: Array[String] = ["human"]
	for slot: String in ["body", "head"]:
		var item: Dictionary = Sm2BattleText.item(actor, slot)
		var sprite: String = equipment.get(item.get("definition_id", ""), "")
		if not sprite.is_empty(): result.append(sprite)
	var hand: Dictionary = part(actor, "right_hand")
	if not str(hand.get("prosthesis_id", "")).is_empty(): result.append("prosthesis")
	for slot: String in ["weapon", "shield"]:
		var item: Dictionary = Sm2BattleText.item(actor, slot)
		var sprite: String = equipment.get(item.get("definition_id", ""), "")
		if not part(actor, "right_hand" if slot == "weapon" else "left_hand").get("working", true): continue
		if slot == "shield" and int(item.get("current", 0)) <= 0: continue
		if not sprite.is_empty(): result.append(sprite)
	# A foreground hand overlaps the grip, keeping the item attached to the pose.
	if part(actor, "right_hand").get("working", true) and not Sm2BattleText.item(actor, "weapon").is_empty():
		if str(hand.get("prosthesis_id", "")).is_empty(): result.append("grip")
	return result

func stamp(canvas: CanvasItem, id: String, point: Vector2, height: float, anchor: Vector2 = Vector2(0.5, 1.0), tint: Color = Color.WHITE) -> void:
	if not sprites.has(id): return
	var texture: Texture2D = sprites[id]
	var dimensions: Vector2 = texture.get_size() * (height / texture.get_height())
	var position: Vector2 = point - dimensions * anchor
	canvas.draw_texture_rect(texture, Rect2(position, dimensions), false, tint)

func figure(canvas: CanvasItem, actor: Dictionary, foot: Vector2, height: float, tint: Color = Color.WHITE) -> void:
	var flip: bool = actor.side != "company"
	canvas.draw_set_transform(foot, 0, Vector2(-1 if flip else 1, 1))
	for id: String in layers(actor):
		if id == "human": stamp(canvas, id, Vector2.ZERO, height, Vector2(0.5, 1), tint); continue
		var entry: Dictionary = attachments[id]
		var shift: Vector2 = Vector2(entry.point[0], entry.point[1]) * height
		var color: Color = tint
		if id == "prosthesis" and not part(actor, "right_hand").get("working", true): color = color.darkened(0.5)
		stamp(canvas, id, shift, height * float(entry.height), Vector2(entry.anchor[0], entry.anchor[1]), color)
	canvas.draw_set_transform(Vector2.ZERO)

func tile(canvas: CanvasItem, points: PackedVector2Array, center: Vector2, radius: float, material: int, shade: Color) -> void:
	var uv: PackedVector2Array = []
	var origin: Vector2 = Vector2(material % 2, material / 2) * 0.5
	for point: Vector2 in points: uv.append(origin + (point - center + Vector2.ONE * radius) / (radius * 4.0))
	canvas.draw_polygon(points, PackedColorArray([shade]), uv, ground)
