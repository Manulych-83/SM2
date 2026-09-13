extends RefCounted
const CHECKPOINT=preload("res://tests/scenarios/test_checkpoint.gd")
const HYBRID=preload("res://tests/scenarios/test_p5_hybrids.gd")
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")

static func run(t: Sm2TestHarness) -> void:
	for variant: int in 3: _parameters(t,variant)
	_route(t)
	t.complete_suite("combat_profile")

static func _parameters(t: Sm2TestHarness,variant: int) -> void:
	var fast: Sm2TacticalBattle=SHIELD.fixture(t) if variant==2 else HYBRID.fixture(t,1,variant==1)
	var raw: Dictionary=fast.capture(); raw.development["growth_timing"]=Sm2BattleDevelopment.AFTER_BATTLE
	t.expect(fast.restore(raw).ok,"fully validated encounter compiles its profile")
	var profile: Sm2CombatGrowthProfile=fast._state.development._profile
	t.expect(profile!=null,"compiled profile exists")
	var full: Sm2TacticalBattle=fast.copy(); full._compact_development=false; full._state.development._materialize()
	t.equal(full.capture(),fast.capture(),"public snapshot retains exact original shape")
	for actor: int in [1,2,3,4]:
		for stat: String in ["melee_skill","melee_defense","ranged_skill"]:
			t.equal(fast._state.development.stat_bonus(actor,stat),full._state.development.stat_bonus(actor,stat),"compiled stat equals full query")
		for id: String in fast._development.psionics().ids():
			t.equal(fast._state.development.psionic_available(actor,id),full._state.development.psionic_available(actor,id),"compiled spell knowledge equals full query")
			t.equal(fast._state.development.concentration_cost(actor,int(fast._development.psionics().ability(id).concentration_cost),id),full._state.development.concentration_cost(actor,int(fast._development.psionics().ability(id).concentration_cost),id),"compiled concentration cost includes implant")
			if actor==1:
				var shield: bool=fast._development.psionics().ability(id).get("operation")=="self_barrier"
				t.equal(fast._state.development.psionic_parameter(actor,id,shield),full._state.development.psionic_parameter(actor,id,shield),"compiled psi calculation includes sources")
		if fast._development.has_hybrids():
			for id: String in fast._development.hybrids().ids():
				t.equal(fast._state.development.hybrid_available(actor,id),full._state.development.hybrid_available(actor,id),"compiled hybrid knowledge")
				if actor==1: t.equal(fast._state.development.hybrid_parameter(actor,id),full._state.development.hybrid_parameter(actor,id),"compiled hybrid damage including upgrades")
	t.equal(fast.view(),full.view(),"detached HUD view equivalent")
	t.expect(fast._state.development._profile==profile,"HUD queries do not materialize full body")
	var command: Sm2Command=SHIELD.cast(fast) if variant==2 else HYBRID.command(fast)
	t.equal(fast.preview(command),full.preview(command),"preview equivalent")
	var accepted: Sm2CommandResult=fast.execute(command); var oracle: Sm2CommandResult=full.execute(command)
	t.expect(accepted.accepted and oracle.accepted,"actual compiled action and oracle accepted")
	t.equal(accepted.events,oracle.events,"actual effects and XP events exact")
	t.equal(fast.capture(),full.capture(),"actual complete resulting snapshot exact")
	t.expect(fast._state.development._profile==profile,"live action shares original immutable profile")
	var before: String=fast.state_hash()
	var copy: Sm2TacticalState=fast.state_copy(); copy.development.bodies[1].tracks["p1:skill.psionics"].earned+=1; copy.development.origin.world_id="changed"
	t.equal(fast.state_hash(),before,"public body and origin mutations cannot affect live profile")
	var internal_copy: Sm2TacticalBattle=fast.copy(); internal_copy._state.development.bodies[1].tracks["p1:skill.psionics"].earned+=1
	t.equal(fast.state_hash(),before,"explicit mutable access detaches only the copy")
	var compact: Dictionary=fast.capture(true)
	t.expect(not fast.restore(compact).ok,"internal compact token is not a loadable save")
	t.equal(fast.state_hash(),before,"rejected compact file is atomic")
	for defect: String in ["profile","extra","count","sequence","body","profile_type","actor_type","ability_type"]:
		var bad: Dictionary=compact.duplicate(true)
		match defect:
			"profile": bad.development.profile="foreign"
			"profile_type": bad.development.profile=[]
			"actor_type": bad.development.members[0].actor_id=[]
			"ability_type": bad.development.members[0].attacks[0].ability_id=[]
			"extra": bad.development["nodes"]=[]
			"count": bad.development.members[0].attacks[0].count=-1
			"sequence": bad.development.sequence="999999"
			"body": bad.development.members[0]["body"]={}
		t.expect(not fast._decode_with_cache(bad,fast._progress_decode_cache,profile).ok,"compact candidate rejects corrupted "+defect)
		t.equal(fast.state_hash(),before,"compact rejection cannot mutate live state")

