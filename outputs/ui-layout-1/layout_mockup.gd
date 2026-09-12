extends "res://tests/display_ui.gd"
## Review-only composition. Uses a fresh real encounter, never the player's save.
var canvas: Control
var field_preview: Sm2HexBoard
var target_panel: Control
var target_hint: Control
var move_tile: Control
var psi_tile: Control
var snapshot: Dictionary
var palette: Sm2CombatHud
const B=preload("res://src/presentation/sm2_bronze_theme.gd")

func _run() -> void:
	OS.add_logger(captured)
	output="res://outputs/ui-layout-1"
	var s: Sm2JourneySession=Sm2JourneySession.new(Sm2SurvivalContentLoader.load_scenario(true,true),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://layout-preview"))
	t.expect(s.new_game().ok,"fresh preview session")
	SHIELD.learn(s,t)
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"reach actual ruins")
	t.expect(s.act(s.command("start_battle")).ok,"start actual encounter")
	screen=Sm2BattleScreen.new(); screen.life_session=s; screen.runner=s.runner; screen.auto_advance=false
	root.add_child(screen); await _frames(); screen.hide()
	snapshot=screen.state.duplicate(true); palette=screen.hud
	var before: String=s.state_hash()
	canvas=Control.new(); canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); canvas.theme=B.create(); root.add_child(canvas)
	build_layout()
	await _frames(); await RenderingServer.frame_post_draw
	var overview: Image=root.get_texture().get_image()
	t.equal(overview.get_size(),Vector2i(2560,1440),"native QHD overview")
	t.equal(overview.save_png(output.path_join("01-overview-2560.png")),OK,"write overview")
	target_panel.show(); target_hint.show()
	move_tile.add_theme_stylebox_override("panel",B.box(B.PANEL,B.BORDER,0))
	psi_tile.add_theme_stylebox_override("panel",B.box(Color("20343b"),B.PSI,0))
	field_preview.update_view(snapshot,{}, {Vector2i(4,1):true},3)
	field_preview.route.clear()
	await _frames(); await RenderingServer.frame_post_draw
	var target: Image=root.get_texture().get_image()
	t.equal(target.get_size(),Vector2i(2560,1440),"native QHD target view")
	t.equal(target.save_png(output.path_join("02-target-2560.png")),OK,"write target view")
	t.equal(s.state_hash(),before,"both compositions leave encounter unchanged")
	var evidence: FileAccess=FileAccess.open(output.path_join("preview-state.json"),FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"state":snapshot,"impulse_preview":s.runner.preview(Sm2CombatHudView.command(snapshot,"use_ability","p5:ability.impulse",3)),"read_only":before==s.state_hash(),"size":"2560x1440","purpose":"layout proposal, not shipped UI"},"\t")); evidence.close()
	canvas.queue_free(); screen.queue_free(); await _frames()
	_finish()

