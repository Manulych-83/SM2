class_name Sm2BattleText
extends RefCounted
const STATS: Dictionary = {"melee_skill":"Ближний навык","ranged_skill":"Дальний навык","melee_defense":"Ближняя защита","ranged_defense":"Дальняя защита"}
const EFFECT_REASONS: Dictionary = {"effect_immune":"Цель невосприимчива к этому эффекту", "effect_already_full":"Эффект уже действует полный срок", "no_dispellable_effects":"Нет отрицательных эффектов для снятия", "effect_target_side":"Выберите подходящего союзника или противника", "effect_limit":"Достигнут предел эффектов", "effect_id_limit":"Исчерпан счётчик эффектов"}
const ABILITIES: Dictionary = {"psionic_strike":"Псионический удар","hand_strike":"Удар по правой руке", "shield_hand_strike":"Удар по левой руке","sword_strike": "Удар мечом", "spear_thrust": "Укол копьём", "axe_strike": "Удар топором", "bow_shot": "Выстрел", "split_shield": "Разрубить щит", "shieldwall": "Защита щитом"}
const MORALE: Dictionary = {"steady": "Уверен", "wavering": "Колеблется", "breaking": "На грани", "fleeing": "Бежит"}
const REASONS: Dictionary = {"area_cell_required":"Выберите центральный гекс", "area_center_blocked":"Здесь нельзя разместить центр области", "area_no_enemies":"В области нет противников", "target_out_of_bounds":"Выберите клетку поля", "not_active_actor": "Сейчас ходит другой боец", "insufficient_ap": "Не хватает очков действий", "fatigue_limit": "Не хватает сил", "attack_range": "Цель вне дальности", "line_of_sight_blocked": "Линия огня перекрыта", "ranged_in_control": "Враг рядом мешает стрелять", "elevation_gap": "Слишком большой перепад высоты", "target_shield_missing": "У цели нет целого щита", "shieldwall_already_used": "Защита уже использована в этом раунде", "no_ammunition": "Закончились стрелы", "wait_already_used": "Ожидание уже использовано", "wait_phase": "В отложенном ходе ждать нельзя", "escape_boundary_required": "Выход доступен только на краю поля", "battle_finished": "Бой завершён", "occupied": "Клетка занята", "impassable": "Непроходимая клетка", "not_player_turn": "Сейчас ход противника", "fleeing_cannot_wait": "Бегущий боец не может ждать", "fleeing_cannot_attack": "Бегущий боец не может атаковать"}

static func effect_description(effect: Dictionary) -> String:
	var text_value: String = effect.name
	if effect.has("remaining"): text_value += " · осталось %s завершений хода" % effect.remaining
	for op: Dictionary in effect.get("operations",[]):
		if op.kind == "periodic_hp_damage": text_value += "\nТик: %s HP · сопротивление %s%%" % [op.tick_loss,op.resistance]
		elif op.kind == "flat_stat_modifier": text_value += "\n%s: %+d" % [STATS.get(op.stat,op.stat),op.amount]
	return text_value

static func function_status(part: Dictionary) -> String:
	if not str(part.get("prosthesis_id","")).is_empty(): return "протез работает" if part.working else "протез повреждён"
	if part.get("missing",false): return "рука утрачена · нужен протез"
	return "работает" if part.working else "тяжёлая травма · не работает"

static func ability(id: String) -> String:
	if id=="p4:ability.sever_right": return "Отсечь правую руку"
	if id=="p4:ability.sever_left": return "Отсечь левую руку"
	if id=="p4:ability.punch": return "Удар кулаком"
	return ABILITIES.get(id.get_slice(".", 1), id)

static func actor(data: Dictionary) -> String:
	if data.is_empty(): return "Боец"
	if data.has("display_name"): return "%s №%s" % [data.display_name,data.actor_id]
	var role: String = "Боец"
	var id: String = data.loadout_id
	if id.contains("archer"): role = "Лучник"
	elif id.contains("shieldbearer"): role = "Щитоносец"
	elif id.contains("spear"): role = "Копейщик"
	elif id.contains("axe"): role = "Секироносец"
	elif id.contains("sword"): role = "Мечник"
	return "%s №%s" % [role, data.actor_id]

static func reason(code: String) -> String:
	if code == "self_target_required": return "Эта способность применяется только на себя"
	if code == "insufficient_concentration": return "Не хватает концентрации"
	if code == "insufficient_mana": return "Не хватает маны"
	if code == "spell_enemy_required": return "Заклинание требует противника"
	return EFFECT_REASONS.get(code,REASONS.get(code, "Действие недоступно (%s)" % code))

static func item(actor_data: Dictionary, slot: String) -> Dictionary:
	for entry: Dictionary in actor_data.combat.items:
		if entry.slot == slot: return entry
	return {}

