class_name Sm2BarrierRules
extends RefCounted
## Only direct attacks call absorption; internal damage uses HpApplication directly.
static func loss(target: Sm2TacticalActor, incoming: int) -> Dictionary:
	var amount: int=maxi(0,incoming)
	var absorbed: int=mini(amount,target.barrier.remaining) if target.barrier!=null else 0
	return {"absorbed":absorbed,"hp_loss":amount-absorbed if target.anatomy!=null else mini(target.combat.hp,amount-absorbed)}

static func absorb(target: Sm2TacticalActor, incoming: int, events: Array[Dictionary]) -> int:
	var result: Dictionary=loss(target,incoming)
	if result.absorbed>0:
		target.barrier.remaining-=int(result.absorbed)
		events.append({"type":"barrier_absorbed","target_actor_id":str(target.spatial.actor_id),"amount":result.absorbed,"remaining":target.barrier.remaining})
		if target.barrier.remaining==0: target.barrier.clear()
	return int(result.hp_loss)

static func clear(target: Sm2TacticalActor, reason: String, events: Array[Dictionary]) -> void:
	if target.barrier==null or target.barrier.remaining==0: return
	target.barrier.clear()
	events.append({"type":"barrier_removed","target_actor_id":str(target.spatial.actor_id),"reason":reason})

static func expire(target: Sm2TacticalActor, round_number: int, events: Array[Dictionary]) -> void:
	if target.barrier!=null and target.barrier.remaining>0 and target.barrier.expires_round<=round_number: clear(target,"expired",events)

static func restore(raw: Dictionary, state: Sm2TacticalState, actor: Sm2TacticalActor) -> String:
	actor.barrier=Sm2BarrierState.new()
	if raw.is_empty(): return ""
	if not Sm2Validate.fields(raw,["ability_id","capacity","remaining","expires_round"]): return "barrier_fields"
	if not Sm2Validate.text(raw.ability_id) or not Sm2Validate.integer(raw.capacity,1,10000) or not Sm2Validate.integer(raw.remaining,1,int(raw.capacity)) or not Sm2Validate.integer(raw.expires_round,state.round,state.round+1): return "barrier_values"
	var dev: Sm2BattleDevelopment=state.development
	if actor.spatial.actor_id!=dev.catalog.hero() or not actor.spatial.occupies(): return "barrier_owner"
	var psi: Sm2PsionicCatalog=dev.catalog.psionics()
	if psi.ability(raw.ability_id).get("operation")!="self_barrier" or not dev.psionic_available(actor.spatial.actor_id,raw.ability_id) or int(dev.counts[actor.spatial.actor_id].get(raw.ability_id,0))==0: return "barrier_source"
	if int(raw.capacity)>int(dev.psionic_parameter(actor.spatial.actor_id,raw.ability_id,true).total): return "barrier_capacity"
	if int(raw.expires_round)==state.round and actor.activation_started: return "barrier_expired"
	actor.barrier.ability_id=raw.ability_id; actor.barrier.capacity=int(raw.capacity); actor.barrier.remaining=int(raw.remaining); actor.barrier.expires_round=int(raw.expires_round)
	return ""
