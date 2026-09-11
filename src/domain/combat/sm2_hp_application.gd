class_name Sm2HpApplication
extends RefCounted
## Apply already resolved HP loss; damage calculation remains in its own resolver.
static func apply(state: Sm2TacticalState, target: Sm2TacticalActor, source_id: int, loss: int, events: Array[Dictionary], part: String = "", cut: bool = false) -> void:
	if state.survival!=null:
		Sm2SurvivalBattle.damage(state,target,source_id,loss,part,cut,events); return
	loss = mini(target.combat.hp,maxi(0,loss))
	target.combat.hp -= loss
	events.append({"type":"hp_damaged","target_actor_id":str(target.spatial.actor_id),"loss":loss,"remaining":target.combat.hp})
	if target.combat.hp != 0 or not target.spatial.alive: return
	kill(state,target,source_id,events)

static func kill(state: Sm2TacticalState,target: Sm2TacticalActor,source_id: int,events: Array[Dictionary]) -> void:
	if not target.spatial.alive: return
	Sm2BarrierRules.clear(target,"death",events)
	target.spatial.alive = false
	target.spatial.ap = 0
	target.reactions_left = 0
	target.turn_done = true
	target.combat.clear_wall()
	state.main_queue.erase(target.spatial.actor_id)
	state.deferred_queue.erase(target.spatial.actor_id)
	events.append({"type":"actor_died","actor_id":str(target.spatial.actor_id),"source_actor_id":str(source_id),"side":target.spatial.side,"q":target.spatial.position.x,"r":target.spatial.position.y})
	Sm2EffectResolver.clear_target(state,target.spatial.actor_id,"death",events)
