class_name Sm2Controls
extends RefCounted
## One keyboard map supplies both dispatch and captions. Physical keys survive layout changes.
static var bindings: Dictionary=Sm2ControlPreferences.DEFAULT.duplicate()
static var load_ok: bool=true

static func initialize() -> void:
	var result: Dictionary=Sm2ControlPreferences.new().read()
	bindings=result.value.duplicate(); load_ok=result.ok

static func definitions() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/key_bindings.json"))

static func label_for(id: String, values: Dictionary={}) -> String:
	return OS.get_keycode_string(int((bindings if values.is_empty() else values).get(id,0)))

static func action(event: InputEvent) -> String:
	if not event is InputEventKey or not event.pressed or event.echo: return ""
	if event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed: return ""
	var code: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	for id: String in bindings:
		if bindings[id]==code: return id
	return ""

static func text_focused(control: Control) -> bool:
	var focus: Control=control.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

static func back(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode==KEY_ESCAPE or event.keycode==KEY_ESCAPE)) or event.is_action_pressed("ui_cancel",false)

static func caption(id: String, title: String) -> String:
	return title+" ["+label_for(id)+"]"

static func press(owner: Node, id: String) -> bool:
	var button: Button=owner.find_child(id,true,false) as Button
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled: return false
	button.pressed.emit(); return true
