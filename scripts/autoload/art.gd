extends Node
## Sprite lookup with graceful fallback. Code must work when a sprite is missing
## (returns null -> caller draws a placeholder), so art and code can land independently.

const ROOT := "res://art/sprites/"
var _cache: Dictionary = {}


## id is a path under art/sprites without extension, e.g. "trees/kavak_0".
func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := ROOT + id + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	elif FileAccess.file_exists(path):
		# Not imported yet (e.g. fresh file, no editor pass) -> load raw image.
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			t = ImageTexture.create_from_image(img)
	_cache[id] = t
	return t


func has(id: String) -> bool:
	return tex(id) != null
