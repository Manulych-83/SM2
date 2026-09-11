class_name Sm2BattleScreen
extends Control
signal menu_requested
var life_session: Sm2LifeSession = null
var runner: Sm2BattleRunner
var state: Dictionary = {}
var board: Sm2HexBoard
var auto_advance: bool = true
var _title: Label
var _queue: Label
var _inspector: RichTextLabel
var _preview: RichTextLabel
var _notice: Label
var _log: RichTextLabel
var _actions: HFlowContainer
var _reachable: Dictionary = {}
var _targets: Dictionary = {}
var _selected: String = ""
var _inspected: int = 0
var _active: int = 0
var _path: Array[Vector2i] = []
var _walking_actor: int = 0
var _delay: float = 0.5
var _finished_seen: bool = false
var _journal: Array[String] = []
var _development_panel: Sm2BattleProgressPanel = null
const GOLD: Color = Color("e3bf7b")
const MUTED: Color = Color("a0b4b4")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()
	if not state.finished:
		_notice.text = "Наведите на клетку или противника. Щелчок выполняет действие. Правая кнопка — отмена выбора."

func _build() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("101c20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation",8)
	column.add_child(header)
	_title = _label("",22,GOLD)
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title)
	if (runner.view().ruleset == Sm2DevelopmentSnapshot.RULESET and life_session == null) or runner.view().ruleset in [Sm2EncounterOrigin.PARTY_RULESET,Sm2EncounterOrigin.BODY_RULESET,Sm2EncounterOrigin.PROSTHESIS_RULESET,Sm2EncounterOrigin.PSIONIC_RULESET,Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET,Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET,Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET]:
		header.add_child(_button("Развитие", "DevelopmentButton", _open_development))
	header.add_child(_button("Сохранить", "SaveBattleButton", _save))
	header.add_child(_button("Загрузить", "LoadBattleButton", _load))
	header.add_child(_button("Меню", "BattleMenuButton", func() -> void: _path.clear(); menu_requested.emit()))
	_queue = _label("",14,MUTED)
	_queue.name = "TurnQueue"
	column.add_child(_queue)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",14)
	column.add_child(row)
	board = Sm2HexBoard.new()
	board.name = "Battlefield"
	board.size_flags_horizontal = SIZE_EXPAND_FILL
	board.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_child(board)
	board.cell_clicked.connect(_clicked)
	board.cell_hovered.connect(_hovered)
	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size.x = 292
	side.add_theme_constant_override("separation",10)
	row.add_child(side)
	side.add_child(_label("УЧАСТНИК",12,GOLD))
	_inspector = RichTextLabel.new()
	_inspector.add_theme_font_size_override("normal_font_size",14)
	_inspector.add_theme_color_override("default_color",Color("e5e6db"))
	_inspector.selection_enabled = true
	_inspector.name = "ActorDetails"
	_inspector.custom_minimum_size = Vector2(292,130)
	if runner.view().ruleset in [Sm2DevelopmentSnapshot.RULESET,Sm2EncounterOrigin.RULESET,Sm2EncounterOrigin.PARTY_RULESET,Sm2EncounterOrigin.BODY_RULESET,Sm2EncounterOrigin.PROSTHESIS_RULESET,Sm2EncounterOrigin.PSIONIC_RULESET,Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET,Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET,Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET]: _inspector.custom_minimum_size.y=180
	# This profile has more actions; retain space for the second action row at 1000x700.
	if runner.view().ruleset in [Sm2EncounterOrigin.PROSTHESIS_RULESET,Sm2EncounterOrigin.PSIONIC_RULESET,Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET,Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET,Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET]: _inspector.custom_minimum_size.y=125
	_inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_inspector)
	side.add_child(_label("ПРОГНОЗ ДЕЙСТВИЯ",12,GOLD))
	_preview = RichTextLabel.new()
	_preview.add_theme_font_size_override("normal_font_size",14)
	_preview.add_theme_color_override("default_color",MUTED)
	_preview.selection_enabled = true
	_preview.name = "ActionPreview"
	_preview.custom_minimum_size = Vector2(292,138)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_preview)
	side.add_child(_label("ЖУРНАЛ БОЯ",12,GOLD))
	_log = RichTextLabel.new()
	_log.name = "BattleLog"
	_log.custom_minimum_size = Vector2(292,80)
	_log.size_flags_vertical = SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size",13)
	_log.scroll_following = true
	_log.selection_enabled = true
	side.add_child(_log)
	_actions = HFlowContainer.new()
	_actions.name = "BattleActions"
	_actions.add_theme_constant_override("separation",7)
	column.add_child(_actions)
	_notice = _label("",14,GOLD)
	_notice.name = "BattleNotice"
	_notice.custom_minimum_size.y = 36
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_notice)

