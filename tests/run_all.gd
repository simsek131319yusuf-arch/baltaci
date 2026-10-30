extends SceneTree
## Runs every tests/test_*.gd plus tests/smoke_autoload.gd, each in its own headless process.
## Usage: godot --headless --path . -s tests/run_all.gd   (exit code != 0 on any failure)

const TIMEOUT_SEC := 60.0     # a test still running after this is killed and counted as a failure
const TIMEOUT_NOTE := "(per-test timeout 60 s)"


func _initialize() -> void:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var scripts := _collect()
	var failed: Array[String] = []
	print("Running %d test script(s) %s" % [scripts.size(), TIMEOUT_NOTE])
	for s in scripts:
		var log_path := OS.get_user_data_dir().path_join("run_all_%s.log" % s.get_basename())
		DirAccess.remove_absolute(log_path)
		var t0 := Time.get_ticks_msec()
		# create_process (not execute) so a hung test can be killed; the child's output goes to a
		# log file, and pass/fail is decided from that log.
		var pid := OS.create_process(exe, ["--headless", "--path", project, "--log-file", log_path, "-s", "res://tests/" + s])
		var timed_out := false
		if pid <= 0:
			failed.append(s)
			print("[FAIL] %s  (could not start)" % s)
			continue
		while OS.is_process_running(pid):
			if (Time.get_ticks_msec() - t0) / 1000.0 > TIMEOUT_SEC:
				timed_out = true
				OS.kill(pid)
				break
			OS.delay_msec(50)
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		OS.delay_msec(100)   # let the log flush
		var text := FileAccess.get_file_as_string(log_path)
		var ok := (not timed_out) and _log_passed(text)
		print("[%s] %s  (%.1fs%s)" % ["PASS" if ok else "FAIL", s, secs, ", TIMEOUT" if timed_out else ""])
		if not ok:
			failed.append(s)
			print(text)
		else:
			for line in text.split("
"):
				if line.begins_with("TEST_") or line.begins_with("SMOKE"):
					print("      ", line.strip_edges())
	print("---")
	print("%d/%d passed" % [scripts.size() - failed.size(), scripts.size()])
	if not failed.is_empty():
		print("FAILED: ", ", ".join(failed))
	quit(1 if not failed.is_empty() else 0)


## A test passes when it printed its "<NAME> OK" summary and no FAIL / script error lines.
func _log_passed(text: String) -> bool:
	var summary_ok := false
	for line in text.split("
"):
		var l := line.strip_edges()
		if (l.begins_with("TEST_") or l.begins_with("SMOKE")) and l.contains(" OK"):
			summary_ok = true
		if l.begins_with("FAIL ") or l.begins_with("  FAIL ") or l.contains("SCRIPT ERROR") or l.contains("Parse Error"):
			return false
		if (l.begins_with("TEST_") or l.begins_with("SMOKE")) and l.contains(" FAIL"):
			return false
	return summary_ok


func _collect() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd") and (f.begins_with("test_") or f == "smoke_autoload.gd"):
			out.append(f)
	out.sort()
	return out
