extends SceneTree
## One-off tool: godot --headless --path . -s scenes/ui/make_theme.gd
## Regenerates scenes/ui/theme.tres from ui_theme.gd.

func _initialize() -> void:
	var theme: Theme = load("res://scenes/ui/ui_theme.gd").build()
	var err := ResourceSaver.save(theme, "res://scenes/ui/theme.tres")
	print("theme saved: ", error_string(err))
	quit(0 if err == OK else 1)
