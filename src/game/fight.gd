class_name HHFight
extends Node3D
## The fight scene: owns an HHSim, steps it at 30 Hz, draws it (HHArenaView,
## bodies, HUD), and turns input into orders.
##   right-click    on the monster: target it and auto-attack (H32); on the
##                  ground: run to that exact point (free movement, H31)
##   left-drag      orbit the camera; a left click (sandbox) paints (H20)
##   Q / E / R      cast at the hex under the cursor; W swaps elements
##   1-7            (sandbox) pick the element to paint
##   Shift          hold to walk (you run by default, H37);  Space  stop
##   T              drink a potion (H40)
##   F1             tune panel;  Esc / F10  abort back to the lobby (H48)
## `autoplay` runs a scripted walk, paint, attack and cast sequence for the
## smoke run and the capture tool, then quits.
## `setup_cfg(cfg)` builds the fight from the launch config (guide/02, H48)
## and `finished` fires once with { result: "win"|"fallen"|"abort", cfg,
## ticks, hp, monster_hp } when the sim ends (after `fight_end_hold_s`, so
## the VICTORY / FALLEN text shows) or on Esc / F10.

signal finished(result: Dictionary)

const ELEMENT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]
const NO_HEX := Vector2i(-9999, -9999)

var sim: HHSim
var arena: HHArena
var asset: GKAsset
var view: HHArenaView
var camera: HHCameraRig
var hud: HHHud
var sfx: HHSfx
var debug: Label
var player_id := "p1"
var weapon := "lance"        # --weapon lance | daggers | bow
var element := "fire"        # the hunter's active element (the lobby's pick, L-15)
var backup := "water"        # ... and backup
var upgrades: Dictionary = {}    # slotted upgrade ids per skill (cfg.upgrades, Lane U's R-U1)
var cfg: Dictionary = {}     # the launch config this fight came from (setup_cfg)
var headless := false        # cfg.headless: no view, camera, bodies or HUD (tests)
var monster_id := ""
var bodies := {}             # unit id -> Node3D
var monster_bodies := {}     # unit id -> Lane E body (duck-typed)
var player_body: Node3D = null   # Lane B body (duck-typed: build(weapon), play(clip, loop), update(delta))
var autoplay := false
var sandbox := false
var autoplay_seconds := 14.0
var paint_element := "fire"
var _acc := 0.0
var _pending := {}
var _script: Array = []
var _elapsed := 0.0
var _log := PackedStringArray()
var _over_for := -1.0        # seconds since sim.over was set; -1 while the fight runs
var _finished := false


## Build the fight from a launch config (guide/02 "Launch config"). Keys
## beyond the contract that the flags pass through: sandbox, autoplay,
## autoplay_seconds, headless.
func setup_cfg(p_cfg: Dictionary) -> void:
	cfg = p_cfg.duplicate(true)
	var seed := int(cfg.get("seed", 1))
	weapon = str(cfg.get("weapon", "lance"))
	element = str(cfg.get("element", "fire"))
	backup = str(cfg.get("backup", "water"))
	upgrades = (cfg.get("upgrades", {}) as Dictionary).duplicate(true)
	sandbox = bool(cfg.get("sandbox", false))
	autoplay = bool(cfg.get("autoplay", false))
	autoplay_seconds = float(cfg.get("autoplay_seconds", autoplay_seconds))
	headless = bool(cfg.get("headless", false))
	var loaded := HHRegistry.load_arena(str(cfg.get("arena", "round")), seed)
	setup(loaded.arena, seed, str(cfg.get("monster", "")), loaded.asset)
	var cp := str(cfg.get("cam", "")).split(",")
	if camera != null and cp.size() == 2:
		camera.dist = float(cp[0])
		camera.pitch = deg_to_rad(float(cp[1]))


## Feel numbers the fight scene owns, registered under "fight_" so the F1
## panel edits them live (HHTune.value("fight_end_hold_s")).
const TUNE := {
	"end_hold_s": 2.0,       # seconds the VICTORY / FALLEN text holds before `finished` fires
}


