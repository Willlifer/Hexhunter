extends SceneTree
## Lane W review renders (H56, H57): the commit-feel visuals through the real
## fight (HHFight: sim, bodies, arena view, HHAimFx, HUD) on the pond, the
## monster held still (its brain removed) so every frame is reproducible.
## Needs a window (not headless):
##   godot --path . --script res://tools/feel_preview.gd [-- --out design/feel] [--only lance]
## Writes, per weapon: <w>_ring (the reach ring), <w>_L1_aim, <w>_L1_release,
## <w>_L3_aim, <w>_L3_release, <w>_dash; lance / daggers: <w>_combo1..3
## (each string hit at its contact, close up); plus potion_zone and
## exposed (a monster in its punish window), and sheet_<w>.png contact
## sheets.

const OUT := "design/feel"
const SAVE := Vector2i(960, 600)
const DIST := { "lance": 3, "daggers": 1, "bow": 7 }

var out_dir := OUT
var only := ""
var shots := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	root.size = Vector2i(1280, 800)
	_run.call_deferred()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	for w in ["lance", "bow", "daggers"]:
		if only != "" and w != only:
			continue
		await _weapon(w)
	if only == "" or only == "extra":
		await _extras()
	print("feel_preview: done -> ", _abs(out_dir))
	quit(0)


func _fight(weapon: String) -> HHFight:
	var f := HHFight.new()
	f.setup_cfg({ "arena": "pond", "monster": "swampfang", "weapon": weapon, "element": "fire", "backup": "water", "seed": 1, "cam": "30,44" })
	root.add_child(f)
	f.set_process(false)
	f.sim.brains.clear()                                 # hold the monster still
	f.sim.env = null                                     # no swells mid-shot
	return f


func _drawn() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _frame(f: HHFight, dist: float = 26.0, pitch: float = 46.0, focus: Variant = null) -> void:
	f._draw(HHSim.TICK)
	var m := f.sim.unit("swampfang")
	var p := f.sim.unit("p1")
	var mid: Vector3 = ((m.pos as Vector3) * 0.4 + (p.pos as Vector3) * 0.6)
	if focus is Vector3:
		mid = focus
	var to := (p.pos as Vector3) - (m.pos as Vector3)
	f.camera.yaw = atan2(to.x, to.z) + 0.35
	f.camera.dist = dist
	f.camera.pitch = deg_to_rad(pitch)
	f.camera.follow(mid, true)


func _tick(f: HHFight, orders: Dictionary = {}) -> void:
	var ev := f.sim.step(orders)
	for e in ev:
		f._consume(e)


func _shot(f: HHFight, key: String) -> void:
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	img.resize(SAVE.x, SAVE.y, Image.INTERPOLATE_LANCZOS)
	shots[key] = img
	img.save_png(_abs(out_dir).path_join(key + ".png"))
	print("feel_preview: ", key)


func _settle(f: HHFight, n: int = 6, dist: float = 26.0) -> void:
	for k in n:
		_tick(f)
		_frame(f, dist)
		await _drawn()


## A hunter `d` hexes off the monster's footprint, in the open.
func _place(f: HHFight, d: int) -> void:
	var sim := f.sim
	var m := sim.unit("swampfang")
	var p := sim.unit("p1")
	var best: Vector2i = p.hex
	var bd := 1 << 30
	for h in sim.arena.ring(m.hex, int(m.size) + d):
		if sim.arena.walkable(h) and sim.arena.kind(h) in ["floor", "pad"]:
			var dd := HHHex.distance(h, p.hex)
			if dd < bd:
				bd = dd
				best = h
	p.hex = best
	p.prev = best
	p.crossed = best
	p.pos = sim.arena.stand(best)
	p.path = [] as Array[Vector2i]
	p.target = "swampfang"
	p.attacking = false
	sim._face_pos(p, m.pos)


func _ready_again(f: HHFight) -> void:
	var p := f.sim.unit("p1")
	p.cooldowns.q = 0
	p.recovery = 0
	p.windup = {}