func _refresh() -> void:
	if life_session != null: runner=life_session.runner
	state = runner.view()
	board.area_cells.clear()
	board.area_targets.clear()
	if state.is_empty(): return
	if _active != int(state.active_actor_id):
		_active = int(state.active_actor_id)
		_selected = ""
		_inspected = _active
		board.route.clear()
		_delay = 0.55
	var active: Dictionary = _actor(_active)
	_title.text = ("Области · Раунд %s" if state.ruleset == Sm2MagicSnapshot.AREA_RULESET else "Магия · Раунд %s" if state.ruleset == Sm2MagicSnapshot.RULESET else "Эффекты · Раунд %s" if state.ruleset == Sm2EffectSnapshot.RULESET else "Стычка · Раунд %s") % state.round
	if state.ruleset in [Sm2DevelopmentSnapshot.RULESET,Sm2EncounterOrigin.RULESET,Sm2EncounterOrigin.PARTY_RULESET,Sm2EncounterOrigin.BODY_RULESET,Sm2EncounterOrigin.PROSTHESIS_RULESET,Sm2EncounterOrigin.PSIONIC_RULESET,Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET,Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET,Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET]: _title.text = "Развитие · Раунд %s" % state.round
	var ids: Array[String] = []
	for id: int in state.main_queue: ids.append("№%s" % id)
	var deferred: Array[String] = []
	for id: int in state.deferred_queue: deferred.append("№%s" % id)
	var turn_label: String = "Ваш ход: " if _player_turn() else "Ход противника: "
	if active.get("morale", "") == "fleeing": turn_label = "Отступает: "
	_queue.text = turn_label + Sm2BattleText.actor(active) + "     |     Очередь: " + " → ".join(ids)
	if not deferred.is_empty(): _queue.text += "     |     Ожидают: " + " → ".join(deferred)
	_reachable.clear()
	_targets.clear()
	if _player_turn() and _path.is_empty():
		var reached: Dictionary = runner.reachable(_active)
		if reached.ok:
			for cell: Dictionary in reached.cells: _reachable[Vector2i(int(cell.q),int(cell.r))] = cell
		else: _notice.text = "Не удалось рассчитать путь: " + str(reached.reason)
		for actor: Dictionary in state.actors:
			if actor.alive and actor.on_field and (actor.side != active.side or not _effect_action(_selected).is_empty()):
				var command: Sm2Command = _command("use_ability", _attack_id(), int(actor.actor_id))
				var check: Dictionary = runner.preview(command)
				if check.allowed: _targets[Vector2i(int(actor.q),int(actor.r))] = check
	board.update_view(state, _reachable if _selected.is_empty() else {}, _targets, _inspected)
	_inspect(_inspected)
	_refresh_actions()
	_preview.text = "Наведите на противника: шанс и урон.\nНа свободную клетку: путь и стоимость.\n\nСветлое кольцо — активный боец.\n+1 / +2 — высота. Камни закрывают проход."
	if not state.finished and _spell_action(_selected).get("operation") == "area_hp_damage": _hovered(board.hover)
	if state.finished:
		_path.clear()
		var outcome: Dictionary = runner.outcome()
		_title.text = "Победа отряда" if outcome.winner == "company" else ("Отряд отступил или разбит" if outcome.winner == "opposition" else "Ничья")
		_queue.text = "Бой завершён · Раунд %s" % state.round
		_preview.text = "ИТОГ СРАЖЕНИЯ\n"
		for side: String in ["company","opposition"]:
			var counts: Dictionary = outcome.counts[side]
			_preview.text += "%s\nНа поле: %s · Погибли: %s · Ушли: %s\n" % ["Ваш отряд" if side == "company" else "Противник",counts.on_field,counts.dead,counts.escaped]
		if not _finished_seen:
			runner.record_outcome()
			_finished_seen = true
			_notice.text = "Бой завершён. Можно сохранить итог или вернуться в меню."
	if not runner.error_reason().is_empty(): _notice.text = "Бой остановлен из-за ошибки: " + runner.error_reason()