static func lines(events: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in events:
		var source: String = "№" + str(event.get("actor_id", ""))
		var target: String = "№" + str(event.get("target_actor_id", ""))
		match event.type:
			"anatomy_injured": result.append("№%s: ранение %s, кровотечение %s мл/мин" % [event.target_actor_id,event.part,event.bleeding])
			"wound_bandaged": result.append("№%s перевязал рану №%s у №%s" % [event.actor_id,event.wound_id,event.target_actor_id])
			"physiology_advanced": result.append("Прошло %s сек. Учтена кровопотеря." % event.seconds)
			"barrier_cast": result.append("%s: пси-щит — %s защиты до следующего хода" % [source,event.capacity])
			"barrier_absorbed": result.append("%s: пси-щит поглотил %s, осталось %s" % [target,event.amount,event.remaining])
			"barrier_removed": result.append("%s: пси-щит снят (%s)" % [target,{"expired":"начался следующий ход","death":"смерть","escaped":"выход с поля","battle_finished":"конец боя"}.get(event.reason,event.reason)])
			"body_part_lost": result.append("Участник №%s: %s — утрачена" % [event.target_actor_id,event.name])
			"prosthesis_damaged": result.append("Участник №%s: %s — протез повреждён" % [event.target_actor_id,event.name])
			"body_function_lost": result.append("Участник №%s: %s — тяжёлая травма" % [event.target_actor_id,event.name])
			"companion_experience_awarded": result.append("%s: общий опыт +%s · уровень %s" % [source,event.amount,event.level_after])
			"battle_practice_awarded": result.append("%s: %s +%s опыта · уровень %s" % [source,event.name,event.amount,event.level_after])
			"battle_node_purchased": result.append("%s изучил «%s» за %s опыта" % [source,event.name,event.cost])
			"hybrid_started": result.append("%s: %s → %s" % [source,event.name,target])
			"hybrid_damage": result.append("%s: физическая часть %s, пси-часть %s до пси-щита" % [source,event.physical,event.psionic])
			"concentration_spent": result.append("%s: −%s концентрации, осталось %s" % [source,event.amount,event.current])
			"concentration_recovered": result.append("%s: +%s концентрации, теперь %s/%s" % [source,event.amount,event.current,event.maximum])
			"mana_spent": result.append("%s: −%s маны, осталось %s" % [source,event.amount,event.current])
			"mana_recovered": result.append("%s: +%s маны, теперь %s/%s" % [source,event.amount,event.current,event.maximum])
			"area_spell_cast": result.append("%s: %s · центр (%s, %s) · целей: %s" % [source,event.name,event.q,event.r,event.target_count])
			"spell_cast": result.append("%s → %s: %s · %s HP" % [source,target,event.name,event.loss])
			"effect_applied", "effect_refreshed": result.append("%s: %s · срок %s" % [target,event.name,event.remaining])
			"effect_ticked": result.append("%s: %s, тик −%s HP" % [target,event.name,event.loss])
			"effect_removed": result.append("%s: %s снят (%s)" % [target,event.name,{"expired":"срок истёк","dispelled":"очищение","death":"смерть","escaped":"выход","battle_finished":"конец боя"}.get(event.reason,event.reason)])
			"round_started": result.append("— Раунд %s —" % event.round)
			"attack_hit": result.append("%s попал по %s · шанс %s%%, бросок %s" % [source, target, event.hit_chance, event.roll])
			"attack_missed": result.append("%s промахнулся по %s · шанс %s%%, бросок %s" % [source, target, event.hit_chance, event.roll])
			"hp_damaged": result.append("%s: −%s здоровья, осталось %s" % [target, event.loss, event.remaining])
			"armor_damaged": result.append("%s: %s −%s" % [target, "шлем" if event.zone == "head" else "броня", event.loss])
			"actor_died": result.append("%s погиб" % source)
			"actor_escaped": result.append("%s покинул поле боя" % source)
			"morale_changed": result.append("%s: %s" % [source, MORALE.get(event.to, event.to)])
			"reaction_spent": result.append("%s: ответный удар по %s" % [source, target])
			"movement_interrupted": result.append("%s: отход остановлен попаданием" % source)
			"shieldwall_started": result.append("%s прикрылся щитом" % source)
			"shield_destroyed": result.append("Щит %s разрушен" % target)
			"shield_damaged": result.append("Щит %s: −%s, осталось %s" % [target, event.loss, event.remaining])
			"actor_waited": result.append("%s откладывает ход" % source)
			"moved": result.append("%s: шаг на (%s, %s)" % [source, event.q, event.r])
			"battle_finished": result.append("Бой завершён")
	return result
