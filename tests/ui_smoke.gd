extends SceneTree
## Real rendered scene plus actual signal handlers, under isolated APPDATA.

var _harness: Sm2TestHarness = Sm2TestHarness.new()
var _screen: Control
var _output: String = "user://tests/ui"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output":
		_output = args[1]
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(1180, 740)
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_harness.expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	_screen = packed.instantiate() as Control
	root.add_child(_screen)
	await process_frame
	await process_frame
	_harness.expect(_button("NewGameButton") != null, "new game button exists")
	_harness.expect(_button("ContinueButton") != null and _button("ContinueButton").disabled, "clean install has no Continue")
	await _capture("01_menu.png")
	await _press("NewGameButton")
	_harness.expect(_button("SaveButton") != null, "new game opens actual party screen")
	_harness.expect(_contains_label("Страж"), "party displays catalog actor name")
	await _capture("02_party.png")
	await _press("SaveButton")
	_harness.expect(_contains_label("Отряд сохранён. Можно закрыть игру и продолжить позже."), "save succeeds through UI")
	await _press("MenuButton")
	_harness.expect(_button("ContinueButton") != null and not _button("ContinueButton").disabled, "save enables Continue")
	# Recreate the screen and application: continuing must read disk, not old memory.
	root.remove_child(_screen)
	_screen.queue_free()
	await process_frame
	_screen = packed.instantiate() as Control
	root.add_child(_screen)
	await process_frame
	await _press("ContinueButton")
	_harness.expect(_button("SaveButton") != null, "fresh application restores party from disk")
	_harness.expect(_contains_label("Сохранённый отряд восстановлен."), "continue reports success")
	_harness.expect(_contains_label("Страж"), "restored actor visible")
	await _capture("03_restored.png")
	root.size = Vector2i(940, 620)
	await process_frame
	await process_frame
	await _capture("04_minimum.png")
	await _press("MenuButton")
	await _capture("05_minimum_menu.png")
	_finish()

func _press(button_name: String) -> void:
	var button: Button = _button(button_name)
	_harness.expect(button != null and not button.disabled, button_name + " is usable")
	if button!=null and not button.is_visible_in_tree():
		var toggle: Button=_button("OtherModesButton")
		if toggle!=null: toggle.pressed.emit(); await process_frame; await process_frame
	if button != null and not button.disabled:
		button.pressed.emit()
	await process_frame
	await process_frame

func _button(button_name: String) -> Button:
	return _screen.find_child(button_name, true, false) as Button

func _contains_label(text_value: String) -> bool:
	for node: Node in _screen.find_children("*", "Label", true, false):
		if (node as Label).text == text_value:
			return true
	return false

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	for node: Node in _screen.find_children("*", "Control", true, false):
		var parent: Node=node.get_parent(); var clipped: bool=false
		while parent!=null:
			if parent is ScrollContainer: clipped=true; break
			parent=parent.get_parent()
		# Scroll content may extend below its viewport; the viewport itself must fit.
		if not clipped and (node is Label or node is Button or node is ScrollContainer) and (node as Control).is_visible_in_tree():
			_harness.expect(_screen.get_global_rect().encloses((node as Control).get_global_rect()), filename + ": visible control inside screen: " + node.name)
	var picture: Image = root.get_texture().get_image()
	_harness.expect(not picture.is_empty(), filename + ": rendered image exists")
	_harness.equal(picture.save_png(_output.path_join(filename)), OK, filename + ": screenshot saved")

func _finish() -> void:
	var report: Dictionary = {"passed":_harness.failures.is_empty(), "checks":_harness.checks, "failures":_harness.failures}
	var file: FileAccess = FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		push_error("UI report cannot be written")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SM2_UI_REPORT " + JSON.stringify(report))
	quit(0 if report["passed"] else 1)