func _refresh_actions() -> void:
	for child: Node in _actions.get_children(): _actions.remove_child(child); child.queue_free()
	var player: bool = _player_turn() and _path.is_empty()
	_actions.add_child(_button("Движение", "MoveButton", func() -> void: _selected = ""; _refresh(), not player))
	var active: Dictionary = _actor(_active)
	if not active.is_empty():
		for id: String in active.abilities:
			var self_target: bool = id.ends_with("shieldwall") or _spell_action(id).get("operation")=="self_barrier"
			var text_value: String = _ability_name(id)
			if _selected == id: text_value = "• " + text_value
			var disabled_value: bool = not player
			if self_target: disabled_value = disabled_value or not runner.preview(_command("use_ability",id,_active)).allowed
			var button: Button = _button(text_value, "Ability_"+id.get_slice(".",1), _ability_clicked.bind(id,self_target),disabled_value)
			if _spell_action(id).get("operation")=="self_barrier":
				button.tooltip_text="Щит на себя до следующего хода. Поглощает атаки после брони; яд проходит. Повтор обновляет защиту."
				button.mouse_entered.connect(_barrier_preview.bind(id))
			_actions.add_child(button)
	for action: Array in [["wait","Ждать","WaitButton"],["end_turn","Конец хода","EndTurnButton"],["escape","Уйти с поля","EscapeButton"]]:
		var check: Dictionary = runner.preview(_command(action[0]))
		var button: Button = _button(action[1],action[2],_execute_kind.bind(action[0]),not player or not check.allowed)
		button.tooltip_text = "" if check.allowed else Sm2BattleText.reason(check.reason)
		_actions.add_child(button)

func _barrier_preview(id: String) -> void:
	var check: Dictionary=runner.preview(_command("use_ability",id,_active))
	_preview.text="Псионический щит · на себя\n"
	if not check.allowed: _preview.text+=Sm2BattleText.reason(check.reason); return
	_preview.text+=_cost_text(check)
	_preview.text+="Цена: %s действий · %s концентрации\n" % [check.ap_cost,check.mana_cost]
	_preview.text+=Sm2AbilityParameterText.describe(check.capacity_calculation,"Защита","защиты","защиты")
	_preview.text+="\nДо начала следующего хода.\nАтаки поглощаются после брони; яд проходит.\nПовтор заменит оставшиеся %s защиты.\nПрактика Псионики и Резонанса." % check.previous

func _player_turn() -> bool:
	if state.is_empty() or state.finished or not runner.error_reason().is_empty(): return false
	var active: Dictionary = _actor(int(state.active_actor_id))
	return not active.is_empty() and active.controller == "player" and active.morale != "fleeing"

func _actor(id: int) -> Dictionary:
	for actor: Dictionary in state.get("actors",[]):
		if int(actor.actor_id) == id: return actor
	return {}

