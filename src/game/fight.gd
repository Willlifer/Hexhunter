class_name HHFight
extends Node3D
## The fight scene: owns an HHSim, steps it at 30 Hz, draws it (HHArenaView,
## bodies, HUD), and turns input into orders.
##   right-click    walk to the hex under the cursor (true-hex snapped)
##   left-click     on the monster: target it and auto-attack (H25);
##                  with --sandbox, on ground: paint the selected element (H20)
##   Q / E / R      cast at the hex under the cursor; W swaps elements
##   1-7            (sandbox) pick the element to paint
##   Shift          hold to run;  Space  stop;  F1  tune panel;  Esc  quit
## `autoplay` runs a scripted walk, paint, attack and cast sequence for the
## smoke run and the capture tool, then quits.

const ELEMENT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]
const NO_HEX := Vector2i(-9999, -9999)

var sim: HHSim
var arena: HHArena
var asset: GKAsset
var view: HHArenaView
var camera: HHCameraRig
var hud: HHHud
var debug: Label
var player_id := "p1"
var monster_id := ""
var bodies := {}             # unit id -> Node3D
var monster_bodies := {}     # unit id -> Lane E body (duck-typed)
var autoplay := false
var sandbox := false
var autoplay_seconds := 14.0
var paint_element := "fire"
var _acc := 0.0
var _pending := {}
var _script: Array = []
var _elapsed := 0.0
var _log := PackedStringArray()


func setup(p_arena: HHArena, seed: int, monster: String = "", p_asset: GKAsset = null) -> void:
	arena = p_arena
	asset = p_asset
	sim = HHSim.new(arena, seed)
	sim.sandbox = sandbox or autoplay
	var start: Vector2i = arena.spawns.player[0]
	sim.add_player(player_id, start, "fire", "water", "lance")
	if monster != "":
		monster_id = monster
		_add_monster(monster)
	view = HHArenaView.new()
	view.name = "ArenaView"
	add_child(view)
	view.build(arena, asset)
	camera = HHCameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.clicked.connect(_on_click)
	camera.follow(sim.unit(player_id).pos, true)
	_build_bodies()
	_build_hud()
	if autoplay:
		_script = _autoplay_script()


## A monster by id: Lane E's brain and body when their scripts exist, else
## the stub (a footprint, HP, no brain).
func _add_monster(id: String) -> void:
	var brain_path := "res://src/monster/%s.gd" % id
	var allowed: Array = []
	var brain: Variant = null
	if ResourceLoader.exists(brain_path):
		var s: GDScript = load(brain_path)
		if s != null:
			brain = s.new()
			if brain.has_method("allowed_kinds"):
				allowed = brain.allowed_kinds()
	var hp := HHTune.value("monster_hp")
	var u := sim.add_monster(id, arena.spawns.monster, hp, 2, allowed)
	if brain != null:
		sim.brains[id] = brain
		if brain.has_method("setup"):
			brain.setup(sim, u)
		_log.append("brain: %s" % id)


func _build_bodies() -> void:
	for id in sim.order:
		var u: Dictionary = sim.units[id]
		var node: Node3D = null
		if u.kind == "monster" and ResourceLoader.exists("res://src/monster/monster_body.gd"):
			var s: GDScript = load("res://src/monster/monster_body.gd")
			var body: Node3D = s.new()
			for m in ["load_monster", "setup", "load_id"]:
				if body.has_method(m):
					body.call(m, id)
					break
			monster_bodies[id] = body
			node = body
		if node == null:
			node = _placeholder(u)
		node.name = id
		add_child(node)
		bodies[id] = node


