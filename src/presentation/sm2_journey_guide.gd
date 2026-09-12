class_name Sm2JourneyGuide
extends RefCounted

static func build(screen: Sm2LifeScreen,parent: VBoxContainer) -> void:
	var session: Sm2JourneySession=screen.session as Sm2JourneySession
	var v: Dictionary=Sm2JourneyGuideView.build(session)
	if v.is_empty(): return
	var texts: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/journey_guide.json"))
	var copy: Dictionary=texts.get(v.stage,{}) if texts is Dictionary else {}
	var panel: PanelContainer=PanelContainer.new(); panel.name="JourneyGuide"; parent.add_child(panel)
	var margin: MarginContainer=MarginContainer.new(); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,14)
	var column: VBoxContainer=VBoxContainer.new(); margin.add_child(column)
	column.add_child(screen._label("МАРШРУТ · %s · завершено встреч %s/%s" % [v.location,v.completed,v.total],14,screen.MUTED))
	var title: Label=screen._label(str(copy.get("title","Продолжение путешествия")),21,screen.GOLD); title.name="GuideTitle"; column.add_child(title)
	column.add_child(screen._label(str(copy.get("text","Выберите доступное занятие.")),15,screen.INK))
	for fact: String in v.facts: column.add_child(screen._label(fact,14,screen.GOLD))
	var buttons: HFlowContainer=HFlowContainer.new(); column.add_child(buttons)
	for index: int in v.actions.size():
		var row: Dictionary=v.actions[index]
		var command: Sm2WorldCommand=null
		if row.has("kind"): command=session.command(row.kind,row.target,row.content)
		var button: Button=screen._button(row.title,"Guide_"+(str(row.link) if row.has("link") else str(row.kind)+"_"+str(row.target)+"_"+str(row.content)),activate.bind(screen,row.duplicate(true),command),not row.reason.is_empty())
		button.tooltip_text=row.reason; buttons.add_child(button)
		if not row.reason.is_empty(): column.add_child(screen._label(row.title+": "+str(row.reason),13,screen.MUTED))

static func activate(screen: Sm2LifeScreen,row: Dictionary,command: Sm2WorldCommand) -> void:
	if command!=null:
		var before: Dictionary=screen.session.view()
		var result: Dictionary=screen.session.act(command)
		screen._notice=Sm2JourneyGuideView.feedback(command.kind,before,screen.session.view()) if result.ok else str(result.errors[0])
		if result.ok and command.kind=="start_battle": screen.battle_requested.emit()
		else: screen.redraw()
		return
	match str(row.link):
		"resume":
			if screen.session.world.busy(): screen.battle_requested.emit()
			else: screen.redraw()
		"development": screen.development_requested.emit()
		"inventory", "body":
			screen._workspace_state={"body":int(row.body),"tab":1 if row.link=="inventory" else 0,"part":"","item":"","destination":"","scope":1,"query":""}
			screen._open_workspace()