func _inspect(id: int) -> void:
	var actor: Dictionary = _actor(id)
	if actor.is_empty(): _inspector.text = "Наведите на бойца"; return
	var head: Dictionary = Sm2BattleText.item(actor,"head")
	var body: Dictionary = Sm2BattleText.item(actor,"body")
	var shield: Dictionary = Sm2BattleText.item(actor,"shield")
	var weapon: Dictionary = Sm2BattleText.item(actor,"weapon")
	_inspector.text = "%s · %s\nЗдоровье: %s / %s\nДействия: %s / %s · Усталость: %s / %s\nШлем: %s · Броня: %s · Щит: %s\n%s · Инициатива: %s" % [Sm2BattleText.actor(actor),"отряд" if actor.side == "company" else "враг",actor.combat.hp,actor.hp_max,actor.ap,actor.ap_max,actor.fatigue,actor.fatigue_max,head.get("current",0),body.get("current",0),shield.get("current",0),Sm2BattleText.MORALE.get(actor.morale,actor.morale),actor.initiative]
	if str(weapon.get("definition_id","")).ends_with("bow"): _inspector.text += "\nСтрелы: %s" % weapon.ammo
	elif actor.combat.shieldwall_source != "0": _inspector.text += "\nЗащита щитом активна"
	if actor.has("effects") and not actor.get("psionic",false):
		var details: String = _inspector.text
		_inspector.text = "%s · HP %s/%s · AP %s/%s\n" % [Sm2BattleText.actor(actor),actor.combat.hp,actor.hp_max,actor.ap,actor.ap_max]
		for effect: Dictionary in actor.effects: _inspector.text += Sm2BattleText.effect_description(effect)+"\n"
		if actor.effects.is_empty(): _inspector.text += "Нет временных эффектов\n"
		var profile: Dictionary = actor.effect_profile
		if profile.get("immunities",[]).has("status.poison"): _inspector.text += "Иммунитет к отравлению\n"
		_inspector.text += "Сопротивление яду: %s%%\n" % profile.get("resistances",{}).get("poison",0)
		_inspector.text += details+"\n"
		for stat: String in actor.stats:
			_inspector.text += "%s: %s (эффекты %+d)\n" % [Sm2BattleText.STATS.get(stat,stat),actor.stats[stat].value,actor.stats[stat].flat]

	if actor.has("mana") and not actor.get("psionic",false):
		_inspector.text = "Мана: %s / %s · +%s за раунд\nСопротивление магии: %s%%\n" % [actor.mana,actor.magic_profile.mana_max,actor.magic_profile.mana_per_round,actor.magic_profile.arcane_resistance] + _inspector.text
	if actor.has("development"):
		var development_lines: String="%s · HP %s/%s · AP %s/%s\nУсталость %s/%s · %s\n" % [actor.display_name,actor.combat.hp,actor.hp_max,actor.ap,actor.ap_max,actor.fatigue,actor.fatigue_max,Sm2BattleText.MORALE.get(actor.morale,actor.morale)]
		if actor.development.has("growth"):
			development_lines+="Уровень %s · общий опыт %s/%s\n" % [actor.development.growth.level,actor.development.growth.progress,actor.development.growth.needed]
		var shown_tracks: Array[String]=[]
		shown_tracks.assign(["p1:skill.melee","p1:skill.psionics","p4a:stat.resonance"] if state.ruleset==Sm2EncounterOrigin.HYBRID_RULESET else ["p1:stat.strength","p1:skill.psionics","p4a:stat.resonance"] if state.ruleset in [Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET] else ["p1:skill.psionics","p4a:stat.resonance"] if state.ruleset in [Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET,Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET,Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET] else ["p1:skill.psionics"] if actor.get("psionic",false) else ["p1:stat.strength","p1:skill.melee"])
		for track: Dictionary in actor.development.tracks:
			if actor.development.has("growth") or track.id not in shown_tracks: continue
			if int(track.get("upgrade_bonus",0))>0:
				development_lines+="%s: свой %s +%s улучшение = %s\n" % [track.name,track.level,track.upgrade_bonus,track.effective]
				continue
			development_lines += "%s %s · опыт %s/%s\n" % [track.name,track.level,track.progress,track.needed]
		development_lines += "Навык попадания %s (развитие %+d)\nШлем %s · Броня %s · Щит %s" % [actor.melee_stat.value,actor.development.melee_bonus,head.get("current",0),body.get("current",0),shield.get("current",0)]
		_inspector.text=development_lines
	if actor.has("barrier") and int(actor.magic_profile.mana_max)>0:
		_inspector.text="Пси-щит: %s · до следующего хода\n" % actor.barrier.get("remaining",0)+_inspector.text if not actor.barrier.is_empty() else "Пси-щит: не действует\n"+_inspector.text
	if actor.get("psionic",false) and int(actor.magic_profile.mana_max)>0:
		_inspector.text="Концентрация: %s/%s · +%s за раунд\n" % [actor.mana,actor.magic_profile.mana_max,actor.magic_profile.mana_per_round]+_inspector.text
	if actor.has("body_functions"):
		for part: Dictionary in actor.body_functions.parts:
			if not part.working or not str(part.get("prosthesis_id","")).is_empty(): _inspector.text+="\n"+("Правая рука" if part.id=="right_hand" else "Левая рука")+": "+Sm2BattleText.function_status(part)

func actor_upgrade_cost() -> int:
	return int(_actor(_active).get("upgrade_attack_fatigue",0))

