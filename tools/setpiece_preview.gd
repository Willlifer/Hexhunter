extends SceneTree
## Lane M review renders (H360-H389): the NORMAL-tier mechanics through the
## real fight (HHFight on difficulty "normal": sim, bodies, arena view, the
## monster body's HHTierFx, HUD). Each set-piece is started by hand
## (HHTierBrain._start_*) so every frame is reproducible; the periodic
## mechanics are switched off while a shot is set up.
## Needs a window (not headless):
##   godot --path . --script res://tools/setpiece_preview.gd [-- --out design/setpieces] [--only fakeout]
## Writes fakeout_beat2_decoys, fakeout_beat2_single, fakeout_beat3, sweep_wedge,
## siphon_path, rooted, root_stunned, idle_calm, idle_enraged, purge_roar_tell,
## purge_roar_blast, purge_quench_blast, and sheet.png.

const OUT := "design/setpieces"
const SAVE := Vector2i(960, 600)
const QUIET := { "tier_avoid_frac": 99.0, "tier_sp_first_s": 9999.0, "tier_pulse_every_s": 9999.0, "tier_pain_pct": 9999.0 }

var out_dir := OUT
var only := ""
var shots := {}
var order: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	root.size = Vector2i(1280, 800)
	for k in QUIET:
		HHTune.set_value(k, QUIET[k])
	_run.call_deferred()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _want(k: String) -> bool:
	return only == "" or only == k


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	if _want("fakeout"):
		await _fakeout()
	if _want("sweep"):
		await _sweep()
	if _want("siphon"):
		await _siphon()
	if _want("root"):
		await _root()
	if _want("idle"):
		await _idle()
	if _want("purge"):
		await _purge()
	_sheet()
	print("setpiece_preview: done -> ", _abs(out_dir))
	quit(0)


func _fight(mon: String, arena: String, weapon: String = "lance") -> HHFight:
	var f := HHFight.new()
	f.setup_cfg({ "arena": arena, "monster": mon, "weapon": weapon, "element": "fire", "backup": "water", "seed": 1, "cam": "30,44", "difficulty": "normal" })
	root.add_child(f)
	f.set_process(false)
	f.sim.env = null
	if f.debug != null:
		f.debug.visible = false
	return f


func _drawn() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _cam(f: HHFight, look: Vector3, yaw: float, dist: float = 30.0, pitch: float = 44.0) -> void:
	f.camera.yaw = yaw
	f.camera.dist = dist
	f.camera.pitch = deg_to_rad(pitch)
	f.camera.follow(look, true)


func _tick(f: HHFight, n: int = 1) -> void:
	for k in n:
		var ev := f.sim.step({})
		for e in ev:
			f._consume(e)
		var p := f.sim.unit("p1")
		if float(p.hp) > 0.0:
			p.hp = p.max_hp


## Draw a few frames (bodies cross-fade, shaders animate) at the given camera.
func _settle(f: HHFight, look: Vector3, yaw: float, dist: float = 30.0, pitch: float = 44.0, frames: int = 6) -> void:
	Input.warp_mouse(Vector2(2, 2))                      # off the monster: no Attack Ring hover
	for k in frames:
		f._draw(1.0 / 30.0)
		_cam(f, look, yaw, dist, pitch)
		await _drawn()


func _shot(key: String) -> void:
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	img.resize(SAVE.x, SAVE.y, Image.INTERPOLATE_LANCZOS)
	shots[key] = img
	order.append(key)
	img.save_png(_abs(out_dir).path_join(key + ".png"))
	print("setpiece_preview: ", key)


func _put(f: HHFight, id: String, h: Vector2i) -> void:
	var u := f.sim.unit(id)
	u.hex = h
	u.prev = h
	u.crossed = h
	u.pos = f.sim.arena.stand(h)
	u.path = [] as Array[Vector2i]
	u.target = ""
	u.attacking = false


## Stand the monster on open ground near the arena centre (clear lanes round it).
func _centre(f: HHFight, mon: String) -> void:
	var m := f.sim.unit(mon)
	var best: Vector2i = m.hex
	var best_s := -1
	for h in f.sim.arena.area(HHTierBrain.centre_hex(f.sim), 6):
		if HHTierBrain._nearest_fit(f.sim, m, h, 0) != h:
			continue
		var open := 0
		for n in f.sim.arena.area(h, 9):
			if f.sim.arena.walkable(n) and str(f.sim.arena.kind(n)) in ["floor", "sun", "shade", "pad"]:
				open += 1
		if open > best_s:
			best_s = open
			best = h
	_put(f, mon, best)
	f.sim.brains[mon].set("busy_until", 0)


