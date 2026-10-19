class_name HHBench
extends Node3D
## The arena bench (Lane C): pick a GKDef, drag its sliders, watch the asset
## rebuild live, undo/redo, presets, save/load to user://, export the arena
## JSON, and an overlay of the logical hex underlay coloured by kind.
##   HHBench.open(get_tree())      from a `--bench` flag (integrator wiring)
##   Ctrl+Z / Ctrl+Y              undo / redo a parameter change
##   middle/right drag, wheel     orbit and zoom (HHCameraRig)
##   H                            toggle the hex overlay
## Windowed only; it is a tool, not part of the game.

const PRESET_DIR := "user://hexhunt_presets/"
const REBUILD_DELAY := 0.15      ## s after the last slider move before a rebuild
const UNDO_COALESCE := 0.6       ## s: moves of the same key inside this window are one undo step

var def: GKDef
var params := {}
var asset: GKAsset
var arena: HHArena
var world: Node3D
var asset_node: Node3D
var overlay_node: MeshInstance3D
var camera: HHCameraRig
var sun: DirectionalLight3D
var sky: WorldEnvironment

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _last_key := ""
var _last_change_ms := 0
var _rebuild_timer: Timer
var _controls := {}              # key -> Control
var _syncing := false
var _overlay_on := false

var _ui: CanvasLayer
var _panel: VBoxContainer
var _status: Label
var _def_pick: OptionButton
var _preset_pick: OptionButton
var _saved_pick: OptionButton
var _name_edit: LineEdit


## The generators the bench can pick from (a script literal is not a constant).
static func defs() -> Array:
	return [HHPondGen]


static func open(tree: SceneTree) -> HHBench:
	var b := HHBench.new()
	b.name = "Bench"
	tree.root.add_child.call_deferred(b)
	return b


func _ready() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	camera = HHCameraRig.new()
	camera.name = "Camera"
	add_child(camera)
	camera.pivot = Vector3.ZERO
	camera.pivot_lift = 0.0
	camera.dist = 40.0
	camera.pitch = deg_to_rad(50.0)
	_rebuild_timer = Timer.new()
	_rebuild_timer.one_shot = true
	_rebuild_timer.wait_time = REBUILD_DELAY
	_rebuild_timer.timeout.connect(_rebuild)
	add_child(_rebuild_timer)
	_build_ui()
	_pick_def(0)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var side := PanelContainer.new()
	side.anchor_left = 0.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_right = 340.0
	_ui.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.custom_minimum_size.x = 320.0
	scroll.add_child(_panel)
	var title := Label.new()
	title.text = "Hexhunt arena bench"
	_panel.add_child(title)
	_def_pick = OptionButton.new()
	for d in defs():
		var inst: GKDef = (d as GDScript).new()
		_def_pick.add_item(inst.title())
	_def_pick.item_selected.connect(_pick_def)
	_panel.add_child(_row("Generator", _def_pick))
	_preset_pick = OptionButton.new()
	_preset_pick.item_selected.connect(_pick_preset)
	_panel.add_child(_row("Preset", _preset_pick))
	var hb := HBoxContainer.new()
	hb.add_child(_button("Undo (Ctrl+Z)", undo))
	hb.add_child(_button("Redo (Ctrl+Y)", redo))
	hb.add_child(_button("Reset", func() -> void: set_params(def.defaults())))
	_panel.add_child(hb)
	var ov := CheckBox.new()
	ov.text = "Overlay hexes (H)"
	ov.toggled.connect(func(on: bool) -> void: set_overlay(on))
	_panel.add_child(ov)
	_controls["__overlay"] = ov
	_panel.add_child(HSeparator.new())
	var params_box := VBoxContainer.new()
	params_box.name = "Params"
	_panel.add_child(params_box)
	_panel.add_child(HSeparator.new())
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "preset name"
	_name_edit.text = "mine"
	var hb2 := HBoxContainer.new()
	hb2.add_child(_name_edit)
	hb2.add_child(_button("Save", save_preset))
	_panel.add_child(hb2)
	_saved_pick = OptionButton.new()
	var hb3 := HBoxContainer.new()
	hb3.add_child(_saved_pick)
	_saved_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb3.add_child(_button("Load", load_selected_preset))
	_panel.add_child(hb3)
	_panel.add_child(_button("Export arenas/<id>.json", export_arena))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 300.0
	_panel.add_child(_status)


