class_name HHTunePanel
extends CanvasLayer
## F1: the live tuning panel (the MobaTune / FpsTune pattern). One SpinBox
## per numeric HHTune key; edits apply at once and are saved to
## user://hexhunt_tune.cfg (H48: the Gauntlet FpsTune pattern), which boot
## reloads before the lobby opens. Reset restores the shipped defaults and
## clears the file. The status line shows the cfg path and how many keys
## differ from the defaults. The lobby's gear button opens it too.

const PATH := "user://hexhunt_tune.cfg"
const SECTION := "tune"

var _panel: PanelContainer
var _spins := {}
var _status: Label
var _table: Label
const REACTIONS_LAST_KEY := "reaction_unit_other"   # the last key of tune.gd's "eruptions and reactions" section


## Apply the saved values (boot, before the first screen). Returns the count.
static func load_saved() -> int:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return 0
	var n := 0
	for k in cf.get_section_keys(SECTION):
		HHTune.set_value(str(k), float(cf.get_value(SECTION, k, 0.0)))
		n += 1
	return n


## Write every key that differs from its default; delete the file when none do.
static func save() -> int:
	var cf := ConfigFile.new()
	var n := 0
	for k in HHTune.keys():
		var dv: Variant = HHTune.default_of(str(k))
		if not (dv is float or dv is int):
			continue
		if not is_equal_approx(HHTune.value(str(k)), float(dv)):
			cf.set_value(SECTION, str(k), HHTune.value(str(k)))
			n += 1
	if n == 0:
		if FileAccess.file_exists(PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	else:
		cf.save(PATH)
	return n


## Keys whose live value differs from the shipped default.
static func changed_keys() -> Array:
	var out: Array = []
	for k in HHTune.keys():
		var dv: Variant = HHTune.default_of(str(k))
		if (dv is float or dv is int) and not is_equal_approx(HHTune.value(str(k)), float(dv)):
			out.append(str(k))
	return out


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 60)
	_panel.custom_minimum_size = Vector2(360, 700)
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "Tune (F1)   edits apply live"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "x"
	close.pressed.connect(func(): _panel.visible = false)
	head.add_child(close)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(_reset)
	vb.add_child(reset)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	vb.add_child(_status)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(350, 600)
	vb.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	sc.add_child(grid)
	for k in HHTune.keys():
		var dv: Variant = HHTune.default_of(str(k))
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
		sb.value_changed.connect(func(v: float):
			HHTune.set_value(str(k), v)
			save()
			_refresh_status())
		grid.add_child(sb)
		_spins[k] = sb
		if str(k) == REACTIONS_LAST_KEY:              # H427: the read-only comparison under the reaction keys
			_table = Label.new()
			_table.add_theme_font_size_override("font_size", 11)
			_table.add_theme_color_override("font_color", Color(1, 0.92, 0.75, 0.85))
			grid.add_child(_table)
			grid.add_child(Control.new())
	_refresh_status()


## H427: every reaction as x the triggering hunter's auto attack, and as damage
## from the lance's (HHFormulas.reaction_table, the live values).
static func reaction_lines() -> String:
	var lance := HHWeapons.basic_damage("lance") * HHTune.value("lance_basic_ticks") / maxf(1.0, float(HHWeapons.basic_ticks("lance")))
	var out: Array = ["REACTIONS  x auto attack  (lance dmg)"]
	for r in HHFormulas.reaction_table():
		var a := str(r.anchor).replace("anchor: ", "")
		out.append("%s: %s  x%.2f  (%.0f)%s" % [r.reaction, r.case, float(r.mult), lance * float(r.mult), ("  " + a) if a != "" else ""])
	return "\n".join(out)


func open() -> void:
	_panel.visible = true


func toggle() -> void:
	_panel.visible = not _panel.visible


func is_open() -> bool:
	return _panel.visible


func _refresh_status() -> void:
	_status.text = "changed: %d   saved to %s" % [changed_keys().size(), ProjectSettings.globalize_path(PATH)]
	if _table != null:
		_table.text = reaction_lines()


func _reset() -> void:
	HHTune.reset()
	for k in _spins:
		(_spins[k] as SpinBox).set_value_no_signal(HHTune.value(str(k)))
	save()
	_refresh_status()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F1:
		toggle()
		get_viewport().set_input_as_handled()
