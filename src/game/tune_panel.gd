class_name HHTunePanel
extends CanvasLayer
## F1: the live tuning panel (the MobaTune / FpsTune pattern). One SpinBox
## per numeric HHTune key; edits apply at once. Reset restores defaults.
## Values are not saved; write the keepers into tune.gd.

var _panel: PanelContainer
var _spins := {}


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 60)
	_panel.custom_minimum_size = Vector2(330, 620)
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "Tune (F1)   edits apply live"
	vb.add_child(title)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(_reset)
	vb.add_child(reset)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(320, 560)
	vb.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	sc.add_child(grid)
	for k in HHTune.keys():
		var dv: Variant = HHTune.DEFAULTS[k]
		if not (dv is float or dv is int):
			continue
		var l := Label.new()
		l.text = str(k)
		grid.add_child(l)
		var sb := SpinBox.new()
		sb.min_value = -10000.0
		sb.max_value = 100000.0
		sb.step = 0.05 if absf(float(dv)) < 5.0 else 1.0
		sb.value = HHTune.value(str(k))
		sb.custom_minimum_size = Vector2(130, 0)
		sb.value_changed.connect(func(v: float): HHTune.set_value(str(k), v))
		grid.add_child(sb)
		_spins[k] = sb


func _reset() -> void:
	HHTune.reset()
	for k in _spins:
		(_spins[k] as SpinBox).set_value_no_signal(HHTune.value(str(k)))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F1:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()
