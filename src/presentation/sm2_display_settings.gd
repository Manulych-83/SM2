class_name Sm2DisplaySettings
extends RefCounted
## Window presentation only; simulation and campaign snapshots never participate.
static func capture(window: Window) -> Dictionary:
	return {"mode":window.mode,"size":window.size,"position":window.position,"borderless":window.borderless,"vsync":DisplayServer.window_get_vsync_mode()}

static func restore(window: Window,snapshot: Dictionary) -> void:
	window.mode=Window.MODE_WINDOWED; window.borderless=snapshot.borderless; window.size=snapshot.size; window.position=snapshot.position; window.mode=snapshot.mode
	DisplayServer.window_set_vsync_mode(snapshot.vsync)

static func apply(window: Window,value: Dictionary) -> void:
	if not Sm2DisplayPreferences.valid(value): return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value.vsync else DisplayServer.VSYNC_DISABLED)
	if value.mode=="fullscreen": window.mode=Window.MODE_EXCLUSIVE_FULLSCREEN; return
	window.mode=Window.MODE_WINDOWED; window.borderless=false
	var requested: Vector2=Vector2(float(str(value.resolution).get_slice("x",0)),float(str(value.resolution).get_slice("x",1)))
	var area: Rect2i=DisplayServer.screen_get_usable_rect(window.current_screen)
	var available: Vector2=Vector2(area.size-Vector2i(32,80))
	var scale: float=minf(1.0,minf(available.x/requested.x,available.y/requested.y))
	window.size=Vector2i(requested*scale).max(window.min_size)
	window.position=area.position+(area.size-window.size)/2
