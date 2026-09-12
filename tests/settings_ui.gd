extends "res://tests/display_ui.gd"
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	var prefs: Sm2DisplayPreferences=Sm2DisplayPreferences.new()
	t.expect(prefs.read().ok and not prefs.read().exists,"new runtime has default preferences without disk write")
	t.expect(not prefs.write({"mode":"windowed","resolution":"1x1","vsync":true}),"reject unsupported resolution")
	t.expect(not prefs.write({"mode":"windowed","resolution":"1280x720","vsync":1}),"reject nonboolean vsync")
	var invalid: ConfigFile=ConfigFile.new(); invalid.set_value("display","version",1); invalid.save(prefs.path)
	t.expect(not prefs.read().ok,"incomplete preferences safely rejected")
	DirAccess.remove_absolute(prefs.path)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("SettingsButton")
	var settings: Sm2SettingsScreen=app.find_child("SettingsScreen",true,false) as Sm2SettingsScreen
	t.expect(settings!=null and settings.resolution.disabled,"fullscreen disables window-only size selector")
	await _capture("settings-2560-1440.png")
	var original: Dictionary=Sm2DisplaySettings.capture(root)
	settings.mode.select(1); settings.mode.item_selected.emit(1)
	settings.resolution.select(2); settings.resolution.item_selected.emit(2)
	settings.vsync.button_pressed=false
	t.equal(Sm2DisplaySettings.capture(root),original,"editing options does not change display")
	await _press("SettingsApply"); await _frames()
	t.expect(settings.pending,"display confirmation active")
	t.equal(root.mode,Window.MODE_WINDOWED,"preview switches to windowed")
	t.equal(root.size,Vector2i(1280,720),"preview uses selected client size")
	t.equal(DisplayServer.window_get_vsync_mode(),DisplayServer.VSYNC_DISABLED,"preview changes vsync")
	t.expect(not prefs.read().exists,"preview does not persist")
	await _key(KEY_ESCAPE); await _frames()
	t.expect(not settings.pending,"Escape cancels preview")
	t.equal(Sm2DisplaySettings.capture(root),original,"cancel restores mode size position border and vsync")
	await _press("SettingsApply"); await _press("SettingsRevert"); await _frames()
	t.equal(Sm2DisplaySettings.capture(root),original,"explicit revert restores exact display")
	await _press("SettingsApply"); await settings.timer.timeout; await _frames()
	t.expect(not settings.pending,"real fifteen-second timeout cancels preview")
	t.equal(Sm2DisplaySettings.capture(root),original,"timeout restores exact display")
	await _press("SettingsApply"); await _press("SettingsKeep")
	t.expect(prefs.read().ok and prefs.read().exists,"confirmed preference persisted")
	t.equal(prefs.read().value,{"mode":"windowed","resolution":"1280x720","vsync":false},"saved values exact")
	await _capture("settings-window-1280.png")
	await _press("SettingsBack"); await _press("NewSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var session: Sm2JourneySession=life.session as Sm2JourneySession; var before: String=session.state_hash()
	await _press("CampSettings"); settings=app.find_child("SettingsScreen",true,false) as Sm2SettingsScreen
	t.equal(settings.draft,prefs.read().value,"settings reopen saved values")
	await _press("SettingsDefaults")
	t.equal(settings.draft,Sm2DisplayPreferences.DEFAULT,"default button prepares base QHD profile")
	t.equal(root.mode,Window.MODE_WINDOWED,"default button requires applying")
	await _press("SettingsApply"); await _press("SettingsKeep")
	t.equal(root.mode,Window.MODE_EXCLUSIVE_FULLSCREEN,"confirmed defaults restore fullscreen")
	t.equal(root.content_scale_size,Vector2i(2560,1440),"QHD composition unchanged")
	t.expect(is_equal_approx(root.content_scale_factor,1.6),"design scale unchanged")
	await _press("SettingsBack")
	t.expect(app._life==session and session.state_hash()==before,"settings return same unmodified campaign")
	await _press("CampSettings"); settings=app.find_child("SettingsScreen",true,false) as Sm2SettingsScreen
	settings.mode.select(1); settings.mode.item_selected.emit(1); settings.resolution.select(1); settings.resolution.item_selected.emit(1)
	await _press("SettingsApply"); await _press("SettingsKeep"); await _press("SettingsBack")
	before=session.state_hash(); t.expect(session.save_game().ok,"campaign save remains separate")
	# A new Main instance models application startup, with the same user preference file.
	root.remove_child(app); app.queue_free(); await _frames()
	root.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	t.equal(root.mode,Window.MODE_WINDOWED,"startup applies saved window mode")
	t.equal(root.size,Vector2i(1920,1080),"startup applies saved resolution")
	await _press("ContinueSurvivalTissuesButton"); t.equal(app._life.state_hash(),before,"campaign reload independent of display preferences")
	await _press("CampSettings"); settings=app.find_child("SettingsScreen",true,false) as Sm2SettingsScreen
	var bad_store: Sm2DisplayPreferences=Sm2DisplayPreferences.new(); bad_store.path="user://missing-directory/settings.cfg"; settings.preferences=bad_store
	settings.draft=Sm2DisplayPreferences.DEFAULT.duplicate(); settings.synchronize(); original=Sm2DisplaySettings.capture(root)
	await _press("SettingsApply"); await _press("SettingsKeep"); await _frames()
	t.equal(Sm2DisplaySettings.capture(root),original,"write failure restores previous display")
	t.expect(settings.notice.text.contains("Не удалось"),"write failure explained")
	settings.preferences=prefs
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions); await _capture("settings-%s-%s.png" % [dimensions.x,dimensions.y])
	t.equal(app._life.state_hash(),before,"display changes never modify campaign")
	_finish()