func _weapon(w: String) -> void:
	var f := _fight(w)
	await process_frame
	if f.debug != null:
		f.debug.visible = false
	_place(f, int(DIST[w]))
	var sim := f.sim
	var m := sim.unit("swampfang")
	var aim: Vector2i = sim.nearest_hex_of(m, sim.unit("p1").hex)
	await _settle(f)
	_frame(f)
	await _shot(f, "%s_ring" % w)
	# level 1: a tap's preview (a few ticks held) and its release
	_tick(f, { "p1": { "charge": { "skill": "q", "aim": aim } } })
	for k in 6:
		_tick(f)
		_frame(f)
		await _drawn()
	await _shot(f, "%s_L1_aim" % w)
	_tick(f, { "p1": { "release": { "skill": "q", "aim": aim } } })
	for k in 40:
		_tick(f)
		_frame(f)
		var p := sim.unit("p1")
		if (p.windup as Dictionary).is_empty():
			break
	_frame(f)
	await _shot(f, "%s_L1_release" % w)
	await _settle(f, 40)
	_ready_again(f)
	# level 3: held to the frame it fires, then the release
	_tick(f, { "p1": { "charge": { "skill": "q", "aim": aim } } })
	var l3 := int(roundf(HHTune.value("charge_l3_s") * 30.0))
	for k in l3 - 2:
		_tick(f)
		if k % 4 == 0:
			_frame(f)
			await _drawn()
	var ch: Dictionary = sim.unit("p1").charging
	ch.level = 3                                          # the frame the level-3 preview shows, before it fires
	_frame(f)
	await _shot(f, "%s_L3_aim" % w)
	ch.level = 2
	var landed := false
	for k in 60:
		_tick(f)
		_frame(f)
		await _drawn()
		for e in sim.events:
			if e.type in ["pierce", "energized_shot", "flourish"]:
				landed = true
		if landed:
			break
	for k in 2:
		_tick(f)
		_frame(f)
	await _shot(f, "%s_L3_release" % w)
	await _settle(f, 30)
	_ready_again(f)
	# the dash
	var p2 := sim.unit("p1")
	var side := ((p2.pos as Vector3) - (m.pos as Vector3)).cross(Vector3.UP).normalized()
	_tick(f, { "p1": { "dash": (p2.pos as Vector3) + side * 5.0 } })
	for k in 3:
		_tick(f)
		_frame(f, 18.0, 40.0)
	await _shot(f, "%s_dash" % w)
	await _settle(f, 20)
	# the basic string, each hit at its contact, close up
	if HHWeapons.has_combo(w):
		_place(f, 7)                                      # clear of the fire the releases laid
		sim.charge.entries.clear()
		await _settle(f, 4)
		var body: HHPlayerBody = f.player_body
		var me := sim.unit("p1")
		for step in [1, 2, 3]:
			var c := body.combo_clip(step)
			_frame(f, 6.5, 14.0, (me.pos as Vector3) + Vector3(0, 1.0, 0))
			f.camera.yaw = float(me.facing) + 0.9            # three-quarter front: the pose and the weapon read
			f.camera.follow((me.pos as Vector3) + Vector3(0, 1.0, 0), true)
			await _drawn()
			body.pose_at(c, maxf(body.contact_time(c), 0.0) + 0.03)
			await _shot(f, "%s_combo%d" % [w, step])
	f.queue_free()
	await process_frame


func _extras() -> void:
	var f := _fight("bow")
	await process_frame
	if f.debug != null:
		f.debug.visible = false
	_place(f, 6)
	var sim := f.sim
	var p := sim.unit("p1")
	await _settle(f)
	var m := sim.unit("swampfang")
	var at: Vector2i = HHHex.line(p.hex, m.hex)[2]
	_tick(f, { "p1": { "potion": { "aim": at } } })
	for k in int(HHTune.value("potion_windup")) + 30:
		_tick(f)
		_frame(f)
		if k % 3 == 0:
			await _drawn()
	_frame(f)
	await _shot(f, "potion_zone")
	m.exposed = 40
	for k in 6:
		_tick(f)
		_frame(f)
		await _drawn()
	await _shot(f, "exposed")
	f.queue_free()
	await process_frame
