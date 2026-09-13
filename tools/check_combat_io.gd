extends "res://tools/check_combat_runtime.gd"
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size() not in [2,3] or args[0]!="--output" or (args.size()==3 and args[2]!="--ordinary"): quit(2); return
	var ordinary: bool=args.size()==3
	report["profile"]="ordinary" if ordinary else "large"
	report["growth_timing"]=Sm2BattleDevelopment.AFTER_BATTLE
	var output: String=args[1]; DirAccess.make_dir_recursive_absolute(output)
	var s: Sm2CheckpointSession=preload("res://tests/scenarios/test_checkpoint.gd").make("user://ordinary-io") if ordinary else FIXTURE.session()
	check(s.new_game().ok,"initial world")
	s.world.world_id="p4:00000000000000000000000000000042"; s._bind_archive()
	for i: int in 8: check(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"practice")
	check(s.act(s.command("buy_node",2,"p5:node.impulse")).ok,"impulse")
	if not ordinary:
		var ids: Array=s.world._progress.nodes_for_track(FIXTURE.TRACK)
		Sm2ProgressRules.award(s.world.bodies[2].progress,{FIXTURE.TRACK:ids.size()})
		for i: int in range(ids.size()-1,-1,-1): Sm2ProgressRules.purchase(s.world.bodies[2].progress,s.world._progress.node(ids[i]))
	check(s.act(s.command("travel",0,"ruins")).ok,"travel")
	check(measure("start_battle",func(): return s.act(s.command("start_battle"))).ok,"battle starts")
	# Exercise the production store policy with the large fixture's own validator.
	var owner: WeakRef=weakref(s)
	s._store=Sm2CampaignStore.new("user://combat-io",0,func(raw: Dictionary):
		var candidate: Sm2CheckpointSession=(owner.get_ref() as Sm2CheckpointSession)._fresh()
		var result: Dictionary=candidate.restore(raw)
		if result.ok: result["validated_session"]=candidate
		return result)
	s._store.large_profile=not ordinary; s.repository=Sm2HistoryRepository.new(s._store._base_directory); s.repository.store.large_profile=not ordinary
	var initial: Dictionary=s.capture(); write(output.path_join("initial.json"),initial)
	check(measure("prepare",func(): return s._copy()._prepare()).ok,"isolated prepare")
	check(measure("check_battle",func(): return s._copy()._check_battle(s.runner.capture())).ok,"isolated check")
	var seen: Dictionary={}
	for i: int in 160:
		if not s.world.busy(): break
		var status: Dictionary=s.runner.status(); var active: Dictionary={}
		for actor: Dictionary in status.actors:
			if actor.actor_id==status.active_actor_id: active=actor
		var events: Array=[]; var result_data: Dictionary={}
		if active.controller=="player" and active.morale!="fleeing":
			var decision: Dictionary=s.runner._session.ai_decision(s._profile)
			check(decision.ok,"AI oracle chooses player command")
			if not decision.ok: break
			var command: Sm2Command=decision.command
			var result: Sm2CommandResult=measure("action_%s_%s" % [i,command.kind],func(): return s.attack(command))
			check(result.accepted,"player command "+result.code); events=result.events
			result_data={"code":result.code,"events":result.events,"revision":result.revision}
		else:
			result_data=measure("action_%s_ai" % i,func(): return s.step())
			check(result_data.ok,"AI step"); events=result_data.get("events",[])
		for event: Dictionary in events: seen[event.type]=true
		report.steps.append({"result":result_data,"hash":s.state_hash()})
		if i==6:
			var before: String=s.state_hash()
			check(measure("active_save",func(): return s.save_game()).ok,"active save")
			check(measure("active_resave",func(): return s.save_game()).ok,"replace existing valid primary")
			check(measure("active_load",func(): return s.load_game()).ok,"active load")
			check(s.state_hash()==before,"load preserves entire active state")
	check(not s.world.busy(),"full battle completes")
	check(seen.has("attack_hit") and seen.has("attack_missed") and seen.has("battle_practice_accumulated") and seen.has("battle_growth_applied"),"battle includes hits, misses, pending practice and closing growth")
	var before: String=s.state_hash()
	var results: Dictionary=measure("results_view",func(): return Sm2BattleResultsView.build(s))
	check(not results.is_empty(),"results available"); write(output.path_join("results.json"),results)
	check(measure("finished_save",func(): return s.save_game()).ok,"finished save")
	check(measure("finished_load",func(): return s.load_game()).ok,"finished load")
	check(s.state_hash()==before,"completed load exact")
	write(output.path_join("final.json"),s.capture()); report["events"]=seen.keys()
	write(output.path_join("report.json"),report); quit(0 if report.passed else 1)
