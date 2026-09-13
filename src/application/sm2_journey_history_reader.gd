class_name Sm2JourneyHistoryReader
extends RefCounted
## Visits validated transitions in a disposable session; no store or live commands.
static func visit(session: Sm2JourneySession, observer: Callable) -> bool:
	var shadow: Sm2JourneySession=Sm2JourneySession.new(session._content,session._profile,null)
	shadow.world.start(session.world.world_id)
	for index: int in session.history.size():
		var entry: Dictionary=session.history[index]
		observer.call(shadow,entry,index,false)
		if entry.kind=="camp":
			if not shadow._camp(entry.command,true).ok: return false
		elif entry.kind=="outcome":
			var checked: Dictionary=shadow._check_battle(entry.battle)
			if not checked.ok or not checked.state.finished: return false
			shadow.world.revision+=checked.state.revision
			if not shadow._finish().ok: return false
		else: return false
		observer.call(shadow,entry,index,true)
	if session.world.busy():
		var checked: Dictionary=shadow._check_battle(session.runner.capture())
		if not checked.ok or checked.state.finished: return false
		shadow.world.revision+=checked.state.revision
	return Sm2Canonical.hash(shadow.world.capture())==Sm2Canonical.hash(session.world.capture())
