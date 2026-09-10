# Контракты реализации M0–M1

Это ограниченный архитектурный срез, не полная боевая система. Все численные правила называются sm2.m1.fixture.1.

## Владение файлами в первом проходе

- Исполнитель ядра: src/domain/** и tests/unit/test_domain.gd.
- Исполнитель данных/сохранения: src/content/**, src/infrastructure/**, content/** и tests/integration/test_storage.gd.
- Исполнитель Windows-запуска: tools/run_game.ps1, tools/run_checks.ps1, tools/export_game.ps1, tools/find_godot.ps1, export_presets.cfg, два .cmd запуска. Не меняет project.godot.
- Основной исполнитель: project.godot, src/application/**, src/presentation/**, scenes/**, test_runner и остальные tests/**, документация, общая приёмка.

Не менять чужие файлы без сообщения; согласовывать изменение контрактов.

## Общие API

Все классы имеют префикс Sm2. class_name используется для типов, не singleton. Имена ниже согласованы между частями.

### Sm2Catalog (src/domain/content/sm2_catalog.gd)

- new(), build(raw: Dictionary) -> PackedStringArray: проверяет и преобразует все определения; пустой список означает успех. Ошибка не публикует частичный каталог.
- fingerprint() -> String, version() -> String, to_data() -> Dictionary: отделённые нормализованные данные.
- actor(id: String) -> Sm2ActorDefinition; weapon(id: String) -> Sm2WeaponDefinition; ability(id: String) -> Sm2AbilityDefinition; status(id: String) -> Sm2StatusDefinition. Возвращаются копии; неизвестный ID -> null.
- has_actor/has_weapon/has_ability/has_status(id: String) -> bool.
- definitions raw: {version: String, actors: Array[Dictionary], weapons: Array[Dictionary], abilities: Array[Dictionary], statuses: Array[Dictionary]}.
- actor fields: id, name, hp, ap, max_fatigue, initiative, weapon_id, abilities (Array[String]), immunities (Array[String]).
- weapon fields: id, name, damage_min, damage_max, durability.
- ability fields: id, name, operation (damage/status/summon), ap_cost, fatigue_cost, range, damage_bonus, status_id, summon_template_id.
- status fields: id, name, tick_damage, duration.
- Все поля обязательны; неиспользуемые status_id/summon_template_id пусты, damage_bonus=0. Уникальные ID, ссылки правильного типа, диапазоны, известные операции. Метаданные каталога включаются в fingerprint.

### Sm2BattleEngine (src/domain/battle/sm2_battle_engine.gd)

- new(catalog: Sm2Catalog).
- start(setup: Dictionary) -> Dictionary {ok: bool, errors: PackedStringArray}.
- setup = {battle_id: String, seed: int, width: int, height: int, actors: Array[Dictionary]}.
- Каждый actor spawn = {template_id: String, side: String, owner: String, controller: String, q: int, r: int}. ID выдаются детерминированно в порядке setup, с 1; новые сущности берут сохраняемый монотонный счётчик. Первая сторона company, вторая opposition — только fixture.
- execute(command: Sm2Command) -> Sm2CommandResult.
- preview(command: Sm2Command) -> Dictionary {allowed: bool, reason: String, ap_cost: int, fatigue_cost: int, damage_min: int, damage_max: int}. Не расходует RNG/ID и не меняет состояние.
- view() -> Dictionary: отделённые значения {battle_id, revision:int, round:int, active_actor_id:int, finished:bool, winner:String, actors:Array[Dictionary]}.
- actor view минимум {actor_id:int, name:String, side:String, q:int, r:int, hp:int, hp_max:int, ap:int, ap_max:int, fatigue:int, fatigue_max:int, alive:bool, template_id:String, abilities:Array[String]}; можно добавлять owner/controller/creator/effects/items для проверки.
- capture() -> Dictionary: точный JSON-safe снимок; ID, счётчики и состояния RNG — десятичные строки; массивы объектов переводятся явно, без ссылок на живые классы.
- restore(snapshot: Dictionary) -> Dictionary {ok:bool, errors:PackedStringArray}; полная кандидатная валидация, отказ не меняет текущий engine; fingerprint и ruleset входят в snapshot.
- state_hash() -> String: каноническое представление snapshot с устойчивым порядком ключей.
- outcome() -> Dictionary {battle_id:String, winner:String, finished:bool, participants:Array[Dictionary]}; отделённые данные, законченный результат проверяется прикладным слоем.

### Sm2Command / Sm2CommandResult

- Sm2Command (src/domain/battle/sm2_command.gd) поля kind:String (move/use_ability/end_turn), actor_id:int, expected_revision:int, ability_id:String, target_actor_id:int, target:Vector2i.
- Конструктор без обязательных параметров; вызывающая сторона заполняет поля.
- Sm2CommandResult поля accepted:bool, code:String, events:Array[Dictionary], revision:int. События содержат только JSON-safe значения и выдаются независимо.

### Фикстуры и правила

- Поле 6×4 в осевых координатах, прямоугольные границы q/r, без terrain/LOS/ZoC.
- core:actor.vanguard: hp 12, ap 4, max_fatigue 20, initiative 10, weapon core:weapon.practice_blade, abilities strike/venom/summon.
- core:actor.raider: hp 12, ap 4, max_fatigue 20, initiative 8, weapon core:weapon.practice_blade, abilities strike.
- core:actor.wisp: hp 4, ap 2, max_fatigue 10, initiative 6, weapon core:weapon.practice_blade, abilities strike.
- core:weapon.practice_blade: damage 3..5, durability 20. Второй предмет core:weapon.heavy_practice_blade: damage 5..7, durability 16.
- core:ability.strike: damage, AP 2, fatigue 3, range 1, damage_bonus 0, остальные ссылки пустые.
- core:ability.venom: status, AP 2, fatigue 2, range 1, status_id core:status.poison; duration 2, tick_damage 1, срабатывает в начале активации носителя, затем уменьшается; повторное наложение обновляет срок.
- core:ability.summon: summon, AP 3, fatigue 4, range 1, summon_template_id core:actor.wisp. Призыв ходит со следующего раунда. Это техническая политика, не канон магии.
- move только в соседний свободный гекс, AP 1, fatigue 1. end_turn завершает активацию. На новой активации AP до max, fatigue уменьшается на 2 до 0. Порядок раунда initiative убыв., при равенстве ID возраст.; мёртвые пропускаются. В начале боя все полные AP.
- strike наносит целочисленный случайный урон в диапазоне оружия; попадание гарантировано в fixture (полная математика M2 позже). Износ оружия минус 1 за принятый strike; при 0 удар запрещён. Переполнение урона обрезается до текущего HP, факт смерти один раз.
- victory после отсутствия живых одной стороны; после конца команды больше не принимаются.
- Проверка всех затрат/ссылок/дальности до списания. Неверная команда не меняет snapshot/revision/RNG/ID. accepted-команда увеличивает revision один раз.
- RNG: фиксированная простая реализация с версией и тестовыми векторами; integer arithmetic без переполнения и modulo bias в выборке. Не глобальный генератор.

### Sm2ContentLoader (src/content/sm2_content_loader.gd)

- static load_catalog(path: String = "res://content/core/manifest.tres") -> Dictionary {ok:bool, catalog:Sm2Catalog или null, errors:PackedStringArray}.
- Пользовательские Resource с экспортируемыми типизированными полями. Манифест version и коллекции ресурсов, преобразование в raw выше; ошибки обнаруживаются до публикации. Без ссылок на живую сессию.

### Sm2SaveStore (src/infrastructure/sm2_save_store.gd)

- new(base_directory: String = "user://saves").
- save_slot(payload: Dictionary, slot_name: String = "session") -> Dictionary {ok:bool, errors:PackedStringArray}.
- load_slot(slot_name: String = "session") -> Dictionary {ok:bool, payload:Dictionary, errors:PackedStringArray}.
- has_slot(slot_name: String = "session") -> bool.
- Payload сессии JSON-safe; base directory и имя проверять (имя без пути). Envelope {format:"sm2.save", schema_version:2, payload, checksum}; checksum канонического payload.
- Схема1 для миграционной fixture {format:"sm2.save", schema_version:1, state:payload, checksum}; проверить старую целостность, преобразовать в схему2 в памяти. Это учебная миграция, а не поддержка неизвестных старых игр.
- Проверить временную запись/reload/checksum, публиковать с .bak; ошибка публикации должна сохранять/восстанавливать предыдущий рабочий слот насколько файловая система позволяет. Не обещать аппаратную атомарность. Ошибка не оставляет полуслот как валидный. Явные лимиты файла и поля envelope; обход пути запрещён.
- Восстановление BattleEngine и Session в отдельный кандидат делает прикладной слой; SaveStore проверяет формат и целостность, не знает игровые правила.

### Sm2TestHarness (tests/support/sm2_test_harness.gd)

- expect(condition: bool, label: String) -> void.
- equal(actual: Variant, expected: Variant, label: String) -> void.
- Не бросает ранний assert, накапливает количество проверок и ошибок.
- Каждый файл-suite имеет static run(t: Sm2TestHarness) -> void. Базовые фикстуры загружаются Sm2ContentLoader либо Sm2TestFixtures.raw_catalog()/setup(). Root создаст helper.
- test_runner запускает suites, даёт JSON-отчёт и явный exit code; пустой/неизвестный suite не может дать PASS.

## Стартовый экран

В M1 предусмотрено настоящее окно SM2 с созданием и восстановлением минимальной сессии. Поле с интерактивным тактическим боем относится к M2/M3. Проверки команд и призыва пока выполняются автоматически и показывают готовность архитектуры.
