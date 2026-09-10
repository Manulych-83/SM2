# M2.2 — контракт очереди и сохранения

Объём согласован командой пользователя «делай» после предложения M2.2. Реализован §4 и соответствующая часть §10.4 COMBAT_RULES_M2.md. Этот документ фиксирует действующие контракты; фактические результаты запусков и границы приёмки — в [STATUS_M2_2.md](STATUS_M2_2.md).

## Граница и владение

Новый координатор `Sm2TacticalBattle` развивает M2, используя существующие Sm2SpatialQueries и Sm2MovementResolver. M1 остаётся совместимой технической fixture; Sm2FieldSession остаётся пространственной проверкой M2.1. Не копировать в M2 формулы или очередь M1. Доступны move/wait/end_turn, ещё нет атак, реакций, щита, моральных проверок, бегства, ИИ и UI. Мораль/жизнь/участие во входе — готовые состояния для расчёта очереди, без реализации их изменения.

- Модели и планировщик: `src/domain/tactical/sm2_tactical_actor.gd`, `sm2_tactical_state.gd`, `sm2_turn_scheduler.gd`.
- Проверка снимка: `src/domain/tactical/sm2_tactical_snapshot.gd`.
- Определения и авторский контент: `src/domain/content/sm2_turn_definition.gd`, `sm2_turn_catalog.gd`, `src/content/turns/**`, `content/m2/turns/**`, `content/m2/turn_scenario.tres`.
- Командная транзакция: `src/domain/tactical/sm2_tactical_battle.gd`; прикладной слот: `src/application/sm2_tactical_session.gd`.

Все запускаемые процессы используют tools и RuntimeRoot внутри E:\GPT\SM2. Приёмку проводить на стабильных исходниках; изменение проверяемых файлов требует нового прогона.

## Данные характеристик (content API)

`Sm2TurnCatalog` RefCounted: build(raw)->PackedStringArray атомарно; to_data()->Dictionary копия; fingerprint()->String; version()->String; has_loadout(id)->bool; definition(loadout_id)->Sm2TurnDefinition копия или null.

Raw exact: `{version, profiles:Array[{id,ap_max,fatigue_base,initiative_base}], equipment:Array[{id,load_penalty}], loadouts:Array[{id,profile_id,equipment_ids:Array[String]}]}`. ID уникальны в своей коллекции, ссылки правильного типа, повтор одного предмета в loadout запрещён. Лимиты: ap_max1..1000, fatigue_base15..10000, initiative_base0..10000, gear load0..10000; до64 предметов в loadout, до10000 определений каждой коллекции. Сумма нагрузки <=fatigue_base−15. Это только свойства экипировки для ресурсов/инициативы; атаки/броня добавляются на M2.3.

`Sm2TurnDefinition`: id:String (loadout), ap_max:int, fatigue_base:int, initiative_base:int, load_penalty:int, fatigue_max:int=fatigue_base−load_penalty. Это вычисленные определения, не живые экземпляры вещей.

Авторские Resource: профили щитоносец/боец/лучник (AP9, fatigue100/100/90, initiative110/115/120); предметы sword5/spear6/axe7/bow4/shield10/padded8/mail15/helmet4; loadouts для четырёх сочетаний основной карты: spear+shield+mail+helmet, sword+shield+padded+helmet, axe+shield+mail+helmet, bow+padded+helmet. Данные не дублируют готовые fatigue_max или итоговую инициативу.

`Sm2TurnContentLoader.load_scenario(path="res://content/m2/turn_scenario.tres")->{ok,catalog:Sm2TurnCatalog|null,setup:Dictionary,errors:PackedStringArray}`. Авторский сценарий ссылается на существующий field manifest, turn catalog manifest, содержит round_limit=100 и соответствия actor_id→loadout_id. Перед публикацией проверяет точное покрытие маркеров, отсутствие лишних/повторных IDs, ссылки. ID1/5 — копьё;2 — меч;3/6 — лук;4 — топор. Владелец, сторона, контролёр, seed и позиции берутся из field manifest.

## Вход координатора

`Sm2TacticalBattle.new(catalog)` копирует каталог. `start(setup)->{ok,errors,events}` — кандидатная инициализация.

Setup exact: `{battle_id:String,scenario_id:String,seed:int,field:Dictionary,round_limit:int,actors:Array[Dictionary]}`; field — существующий raw Sm2Battlefield. Каждый actor exact: `{actor_id:int,loadout_id:String,side:String,owner:String,controller:String,creator:int,q:int,r:int,fatigue:int,alive:bool,on_field:bool,morale:String}`. Creator0 либо меньший существующий ID. ID1..9223372036854775805; до4096 записей; ровно две исходные стороны и минимум один живой участник на поле. Поле/занятость валидируются как в M2.1. Round_limit1..1000 — параметр сценария, основной100. Fatigue перед восстановлением не выше предела loadout. AP выдаются при начале раунда.