func _placeholder(u: Dictionary) -> Node3D:
	var mi := MeshInstance3D.new()
	if u.kind == "player":
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = HHLook.RIG_HEIGHT
		mi.mesh = cm
		mi.position.y = HHLook.RIG_HEIGHT * 0.5
		mi.material_override = HHLook.flat(Color(0.92, 0.92, 0.9))
		# a nose so facing reads
		var nose := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.2, 0.5)
		nose.mesh = bm
		nose.position = Vector3(0, 0.6, 0.5)
		nose.material_override = HHLook.flat(Color(0.9, 0.5, 0.2))
		mi.add_child(nose)
	else:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		mi.scale = Vector3(2.6, 1.6, 3.4)
		mi.position.y = 1.6
		mi.material_override = HHLook.flat(Color(0.3, 0.35, 0.6))
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var root := Node3D.new()
	root.add_child(mi)
	return root


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HHHud.new()
	hud.sim = sim
	hud.player_id = player_id
	hud.monster_id = monster_id
	layer.add_child(hud)
	debug = Label.new()
	debug.position = Vector2(16, 60)
	debug.add_theme_font_size_override("font_size", 14)
	debug.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	debug.add_theme_constant_override("outline_size", 4)
	layer.add_child(debug)
	add_child(HHTunePanel.new())


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
		var node: Node3D = bodies[id]
		node.position = u.pos
		node.rotation.y = float(u.facing)
		node.visible = sim.alive(u) or u.kind == "monster"
		if monster_bodies.has(id) and (monster_bodies[id] as Node).has_method("update"):
			monster_bodies[id].update(delta)
	var p := sim.unit(player_id)
	camera.follow(p.pos)
	view.sync(sim, player_id, delta)
	var lines := PackedStringArray()
	lines.append("tick %d  seed %d  hex %s%s" % [sim.tick, sim.seed, p.hex, "   [sandbox paint: %s]" % paint_element if sandbox else ""])
	if p.target != "":
		lines.append("target %s%s" % [p.target, "  attacking" if bool(p.attacking) else ""])
	for i in range(maxi(0, _log.size() - 7), _log.size()):
		lines.append(_log[i])
	debug.text = "\n".join(lines)


func _note(e: Dictionary) -> void:
	match str(e.type):
		"detonate": _log.append("t%d detonate %s %.0f%%" % [e.tick, e.hex, e.pct])
		"overheat": _log.append("t%d OVERHEAT %s" % [e.tick, e.hex])
		"overfreeze": _log.append("t%d OVERFREEZE %s" % [e.tick, e.hex])
		"douse": _log.append("t%d douse %s" % [e.tick, e.hex])
		"gale": _log.append("t%d gale %s" % [e.tick, e.hex])
		"strike": _log.append("t%d %s hits %s %d%s" % [e.tick, e.id, e.target, int(e.amount), " REAR" if bool(e.rear) else ""])
		"hurt": if e.id == player_id: _log.append("t%d you -%d (%s)" % [e.tick, int(e.amount), e.cause])
		"cast": _log.append("t%d %s (%s)" % [e.tick, e.name, e.element])
		"cast_refused": _log.append("t%d %s on cooldown" % [e.tick, str(e.skill).to_upper()])
		"guard_block": _log.append("t%d GUARD blocked, counter!" % e.tick)
		"telegraph": _log.append("t%d %s telegraphs %s (%d hexes)" % [e.tick, e.owner, e.name, (e.hexes as Array).size()])
		"stagger": if e.id == player_id: _log.append("t%d staggered %d" % [e.tick, e.ticks])
		"monster_anim":
			if monster_bodies.has(e.id) and (monster_bodies[e.id] as Node).has_method("play"):
				monster_bodies[e.id].play(str(e.clip))
		"over": _log.append("t%d OVER: %s" % [e.tick, e.result])


# ------------------------------------------------------------------ input

func _on_click(button: int, screen_pos: Vector2) -> void:
	var hex := _hex_under(screen_pos)
	if hex == NO_HEX:
		return
	match button:
		MOUSE_BUTTON_RIGHT:
			_order({ "move": hex })
		MOUSE_BUTTON_LEFT:
			var m := _monster_at(hex)
			if m != "":
				_order({ "target": m, "attack": true })
			elif sandbox:
				_order({ "paint": { "element": paint_element, "hex": hex, "steps": 1 } })


func _monster_at(hex: Vector2i) -> String:
	for u in sim.unit_at(hex):
		if u.kind == "monster" and sim.targetable(u):
			return u.id
	# a near miss on a big body still counts
	for m in sim.monsters():
		if sim.targetable(m) and HHHex.distance(m.hex, hex) <= int(m.size) + 1:
			return m.id
	return ""


