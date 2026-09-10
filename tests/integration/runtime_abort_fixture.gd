extends RefCounted
## Deliberately broken, used only by the negative runner acceptance check.


static func run(t: Sm2TestHarness) -> void:
	t.expect(true, "runtime fault fixture: one successful check before abort")
	var missing_target: Variant = null
	missing_target.call("intentional_runtime_fault")
	t.complete_suite("runtime_abort")
