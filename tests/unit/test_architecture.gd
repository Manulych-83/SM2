extends RefCounted
## A small dependency guard, complemented by actual headless domain execution.

static func run(t: Sm2TestHarness) -> void:
	var paths: Array[String] = []
	_collect("res://src/domain", paths)
	t.expect(paths.size() >= 10, "architecture: non-empty domain inventory")
	var forbidden: RegEx = RegEx.new()
	forbidden.compile("\\b(Node[23]D|Node|Control|SceneTree|FileAccess|DirAccess|ResourceLoader|ResourceSaver|Input|Time|OS|Engine|Timer|RandomNumberGenerator|Sm2Session|Sm2SaveStore|Sm2ContentLoader)\\b|\\b(randi|randf|randfn|randomize|seed|load|preload|get_tree|_process|_physics_process)\\s*\\(")
	for path: String in paths:
		var source: String = FileAccess.get_file_as_string(path)
		var code: PackedStringArray = []
		for line: String in source.split("\n"):
			code.append(line.get_slice("#", 0))
		t.expect(forbidden.search("\n".join(code)) == null, "architecture: no outer/runtime dependency in " + path.get_file())
	t.complete_suite("architecture")

static func _collect(directory: String, output: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			output.append(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_collect(directory.path_join(child), output)