func _row(label: String, ctl: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 120.0
	hb.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ctl)
	return hb


func _button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	return b


func _build_param_controls() -> void:
	var box: VBoxContainer = _panel.get_node("Params")
	for c in box.get_children():
		c.free()
	for k in _controls.keys():
		if k != "__overlay":
			_controls.erase(k)
	var group := ""
	for e in def.schema():
		var entry: Dictionary = e
		var g := str(entry.get("group", ""))
		if g != group:
			group = g
			var gl := Label.new()
			gl.text = group
			gl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
			box.add_child(gl)
		var key := str(entry.key)
		var ctl: Control
		match str(entry.get("type", "float")):
			"bool":
				var cb := CheckBox.new()
				cb.toggled.connect(func(on: bool) -> void: _on_change(key, on))
				ctl = cb
			"enum":
				var ob := OptionButton.new()
				for o in entry.options:
					ob.add_item(str(o))
				ob.item_selected.connect(func(i: int) -> void: _on_change(key, str(entry.options[i])))
				ctl = ob
			"int":
				var sb := SpinBox.new()
				sb.min_value = float(entry.get("min", 0))
				sb.max_value = float(entry.get("max", 100))
				sb.step = 1.0
				sb.value_changed.connect(func(v: float) -> void: _on_change(key, int(v)))
				ctl = sb
			_:
				var hb := HBoxContainer.new()
				var sl := HSlider.new()
				sl.min_value = float(entry.get("min", 0.0))
				sl.max_value = float(entry.get("max", 1.0))
				sl.step = float(entry.get("step", 0.001))
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var vl := Label.new()
				vl.custom_minimum_size.x = 52.0
				sl.value_changed.connect(func(v: float) -> void:
					vl.text = "%.2f" % v
					_on_change(key, v))
				hb.add_child(sl)
				hb.add_child(vl)
				hb.set_meta("slider", sl)
				hb.set_meta("label", vl)
				ctl = hb
		_controls[key] = ctl
		box.add_child(_row(str(entry.get("label", key)), ctl))


## Push the current params into the controls without firing changes.
func _sync_controls() -> void:
	_syncing = true
	for e in def.schema():
		var entry: Dictionary = e
		var key := str(entry.key)
		if not _controls.has(key):
			continue
		var ctl: Control = _controls[key]
		var v: Variant = params.get(key, entry.default)
		if ctl is CheckBox:
			(ctl as CheckBox).button_pressed = bool(v)
		elif ctl is OptionButton:
			var opts: Array = entry.options
			(ctl as OptionButton).selected = opts.find(str(v))
		elif ctl is SpinBox:
			(ctl as SpinBox).value = float(v)
		elif ctl.has_meta("slider"):
			var sl: HSlider = ctl.get_meta("slider")
			var vl: Label = ctl.get_meta("label")
			sl.value = float(v)
			vl.text = "%.2f" % float(v)
	_syncing = false


# ------------------------------------------------------------------ params, undo

func _pick_def(i: int) -> void:
	var ds := defs()
	def = (ds[clampi(i, 0, ds.size() - 1)] as GDScript).new()
	_preset_pick.clear()
	for n in def.presets():
		_preset_pick.add_item(str(n))
	_build_param_controls()
	_undo.clear()
	_redo.clear()
	params = def.preset("default")
	_sync_controls()
	_refresh_saved()
	_rebuild()


func _pick_preset(i: int) -> void:
	set_params(def.preset(_preset_pick.get_item_text(i)))


## Replace every parameter (one undo step), rebuild.
func set_params(p: Dictionary) -> void:
	_push_undo()
	params = def.validate(p)
	_sync_controls()
	_schedule()


func _on_change(key: String, v: Variant) -> void:
	if _syncing:
		return
	if params.get(key) == v:
		return
	var now := Time.get_ticks_msec()
	if key != _last_key or now - _last_change_ms > UNDO_COALESCE * 1000.0:
		_push_undo()
	_last_key = key
	_last_change_ms = now
	params[key] = v
	_schedule()