func _aggro(f: HHFight, mon: String) -> Dictionary:
	var m := f.sim.unit(mon)
	var b: Object = f.sim.brains[mon]
	b.call("_force_phase", f.sim, m, "aggravated")
	_tick(f, 2)
	return m


## The nearest walkable floor hex to `want` that is `d` from the monster.
func _spot(f: HHFight, m: Dictionary, d: int, toward: Vector2i) -> Vector2i:
	var best: Vector2i = toward
	var bd := 1 << 30
	for h in f.sim.arena.ring(m.hex, d):
		if f.sim.arena.walkable(h) and str(f.sim.arena.kind(h)) in ["floor", "pad", "sun", "shade"]:
			var dd := HHHex.distance(h, toward)
			if dd < bd:
				bd = dd
				best = h
	return best


func _yaw_from(a: Vector3, b: Vector3) -> float:
	var d := b - a
	return atan2(d.x, d.z)


# ------------------------------------------------------------------ shots

func _fakeout() -> void:
	for variant in ["decoys", "single"]:
		var f := _fight("colambros", "caldera")
		await process_frame
		var m := _aggro(f, "colambros")
		var sim := f.sim
		var p := sim.unit("p1")
		_centre(f, "colambros")
		_put(f, "p1", _spot(f, m, 13, sim.arena.spawns.player[0]))
		var T: Dictionary = m.tier
		HHTierBrain._start_fakeout(sim, sim.brains["colambros"], m, T)
		T.act.variant = variant
		if variant == "decoys":
			T.act.truth = 2 if (T.act.lanes[2].line as Array).size() >= 6 else 0
			T.act.tell = int(T.act.lanes[int(T.act.truth)].side)
		_tick(f, HHTierBrain.ti("fk_rear_ticks") + 22)
		var look: Vector3 = (m.pos as Vector3).lerp(p.pos, 0.45)
		var yaw := _yaw_from(p.pos, m.pos) + 0.35
		await _settle(f, look, yaw + PI, 34.0, 58.0, 10)
		await _shot("fakeout_beat2_%s" % variant)
		if variant == "decoys":
			_tick(f, HHTierBrain.ti("fk_chevron_ticks") - 22 + 6)
			await _settle(f, look, yaw + PI, 34.0, 58.0, 4)
			await _shot("fakeout_beat3")
		f.queue_free()
		await process_frame


func _sweep() -> void:
	var f := _fight("spirewalker", "glade")
	await process_frame
	var m := _aggro(f, "spirewalker")
	var sim := f.sim
	var p := sim.unit("p1")
	var T: Dictionary = m.tier
	HHTierBrain._start_sweep(sim, sim.brains["spirewalker"], m, T)
	for k in 400:
		_tick(f)
		if str(T.act.get("phase", "")) == "wind":
			break
	# the lance hunter guards 5 out, a little clockwise of the beam's start
	var a0 := float(T.act.a0) - deg_to_rad(80.0)
	var c: Vector2 = HHHex.to_world(m.hex, 1.0)
	var gh: Vector2i = HHHex.from_world(c + Vector2(sin(a0), cos(a0)) * 6.0, 1.0)
	_put(f, "p1", gh)
	for k in 200:
		p.guard = 30
		_tick(f)
		if int(T.act.get("start", -1)) > 0 and sim.tick >= int(T.act.start) + 24:
			break
	p.guard = 30
	var look: Vector3 = (m.pos as Vector3).lerp(p.pos, 0.9)
	await _settle(f, look, _yaw_from(m.pos, p.pos) + PI, 36.0, 66.0, 8)
	await _shot("sweep_wedge")
	f.queue_free()
	await process_frame


func _siphon() -> void:
	# on the glade: a hunter's fire there cannot be mistaken for the caldera's lava
	var f := _fight("colambros", "glade")
	await process_frame
	var m := _aggro(f, "colambros")
	var sim := f.sim
	_centre(f, "colambros")
	var best: Vector2i = m.hex
	var bo := -1
	for h in sim.arena.ring(m.hex, 13):
		var open := 0
		for n in HHHex.area(h, 2):
			if sim.arena.walkable(n) and str(sim.arena.kind(n)) == "floor":
				open += 1
		if open > bo:
			bo = open
			best = h
	var cluster: Array = []
	for h in HHHex.area(best, 1):
		if sim.arena.walkable(h):
			cluster.append(h)
	sim.paint(cluster, "fire", "p1", 2)
	_put(f, "p1", _spot(f, m, 9, best + Vector2i(6, 0)))
	HHTierBrain._start_siphon(sim, sim.brains["colambros"], m, m.tier)
	_tick(f, 4)
	var look: Vector3 = (m.pos as Vector3).lerp(sim.arena.stand(best), 0.5)
	await _settle(f, look, _yaw_from(sim.arena.stand(best), m.pos) + 1.4, 30.0, 58.0, 8)
	await _shot("siphon_path")
	f.queue_free()
	await process_frame