`Sm2TacticalActor`: spatial:Sm2SpatialActor, loadout_id:String, creator:int, morale:String; round_fatigue:int, round_morale:String, initiative:int; activation_started:bool, wait_used:bool, turn_done:bool, reactions_left:int. static from_setup(raw:Dictionary,catalog)->{ok,errors,actor|null}; copy()->Sm2TacticalActor; view()->Dictionary; to_data()->Dictionary. Пространственная модель получает ap_max/fatigue_max из определения. Живое состояние только в spatial, не дублировать позицию/ресурсы.

Actor to_data exact (плоский словарь): actor_id:String,loadout_id,side,owner,controller,creator:String,q,r,ap,fatigue,alive,on_field,morale,round_fatigue,round_morale,initiative,activation_started,wait_used,turn_done,reactions_left. AP max и fatigue max в snapshot не пишутся — восстанавливаются из каталога; view их добавляет и использует int IDs.

`Sm2TacticalState`: battle_id:String,scenario_id:String,field:Sm2Battlefield,round_limit:int,round:int (0 только до старта),revision:int,next_actor_id:int,actors:Dictionary[int,Sm2TacticalActor],sides:Array[String] (лексикографически),main_queue:Array[int],deferred_queue:Array[int],phase:String(main/deferred/finished),finished:bool,finish_reason:String(""/round_limit/no_participants),rng:Sm2DeterministicRng. actor(id)->Sm2TacticalActor|null; active_id()->int (голова очереди текущей фазы или0); sorted_ids()->Array[int]; occupancy()->Array[Vector2i]; copy()->Sm2TacticalState (глубокая); to_data(catalog_fingerprint:String)->Dictionary.

## Планировщик

`Sm2TurnScheduler` static: compute_initiative(definition:Sm2TurnDefinition,fatigue:int,morale:String)->int; start_round(state,catalog,events:Array[Dictionary])->void; advance(state,catalog,events)->void; wait_active(state,catalog,events)->void; end_active(state,catalog,events,automatic:bool=false)->void; after_action(state,catalog,events)->void. Работает только с кандидатом, не повышает revision и не трогает RNG/ID.

- start_round увеличивает round на1; если предыдущий уже round_limit — finished/round_limit без раунда101. Для живых on_field AP=max, fatigue=max(0, fatigue−15), reactions_left=1. Остальным AP0/reactions0. Для всех фиксируются round_fatigue и round_morale; initiative вычисляется по этим опорным значениям, wait_used/activation_started=false, turn_done=!occupies.
- I=max(0,floor((initiative_base−load_penalty−round_fatigue)*morale_percent/100)); steady100,wavering90,breaking80,fleeing100. Округление после max0 можно сделать положительным целочисленным делением. Мораль и усталость внутри раунда не пересортировывают очередь.
- main_queue содержит текущего и ещё не начавших по I desc, числовому ID asc. deferred_queue также всегда хранится в этом порядке. При начале основной активации activation_started=true, событие activation_started; при возврате после Wait — только activation_resumed, без выдачи ресурсов.
- wait разрешён только в main, active alive/on_field, не fleeing, AP>0, wait_used=false. Удаляет из main, выставляет wait_used=true, добавляет в deferred. AP/fatigue не меняются. Если main закончилась, начинается deferred. Последний Wait может сразу вернуть управление тому же актёру.
- end_turn выставляет AP0 и turn_done=true, убирает из текущей очереди и передаёт управление. after_action автоматически делает это при AP0; недоступного участника удаляет. advance исключает unavailable из обеих очередей (AP0,turn_done=true,reactions0), затем выбирает доступную активацию либо начинает новый раунд.
- При отсутствии любых alive/on_field завершение no_participants — защитная граница планировщика, не расчёт победителя. На старте такое состояние отклоняется. В M2.2 не определяются боевые победы.
- События (без общих метаданных): round_started, round_resources(actor_id,ap,fatigue,restored_fatigue), activation_started, activation_resumed, actor_waited, turn_ended(actor_id,automatic), round_limit_reached/no_participants. Actor IDs/round — строки; payload отделённый. Root добавляет battle_id,revision:String,sequence:int.

## Снимок и проверка

`Sm2TacticalSnapshot.decode(data:Dictionary,catalog:Sm2TurnCatalog)->{ok,errors:PackedStringArray,state:Sm2TacticalState|null}`. Ничего не публикует и не запускает scheduler. M1 и field_probe отклоняются.

