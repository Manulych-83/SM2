extends "res://tests/p3_world_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(1280, 800)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); await _press("Travel_ruins"); await _press("WorldBattle")
	screen = app.find_child("BattleScreen", true, false) as Sm2BattleScreen
	t.expect(screen != null, "production layered profile opens battle")
	if screen == null: _finish(); return
	screen.auto_advance = false
	t.expect(screen.board.art != null, "production opts into illustrated board")
	if screen.board.art == null: _finish(); return
	var session: Sm2JourneySession = screen.life_session as Sm2JourneySession
	var before: String = session.state_hash()
	for dimensions: Vector2i in [Vector2i(1280,800), Vector2i(1000,700)]:
		root.size = dimensions; await _frames()
		for r: int in screen.board.field.height():
			for q: int in screen.board.field.width():
				var cell: Vector2i = Vector2i(q,r)
				t.equal(screen.board.pick(screen.board.center(cell)),cell,"art preserves picking "+str(dimensions))
		await _capture("ruins-%s.png" % dimensions.x)
	t.equal(session.state_hash(), before, "rendering resizing and art loading preserve full world and RNG")
	var art: Sm2BattleArt = screen.board.art
	var actor: Dictionary = screen.state.actors[0].duplicate(true)
	for entry: Dictionary in actor.combat.items:
		t.expect(art.equipment.has(entry.definition_id), "equipped item has presentation mapping")
	for id: String in art.sprites:
		var texture: AtlasTexture = art.sprites[id]
		t.expect(texture.filter_clip, "atlas uses clipped sampling "+id)
		t.expect(texture.get_image().detect_alpha() != Image.ALPHA_NONE, "transparent sprite "+id)
	var equipped: Array[String] = art.layers(actor)
	for entry: Dictionary in actor.get("body_functions", {}).get("parts", []):
		if entry.id == "right_hand": entry.working = false; entry.prosthesis_id = "99"
	t.expect(art.layers(actor).has("prosthesis"), "detached visual fixture shows installed broken device")
	for id: String in ["sword", "spear", "axe", "bow"]: t.expect(not art.layers(actor).has(id), "unusable weapon hidden "+id)
	t.equal(session.state_hash(), before, "editing detached art fixture preserves live world")
	t.expect(equipped.has("human"), "full body layer")
	# Use the production action gateway until an actual enemy attack arrives.
	root.size = Vector2i(1280,800); await _frames()
	for index: int in 90:
		if screen.state.finished or screen.board.motion.cues.any(func(cue: Dictionary) -> bool: return cue.kind in ["attack_hit", "attack_missed"]): break
		screen.board.clear_motion()
		if screen._player_turn(): screen._execute(screen._command("end_turn"))
		else:
			screen._delay = 0; screen.auto_advance = true; screen._process(0.01); screen.auto_advance = false
	t.expect(not screen.board.motion.cues.is_empty(), "real accepted attack schedules visual cue")
	while not screen.board.motion.cues.is_empty() and screen.board.motion.cues[0].kind == "moved": screen.board.motion.advance(screen.board.motion.duration())
	before = session.state_hash()
	screen.board.set_process(false); screen.board.motion.advance(0.18); screen.board.queue_redraw()
	await _capture("attack.png")
	t.equal(session.state_hash(), before, "mid-attack display time does not change simulation")
	screen.board._process(10.0)
	t.expect(screen.board.motion.cues.is_empty(), "long frame drains bounded visual queue")
	t.equal(session.state_hash(), before, "finishing animation does not execute another action")
	await _press("SaveBattleButton"); before = session.state_hash()
	var ids: Array = screen.state.actors
	var fake: Array[Dictionary] = [{"type":"attack_missed", "actor_id": str(ids[0].actor_id), "target_actor_id": str(ids[1].actor_id)}]
	screen.board.play_events(fake); screen.board.set_process(false)
	await _press("LoadBattleButton")
	t.equal(session.state_hash(), before, "load preserves exact world")
	t.expect(screen.board.motion.cues.is_empty(), "load discards old visual events")
	var clock: Sm2BattleMotion = Sm2BattleMotion.new()
	for index: int in 20: clock.play(fake, ids)
	t.equal(clock.cues.size(),8,"visual queue bounded independently of domain history")
	t.expect(not clock.cues[0].hit, "miss remains a miss")
	clock.advance(20); t.expect(clock.cues.is_empty(), "large display delta handles all queued cues")
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("NewBattleButton")
	screen = app.find_child("BattleScreen", true, false) as Sm2BattleScreen; screen.auto_advance = false
	t.expect(screen.board.art == null, "historical battle retains old presentation")
	await _gallery(art, ids[0])
	_finish()

func _gallery(art: Sm2BattleArt, sample: Dictionary) -> void:
	var gallery: Control = Control.new(); gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.add_child(gallery)
	gallery.draw.connect(func() -> void:
		gallery.draw_rect(Rect2(Vector2.ZERO, gallery.size), Color("172425"))
		gallery.draw_string(ThemeDB.fallback_font, Vector2(35, 48), "НАБОР ГРАФИКИ · ДИАГНОСТИЧЕСКИЙ СТЕНД", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("e3bf7b"))
		gallery.draw_string(ThemeDB.fallback_font, Vector2(35, 80), "Примеры сборки внешности; состав игровых встреч не меняется.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("b8c1b7"))
		var names: Array[String] = ["Меч · стёганая броня", "Копьё · кольчуга", "Лук · без доспеха", "Топор · протез", "Мутант · резерв"]
		for index: int in 5:
			var foot: Vector2 = Vector2(138 + index * 245, 560)
			gallery.draw_string(ThemeDB.fallback_font, Vector2(38 + index * 245, 660), names[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e3dfcd"))
			if index == 4: art.stamp(gallery, "mutant", foot, 340); continue
			var actor: Dictionary = sample.duplicate(true); actor.side = "company"
			var items: Array = []
			for entry: Dictionary in actor.combat.items:
				if entry.slot == "head" or entry.slot == "shield": continue
				if entry.slot == "body":
					if index == 2: continue
					entry.definition_id = "m2:equipment.mail" if index == 1 else "m2:equipment.padded"
				if entry.slot == "weapon": entry.definition_id = "m2:equipment." + ["sword","spear","bow","axe"][index]
				items.append(entry)
			actor.combat.items = items
			for part: Dictionary in actor.get("body_functions", {}).get("parts", []):
				part.working = true; part.prosthesis_id = "99" if index == 3 and part.id == "right_hand" else ""
			art.figure(gallery, actor, foot, 320)
	)
	await _capture("assembly-gallery.png")
