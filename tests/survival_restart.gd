extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var t: Sm2TestHarness=Sm2TestHarness.new()
	var content: Dictionary=Sm2SurvivalContentLoader.load_scenario()
	var profile: Sm2AiProfile=Sm2AiContentLoader.load_profile().profile
	var store: Sm2SaveStore=Sm2SaveStore.new("user://survival_journey")
	var expected: Dictionary=store.load_slot("survival_journey")
	t.expect(expected.ok,"read UI save from earlier process")
	if not expected.ok: print("SURVIVAL_RESTART_FAILED"); quit(1); return
	var session: Sm2JourneySession=Sm2JourneySession.new(content,profile,store)
	t.expect(session.load_game().ok,"new process loads UI save")
	t.equal(Sm2Canonical.hash(session.capture()),Sm2Canonical.hash(expected.payload),"fresh process exact snapshot without tick")
	var control: Sm2JourneySession=Sm2JourneySession.new(content,profile,store)
	t.expect(control.restore(expected.payload).ok,"independent control restored")
	if session.world.busy():
		var decision: Dictionary=session.runner._session.ai_decision(profile)
		t.expect(decision.ok,"deterministic next command available")
		if decision.ok:
			var a: Sm2CommandResult=session.attack(decision.command)
			var b: Sm2CommandResult=control.attack(decision.command)
			t.equal(a.accepted,b.accepted,"same next command outcome")
			t.expect(a.accepted,"next command accepted")
			t.equal(session.state_hash(),control.state_hash(),"same next state including RNG and wounds")
	else:
		t.equal(session.world.hero_id(),8,"new incarnation persisted")
		t.equal(session.journey().survival.bodies["8"].blood,5000,"new body healthy on restart")
	print("SURVIVAL_RESTART "+JSON.stringify({"passed":t.failures.is_empty(),"checks":t.checks,"failures":t.failures}))
	quit(0 if t.failures.is_empty() else 1)