func setup(p_arena: HHArena, seed: int, monster: String = "", p_asset: GKAsset = null) -> void:
	HHTune.register("fight", TUNE)
	arena = p_arena
	asset = p_asset
	sim = HHSim.new(arena, seed)
	sim.sandbox = sandbox or autoplay
	var start: Vector2i = arena.spawns.player[0]
	sim.add_player(player_id, start, element, backup, weapon, upgrades)
	if monster != "":
		monster_id = monster
		_add_monster(monster)
	if headless:
		return
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
	sfx = HHSfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
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
			for m in ["build", "load_monster", "setup", "load_id"]:
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
	if u.kind == "player" and ResourceLoader.exists("res://src/game/anim/player_body.gd"):
		var s: GDScript = load("res://src/game/anim/player_body.gd")      # Lane B: the rigged player
		var body: Node3D = s.new()
		if body.has_method("build"):
			body.build(str(u.weapon))
		if body.has_method("bind"):
			body.bind(sim, u.id)
		player_body = body
		return body
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
			if sfx != null:
				sfx.on_event(e, sim)
		steps += 1
	_draw(delta)
	_watch_over(delta)
	if autoplay and _elapsed >= autoplay_seconds:
		_finish_autoplay()


## Once the sim is over, hold `fight_end_hold_s` (the VICTORY / FALLEN text
## shows), then emit `finished` once. Autoplay runs keep quitting on their own.
func _watch_over(delta: float) -> void:
	if _finished or sim.over == "" or autoplay:
		return
	_over_for = maxf(_over_for, 0.0) + delta
	if _over_for >= HHTune.value("fight_end_hold_s"):
		_finish("win" if sim.over == "win" else "fallen")


func _finish(result: String) -> void:
	if _finished:
		return
	_finished = true
	var p := sim.unit(player_id)
	var m := sim.unit(monster_id) if monster_id != "" else {}
	finished.emit({ "result": result, "cfg": cfg, "ticks": sim.tick,
		"hp": float(p.get("hp", 0.0)), "monster_hp": float(m.get("hp", 0.0)) })


func _draw(delta: float) -> void:
	if headless:
		return
	for id in bodies:
		var u: Dictionary = sim.units[id]
		var node: Node3D = bodies[id]
		node.position = u.pos
		node.rotation.y = float(u.facing)
		node.visible = sim.alive(u) or u.kind == "monster"
		if monster_bodies.has(id) and (monster_bodies[id] as Node).has_method("update"):
			monster_bodies[id].update(delta)
	if player_body != null and player_body.has_method("update"):
		player_body.update(delta)
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
	if player_body != null and player_body.has_method("on_event") and str(e.get("id", "")) == player_id:
		player_body.on_event(e, sim)
	match str(e.type):
		"detonate": _log.append("t%d detonate %s %.0f%%" % [e.tick, e.hex, e.pct])
		"overheat": _log.append("t%d OVERHEAT %s" % [e.tick, e.hex])
		"overfreeze": _log.append("t%d OVERFREEZE %s" % [e.tick, e.hex])
		"douse": _log.append("t%d douse %s" % [e.tick, e.hex])
		"gale": _log.append("t%d gale %s" % [e.tick, e.hex])
		"strike":
			_log.append("t%d %s hits %s %d%s" % [e.tick, e.id, e.target, int(e.amount), " REAR" if bool(e.rear) else ""])
			if camera != null:
				camera.shake(0.08 + 0.12 * clampf(float(e.amount) / 200.0, 0.0, 1.0))   # impact (H34)
			_body_react(str(e.target), "hit_react")
		"hurt":
			if e.id == player_id:
				_log.append("t%d you -%d (%s)" % [e.tick, int(e.amount), e.cause])
				if camera != null and not str(e.cause) in ["fire", "burn", "poison", "dark", "fire_cross"]:
					camera.shake(0.25)
		"stagger":
			if e.id == player_id:
				_log.append("t%d staggered %d" % [e.tick, e.ticks])
			else:
				_body_react(str(e.id), "stagger")
		"death":
			if e.id != player_id:
				_body_react(str(e.id), "death", true)
		"cast": _log.append("t%d %s (%s)" % [e.tick, e.name, e.element])
		"cast_refused": _log.append("t%d %s: %s" % [e.tick, str(e.skill).to_upper(), str(e.get("why", "cooldown"))])
		"potion": _log.append("t%d potion (%d left)" % [e.tick, int(e.left)])
		"guard_block": _log.append("t%d GUARD blocked, counter!" % e.tick)
		"telegraph": _log.append("t%d %s telegraphs %s (%d hexes)" % [e.tick, str(e.get("owner", e.get("id", ""))), str(e.get("name", (e.get("payload", {}) as Dictionary).get("clip", ""))), (e.hexes as Array).size()])
		"monster_state": _log.append("t%d %s is %s" % [e.tick, e.id, e.state])
		"monster_anim":
			if monster_bodies.has(e.id) and (monster_bodies[e.id] as Node).has_method("play"):
				var clips: Dictionary = monster_bodies[e.id].clips(str(e.id)) if (monster_bodies[e.id] as Node).has_method("clips") else {}
				monster_bodies[e.id].play(str(e.clip), bool((clips.get(str(e.clip), {}) as Dictionary).get("loop", false)), float(e.get("speed", 1.0)))
		"over": _log.append("t%d OVER: %s" % [e.tick, e.result])


