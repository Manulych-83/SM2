extends SceneTree
const FIXTURE=preload("res://tests/fixtures/sm2_development_scale_fixture.gd")
var report: Dictionary={"passed":true,"metrics":[],"errors":[],"steps":[]}
func _initialize() -> void: call_deferred("run")
func measure(name: String,operation: Callable) -> Variant:
	var start: int=Time.get_ticks_usec(); var result: Variant=operation.call()
	var elapsed: float=(Time.get_ticks_usec()-start)/1000.0
	report.metrics.append({"name":name,"ms":elapsed}); print("COMBAT_RUNTIME %s %.3f ms" % [name,elapsed]); return result
func check(ok: bool,description: String) -> void:
	if not ok: report.passed=false; report.errors.append(description); push_error(description)
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0]!="--output": quit(2); return
	var output: String=args[1]; DirAccess.make_dir_recursive_absolute(output)
	var s: Sm2CheckpointSession=FIXTURE.session()
	check(s.new_game().ok,"initial world")
	s.world.world_id="p4:00000000000000000000000000000042"; s._bind_archive()
	for i: int in 8: check(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"practice")
	check(s.act(s.command("buy_node",2,"p5:node.impulse")).ok,"impulse")
	var ids: Array=s.world._progress.nodes_for_track(FIXTURE.TRACK)
	Sm2ProgressRules.award(s.world.bodies[2].progress,{FIXTURE.TRACK:ids.size()})
	for i: int in range(ids.size()-1,-1,-1): Sm2ProgressRules.purchase(s.world.bodies[2].progress,s.world._progress.node(ids[i]))
	check(s.act(s.command("travel",0,"ruins")).ok,"travel")
	check(measure("start_battle",func(): return s.act(s.command("start_battle"))).ok,"battle starts")
	var initial: Dictionary=s.capture(); write(output.path_join("initial.json"),initial)
	measure("runner_view",func(): return s.runner.view())
	measure("world_copy",func(): return s.journey().copy_world())
	measure("world_validate",func(): return s.journey().validate())
	measure("session_copy",func(): return s._copy())
	var copied: Sm2CheckpointSession=s._copy() as Sm2CheckpointSession
	measure("publish_unchanged",func(): return s._publish(copied))
	var battle: Sm2TacticalBattle=s.runner._session._battle
	measure("battle_copy",func(): return battle._state.copy())
	measure("battle_decode",func(): return battle._decode(battle.capture()))
	measure("runner_restore",func(): return s.runner.restore(s.runner.capture()))
	var current: Dictionary=s.runner.view()
	var probe: Sm2Command=Sm2Command.new(); probe.kind="move"; probe.actor_id=int(current.active_actor_id); probe.battle_id=current.battle_id; probe.expected_revision=int(current.revision)
	for actor: Dictionary in current.actors:
		if actor.actor_id==current.active_actor_id: probe.target=Vector2i(0,int(actor.r))
	var isolated_runner: Sm2BattleRunner=s.runner.copy()
	check(measure("kernel_command",func(): return isolated_runner.execute_player(probe)).accepted,"isolated kernel action")
	check(measure("capacity_check",func(): return s._check_capacity(s._copy())).ok,"snapshot bounded")
	check(measure("active_save",func(): return s.save_game()).ok,"large active battle saves")
	check(measure("active_load",func(): return s.load_game()).ok,"large active battle loads")
	check(Sm2Canonical.hash(s.capture())==Sm2Canonical.hash(initial),"read operations preserve snapshot")
	for i: int in 12:
		if not s.world.busy(): break
		var view: Dictionary=s.runner.view(); var player: bool=false
		for actor: Dictionary in view.actors:
			if int(actor.actor_id)!=int(view.active_actor_id) or actor.controller!="player" or actor.morale=="fleeing": continue
			player=true
			var command: Sm2Command=Sm2Command.new(); command.actor_id=int(actor.actor_id); command.expected_revision=int(view.revision); command.battle_id=view.battle_id
			command.kind="escape" if int(actor.q)==0 else "move"; command.target=Vector2i(0,int(actor.r))
			if not s.runner.preview(command).allowed: command.kind="end_turn"
			var result: Sm2CommandResult=measure("action_%s_%s" % [i,command.kind],func(): return s.attack(command))
			check(result.accepted,"action "+result.code)
			report.steps.append({"code":result.code,"events":result.events,"hash":s.state_hash()})
			if not result.accepted: break
		if not player:
			var result: Dictionary=measure("action_%s_ai" % i,func(): return s.step())
			check(result.ok,"AI action"); report.steps.append({"result":result,"hash":s.state_hash()})
	check(not s.world.busy(),"route completes")
	write(output.path_join("final.json"),s.capture())
	write(output.path_join("report.json"),report)
	quit(0 if report.passed else 1)
func write(path: String,value: Variant) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE); file.store_string(Sm2Canonical.stringify(value)); file.close()
