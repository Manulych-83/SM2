extends RefCounted
const TISSUES: GDScript=preload("res://tests/scenarios/test_survival_tissues.gd")
const BODY: GDScript=preload("res://tests/scenarios/test_p4_body.gd")

static func started(t: Sm2TestHarness,injury: bool=false) -> Sm2JourneySession:
	var session: Sm2JourneySession=TISSUES.make(TISSUES.content(injury))
	t.expect(session.new_game().ok,"result fixture starts")
	t.expect(Sm2BattleResultsView.build(session).is_empty(),"no invented result before a battle")
	t.expect(session.act(session.command("practice",2,"p5:activity.psionics")).ok,"prebattle practice exists outside the reward window")
	t.expect(session.act(session.command("travel",0,"ruins")).ok,"travel to encounter")
	t.expect(session.act(session.command("start_battle")).ok,"actual encounter starts")
	t.expect(Sm2BattleResultsView.build(session).is_empty(),"running battle has no settled summary")
	return session

static func step(session: Sm2JourneySession,injury: bool=false) -> Dictionary:
	if injury: return BODY.treatment_step(session)
	var v: Dictionary=session.runner.view()
	for actor: Dictionary in v.actors:
		if actor.actor_id==v.active_actor_id and actor.controller=="player" and actor.morale!="fleeing":
			var choice: Dictionary=session.runner._session.ai_decision(session._profile)
			if not choice.ok: return choice
			var result: Sm2CommandResult=session.attack(choice.command)
			return {"ok":result.accepted}
	return session.step()

static func finish(t: Sm2TestHarness,session: Sm2JourneySession,injury: bool=false) -> void:
	for index: int in 500:
		if not session.world.busy(): break
		var result: Dictionary=step(session,injury); t.expect(result.ok,"real action settles result")
		if not result.ok: break
	t.expect(not session.world.busy(),"battle reaches committed outcome")

static func run(t: Sm2TestHarness) -> void:
	for injury: bool in [false,true]:
		var session: Sm2JourneySession=started(t,injury); finish(t,session,injury)
		var before: String=session.state_hash(); var data: Dictionary=Sm2BattleResultsView.build(session)
		t.expect(not data.is_empty(),"committed result available")
		if data.is_empty(): continue
		t.equal(session.state_hash(),before,"summary cannot change resources, XP, RNG or history")
		t.equal(data.party.size(),2,"hero and companion have separate summaries")
		t.equal(data.party[1].practice[0].title,"Общий опыт","companion retains simple progression")
		var raw: Dictionary=session.runner.capture().session.battle.development
		for row: Dictionary in data.party:
			var previous: Dictionary={}; var after: Dictionary={}
			for entry: Dictionary in raw.origin.members:
				if int(entry.body.id)==row.body_id: previous=entry.body
			for entry: Dictionary in raw.members:
				if int(entry.body.id)==row.body_id: after=entry.body
			var actual: int=0
			for reward: Dictionary in row.practice: actual+=int(reward.xp)
			var expected: int=0
			if previous.has("growth"): expected=int(after.growth.earned_total)-int(previous.growth.earned_total)
			else:
				for track: Dictionary in after.tracks:
					for old: Dictionary in previous.tracks:
						if track.track_id==old.track_id: expected+=int(track.earned_total)-int(old.earned_total)
			t.equal(actual,expected,"reported XP is actual battle delta, excluding prior practice")
			var body: Sm2Anatomy=session.journey().survival.bodies[str(row.body_id)]
			t.equal(row.blood,body.blood,"blood matches settled anatomy")
			t.equal(row.bleeding,body.rate(),"bleeding matches settled wounds")
		if injury: t.expect(data.title.contains("отступил"),"retreat has explicit outcome")
		var frozen: Array=data.party.duplicate(true)
		data.party[0].blood=-10; data.counts.company.dead=100
		t.equal(session.state_hash(),before,"detached summary cannot edit world")
		t.equal(Sm2BattleResultsView.build(session).party,frozen,"new query restores frozen facts")
		t.expect(session.save_game().ok and session.load_game().ok,"result survives normal save/load")
		t.equal(Sm2BattleResultsView.build(session).party,frozen,"restored result facts exact")
		t.equal(session.state_hash(),before,"load never repeats rewards")
		if session.world.hero_id()!=0:
			TISSUES.bandage_all(t,session)
			t.equal(Sm2BattleResultsView.build(session).party,frozen,"later bandaging cannot rewrite end-of-battle wounds")
			t.expect(session.act(session.command("travel",0,"camp")).ok,"move after battle")
			t.expect(session.act(session.command("practice",session.world.hero_id(),"p5:activity.psionics")).ok,"additional practice after battle")
			t.equal(Sm2BattleResultsView.build(session).party,frozen,"later practice cannot inflate past battle rewards")
			t.expect(session.act(session.command("end_life")).ok,"end first incarnation after encounter")
			t.equal(Sm2BattleResultsView.build(session).party,frozen,"Soul transition cannot rewrite past participants")
	var fatal: Sm2JourneySession=started(t,false)
	for index: int in 200:
		if not fatal.world.busy(): break
		var view: Dictionary=fatal.runner.view(); var player: bool=false
		for actor: Dictionary in view.actors:
			if actor.actor_id==view.active_actor_id and actor.controller=="player" and actor.morale!="fleeing": player=true
		if player:
			var command: Sm2Command=Sm2Command.new(); command.kind="end_turn"; command.actor_id=int(view.active_actor_id); command.expected_revision=int(view.revision); command.battle_id=view.battle_id
			t.expect(fatal.attack(command).accepted,"passive actor yields in lethal fixture")
		else: t.expect(fatal.step().ok,"lethal fixture opponent acts")
	var death: Dictionary=Sm2BattleResultsView.build(fatal)
	t.expect(not death.is_empty() and not death.party[0].alive,"actual hero death is reported")
	t.equal(fatal.world.hero_id(),0,"lethal encounter leaves Soul without a body")
	var dead_hash: String=fatal.state_hash()
	t.expect(fatal.save_game().ok and fatal.load_game().ok,"dead hero result survives load")
	t.equal(Sm2BattleResultsView.build(fatal).party,death.party,"dead-body facts and experience remain frozen")
	t.equal(fatal.state_hash(),dead_hash,"viewing death cannot revive or reward hero")
	t.complete_suite("battle_results")