## L-9: a reaction clip on a monster body, only when it is not mid-attack
## (a telegraphed wind-up must stay readable). `force` for death.
func _body_react(id: String, clip: String, force: bool = false) -> void:
	if not monster_bodies.has(id):
		return
	var body: Node = monster_bodies[id]
	if not body.has_method("play"):
		return
	var cur := str(body.get("clip"))
	var looping := bool(body.get("loop"))
	if force or looping or cur == "":
		body.play(clip, false)


# ------------------------------------------------------------------ input

func _on_click(button: int, screen_pos: Vector2) -> void:
	match button:
		MOUSE_BUTTON_RIGHT:
			var m := _monster_hit(screen_pos)
			if m != "":
				_order({ "target": m, "attack": true })
				return
			var p := _ground_under(screen_pos)
			var hex := arena.from_world(p) if p != HHSim.NO_POS else NO_HEX
			if hex != NO_HEX and arena.exists(hex):
				_order({ "move": hex, "move_pos": p })
		MOUSE_BUTTON_LEFT:
			if sandbox:
				var hex := _hex_under(screen_pos)
				if hex != NO_HEX:
					_order({ "paint": { "element": paint_element, "hex": hex, "steps": 1 } })


## The monster under the cursor: a ray against each living monster's body
## (a sphere over its footprint), then the hex fallback.
func _monster_hit(screen_pos: Vector2) -> String:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	for m in sim.monsters():
		if not sim.targetable(m):
			continue
		var radius := (float(m.size) + 0.5) * HHArena.HEX * 1.8
		var centre: Vector3 = (m.pos as Vector3) + Vector3(0, radius * 0.5, 0)
		var oc := o - centre
		var b := oc.dot(d)
		var cc := oc.dot(oc) - radius * radius
		if b * b - cc >= 0.0 and -b > 0.0:
			return m.id
	var hex := _hex_under(screen_pos)
	return _monster_at(hex) if hex != NO_HEX else ""


## The exact ground point under the cursor (NO_POS when off the arena).
func _ground_under(screen_pos: Vector2) -> Vector3:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-4:
		return HHSim.NO_POS
	var p := o + d * (-o.y / d.y)
	for i in 6:
		var h := arena.height_at(p.x, p.z)
		var t := (h - o.y) / d.y
		if t <= 0.0:
			break
		p = o + d * t
	return p if arena.exists(arena.from_world(p)) else HHSim.NO_POS


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
			KEY_T: _order({ "potion": true })
			KEY_W: _order({ "swap": true })
			KEY_Q, KEY_E, KEY_R:
				var aim := _hex_under(get_viewport().get_mouse_position())
				_order({ "cast": { "skill": OS.get_keycode_string(ev.keycode).to_lower(), "aim": aim if aim != NO_HEX else sim.unit(player_id).hex } })
			KEY_ESCAPE, KEY_F10:
				get_viewport().set_input_as_handled()
				_finish("abort")                     # the shell returns to the lobby (H48)
	if ev is InputEventKey and ev.keycode == KEY_SHIFT:
		_order({ "run": not ev.pressed })              # H37: run by default, Shift walks


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
		{ "at": 0.2, "order": { "move": a, "move_pos": arena.stand(a) } },
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
		s.append({ "at": 8.5, "order": { "move": start + Vector2i(4, 2), "move_pos": arena.stand(start + Vector2i(4, 2)) } })
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