static func _route(t: Sm2TestHarness) -> void:
	var fast: Sm2CheckpointSession=CHECKPOINT.make("user://profile-fast")
	t.expect(fast.new_game().ok and fast.act(fast.command("travel",0,"ruins")).ok and fast.act(fast.command("start_battle")).ok,"main profile route starts")
	var full: Sm2CheckpointSession=CHECKPOINT.make("user://profile-full")
	t.expect(full.restore(fast.capture()).ok,"independent full oracle restores")
	full.runner._session._battle._compact_development=false; full.runner._session._battle._state.development._materialize()
	var profile: Sm2CombatGrowthProfile=fast.runner.growth_profile()
	var validator: Sm2SaveStore=Sm2SaveStore.new("user://unused")
	t.expect(fast._check_capacity(fast).ok,"immutable development subtree has size certificate")
	var large: Array[int]=[Sm2SaveStore.MAX_NODES]; var small: Array[int]=[Sm2SaveStore.MAX_NODES-fast._capacity_difference]
	t.equal(validator._validate_value(fast.capture(),0,large),validator._validate_value(fast.capture(true),0,small),"full and charged compact size validation agree")
	t.equal(large,small,"remaining node budget is exactly equal")
	var used: int=Sm2SaveStore.MAX_NODES-large[0]
	for limit: int in [used-1,used,used+1]:
		large=[limit]; small=[limit-fast._capacity_difference]
		t.equal(validator._validate_value(fast.capture(),0,large).is_empty(),validator._validate_value(fast.capture(true),0,small).is_empty(),"exact boundary around structural budget")
	for i: int in 160:
		if not fast.world.busy(): break
		var status: Dictionary=fast.runner.status(); var actor: Dictionary={}
		for row: Dictionary in status.actors:
			if row.actor_id==status.active_actor_id: actor=row
		if actor.controller=="player" and actor.morale!="fleeing":
			var decision: Dictionary=fast.runner._session.ai_decision(fast._profile)
			t.expect(decision.ok,"actual player command chosen")
			if not decision.ok: break
			var a: Sm2CommandResult=fast.attack(decision.command); var b: Sm2CommandResult=full.attack(decision.command)
			t.expect(a.accepted and b.accepted,"both kernels accept same command")
			t.equal(a.events,b.events,"player and reaction events exact")
		else:
			var a: Dictionary=fast.step(); var b: Dictionary=full.step()
			t.equal(a,b,"AI and reaction events exact")
		t.equal(fast.state_hash(),full.state_hash(),"entire campaign and battle snapshot exact after step")
		if fast.world.busy(): t.expect(fast.runner.growth_profile()==profile,"same profile throughout active actions")
		if i==6:
			var before: String=fast.state_hash()
			t.expect(fast.save_game().ok and fast.load_game().ok,"file fully validates and recompiles profile")
			t.expect(full.save_game().ok and full.load_game().ok,"oracle performs the same archive sealing and load")
			full.runner._session._battle._compact_development=false; full.runner._session._battle._state.development._materialize()
			t.equal(fast.state_hash(),before,"active load exact")
			t.expect(fast.runner.growth_profile()!=profile,"loaded file does not reuse live trust token")
			profile=fast.runner.growth_profile()
	t.expect(not fast.world.busy(),"route reaches actual settlement")
	t.equal(Sm2BattleResultsView.build(fast),Sm2BattleResultsView.build(full),"growth table and outcome exact")
