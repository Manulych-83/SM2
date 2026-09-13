class_name Sm2CampScene
extends Control
## Composes visual layers from detached state. Does not own or advance world time.
var model: Dictionary={}
var manifest: Dictionary={}
var art: Sm2BattleArt=Sm2BattleArt.new()
var background: TextureRect
var figure: Control
var fire: TextureRect

func _ready() -> void:
	name="CampScene"; mouse_filter=Control.MOUSE_FILTER_IGNORE; clip_contents=true
	art.load_assets()
	background=TextureRect.new(); background.name="CampBackground"
	var definition: Dictionary=manifest.backgrounds.get(model.location,manifest.backgrounds.camp)
	var texture: Texture2D=load(definition.path)
	if definition.has("region"):
		var part: Array=definition.region; var atlas: AtlasTexture=AtlasTexture.new(); atlas.atlas=texture
		atlas.region=Rect2(Vector2(part[0],part[1])*texture.get_size(),Vector2(part[2],part[3])*texture.get_size()); texture=atlas
	background.texture=texture; background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(background); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for row: Dictionary in model.objects:
		if manifest.objects.has(row.visual): _prop(manifest.objects[row.visual],"CampObject_"+str(row.id))
	figure=Control.new(); figure.name="CampHeroFigure"; figure.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(figure)
	figure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); figure.draw.connect(_draw_hero)
	if not model.hero.is_empty(): fire=_prop(manifest.fire,"CampFire")
	resized.connect(func() -> void: figure.queue_redraw())

func _prop(definition: Dictionary,id: String) -> TextureRect:
	var node: TextureRect=TextureRect.new(); node.name=id; node.texture=load(definition.path)
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(node); var rect: Array=definition.rect
	node.anchor_left=rect[0]; node.anchor_top=rect[1]; node.anchor_right=rect[0]+rect[2]; node.anchor_bottom=rect[1]+rect[3]
	return node

func _draw_hero() -> void:
	if model.hero.is_empty(): return
	var foot: Vector2=Vector2(manifest.hero.foot[0],manifest.hero.foot[1])*size
	var height: float=size.y*float(manifest.hero.height)
	figure.draw_set_transform(foot,0,Vector2(1,0.20)); figure.draw_circle(Vector2.ZERO,height*0.22,Color(0,0,0,0.35)); figure.draw_set_transform(Vector2.ZERO)
	art.figure(figure,model.hero,foot,height,Color("eddfcb"))
