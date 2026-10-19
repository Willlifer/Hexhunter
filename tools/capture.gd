class_name HHCapture
extends Node
## `--shot <dir> [--count n] [--every s]`: saves real rendered frames of the
## running scene to <dir>/shot_NN.png, then quits. Needs a window (not
## headless): the viewport texture is read back after each frame is drawn.

var out_dir := "design/art/shots"
var every := 1.5
var count := 6
var _t := 0.0
var _n := 0


func _ready() -> void:
	var abs := out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_dir)
	out_dir = abs.simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(delta: float) -> void:
	_t += delta
	if _t < every:
		return
	_t = 0.0
	_shoot.call_deferred()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("shot_%02d.png" % _n)
	var err := img.save_png(path)
	print("capture: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
	_n += 1
	if _n >= count:
		get_tree().quit(0)
