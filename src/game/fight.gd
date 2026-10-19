class_name HHFight
extends Node3D
## The fight scene: owns an HHSim, steps it at 30 Hz, draws it (HHArenaView,
## placeholder bodies), and turns input into orders. Phase 0 is a sandbox:
##   right-click    walk to the hex under the cursor (true-hex snapped)
##   left-click     paint the selected element on that hex (sandbox only)
##   1-7            pick the element to paint (fire water ice thunder wind dark light)
##   W              Elemental Exchange (swap active / backup)
##   Shift          hold to run
##   Space          stop
## `autoplay` runs a scripted walk-and-paint for the smoke run and the
## capture tool, then quits.

const ELEMENT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]

var sim: HHSim
var arena: HHArena
var view: HHArenaView
var camera: HHCameraRig
var hud: Label
var player_id := "p1"
var monster_id := ""
var bodies := {}             # unit id -> MeshInstance3D
var autoplay := false
var autoplay_seconds := 12.0
var paint_element := "fire"
var _acc := 0.0
var _pending := {}           # orders for the next tick, unit id -> order
var _script: Array = []      # autoplay: [{ at: seconds, order }]
var _elapsed := 0.0
var _log := PackedStringArray()


func setup(p_arena: HHArena, seed: int, monster: String = "") -> void:
	arena = p_arena
	sim = HHSim.new(arena, seed)
	var start: Vector2i = arena.spawns.player[0]
	sim.add_player(player_id, start, "fire", "water")
	if monster != "":
		monster_id = monster
		sim.add_monster(monster, arena.spawns.monster, 20000.0, 2)
	view = HHArenaView.new()
	view.name = "ArenaView"
	add_child(view)
	view.build(arena)
	camera = HHCameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.clicked.connect(_on_click)
	camera.follow(sim.unit(player_id).pos, true)
	_build_bodies()
	_build_hud()
	if autoplay:
		_script = _autoplay_script()


func _build_bodies() -> void:
	for id in sim.order:
		var u: Dictionary = sim.units[id]
		var mi := MeshInstance3D.new()
		if u.kind == "player":
			var cm := CapsuleMesh.new()
			cm.radius = 0.35
			cm.height = HHLook.RIG_HEIGHT
			mi.mesh = cm
			mi.material_override = HHLook.flat(Color(0.92, 0.92, 0.9))
			mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		else:
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			mi.mesh = sm
			mi.scale = Vector3(2.6, 1.6, 3.4)
			mi.material_override = HHLook.flat(Color(0.3, 0.35, 0.6))
			mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mi.name = id
		add_child(mi)
		bodies[id] = mi


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	_elapsed += delta
	if autoplay:
		_drive_autoplay()
	_acc += delta
	var steps := 0
	while _acc >= HHSim.TICK and steps < 6:
		_acc -= HHSim.TICK
		var ev := sim.step(_pending)
		_pending = {}
		for e in ev:
			_note(e)
		steps += 1
	_draw(delta)
	if autoplay and _elapsed >= autoplay_seconds:
		_finish_autoplay()


func _draw(delta: float) -> void:
	for id in bodies:
		var u: Dictionary = sim.units[id]
		var mi: MeshInstance3D = bodies[id]
		var lift := HHLook.RIG_HEIGHT * 0.5 if u.kind == "player" else 1.6
		mi.position = (u.pos as Vector3) + Vector3(0, lift, 0)
		mi.rotation.y = float(u.facing)
		mi.visible = sim.alive(u)
	var p := sim.unit(player_id)
	camera.follow(p.pos)
	view.sync(sim, player_id, delta)
	var lines := PackedStringArray()
	lines.append("Hexhunt sandbox   tick %d   seed %d" % [sim.tick, sim.seed])
	lines.append("HP %d / %d   element %s (backup %s)   hex %s" % [int(p.hp), int(p.max_hp), p.element, p.backup, p.hex])
	lines.append("paint: %s   [1-7 pick, L-click paint, R-click move, W swap, Shift run, Space stop]" % paint_element)
	if monster_id != "":
		var m := sim.unit(monster_id)
		lines.append("%s HP %d / %d" % [monster_id, int(m.hp), int(m.max_hp)])
	for i in range(maxi(0, _log.size() - 6), _log.size()):
		lines.append(_log[i])
	hud.text = "\n".join(lines)