func _spell_action(id: String) -> Dictionary:
	for spell: Dictionary in _actor(_active).get("spells",[]):
		if spell.id == id: return spell
	return {}

func _effect_action(id: String) -> Dictionary:
	for action: Dictionary in _actor(_active).get("effect_actions",[]):
		if action.id == id: return action
	return {}

func _ability_name(id: String) -> String:
	for hybrid: Dictionary in _actor(_active).get("hybrids",[]):
		if hybrid.id==id: return hybrid.name
	var spell: Dictionary = _spell_action(id)
	if not spell.is_empty(): return spell.name
	var action: Dictionary = _effect_action(id)
	return action.name if not action.is_empty() else Sm2BattleText.ability(id)

func _attack_id() -> String:
	if not _selected.is_empty(): return _selected
	var actor: Dictionary = _actor(_active)
	for id: String in actor.get("abilities",[]):
		if not id.ends_with("shieldwall") and not id.ends_with("split_shield"): return id
	return ""

func _command(kind: String, ability: String = "", target_id: int = 0, cell: Vector2i = Vector2i.ZERO) -> Sm2Command:
	var result: Sm2Command = Sm2Command.new()
	if state.get("ruleset") in [Sm2DevelopmentSnapshot.RULESET,Sm2EncounterOrigin.RULESET,Sm2EncounterOrigin.PARTY_RULESET,Sm2EncounterOrigin.BODY_RULESET,Sm2EncounterOrigin.PROSTHESIS_RULESET,Sm2EncounterOrigin.PSIONIC_RULESET,Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET,Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET,Sm2EncounterOrigin.UPGRADE_RULESET,Sm2EncounterOrigin.IMPLANT_RULESET,Sm2EncounterOrigin.HYBRID_RULESET]: result.battle_id = state.battle_id
	result.kind = kind
	result.actor_id = _active
	result.expected_revision = int(state.get("revision",0))
	result.ability_id = ability
	result.target_actor_id = target_id
	result.target = cell
	return result

