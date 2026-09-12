extends SceneTree
const FIXTURE=preload("res://tests/scenarios/test_survival_tissues.gd")
const BODY=preload("res://tests/scenarios/test_p4_body.gd")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var t: Sm2TestHarness=Sm2TestHarness.new()
	var store: Sm2SaveStore=Sm2SaveStore.new("user://tissues-restart")
	var c: Dictionary=FIXTURE.content(true)
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,store)
	if "--prepare" in OS.get_cmdline_user_args():
		t.expect(s.new_game().ok,"prepare real loss world")
		var device: String=s.journey().prostheses.items[0].id
		t.expect(s.act(s.command("travel",0,"ruins")).ok,"travel")
		t.expect(s.act(s.command("start_battle")).ok,"loss encounter")
		for index: int in 120:
			if not s.world.busy(): break
			t.expect(BODY.treatment_step(s).ok,"real loss and retreat")
		for body: int in [2,4]:
			if not s.world.bodies[body].alive: continue
			for wound: Dictionary in s.journey().survival.bodies[str(body)].wounds:
				if int(wound.rate)>0: t.expect(s.act(s.command("bandage",body,wound.id)).ok,"treatment")
		t.expect(s.act(s.command("travel",0,"camp")).ok,"workshop")
		t.expect(s.act(s.command("attach_device",2,device)).ok,"installation")
		t.expect(s.act(s.command("travel",0,"ruins")).ok,"return")
		t.expect(s.act(s.command("start_battle")).ok,"second encounter")
		var damaged: bool=false
		for index: int in 120:
			if not s.world.busy(): break
			t.expect(BODY.treatment_step(s).ok,"real device damage")
			if s.world.busy() and int(s.runner.capture().session.battle.survival.inventory.items.filter(func(row: Dictionary) -> bool: return row.id==device)[0].current)<30: damaged=true; break
		t.expect(damaged and s.world.busy(),"active damaged device fixture")
		t.expect(s.save_game().ok,"save active damaged device")
	else:
		var raw: Dictionary=store.load_slot("survival_tissues")
		t.expect(raw.ok and s.load_game().ok,"different process reads damaged device")
		if not raw.ok or not s.world.busy(): print("TISSUES_RESTART_FAILED"); quit(1); return
		t.equal(Sm2Canonical.hash(s.capture()),Sm2Canonical.hash(raw.payload),"different process exact snapshot without tick")
		var control: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,store)
		t.expect(control.restore(raw.payload).ok,"independent control snapshot")
		t.equal(BODY.treatment_step(s),BODY.treatment_step(control),"next command results match")
		t.equal(s.state_hash(),control.state_hash(),"next state and RNG match")
		# Each malformed live snapshot must fail without publishing.
		for defect: String in ["condition","attachment","missing","parts","layers","wound"]:
			var bad: Dictionary=raw.payload.duplicate(true)
			var physical: Array=bad.active.session.battle.survival.inventory.items
			for item: Dictionary in physical:
				if item.place=="installed":
					if defect=="condition": item.current=31
					if defect=="attachment": item.place="ground"; item.holder="ruins"; item.slot=""
					break
			if defect=="missing": bad.active.session.battle.survival.missing["2"].clear()
			if defect=="parts":
				for index: int in physical.size():
					if physical[index].definition_id=="repair_parts": physical.remove_at(index); break
			if defect=="layers": bad.active.session.battle.survival.bodies["2"].layers.right_hand.skin=1
			if defect=="wound": bad.active.session.battle.survival.bodies["2"].wounds[0].layer_losses.skin=0
			var before: String=s.state_hash()
			t.expect(not s.restore(bad).ok,"reject device snapshot forgery: "+defect)
			t.equal(s.state_hash(),before,"rejected load preserves all state")
	print("TISSUES_RESTART "+JSON.stringify({"checks":t.checks,"passed":t.failures.is_empty(),"failures":t.failures}))
	quit(0 if t.failures.is_empty() else 1)