func _note(e: Dictionary) -> void:
	match str(e.type):
		"detonate": _log.append("t%d detonate %s %.0f%%" % [e.tick, e.hex, e.pct])
		"overheat": _log.append("t%d OVERHEAT %s ring %d" % [e.tick, e.hex, (e.ring as Array).size()])
		"overfreeze": _log.append("t%d OVERFREEZE %s" % [e.tick, e.hex])
		"douse": _log.append("t%d douse %s" % [e.tick, e.hex])
		"gale": _log.append("t%d gale %s x%d" % [e.tick, e.hex, (e.copies as Array).size()])
		"hurt": _log.append("t%d %s -%d (%s)" % [e.tick, e.id, int(e.amount), e.cause])
		"swap": _log.append("t%d swap -> %s" % [e.tick, e.element])
		"over": _log.append("t%d OVER: %s" % [e.tick, e.result])


# ------------------------------------------------------------------ input

func _on_click(button: int, screen_pos: Vector2) -> void:
	var hex := _hex_under(screen_pos)
	if hex == Vector2i(-9999, -9999):
		return
	match button:
		MOUSE_BUTTON_RIGHT:
			_order({ "move": hex })
		MOUSE_BUTTON_LEFT:
			_order({ "paint": { "element": paint_element, "hex": hex, "steps": 1 } })


func _order(o: Dictionary) -> void:
	var cur: Dictionary = _pending.get(player_id, {})
	cur.merge(o, true)
	_pending[player_id] = cur


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var i := ELEMENT_KEYS.find(ev.keycode)
		if i >= 0:
			paint_element = HHFormulas.ELEMENTS[i]
		match ev.keycode:
			KEY_SPACE: _order({ "stop": true })
			KEY_W: _order({ "swap": true })
			KEY_ESCAPE: get_tree().quit(0)
	if ev is InputEventKey and ev.keycode == KEY_SHIFT:
		_order({ "run": ev.pressed })


## The hex under a screen point: the camera ray marched onto the heightfield.
func _hex_under(screen_pos: Vector2) -> Vector2i:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-4:
		return Vector2i(-9999, -9999)
	var p := o + d * (-o.y / d.y)       # the y = 0 plane first
	for i in 6:                           # then refine against the terrain
		var h := arena.height_at(p.x, p.z)
		var t := (h - o.y) / d.y
		if t <= 0.0:
			break
		p = o + d * t
	var hex := arena.from_world(p)
	return hex if arena.exists(hex) else Vector2i(-9999, -9999)


# ------------------------------------------------------------------ autoplay

## A scripted sandbox run: walk, paint fire to 3 and overheat it, douse,
## fuse and detonate, glaze and overfreeze, gale. Exercises every reaction
## through the real scene so the smoke run and the capture see them.
func _autoplay_script() -> Array:
	var start: Vector2i = arena.spawns.player[0]
	var a := start + Vector2i(2, -2)
	var b := start + Vector2i(-3, 0)
	var c := start + Vector2i(0, -3)
	return [
		{ "at": 0.2, "order": { "move": a } },
		{ "at": 1.0, "order": { "paint": { "element": "fire", "hex": b, "steps": 3 } } },
		{ "at": 1.5, "order": { "paint": { "element": "fire", "hex": b, "steps": 1 } } },     # overheat
		{ "at": 2.5, "order": { "paint": { "element": "water", "hex": b, "steps": 2 } } },    # douse
		{ "at": 3.5, "order": { "paint": { "element": "light", "hex": c, "steps": 2 } } },
		{ "at": 4.0, "order": { "paint": { "element": "thunder", "hex": c, "steps": 1 } } },  # detonate
		{ "at": 5.0, "order": { "paint": { "element": "water", "hex": a, "steps": 2 } } },
		{ "at": 5.5, "order": { "paint": { "element": "ice", "hex": a, "steps": 1 } } },      # glaze
		{ "at": 6.0, "order": { "paint": { "element": "ice", "hex": a, "steps": 1 } } },      # overfreeze
		{ "at": 7.0, "order": { "paint": { "element": "dark", "hex": start, "steps": 3 } } },
		{ "at": 7.5, "order": { "paint": { "element": "wind", "hex": start, "steps": 1 } } },   # gale
		{ "at": 8.0, "order": { "swap": true } },
		{ "at": 8.5, "order": { "move": start + Vector2i(4, 2), "run": true } },
		{ "at": 10.0, "order": { "target": monster_id } if monster_id != "" else { "stop": true } },
	]


func _drive_autoplay() -> void:
	while not _script.is_empty() and float(_script[0].at) <= _elapsed:
		_order((_script.pop_front() as Dictionary).order)


func _finish_autoplay() -> void:
	autoplay = false
	var p := sim.unit(player_id)
	print("HHFight autoplay done: tick %d, player hp %d at %s, hash %d, log %d lines" % [sim.tick, int(p.hp), p.hex, sim.state_hash(), _log.size()])
	for l in _log:
		print("  ", l)
	get_tree().quit(0)
