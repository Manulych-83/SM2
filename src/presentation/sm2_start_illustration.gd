class_name Sm2StartIllustration
extends Control
## Static decorative composition from the existing atlas; not a live game preview.
var art: Sm2BattleArt=Sm2BattleArt.new()

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE; clip_contents=true
	art.load_assets(); resized.connect(queue_redraw)

func _draw() -> void:
	if art.ground==null: return
	var frame: Rect2=Rect2(Vector2.ZERO,size)
	var atlas_size: Vector2=art.ground.get_size()
	draw_texture_rect_region(art.ground,frame,Rect2(Vector2(0,atlas_size.y*0.5),atlas_size*0.5),Color("64604a"))
	art.stamp(self,"pillar",Vector2(size.x*0.20,size.y*0.78),size.y*0.86,Vector2(0.5,1),Color("a59d81"))
	art.stamp(self,"pillar",Vector2(size.x*0.83,size.y*0.88),size.y*1.05,Vector2(0.5,1),Color("b2a68a"))
	art.stamp(self,"rocks",Vector2(size.x*0.28,size.y*0.93),size.y*0.23)
	var foot: Vector2=Vector2(size.x*0.52,size.y*0.90)
	draw_set_transform(foot,0,Vector2(1,0.24)); draw_circle(Vector2.ZERO,size.y*0.20,Color(0,0,0,0.45)); draw_set_transform(Vector2.ZERO)
	var actor: Dictionary={"side":"company","combat":{"items":[{"slot":"body","definition_id":"m2:equipment.mail"},{"slot":"weapon","definition_id":"m2:equipment.sword"}]},"body_functions":{"parts":[]}}
	art.figure(self,actor,foot,size.y*0.84)
	art.stamp(self,"grass",Vector2(size.x*0.14,size.y*1.04),size.y*0.30,Vector2(0.5,1),Color("a69d72"))
	art.stamp(self,"grass",Vector2(size.x*0.92,size.y*1.03),size.y*0.32,Vector2(0.5,1),Color("9c966e"))