func _order(o: Dictionary) -> void:
	var cur: Dictionary = _pending.get(player_id, {})
	cur.merge(o, true)
	_pending[player_id] = cur


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var i := ELEMENT_KEYS.find(ev.keycode)
		if i >= 0 and sandbox:
			paint_element = HHFormulas.ELEMENTS[i]
		match ev.keycode:
			KEY_SPACE: _order({ "stop": true })
			KEY_W: _order({ "swap": true })
			KEY_Q, KEY_E, KEY_R:
				var aim := _hex_under(get_viewport().get_mouse_position())
				_order({ "cast": { "skill": OS.get_keycode_string(ev.keycode).to_lower(), "aim": aim if aim != NO_HEX else sim.unit(player_id).hex } })
			KEY_ESCAPE: get_tree().quit(0)
	if ev is InputEventKey and ev.keycode == KEY_SHIFT:
		_order({ "run": ev.pressed })


## The hex under a screen point: the camera ray marched onto the heightfield.
func _hex_under(screen_pos: Vector2) -> Vector2i:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-4:
		return NO_HEX
	var p := o + d * (-o.y / d.y)
	for i in 6:
		var h := arena.height_at(p.x, p.z)
		var t := (h - o.y) / d.y
		if t <= 0.0:
			break
		p = o + d * t
	var hex := arena.from_world(p)
	return hex if arena.exists(hex) else NO_HEX


# ------------------------------------------------------------------ autoplay

## A scripted run: paint every reaction, then target the monster, auto-attack,
## Pierce, Guard, Eruption. The smoke run and the capture see all of it.
func _autoplay_script() -> Array:
	var start: Vector2i = arena.spawns.player[0]
	var a := start + Vector2i(2, -2)
	var b := start + Vector2i(-3, 0)
	var c := start + Vector2i(0, -3)
	var m: Vector2i = arena.spawns.monster
	var s: Array = [
		{ "at": 0.2, "order": { "move": a } },
		{ "at": 1.0, "order": { "paint": { "element": "fire", "hex": b, "steps": 3 } } },
		{ "at": 1.5, "order": { "paint": { "element": "fire", "hex": b, "steps": 1 } } },
		{ "at": 2.5, "order": { "paint": { "element": "water", "hex": b, "steps": 2 } } },
		{ "at": 3.5, "order": { "paint": { "element": "light", "hex": c, "steps": 2 } } },
		{ "at": 4.0, "order": { "paint": { "element": "thunder", "hex": c, "steps": 1 } } },
		{ "at": 5.0, "order": { "paint": { "element": "water", "hex": a, "steps": 2 } } },
		{ "at": 5.5, "order": { "paint": { "element": "ice", "hex": a, "steps": 1 } } },
		{ "at": 6.0, "order": { "paint": { "element": "ice", "hex": a, "steps": 1 } } },
		{ "at": 7.0, "order": { "paint": { "element": "dark", "hex": start, "steps": 3 } } },
		{ "at": 7.5, "order": { "paint": { "element": "wind", "hex": start, "steps": 1 } } },
		{ "at": 8.0, "order": { "swap": true } },
	]
	if monster_id != "":
		s.append_array([
			{ "at": 8.5, "order": { "target": monster_id, "attack": true, "run": true } },
			{ "at": 11.0, "order": { "cast": { "skill": "q", "aim": m } } },
			{ "at": 11.5, "order": { "cast": { "skill": "e", "aim": m } } },
			{ "at": 12.5, "order": { "cast": { "skill": "r", "aim": m + Vector2i(3, 2) } } },
		])
	else:
		s.append({ "at": 8.5, "order": { "move": start + Vector2i(4, 2), "run": true } })
	return s


func _drive_autoplay() -> void:
	while not _script.is_empty() and float(_script[0].at) <= _elapsed:
		_order((_script.pop_front() as Dictionary).order)


func _finish_autoplay() -> void:
	autoplay = false
	var p := sim.unit(player_id)
	print("HHFight autoplay done: tick %d, player hp %d at %s, hash %d, log %d lines" % [sim.tick, int(p.hp), p.hex, sim.state_hash(), _log.size()])
	if monster_id != "":
		var m := sim.unit(monster_id)
		print("  %s hp %d / %d" % [monster_id, int(m.hp), int(m.max_hp)])
	for l in _log:
		print("  ", l)
	get_tree().quit(0)