func _hovered(cell: Vector2i) -> void:
	board.route.clear()
	board.area_cells.clear()
	board.area_targets.clear()
	board.queue_redraw()
	if state.is_empty(): return
	var target: Dictionary = board.actor_at(cell)
	_inspect(int(target.actor_id) if not target.is_empty() else _inspected)
	if state.finished: return
	if not _player_turn() or not _path.is_empty():
		_preview.text = "Противник выполняет ход…" if not _player_turn() else "Отряд движется по маршруту…"
		return
	if _spell_action(_selected).get("operation") == "area_hp_damage":
		if not board.field.in_bounds(cell):
			_preview.text = "Выберите центральный гекс области.\nСвои бойцы не получают урон."
			return
		var check: Dictionary = runner.preview(_command("use_ability",_selected,0,cell))
		board.area_cells.assign(check.get("cells",[]))
		_preview.text = "%s · центр (%s, %s)\nТолько противники · радиус %s\n" % [_ability_name(_selected),cell.x,cell.y,_spell_action(_selected).radius]
		if not check.allowed: _preview.text += Sm2BattleText.reason(check.reason)+"\n"
		if check.has("name"):
			_preview.text += "Цена: %s AP · %s усталости · %s маны\n" % [check.ap_cost,check.fatigue_cost,check.mana_cost]
		for hit: Dictionary in check.get("targets",[]):
			board.area_targets.append(Vector2i(int(hit.q),int(hit.r)))
			_preview.text += "№%s: %s HP · сопротивление %s%%%s\n" % [hit.actor_id,hit.hp_loss,hit.resistance," · смертельно" if hit.lethal else ""]
		board.queue_redraw()
		return
	if not target.is_empty() and (target.side != _actor(_active).side or not _effect_action(_selected).is_empty()):
		var id: String = _attack_id()
		var check: Dictionary = runner.preview(_command("use_ability",id,int(target.actor_id)))
		_preview.text = "%s → №%s\n" % [_ability_name(id),target.actor_id]
		if not check.allowed: _preview.text += Sm2BattleText.reason(check.reason); return
		if actor_upgrade_cost()>0 and check.get("kind","")=="" and not check.has("hybrid"): _preview.text+="Улучшения тела: +%s усталости за физическую атаку (включено в цену).\n" % actor_upgrade_cost()
		if check.has("hybrid"):
			_preview.text+="Цена: %s ОД · %s усталости\nКонцентрация: %s · пси-часть: %s\n" % [check.ap_cost,check.fatigue_cost,check.mana_cost,check.hybrid.psionic_damage]
		else:
			_preview.text += "Цена: %s действий · %s усталости\n" % [check.ap_cost,check.fatigue_cost]
		if check.get("kind","") == "spell":
			if check.channel=="psionic":
				if check.has("damage_calculation"):
					_preview.text+=_cost_text(check)
					_preview.text+="Концентрация: %s · цель потеряет %s HP\n" % [check.mana_cost,check.hp_loss]
					_preview.text+=Sm2AbilityParameterText.describe(check.damage_calculation)+"\nБез промаха; обходит броню и предметный щит.\nПрактика Псионики и Резонанса."
				else:
					_preview.text+="Концентрация: %s\nУрон здоровью: %s HP\nОбходит броню и щит.\nГарантированное попадание.\nПрактика Псионики за применение." % [check.mana_cost,check.hp_loss]
			else:
				_preview.text += "Мана: %s\nУрон здоровью: %s HP\nСопротивление магии: %s%%\nОбходит броню и щит.\nБез броска попадания." % [check.mana_cost,check.hp_loss,check.resistance]
			if check.has("absorbed") and check.absorbed>0: _preview.text+="\nПси-щит поглотит: %s." % check.absorbed
			if check.lethal: _preview.text += "\nСмертельный урон."
		elif check.get("kind","") == "effect":
			_preview.text += "Наложение без броска попадания.\n" if check.operation == "apply_effect" else "Снять эффекты:\n"
			for effect: Dictionary in check.effects:
				_preview.text += Sm2BattleText.effect_description(effect)+"\n"
		elif id.ends_with("split_shield"):
			_preview.text += "Щит потеряет %s прочности\nБез броска попадания" % check.shield_loss
		else:
			_preview.text += "Попадание: %s%%\n" % check.hit_chance
			if not target.get("barrier",{}).is_empty(): _preview.text+="Пси-щит цели: %s. Потери HP ниже уже учитывают защиту.\n" % target.barrier.remaining
			for zone: Dictionary in check.zones:
				_preview.text += "%s (%s%%): HP %s–%s, броня %s–%s\n" % [str(check.function_trauma) if check.has("function_trauma") else "Голова" if zone.id == "head" else "Тело",zone.chance,zone.hp_min,zone.hp_max,zone.armor_min,zone.armor_max]
			_preview.text += "Урон указан при попадании."
			if check.has("hybrid"):
				_preview.text+="\nПси-часть уже включена в потери HP выше.\nПромах: урона нет, затраты и практика сохраняются."
				_preview.text+="\n"+_cost_text(check)
			if check.has("function_trauma"): _preview.text += "\n"+str(check.function_trauma)+(": утрата при потере HP выжившей целью; установленный протез повреждается." if check.get("function_sever",false) else ": травма при потере HP, если цель выживет.")
	elif _reachable.has(cell) and _selected.is_empty():
		var value: Dictionary = _reachable[cell]
		board.route.assign(value.path)
		_preview.text = "Перемещение: (%s, %s)\nЦена пути: %s действий · %s усталости\nШагов: %s\n\nКаждый шаг выполняется отдельно. Попадание ответного удара остановит движение." % [cell.x,cell.y,value.ap_cost,value.fatigue_cost,value.path.size()]
	elif board.field.in_bounds(cell):
		_preview.text = "Клетка (%s, %s)\n" % [cell.x,cell.y]
		_preview.text += "Недоступна для перемещения сейчас." if target.is_empty() else "Вы управляете только бойцом, чей ход наступил."
	board.queue_redraw()

func _clicked(cell: Vector2i, right: bool) -> void:
	if right:
		_path.clear()
		_selected = ""
		_refresh()
		return
	if not board.field.in_bounds(cell): return
	var target: Dictionary = board.actor_at(cell)
	if not target.is_empty():
		_inspected = int(target.actor_id)
		_inspect(_inspected)
	if not _player_turn() or not _path.is_empty(): return
	if _spell_action(_selected).get("operation") == "area_hp_damage":
		_execute(_command("use_ability",_selected,0,cell))
		return
	if not target.is_empty():
		if target.side != _actor(_active).side or not _effect_action(_selected).is_empty(): _execute(_command("use_ability",_attack_id(),int(target.actor_id)))
		return
	if not _selected.is_empty(): _notice.text = "Выберите противника для атаки или нажмите «Движение»."; return
	if not _reachable.has(cell): _notice.text = "До этой клетки сейчас нельзя дойти."; return
	_path.assign(_reachable[cell].path)
	board.route.clear()
	_walking_actor = _active
	_walk_step()

