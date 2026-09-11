extends SceneTree
## Structured, non-empty acceptance report; unknown arguments always fail.

const SUITES: Dictionary = {
 "p6_region":"res://tests/scenarios/test_p6_region.gd",
	"p5_hybrids":"res://tests/scenarios/test_p5_hybrids.gd",
	"p5_cross_nodes":"res://tests/scenarios/test_p5_cross_nodes.gd",
	"p5_implants":"res://tests/scenarios/test_p5_implants.gd",
	"p5_upgrades":"res://tests/scenarios/test_p5_upgrades.gd",
	"p5_shield":"res://tests/scenarios/test_p5_shield.gd",
	"p5_growth":"res://tests/scenarios/test_p5_growth.gd",
	"p5_psionics":"res://tests/scenarios/test_p5_psionics.gd",
	"p4_hero_screen":"res://tests/scenarios/test_p4_hero_screen.gd",
	"p4_discovery":"res://tests/scenarios/test_p4_discovery.gd",
	"p4_search":"res://tests/scenarios/test_p4_search.gd",
	"p4_exploration":"res://tests/scenarios/test_p4_exploration.gd",
	"p4_care":"res://tests/scenarios/test_p4_care.gd",
	"p4_prosthesis":"res://tests/scenarios/test_p4_prosthesis.gd",
	"p4_body":"res://tests/scenarios/test_p4_body.gd",
	"p4_party":"res://tests/scenarios/test_p4_party.gd",
	"p4_attributes":"res://tests/scenarios/test_p4_attributes.gd",
	"p4_journey":"res://tests/scenarios/test_p4_journey.gd",
	"p3_world":"res://tests/scenarios/test_p3_world.gd",
 "p2_development":"res://tests/scenarios/test_p2_development.gd",
	"p1_progression":"res://tests/scenarios/test_p1_progression.gd",
	"unit":"res://tests/unit/test_domain.gd",
	"integration":"res://tests/integration/test_storage.gd",
	"scenario":"res://tests/scenarios/test_session.gd",
	"spatial":"res://tests/unit/test_spatial.gd",
	"m2_content":"res://tests/integration/test_m2_content.gd",
	"m2_movement":"res://tests/scenarios/test_m2_movement.gd",
	"turn_scheduler":"res://tests/unit/test_turn_scheduler.gd",
	"turn_content":"res://tests/integration/test_turn_content.gd",
	"m2_snapshot":"res://tests/integration/test_m2_snapshot.gd",
	"m2_turns":"res://tests/scenarios/test_m2_turns.gd",
	"m2_turn_storage":"res://tests/integration/test_m2_turn_storage.gd",
	"m2_attacks":"res://tests/unit/test_m2_attacks.gd",
	"m2_combat_storage":"res://tests/integration/test_m2_combat_storage.gd",
 "m2_consequences":"res://tests/unit/test_m2_consequences.gd",
 "m2_consequence_storage":"res://tests/integration/test_m2_consequence_storage.gd",
 "m2_ai":"res://tests/scenarios/test_m2_ai.gd",
 "m4_effects":"res://tests/scenarios/test_m4_effects.gd",
 "m4_magic":"res://tests/scenarios/test_m4_magic.gd",
 "m4_ability_ai":"res://tests/scenarios/test_m4_ability_ai.gd",
 "m4_areas":"res://tests/scenarios/test_m4_areas.gd"
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var captured_errors: Sm2ErrorCapture = Sm2ErrorCapture.new()
	OS.add_logger(captured_errors)
	var suite_name: String = "all"
	var report_path: String = "user://tests/report.json"
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var parse_errors: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	var index: int = 0
	while index < arguments.size():
		var option: String = arguments[index]
		if option not in ["--suite", "--report"] or index + 1 >= arguments.size() or seen.has(option):
			parse_errors.append("Invalid or duplicate argument: " + option)
			index += 1
			continue
		seen[option] = true
		index += 1
		if option == "--suite":
			suite_name = arguments[index]
		else:
			report_path = arguments[index]
		index += 1
	if suite_name != "all" and not SUITES.has(suite_name):
		parse_errors.append("Unknown suite: " + suite_name)
	var harness: Sm2TestHarness = Sm2TestHarness.new()
	harness.failures.assign(parse_errors)
	var ran: Array[String] = []
	if parse_errors.is_empty():
		if suite_name in ["all", "unit"]:
			var guard: GDScript = load("res://tests/unit/test_architecture.gd") as GDScript
			guard.call("run", harness)
			if not harness.completed_suites.get("architecture", false):
				harness.failures.append("Architecture guard aborted")
		for name_value: String in SUITES:
			if suite_name != "all" and suite_name != name_value:
				continue
			var suite: GDScript = load(SUITES[name_value]) as GDScript
			if suite == null or not suite.can_instantiate() or not suite.has_method("run"):
				harness.failures.append("Suite cannot load: " + name_value)
				continue
			var previous_checks: int = harness.checks
			suite.call("run", harness)
			ran.append(name_value)
			if not harness.completed_suites.get(name_value, false):
				harness.failures.append("Suite aborted before completion: " + name_value)
			if harness.checks == previous_checks:
				harness.failures.append("Empty suite: " + name_value)
	if harness.checks == 0:
		harness.failures.append("No checks executed")
	OS.remove_logger(captured_errors)
	harness.failures.append_array(captured_errors.messages())
	var report: Dictionary = {
		"passed":harness.failures.is_empty(), "checks":harness.checks,
		"failures":harness.failures, "suites":ran,
		"engine_version":Engine.get_version_info().get("string", "unknown")
	}
	if report_path.is_empty() or DirAccess.make_dir_recursive_absolute(report_path.get_base_dir()) != OK:
		push_error("Cannot create report directory: " + report_path)
		quit(2)
		return
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: " + report_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Cannot finish report: " + report_path)
		quit(2)
		return
	print("SM2_TEST_REPORT " + JSON.stringify(report))
	quit(0 if report["passed"] else 1)
