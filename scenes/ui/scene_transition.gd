extends CanvasLayer
## Reusable iris transition. Lives in the root so it survives change_scene_to_file:
##   SceneTransition.go(get_tree(), "res://...")  -> iris closes, scene changes, iris opens.

const COVER_TIME := 0.28
const REVEAL_TIME := 0.34
const NODE_NAME := "SceneTransition"
const SHADER_CODE := """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0; // 1 = fully covered
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(0.10, 0.06, 0.04, 1.0);
void fragment() {
	vec2 uv = (UV - center) * vec2(1.7778, 1.0);
	float r = (1.0 - progress) * 1.25 - 0.02;
	float a = smoothstep(r - 0.015, r + 0.04, length(uv));
	COLOR = vec4(tint.rgb, a);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var _tw: Tween
var busy := false


static func go(tree: SceneTree, path: String, center: Vector2 = Vector2(0.5, 0.5)) -> void:
	var node: Node = tree.root.get_node_or_null(NODE_NAME)
	if node == null:
		node = (load("res://scenes/ui/scene_transition.gd") as GDScript).new()
		node.name = NODE_NAME
		tree.root.add_child(node)
	node.run(path, center)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("progress", 0.0)
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _set_progress(v: float) -> void:
	_mat.set_shader_parameter("progress", v)


func run(path: String, center: Vector2) -> void:
	if busy:
		return
	busy = true
	_mat.set_shader_parameter("center", center)
	_rect.visible = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks while closing
	_tw = create_tween()
	_tw.tween_method(_set_progress, 0.0, 1.0, COVER_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await _tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	_tw = create_tween()
	_tw.tween_method(_set_progress, 1.0, 0.0, REVEAL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _tw.finished
	_rect.visible = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