func _push_undo() -> void:
	_undo.append(params.duplicate(true))
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(params.duplicate(true))
	params = _undo.pop_back()
	_last_key = ""
	_sync_controls()
	_schedule()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(params.duplicate(true))
	params = _redo.pop_back()
	_last_key = ""
	_sync_controls()
	_schedule()


func _schedule() -> void:
	_rebuild_timer.start()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: InputEventKey = ev
		if k.ctrl_pressed and k.keycode == KEY_Z:
			undo()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			redo()
		elif k.keycode == KEY_H:
			var cb: CheckBox = _controls["__overlay"]
			cb.button_pressed = not cb.button_pressed
		elif k.keycode == KEY_ESCAPE:
			get_tree().quit()


# ------------------------------------------------------------------ build

func _rebuild() -> void:
	var t0 := Time.get_ticks_msec()
	asset = def.build(params)
	arena = null
	if def is HHPondGen:
		arena = HHPondGen.arena(params)
	var ms := Time.get_ticks_msec() - t0
	if asset_node != null:
		asset_node.queue_free()
	asset_node = asset.instantiate(false)
	world.add_child(asset_node)
	if sun != null:
		sun.queue_free()
	if sky != null:
		sky.queue_free()
	sun = HHArenaStage.sun(asset.lights)
	sky = HHArenaStage.sky(asset.lights)
	world.add_child(sun)
	world.add_child(sky)
	_refresh_overlay()
	var warn := ""
	if not asset.warnings.is_empty():
		warn = "\nwarnings: " + "; ".join(asset.warnings)
	var cells := ""
	if arena != null:
		cells = "  hexes %d (walkable %d)" % [arena.cells.size(), arena.walkable_count()]
	_status.text = "%s  tris %d  build %d ms%s  undo %d/redo %d%s" % [def.id(), asset.triangle_count(), ms, cells, _undo.size(), _redo.size(), warn]


func set_overlay(on: bool) -> void:
	_overlay_on = on
	_refresh_overlay()


func _refresh_overlay() -> void:
	if overlay_node != null:
		overlay_node.queue_free()
		overlay_node = null
	if _overlay_on and arena != null:
		overlay_node = HHArenaStage.overlay(arena, float(asset.meta.get("water_level", 0.0)))
		world.add_child(overlay_node)


# ------------------------------------------------------------------ presets, export

func _preset_path(preset_name: String) -> String:
	return PRESET_DIR + "%s_%s.json" % [def.id(), preset_name.validate_filename()]


func save_preset() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		_status.text = "give the preset a name"
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	var f := FileAccess.open(_preset_path(n), FileAccess.WRITE)
	if f == null:
		_status.text = "could not write " + _preset_path(n)
		return
	f.store_string(JSON.stringify({ "id": def.id(), "version": def.version(), "params": params }, "  "))
	f.close()
	_refresh_saved()
	_status.text = "saved " + ProjectSettings.globalize_path(_preset_path(n))


func _refresh_saved() -> void:
	_saved_pick.clear()
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return
	var prefix := def.id() + "_"
	var names: Array = []
	for f in dir.get_files():
		if f.begins_with(prefix) and f.ends_with(".json"):
			names.append(f.trim_prefix(prefix).trim_suffix(".json"))
	names.sort()
	for n in names:
		_saved_pick.add_item(str(n))


func load_selected_preset() -> void:
	if _saved_pick.selected < 0:
		return
	var n := _saved_pick.get_item_text(_saved_pick.selected)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_preset_path(n)))
	if not parsed is Dictionary or not (parsed as Dictionary).has("params"):
		_status.text = "preset %s did not parse" % n
		return
	set_params((parsed as Dictionary).params)
	_name_edit.text = n


func export_arena() -> void:
	var path := "res://arenas/%s.json" % def.id()
	var ok := false
	if def is HHPondGen:
		ok = HHPondGen.export_json(params, path)
	elif arena != null:
		var d := arena.to_dict()
		d["gen"] = { "id": def.id(), "version": def.version(), "params": params }
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(d))
			f.close()
			ok = true
	_status.text = ("exported " if ok else "export FAILED ") + ProjectSettings.globalize_path(path)
