extends Control
var art: Sm2BattleArt
var actor: Dictionary
var anatomy_mode: bool=false
func _draw() -> void:
	if art==null: return
	draw_ellipse_shadow()
	art.figure(self,actor,Vector2(size.x/2,size.y-24),size.y-52)
	if anatomy_mode:
		var at: Vector2=Vector2(size.x*0.29,size.y*0.53)
		draw_arc(at,30,0,TAU,64,Sm2BronzeTheme.PSI,2,true)
		draw_circle(at,30,Color(0.3,0.7,0.8,0.1))
func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(size.x/2,size.y-17),0,Vector2(1,0.25))
	draw_circle(Vector2.ZERO,100,Color(0,0,0,0.24)); draw_set_transform(Vector2.ZERO)
