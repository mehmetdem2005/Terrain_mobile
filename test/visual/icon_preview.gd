@tool
extends SceneTree

# TKT-005 L5 icon preview — renders addons/mobile_terrain/icon.svg scaled
# up on a dark editor-like background so the Scene-dock icon can be
# eyeballed without opening the editor. Companion to render_terrain.gd.

var _frames := 0
var _shot_path := "user://icon_preview.png"


func _process(_delta: float) -> bool:
	if _frames == 0:
		var bg := ColorRect.new()
		bg.color = Color(0.18, 0.18, 0.20)
		bg.size = Vector2(256, 256)
		root.add_child(bg)
		var tr := TextureRect.new()
		tr.texture = load("res://addons/mobile_terrain/icon.svg")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(256, 256)
		root.add_child(tr)
	_frames += 1
	if _frames >= 5:
		var img := root.get_texture().get_image()
		if img.save_png(_shot_path) == OK:
			print("ICON_SHOT: " + ProjectSettings.globalize_path(_shot_path))
		quit(0)
		return true
	return false
