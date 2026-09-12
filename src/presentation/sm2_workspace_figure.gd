class_name Sm2WorkspaceFigure
extends Control
var artwork: Sm2WorkspaceArt
var view: Dictionary={}
var anatomy: bool=false
var selected: String=""

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE; resized.connect(queue_redraw)

func _draw() -> void:
	if artwork==null or view.get("body",{}).is_empty(): return
	var height: float=minf(size.y-40,size.x*1.8)
	var foot: Vector2=Vector2(size.x/2,size.y-16)
	draw_set_transform(foot,0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,height*0.23,Color(0,0,0,0.25)); draw_set_transform(Vector2.ZERO)
	var tint: Color=Color.WHITE if view.body.alive else Color("858477")
	artwork.art.figure(self,artwork.actor(view,anatomy),foot,height,tint)
	if not anatomy: return
	for part: Dictionary in view.parts:
		if part.id!=selected or not artwork.metadata.parts.has(part.id): continue
		var coordinates: Array=artwork.metadata.parts[part.id]
		var point: Vector2=foot+Vector2((float(coordinates[0])-0.5)*height*0.52,(float(coordinates[1])-1)*height)
		var color: Color=Sm2SurvivalWorkspace.DANGER if part.damaged or not part.working else Sm2BronzeTheme.PSI
		draw_arc(point,20,0,TAU,40,color,2,true)