func _ability_clicked(id: String, self_target: bool) -> void:
	if self_target: _execute(_command("use_ability",id,_active))
	else: _selected = id; _refresh(); _notice.text = "Выберите цель: " + _ability_name(id)

func _execute_kind(kind: String) -> void:
	_execute(_command(kind))

func _execute(command: Sm2Command) -> Sm2CommandResult:
	var result: Sm2CommandResult = life_session.attack(command) if life_session != null else runner.execute_player(command)
	if result.accepted:
		_append(result.events)
		_notice.text = "Отход остановлен попаданием." if result.code == "movement_interrupted" else "Действие выполнено."
	else: _notice.text = Sm2BattleText.reason(result.code)
	_refresh()
	return result

func _walk_step() -> void:
	if _path.is_empty(): return
	if _walking_actor != _active or not _player_turn(): _path.clear(); _refresh(); return
	var next: Vector2i = _path.pop_front()
	var result: Sm2CommandResult = _execute(_command("move","",0,next))
	if not result.accepted or result.code == "movement_interrupted" or _active != _walking_actor: _path.clear()
	_delay = 0.18
	_refresh()

func _process(delta: float) -> void:
	if is_instance_valid(_development_panel): return
	if runner == null or state.is_empty() or state.finished or not auto_advance: return
	_delay -= delta
	if _delay > 0: return
	if not _path.is_empty(): _walk_step(); return
	if not _player_turn() and runner.error_reason().is_empty():
		var result: Dictionary = life_session.step() if life_session != null else runner.step()
		if result.ok and result.has("events"): _append(result.events)
		if not result.ok: _notice.text = "Бой остановлен: " + str(result.reason)
		_refresh()
		_delay = 0.48

func _append(events: Array[Dictionary]) -> void:
	_journal.append_array(Sm2BattleText.lines(events))
	while _journal.size() > 150: _journal.pop_front()
	_log.text = "\n".join(_journal)

func _open_development() -> void:
	if is_instance_valid(_development_panel): return
	_path.clear()
	_development_panel=Sm2BattleProgressPanel.new(); _development_panel.name="BattleProgressPanel"; _development_panel.runner=runner; _development_panel.life_session=life_session
	_development_panel.changed.connect(_append)
	_development_panel.close_requested.connect(func() -> void:
		remove_child(_development_panel); _development_panel.queue_free(); _development_panel=null; _refresh())
	add_child(_development_panel)

func _save() -> void:
	_path.clear()
	var result: Dictionary = life_session.save_game() if life_session != null else runner.save_game()
	_refresh()
	_notice.text = "Бой сохранён." if result.ok else "Не удалось сохранить бой: " + str(result.errors)

func _load() -> void:
	var result: Dictionary = life_session.load_game() if life_session != null else runner.load_game()
	if life_session != null: runner=life_session.runner
	if result.ok and life_session != null and not life_session.world.busy(): menu_requested.emit(); return
	if result.ok:
		_path.clear()
		_selected = ""
		_inspected = int(runner.view().active_actor_id)
		board.route.clear()
		_finished_seen = false
		_journal.clear()
		_journal.append("Бой восстановлен из сохранения.")
		_log.text = "\n".join(_journal)
	_refresh()
	_notice.text = "Бой загружен." if result.ok else "Не удалось загрузить бой. Текущее состояние сохранено."

static func _label(value: String, font_size: int, tint: Color) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	return label

static func _button(value: String, node_name: String, action: Callable, disabled_value: bool = false) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = value
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size",14)
	button.disabled = disabled_value
	button.pressed.connect(action)
	return button

func _cost_text(check: Dictionary) -> String:
	var text: String=""
	for source: Dictionary in check.get("cost_calculation",{}).get("sources",[]): text+="%s: +%s концентрации (включено в цену).\n" % [source.name,source.amount]
	return text