func build_layout() -> void:
	var bg: ColorRect=ColorRect.new(); bg.color=Color("13130f"); place(canvas,bg,Rect2(0,0,1600,900))
	field_preview=Sm2HexBoard.new(); place(canvas,field_preview,Rect2(130,124,1180,607)); field_preview.enable_art()
	field_preview.panel_style=B.box(Color("13130f"),Color("13130f"),0)
	field_preview.update_view(snapshot,screen._reachable,{},1)
	# Same field and bodies as the running game; composition only.
	var objective: Control=panel(canvas,Rect2(18,18,310,89))
	label_at(objective,"Заросшие руины",Rect2(16,10,278,26),20,B.GOLD,true)
	label_at(objective,"Победите противников",Rect2(16,43,278,22),14)
	label_at(objective,"Ваш отряд: 2     •     Противники: 2",Rect2(16,65,278,18),12,B.MUTED)
	var queue: Array[Dictionary]=Sm2CombatHudView.queue(snapshot)
	var origin: float=800-float(queue.size())*43
	for i: int in queue.size():
		var entry: Dictionary=queue[i]
		var card: Control=panel(canvas,Rect2(origin+i*86,14,76,91),B.PSI if entry.current else B.BORDER if entry.side=="company" else Color("955c4b"))
		portrait_at(card,Rect2(14,5,48,52))
		label_at(card,entry.name,Rect2(3,58,70,16),11,B.TEXT,false,HORIZONTAL_ALIGNMENT_CENTER)
		meter(card,Rect2(6,79,64,4),1.0,B.PSI if entry.side=="company" else Color("bd7969"))
	label_at(canvas,"Ход: Герой  ·  Раунд %s" % snapshot.round,Rect2(600,109,400,25),16,B.GOLD,true,HORIZONTAL_ALIGNMENT_CENTER)
	var tools_panel: Control=panel(canvas,Rect2(1340,18,242,48))
	label_at(tools_panel,"Журнал   ·   Сохранить   ·   Меню",Rect2(8,8,226,30),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	label_at(canvas,"МАКЕТ КОМПОНОВКИ · 2560 × 1440",Rect2(1314,76,268,20),11,B.MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)
	label_at(canvas,"ОТРЯД",Rect2(18,136,94,22),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	for i: int in 2:
		var data: Dictionary=Sm2CombatHudView.card(Sm2CombatHudView.actor(snapshot,i+1))
		var card: Control=panel(canvas,Rect2(18,164+i*143,94,132),B.PSI if i==0 else B.BORDER)
		portrait_at(card,Rect2(15,8,64,74))
		label_at(card,data.name,Rect2(4,81,86,22),13,B.GOLD,false,HORIZONTAL_ALIGNMENT_CENTER)
		meter(card,Rect2(8,107,78,5),float(data.condition[0])/data.condition[1],Color("9bac7a"))
		meter(card,Rect2(8,117,78,4),float(data.ap[0])/data.ap[1],B.PSI)
	build_actor()
	build_actions()
	build_target()
	label_at(canvas,"ЛКМ — действие по цели     ·     ПКМ — отмена выбора",Rect2(365,874,950,19),12,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)

func build_actor() -> void:
	var data: Dictionary=Sm2CombatHudView.card(Sm2CombatHudView.actor(snapshot,1))
	var card: Control=panel(canvas,Rect2(18,746,324,128))
	portrait_at(card,Rect2(12,12,55,65))
	label_at(card,"Герой",Rect2(80,9,230,25),20,B.GOLD,true)
	label_at(card,"Уверен  ·  Кровотечения нет",Rect2(80,36,230,20),12,B.MUTED)
	label_at(card,"ОД  %s / %s" % data.ap,Rect2(80,60,218,22),15,B.TEXT)
	meter(card,Rect2(80,84,218,5),float(data.ap[0])/data.ap[1],B.GOLD)
	label_at(card,"Усталость  %s/%s" % data.fatigue,Rect2(12,99,140,20),12,B.MUTED)
	label_at(card,"Концентрация  %s/%s" % data.focus,Rect2(161,99,151,20),12,B.PSI)

func build_actions() -> void:
	var dock: Control=panel(canvas,Rect2(358,746,952,128))
	var items: Array[Array]=[
		["move","Движение","По маршруту"],
		["m2:ability.sword_strike","Удар мечом",""],
		["m2:ability.shieldwall","Защита щитом",""],
		["p5:ability.impulse","Пси-импульс",""],
		["p5:ability.shield","Пси-щит",""],
		["hand","Прицельные","Выбор удара"],
		["bandage","Перевязка","Нет кровотечения"]]
	for i: int in items.size():
		var entry: Array=items[i]; var psychic: bool=str(entry[0]).begins_with("p5:")
		var tile: Control=panel(dock,Rect2(10+i*133,8,127,87),B.PSI if psychic else B.GOLD if i==0 else B.BORDER)
		if i==0: move_tile=tile; tile.add_theme_stylebox_override("panel",B.box(Color("332c1d"),B.GOLD,0))
		if i==3: psi_tile=tile
		var texture: TextureRect=TextureRect.new(); texture.texture=palette.icon(entry[0]); texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		place(tile,texture,Rect2(46,6,35,35)); texture.modulate=Color("77776a") if i==6 else Color.WHITE
		label_at(tile,str(i+1),Rect2(8,4,18,18),11,B.MUTED)
		label_at(tile,entry[1],Rect2(2,44,123,21),13,B.PSI if psychic else B.TEXT,false,HORIZONTAL_ALIGNMENT_CENTER)
		var price: String=entry[2]
		if price.is_empty(): price=Sm2CombatHud.price(screen.runner.ability_cost(1,entry[0]))
		label_at(tile,price,Rect2(2,68,123,15),10,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	label_at(dock,"ДЕЙСТВИЯ",Rect2(14,101,124,18),11,B.GOLD)
	label_at(dock,"Оружие     ·     Псионика     ·     Помощь",Rect2(160,99,610,22),13,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	label_at(dock,"Настроить",Rect2(829,101,108,18),11,B.MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)
	var end: Control=panel(canvas,Rect2(1326,800,256,51),B.PSI)
	label_at(end,"ЗАВЕРШИТЬ ХОД",Rect2(5,10,246,31),17,B.TEXT,true,HORIZONTAL_ALIGNMENT_CENTER)
	label_at(canvas,"Ждать     ·     Уйти с поля",Rect2(1326,852,256,22),13,B.MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)

func build_target() -> void:
	var data: Dictionary=Sm2CombatHudView.card(Sm2CombatHudView.actor(snapshot,3))
	var check: Dictionary=screen.runner.preview(Sm2CombatHudView.command(snapshot,"use_ability","p5:ability.impulse",3))
	t.expect(check.allowed,"shown impulse is actually available")
	target_panel=panel(canvas,Rect2(1324,303,258,331),Color("9d6a4e"))
	portrait_at(target_panel,Rect2(13,13,49,58))
	label_at(target_panel,"Боец №3",Rect2(76,13,168,27),19,B.GOLD,true)
	label_at(target_panel,"Противник  ·  Уверен",Rect2(76,44,168,22),12,B.MUTED)
	label_at(target_panel,"Состояние  %s / %s" % data.condition,Rect2(14,82,230,23),13)
	meter(target_panel,Rect2(14,111,230,5),float(data.condition[0])/data.condition[1],Color("b97662"))
	label_at(target_panel,"ПСИ-ИМПУЛЬС",Rect2(14,134,230,21),14,B.PSI)
	label_at(target_panel,"Без промаха",Rect2(14,165,230,23),17,B.TEXT,true)
	label_at(target_panel,"Повреждение тканей: %s" % check.get("hp_loss",0),Rect2(14,198,230,25),14)
	label_at(target_panel,"%s" % Sm2CombatHud.price(screen.runner.ability_cost(1,"p5:ability.impulse")),Rect2(14,231,230,24),13,B.PSI)
	label_at(target_panel,"Обходит броню и предметный щит.\nРезультат рассчитан до применения.",Rect2(14,272,230,42),12,B.MUTED)
	target_panel.hide()
	var target_cell: Vector2=field_preview.position+field_preview.center(Vector2i(4,1))
	target_hint=panel(canvas,Rect2(target_cell+Vector2(66,-92),Vector2(170,58)),B.PSI)
	label_at(target_hint,"Без промаха",Rect2(10,6,150,20),14,B.PSI)
	label_at(target_hint,"%s · повреждение тканей" % check.get("hp_loss",0),Rect2(10,31,150,18),11,B.TEXT)
	target_hint.hide()

func place(parent: Control,node: Control,rect: Rect2) -> void:
	parent.add_child(node); node.position=rect.position; node.size=rect.size; node.mouse_filter=Control.MOUSE_FILTER_IGNORE

func panel(parent: Control,rect: Rect2,border: Color=B.BORDER) -> Control:
	var node: Panel=Panel.new(); node.add_theme_stylebox_override("panel",B.box(Color("18160fee"),border,0)); place(parent,node,rect); B.corners(node); return node

func label_at(parent: Control,value: String,rect: Rect2,font_size: int=14,color: Color=B.TEXT,serif: bool=false,align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var node: Label=Label.new(); node.text=value; node.horizontal_alignment=align
	node.add_theme_font_size_override("font_size",font_size); node.add_theme_color_override("font_color",color)
	if serif: node.add_theme_font_override("font",B.SERIF)
	place(parent,node,rect)

func portrait_at(parent: Control,rect: Rect2) -> void:
	var node: TextureRect=TextureRect.new(); node.texture=palette.portrait_texture(); node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; place(parent,node,rect)

func meter(parent: Control,rect: Rect2,ratio: float,color: Color) -> void:
	var back: ColorRect=ColorRect.new(); back.color=Color("363125"); place(parent,back,rect)
	var fill: ColorRect=ColorRect.new(); fill.color=color; place(parent,fill,Rect2(rect.position,Vector2(rect.size.x*clampf(ratio,0,1),rect.size.y)))
