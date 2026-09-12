extends "res://tests/battle_art_ui.gd"
const SHIELD_TEST = preload("res://tests/scenarios/test_p5_shield.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(1280,800)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton")
	life = app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession = life.session as Sm2JourneySession
	SHIELD_TEST.learn(s,t); life.redraw(); await _frames()
	await _press("Travel_ruins"); await _press("WorldBattle")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance = false
	var art: Sm2BattleArt = screen.board.art
	t.expect(art != null, "production feedback enabled")
	if art == null: _finish(); return
	await _press("SaveBattleButton")
	var original: String = s.state_hash()
	var actor: Dictionary = screen._actor(1).duplicate(true)
	var start: Vector2i = Vector2i(int(actor.q),int(actor.r))
	var destination: Vector2i = Vector2i(2,1)
	# Real click commits the logical move once; the figure follows with local interpolation.
	await _cell(destination,false); screen.board.set_process(false)
	t.equal(Vector2i(int(screen._actor(1).q),int(screen._actor(1).r)),destination,"mouse commits exact logical destination")
	t.expect(not screen.board.motion.cues.is_empty() and screen.board.motion.cues[0].kind == "moved", "move event animates")
	var moved: String = s.state_hash()
	screen.board.motion.elapsed = Sm2BattleMotion.MOVE_DURATION / 2; screen.board.queue_redraw()
	var expected: Vector2 = screen.board.center(start).lerp(screen.board.center(destination),0.5)
	t.expect(screen.board.displayed_center(screen._actor(1)).distance_to(expected) < 0.01, "halfway displayed position follows committed segment")
	t.equal(screen.board.pick(screen.board.center(destination)),destination,"picking stays on logical hexes during motion")
	await _capture("moving-1280.png")
	t.equal(s.state_hash(),moved,"display frames never spend more AP or change world")
	await _press("LoadBattleButton")
	t.equal(s.state_hash(),original,"load during move restores exact world")
	t.expect(screen.board.motion.cues.is_empty(),"load clears move")
	# Actual shield learned with practice; no direct editing of combat state.
	await _press("Ability_shield"); screen.board.set_process(false)
	t.equal(screen._actor(1).barrier.remaining,18,"real cast supplies barrier view")
	t.equal(screen.board.motion.cues[0].kind,"barrier_cast","shield event creates expansion effect")
	screen.board.motion.elapsed = 0.19; screen.board.queue_redraw()
	var protected_hash: String = s.state_hash()
	await _capture("shield-1280.png")
	t.equal(s.state_hash(),protected_hash,"shield drawing cannot regenerate protection")
	screen.board.clear_motion(); await _press("SaveBattleButton"); await _press("LoadBattleButton")
	t.equal(s.state_hash(),protected_hash,"shield and concentration exact roundtrip")
	t.equal(screen._actor(1).barrier.remaining,18,"loaded shield visible from snapshot without cast event")
	t.expect(screen.board.motion.cues.is_empty(),"loading shield does not replay casting")
	root.size = Vector2i(1000,700); await _frames(); await _capture("shield-loaded-1000.png")
	root.size = Vector2i(1280,800); await _frames()
	await _press("Ability_impulse"); await _cell(Vector2i(4,1),false); screen.board.set_process(false)
	t.expect(not screen.board.motion.cues.is_empty() and screen.board.motion.cues[0].kind == "spell_cast", "real impulse creates distinct visual cue")
	t.equal(screen._actor(1).mana,0,"real impulse spends remaining focus")
	screen.board.motion.elapsed = 0.14; screen.board.queue_redraw(); var impulse_hash: String = s.state_hash()
	await _capture("impulse-1280.png")
	screen.board._process(4)
	t.equal(s.state_hash(),impulse_hash,"finishing impulse changes no damage or RNG")
	# Advance real enemy actions and rounds; the barrier view follows expiry or exhaustion.
	for index: int in 100:
		if screen.state.finished or screen._actor(1).get("barrier",{}).is_empty(): break
		if screen._player_turn(): screen._execute(screen._command("end_turn"))
		else: screen._delay=0; screen.auto_advance=true; screen._process(0.01); screen.auto_advance=false
		screen.board.clear_motion()
	t.expect(screen._actor(1).get("barrier",{}).is_empty(),"actual battle removes depleted or expired shield")
	await _capture("shield-ended.png")
	_motion_contracts(screen.state.actors)
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("NewBattleButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance = false
	await _fixture()
	t.expect(screen.board.enable_art(), "diagnostic reaction fixture uses same renderer")
	await _cell(Vector2i(0,4),false); screen.board.set_process(false)
	t.equal([screen._actor(2).q,screen._actor(2).r],[1,2],"real reaction interrupts departure at origin")
	t.expect(screen.board.motion.cues.any(func(cue: Dictionary) -> bool: return cue.kind == "attack_hit"),"real reaction hit still has visual feedback")
	t.expect(not screen.board.motion.cues.any(func(cue: Dictionary) -> bool: return cue.kind == "moved"),"real interrupted departure has no false slide")
	var reaction_hash: String = screen.runner.state_hash(); screen.board._process(5)
	t.equal(screen.runner.state_hash(),reaction_hash,"reaction display cannot complete interrupted move")
	await _gallery(art,actor)
	_finish()

func _motion_contracts(actors: Array) -> void:
	var id: int = int(actors[0].actor_id)
	var clock: Sm2BattleMotion = Sm2BattleMotion.new()
	var moves: Array[Dictionary] = [{"type":"moved","actor_id":str(id),"from_q":1,"from_r":1,"q":2,"r":1},{"type":"moved","actor_id":str(id),"from_q":2,"from_r":1,"q":3,"r":1}]
	clock.play(moves,actors)
	t.equal(clock.segment(id,Vector2i(3,1)).from,Vector2i(1,1),"fast queued commands do not teleport display to final destination")
	clock.advance(Sm2BattleMotion.MOVE_DURATION)
	t.equal(clock.segment(id,Vector2i(3,1)).from,Vector2i(2,1),"second segment begins where first ends")
	clock.advance(100)
	t.equal(clock.segment(id,Vector2i(3,1)).to,Vector2i(3,1),"large frame settles to committed state")
	clock.play(moves,actors); clock.clear()
	t.equal(clock.segment(id,Vector2i(1,1)).to,Vector2i(1,1),"clear snaps to restored state")
	var interrupted: Array[Dictionary] = [{"type":"movement_interrupted","actor_id":str(id)}]
	clock.play(interrupted,actors); t.expect(clock.cues.is_empty(),"interrupted departure never invents successful movement")
	# Event order: the attack following a move must start at the new cell.
	var batch: Array[Dictionary] = [moves[0],{"type":"attack_hit","actor_id":str(id),"target_actor_id":str(actors[1].actor_id)}]
	clock.play(batch,actors); t.equal(clock.cues[1].from,Vector2i(2,1),"move and attack in same batch retain event order")
	var slow: Sm2BattleMotion = Sm2BattleMotion.new(); var fast: Sm2BattleMotion = Sm2BattleMotion.new()
	slow.play(moves,actors); fast.play(moves,actors)
	for index: int in 19: slow.advance(0.01)
	fast.advance(0.19)
	t.expect(absf(slow.segment(id,Vector2i(3,1)).blend-fast.segment(id,Vector2i(3,1)).blend)<0.0001,"frame subdivision preserves display progress")
