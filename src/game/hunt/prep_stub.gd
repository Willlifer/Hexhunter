class_name HHHuntPrepStub
extends Control
## The prep screen Lane H uses until Lane L's lobby lands: the locked arena
## and monster as a headline, weapon and element pair buttons, Hunt! and
## Back. Same contract as the lobby: setup(cfg) with cfg.locked naming the
## keys it may not change; finished({ result: "play", cfg }) or
## finished({ result: "back" }).

signal finished(result: Dictionary)

const WEAPONS := ["lance", "daggers", "bow"]

var cfg := {}
var _weapon_btns := {}
var _el_btns := {}
var _bk_btns := {}
var _setup_done := false
var _done := false


func setup(p_cfg: Dictionary) -> void:
	if _setup_done:
		return
	_setup_done = true
	cfg = p_cfg.duplicate(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()                  # fills the viewport whatever the parent is
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.08, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	centre.add_child(col)
	col.add_child(HHHuntKit.label("PREPARE", 56, Color(1.0, 0.9, 0.7)))
	var locked: Array = cfg.get("locked", [])
	var head := "%s waits in %s" % [HHHuntFlow.display_name(str(cfg.get("monster", ""))), HHHuntFlow.display_name(str(cfg.get("arena", "")))]
	if not locked.is_empty():
		head += "   (locked: %s)" % ", ".join(PackedStringArray(locked))
	col.add_child(HHHuntKit.label(head, 20, Color(0.85, 0.85, 0.85)))
	col.add_child(HHHuntKit.label("Weapon", 16, Color(0.65, 0.65, 0.65)))
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(wrow)
	for w in WEAPONS:
		var b := Button.new()
		b.text = w.capitalize()
		b.toggle_mode = true
		b.button_pressed = str(cfg.get("weapon", "lance")) == w
		b.custom_minimum_size = Vector2(120, 40)
		b.pressed.connect(func() -> void: _pick(_weapon_btns, "weapon", w))
		wrow.add_child(b)
		_weapon_btns[w] = b
	col.add_child(HHHuntKit.label("Element  /  backup", 16, Color(0.65, 0.65, 0.65)))
	for which in ["element", "backup"]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(row)
		var table := _el_btns if which == "element" else _bk_btns
		for el in HHFormulas.ELEMENTS:
			var b := Button.new()
			b.text = str(el).capitalize()
			b.toggle_mode = true
			b.button_pressed = str(cfg.get(which, "")) == str(el)
			b.custom_minimum_size = Vector2(92, 34)
			b.add_theme_color_override("font_color", HHLook.element_color(str(el)))
			var key: String = which
			var e := str(el)
			b.pressed.connect(func() -> void: _pick(table, key, e))
			row.add_child(b)
			table[el] = b
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 20)
	col.add_child(brow)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 44)
	back.pressed.connect(func() -> void: _finish({ "result": "back" }))
	brow.add_child(back)
	var hunt := Button.new()
	hunt.text = "Hunt!"
	hunt.custom_minimum_size = Vector2(200, 44)
	hunt.add_theme_font_size_override("font_size", 22)
	hunt.pressed.connect(func() -> void: _finish({ "result": "play", "cfg": cfg.duplicate(true) }))
	brow.add_child(hunt)
	col.add_child(HHHuntKit.label("Enter: hunt    Esc: back", 14, Color(0.55, 0.55, 0.55)))


func _pick(table: Dictionary, key: String, value: String) -> void:
	cfg[key] = value
	for k in table:
		(table[k] as Button).button_pressed = str(k) == value


func _finish(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	finished.emit(result)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ENTER, KEY_KP_ENTER: _finish({ "result": "play", "cfg": cfg.duplicate(true) })
			KEY_ESCAPE: _finish({ "result": "back" })
