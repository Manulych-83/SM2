extends "res://tests/m3_ui.gd"
## Real menu mouse routing, explicit adjacent fixture for a visible enemy spell.
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,800)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await _frames()
	var modern: Sm2AiProfile = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH).profile
	var legacy: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	await _press("NewMagicButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.capture().profile,modern.fingerprint(),"new magic battle selects ability policy")
	var content: Dictionary = Sm2MagicContentLoader.load_scenario()
	t.expect(screen.runner.new_battle(Sm2CombatFixtures.setup(content,[6,2],1231)).ok,"explicit enemy caster fixture")
	var payload: Dictionary = screen.runner.capture()
	Sm2CombatFixtures.item(Sm2CombatFixtures.actor(payload.session.battle,6),"weapon").ammo = 0
	t.expect(screen.runner.restore(payload).ok,"empty enemy bow fixture validates")
	screen._refresh()
	t.expect(not screen._player_turn(),"enemy owns current activation")
	var previous_hp: int = int(screen._actor(2).combat.hp)
	screen.auto_advance = true
	screen._delay = 0.0
	screen._process(0.01)
	screen.auto_advance = false
	t.equal(screen._actor(6).mana,16,"UI enemy pays spell mana")
	t.equal(screen._actor(2).combat.hp,previous_hp-13,"UI enemy spell uses 25 percent resistance")
	t.expect(screen._log.text.contains("Магическая стрела"),"enemy spell appears in journal")
	t.expect(screen.runner.error_reason().is_empty(),"enemy UI step has no error")
	await _capture("enemy-spell.png")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _press("BattleMenuButton")
	await _press("ContinueMagicButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),saved,"menu restores modern profile and exact state")
	await _press("BattleMenuButton")
	# Historical profile remains selected for old saves, without migration.
	for magic: bool in [true,false]:
		var store: Sm2SaveStore = Sm2SaveStore.new("user://magic" if magic else "user://effects")
		var old: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog,content.combat,legacy,store,false,content.effects,content.magic if magic else null)
		t.expect(old.new_battle(content.setup).ok and old.save_game().ok,"create isolated historical save")
		app._redraw_page()
		await _frames()
		await _press("ContinueMagicButton" if magic else "ContinueEffectsButton")
		screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
		screen.auto_advance = false
		t.equal(screen.runner.capture().profile,legacy.fingerprint(),"historical AI profile preserved")
		t.equal(screen.runner.capture(),old.capture(),"old save loaded without state or format changes")
		await _press("BattleMenuButton")
	await _press("NewEffectsButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.capture().profile,modern.fingerprint(),"new effects battle selects ability policy")
	await _press("BattleMenuButton")
	# A checksum-valid but unknown AI version is rejected without publishing it.
	var store: Sm2SaveStore = Sm2SaveStore.new("user://magic")
	var unknown: Dictionary = store.load_slot(Sm2BattleRunner.MAGIC_SLOT).payload
	unknown.profile = "unavailable-policy"
	t.expect(store.save_slot(unknown,Sm2BattleRunner.MAGIC_SLOT).ok,"write isolated unknown-policy fixture")
	var previous: Sm2BattleRunner = app._battle
	var file_before: Dictionary = store.load_slot(Sm2BattleRunner.MAGIC_SLOT)
	await _press("ContinueMagicButton")
	t.equal(app._page,"menu","unknown policy stays in menu")
	t.expect(app._is_error and app._battle == previous,"failed load preserves running battle")
	t.equal(store.load_slot(Sm2BattleRunner.MAGIC_SLOT),file_before,"failed load never rewrites old save")
	await _capture("unknown-policy.png")
	_finish()
