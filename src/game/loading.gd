class_name HHLoading
extends CanvasLayer
## The loading screen in front of a fight while it builds, warms its shaders
## (HHWarmup) and, in co-op, waits for the whole party. The shell puts it up
## and lets it paint before the fight builds (the build is one long frame in
## the browser); the fight takes it over and closes it when play starts.
##
##   HHLoading.open(shell, "Loading the hunt")    # idempotent
##   HHLoading.say(self, "Waiting for the party (1/2)")
##   HHLoading.close(self)

const NAME := "Loading"

var _label: Label


func _init() -> void:
	name = NAME
	layer = 100                               # over the HUD (10) and the F1 panel
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 1.0)   # the clear colour: no flash on the way in
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	bg.add_child(_label)
	_track = ColorRect.new()                   # H463: the boot preload's progress read (hidden otherwise)
	_track.color = Color(1, 1, 1, 0.08)
	_track.anchor_left = 0.3
	_track.anchor_right = 0.7
	_track.anchor_top = 0.5
	_track.anchor_bottom = 0.5
	_track.offset_top = 52.0
	_track.offset_bottom = 58.0
	_track.visible = false
	bg.add_child(_track)
	_fill = ColorRect.new()
	_fill.color = Color(0.92, 0.78, 0.42, 0.85)
	_fill.anchor_bottom = 1.0
	_track.add_child(_fill)


var _track: ColorRect
var _fill: ColorRect


func set_text(text: String) -> void:
	_label.text = text


## Show the bar at `frac` (0..1); a negative frac hides it.
func set_progress(frac: float) -> void:
	_track.visible = frac >= 0.0
	_fill.anchor_right = clampf(frac, 0.0, 1.0)


## The loading screen under the shell above `from` (made when missing).
static func open(from: Node, text: String = "Loading the hunt") -> HHLoading:
	var s := _shell(from)
	if s == null:
		return null
	var l := s.get_node_or_null(NAME) as HHLoading
	if l == null:
		l = HHLoading.new()
		s.add_child(l)
	l._label.text = text
	return l


static func say(from: Node, text: String) -> void:
	var l := open(from, text)
	if l != null:
		l._label.text = text


static func close(from: Node) -> void:
	var s := _shell(from)
	if s != null:
		var l := s.get_node_or_null(NAME)
		if l != null:
			s.remove_child(l)
			l.queue_free()


static func _shell(from: Node) -> Node:
	var n := from
	while n != null and not n is HHShell:
		n = n.get_parent()
	return n
