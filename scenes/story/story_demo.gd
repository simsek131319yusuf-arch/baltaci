extends Control
## Story demo / preview. Usage:
##   godot --path . res://scenes/story/story_demo.tscn                      (click through the intro)
##   godot --path . res://scenes/story/story_demo.tscn -- --autoshot=out.png [--beat=<id>]
## --autoshot writes out_letter.png, out_mid.png, out_after.png, out_emote.png (and out_toast.png)
## and quits. Never touches the real save (GameState.persist = false, flags cleared in memory).

var _shot_base := ""
var _beat_id := "intro"


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	GameState.persist = false
	GameState.flags.clear()
	GameState.runs = 0
	_beat_id = str(args.get("beat", "intro"))
	var bg := ColorRect.new()
	bg.color = Color("5f8f4a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var sky := ColorRect.new()
	sky.color = Color("a9d4e8")
	sky.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sky.offset_bottom = 520
	add_child(sky)
	var btn := Button.new()
	btn.text = "Vardiyaya Başla (oyun butonu, diyalog açıkken tıklanamaz)"
	btn.position = Vector2(560, 300)
	btn.size = Vector2(480, 70)
	add_child(btn)
	await get_tree().process_frame
	if args.has("autoshot"):
		_shot_base = str(args["autoshot"]).trim_suffix(".png")
		_run_shots()
	else:
		_start()


func _start() -> void:
	Story.ui_enabled = true
	if _beat_id == "intro":
		Story.notify("camp_enter", {"runs": 0})
	else:
		Story.queue.append(_beat_id)
		Story.play_next()


func _snap(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_shot_base, suffix]
	print("autoshot: ", path, " -> ", error_string(img.save_png(path)))


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run_shots() -> void:
	_start()
	var box = Story._box
	var has_letter: bool = typeof(Story.current.get("letter")) == TYPE_DICTIONARY
	if has_letter:
		await _wait(1.0)
		await _snap("letter")
		box.advance()
		await _wait(0.8)
	else:
		await _wait(0.7)
	# line 0, a bit into the typewriter
	await _wait(0.45)
	await _snap("mid")
	await _wait(2.0)
	await _snap("after")
	box.advance()
	await _wait(0.9)
	await _snap("emote")
	# toast preview
	box.skip()
	await _wait(0.8)
	Story._ensure_box()
	var toast_scene: PackedScene = load(Story.TOAST_SCENE)
	var t = toast_scene.instantiate()
	add_child(t)
	t.show_line(Story.characters.get("hoca", {}), "hoca", "Bir ağaç ötekini itti! Bodo buna 'orman dansı' derdi.", "")
	await _wait(0.8)
	await _snap("toast")
	get_tree().quit(0)
