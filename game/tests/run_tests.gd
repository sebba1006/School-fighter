extends SceneTree
## Minimal test runner. Runs every test_* method in res://tests/test_*.gd.
## Usage: godot --headless --path game -s res://tests/run_tests.gd


func _init() -> void:
	var passed := 0
	var failed := 0
	var files := DirAccess.get_files_at("res://tests")
	for file in files:
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.call(name)
			if not t.finished:
				t.failures.append("did not finish (script error?)")
			if t.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg in t.failures:
					print("FAIL %s::%s  %s" % [file, name, msg])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
