class_name Sm2TestHarness
extends RefCounted

var checks: int = 0
var failures: Array[String] = []
var completed_suites: Dictionary[String, bool] = {}

func complete_suite(suite_name: String) -> void:
	completed_suites[suite_name] = true

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)

func equal(actual: Variant, expected: Variant, label: String) -> void:
	expect(actual == expected, "%s | actual=%s expected=%s" % [label, str(actual), str(expected)])
