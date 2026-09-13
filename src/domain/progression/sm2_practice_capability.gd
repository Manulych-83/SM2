class_name Sm2PracticeCapability
extends RefCounted

static func query(activity: Sm2PracticeDefinition, body: Sm2ProgressBodyState, catalog: Sm2ProgressCatalog) -> Dictionary:
	if activity.required_track.is_empty(): return {"allowed":true}
	var track: Dictionary=Sm2ProgressRules.track(body,catalog,activity.required_track)
	var value: int = int(track.effective)+activity.assistance
	return {"allowed":value >= activity.required_value,"track_name":track.name,"own_level":track.level,"node_bonus":track.node_bonus,"base_value":track.effective,"assistance":activity.assistance,"source":activity.assistance_name,"effective":value,"minimum":activity.required_value}