State to_data exact: `{format:"sm2.battle",schema_version:2,ruleset:"sm2.m2.turns.1",catalog_fingerprint,battle_id,scenario_id,field:Dictionary,field_fingerprint,round_limit:int,round:String,revision:String,next_actor_id:String,actors:Array[actor_data],sides:Array[String],main_queue:Array[String],deferred_queue:Array[String],phase:String,active_actor_id:String,finished:bool,finish_reason:String,rng:{version,state:String,draws:String}}`.

Строго проверить списки полей, типы/диапазоны/ссылки, правильный fingerprint каталога и поля, уникальные возрастающие IDs массива actors <next_actor_id, creator-граф, максимум4096 actors, ровно2 исходные sides, занятость живых. JSON целые малые float разрешены только через Sm2Validate.integer перед int; IDs/большие счётчики — только канонические десятичные строки.

Очереди содержат существующих живых on_field, не повторяются/не пересекаются, отсортированы по сохранённой I/ID. I проверяется через round_fatigue/round_morale и каталог; нельзя пересчитывать её по текущей усталости. Флаги и разбиение:

- В main wait_used=false,turn_done=false; active основной имеет activation_started=true, остальные false.
- В deferred wait_used=true,activation_started=true,turn_done=false. У всех ожидающих AP>0.
- Вне очередей все turn_done=true и AP0; unavailable не попадают в очереди. У finished все очереди пусты, active0,phase=finished; reason проверяется (round_limit требует round=round_limit; no_participants требует отсутствие живых on_field).
- Для main-фазы main непуста; для deferred main пуста и deferred непуста; active_actor_id строго равен голове. Живой участник на поле вне очередей обязан иметь activation_started=true. Нельзя скрыть ещё не начавшего актёра из очереди, оставив started=false. В main-фазе уже начавшие находятся раньше головы по I/ID; завершённый Wait в этой фазе невозможен. В deferred-фазе завершившие отложенные ходы также предшествуют текущей голове. Обе очереди сохраняют хронологически правильный остаток соответствующего порядка.
- wait_used подразумевает activation_started; turn_done подразумевает AP0. Доступный active/pending/deferred имеет AP>0. Reactions0..1; флаги bool. Anchor fatigue0..max и morale из enum. В M2.2 после начала раунда fatigue может только расти; текущая fatigue>=round_fatigue, morale=round_morale. Публикация будущих новых эффектов потребует новой версии правил/инвариантов.

Это проверка согласованности устойчивого состояния, не доказательство всей истории команд или защита от осмысленно переписанного человеком save. Нельзя получить вторую выдачу ресурсов только из-за load. Нарушенная очередь не «исправляется» сортировкой.

## Координатор и приложение

Sm2TacticalBattle: start/execute(Sm2Command)->Sm2CommandResult/preview/view/capture/restore/state_hash/reachable(actor_id)/route(actor_id,target)/line_of_sight(a,b). Неверная команда inert; принятая работает на глубокой копии, resolver/планировщик разрешают её до устойчивой границы, revision+1, проверка итогового кандидата и публикация. Никакой файловой системы в domain. В M2.2 ни одна команда не расходует RNG и не выдаёт новые ID.

Sm2TacticalSession в application связывает этот координатор со старым Sm2SaveStore через отдельный слот `m2_prototype`. Сохранение сначала проверяет полный payload кандидатом, затем SaveStore. Загрузка проверяет envelope через Store, затем полный доменный кандидат; failure оставляет прежнюю живую сессию. Слот M1 `session` не трогается; неизвестный ruleset не мигрируется автоматически. До M2.3 snapshot не притворяется содержащим предметные экземпляры и атаки; последующее расширение получает совместимость явно.

## Проверка

Сначала чистый импорт. Suites: turn_scheduler, turn_content, m2_snapshot, m2_turns, m2_turn_storage; all сохраняет M1/M2.1. Нужны реальные раунды и команды: начальная очередь3/6/2/4/1/5; движение и Wait сохраняют ресурсы; все Wait/последний Wait; повторный Wait/fleeing wait запрещён; AP0 auto-end; fatigue15 ровно раз/round; инициативный tie и новые порядки; round_limit; dead/escaped пропуск; отделённость и inert failures.

Save/restore через настоящий Store в изолированном RuntimeRoot: до/после Wait, в deferred, перед новым раундом, после auto-end/round_limit; после reload следующие события/hash совпадают. Негативные случаи очередей/флагов/ID/каталога/поля/версии; файлы пользователя неизменны. Диагностический CLI M2.2 записывает реальные команды и продолжение сохранённой очереди. UI и полноценный бой не считаются проверенными.