func _root() -> void:
	var f := _fight("spirewalker", "glade")
	await process_frame
	var m := _aggro(f, "spirewalker")
	var sim := f.sim
	m.hp = float(m.max_hp) * 0.6
	var T: Dictionary = m.tier
	HHTierBrain._start_root(sim, sim.brains["spirewalker"], m, T)
	for k in 400:
		_tick(f)
		if str(T.act.get("phase", "")) == "rooted":
			break
	_put(f, "p1", _spot(f, m, 6, sim.arena.spawns.player[0]))
	_tick(f, 24)
	var p := sim.unit("p1")
	await _settle(f, (m.pos as Vector3).lerp(p.pos, 0.3), _yaw_from(p.pos, m.pos) + PI + 0.3, 26.0, 40.0, 10)
	await _shot("rooted")
	sim.paint([m.hex + Vector2i(1, 0), m.hex + Vector2i(0, 1)], "fire", "p1", 1)
	_tick(f, 20)
	await _settle(f, (m.pos as Vector3).lerp(p.pos, 0.3), _yaw_from(p.pos, m.pos) + PI + 0.3, 26.0, 40.0, 6)
	await _shot("root_stunned")
	f.queue_free()
	await process_frame


func _idle() -> void:
	for e in [0.0, 1.0]:
		var f := _fight("colambros", "caldera")
		await process_frame
		var m := _aggro(f, "colambros")
		var sim := f.sim
		sim.brains.clear()                               # hold the pose: idle only
		_put(f, "p1", _spot(f, m, 7, sim.arena.spawns.player[0]))
		if e > 0.0:
			sim.tick += 200 * 30                         # the fight is 200 s older
		m.tier.aggro_at = 1
		HHTierBrain._enrage(sim, m, m.tier)
		f._consume({ "type": "monster_anim", "id": "colambros", "clip": "aggravated_idle", "speed": 1.0, "tick": sim.tick })
		var p := sim.unit("p1")
		await _settle(f, (m.pos as Vector3) + Vector3(0, 1.2, 0), _yaw_from(p.pos, m.pos) + PI + 0.6, 15.0, 22.0, 40)
		await _shot("idle_%s" % ("calm" if e == 0.0 else "enraged"))
		f.queue_free()
		await process_frame


func _purge() -> void:
	for mon in ["spirewalker", "swampfang"]:
		var f := _fight(mon, "glade" if mon == "spirewalker" else "pond")
		await process_frame
		var m := _aggro(f, mon)
		var sim := f.sim
		var p := sim.unit("p1")
		_put(f, "p1", _spot(f, m, 6, sim.arena.spawns.player[0]))
		# the hunter's uncashed setup round the monster
		var setup: Array = []
		for h in HHHex.area(m.hex, int(m.size) + 3):
			if sim.arena.walkable(h) and (h.x + 2 * h.y) % 3 == 0:
				setup.append(h)
		sim.paint(setup, "fire", "p1", 2)
		sim.paint([m.hex], "fire", "p1", 3)
		var T: Dictionary = m.tier
		HHTierBrain._start_purge(sim, sim.brains[mon], m, T)
		var look: Vector3 = (m.pos as Vector3).lerp(p.pos, 0.3)
		var yaw := _yaw_from(p.pos, m.pos) + PI + 0.4
		if mon == "spirewalker":
			_tick(f, 18)
			await _settle(f, look, yaw, 28.0, 50.0, 6)
			await _shot("purge_roar_tell")
		for k in 60:
			_tick(f)
			if int(T.fx.get("purge_done", -1)) > 0:
				break
		_tick(f, 5)
		await _settle(f, look, yaw, 28.0, 50.0, 3)
		await _shot("purge_%s_blast" % ("roar" if mon == "spirewalker" else "quench"))
		f.queue_free()
		await process_frame


func _sheet() -> void:
	if order.is_empty():
		return
	var cols := 3
	var w := SAVE.x / 2
	var h := SAVE.y / 2
	var rows := int(ceil(float(order.size()) / cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in order.size():
		var img: Image = (shots[order[i]] as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(_abs(out_dir).path_join("sheet.png"))
