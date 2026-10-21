extends SceneTree
## Lane H review renders (H250-H259): the monster hull outline, the Attack
## Ring highlight and a push-out, through the real fight (HHFight: sim,
## bodies, arena view, HHHullFx, HUD) at the gameplay camera (30 m, 44 deg).
## The monster's brain is removed so every frame is reproducible.
## Needs a window (not headless):
##   godot --path . --script res://tools/hull_preview.gd [-- --out design/hull] [--only spirewalker]
## Writes, per monster: <m>_hull (the outline alone), <m>_ring_hover (the
## cursor on the monster: Attack Ring + the spot a click resolves to),
## <m>_ring_approach (walking in after the click); and for Spirewalker and
## Colambros: <m>_push_before (a leap about to land on the hunter) and
## <m>_push_after (slid out to the ring, the leap's element splashed on the
## Attack Ring: Lane P H269), plus sheet.png.

const OUT := "design/hull"
const SAVE := Vector2i(960, 600)
const FIGHTS := { "swampfang": "pond", "colambros": "caldera", "rimeslithe": "cave", "spirewalker": "glade" }
const DIST := 30.0
const PITCH := 44.0

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
	_run.call_deferred()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	for mon in FIGHTS:
		if only != "" and mon != only:
			continue
		await _monster(mon)
	_sheet()
	print("hull_preview: done -> ", _abs(out_dir))
	quit(0)


func _fight(mon: String, weapon: String) -> HHFight:
	var f := HHFight.new()
	f.setup_cfg({ "arena": FIGHTS[mon], "monster": mon, "weapon": weapon, "element": "fire", "backup": "water", "seed": 1, "cam": "30,44" })
	root.add_child(f)
	f.set_process(false)
	f.sim.brains.clear()                                 # hold the monster still
	f.sim.env = null
	if f.debug != null:
		f.debug.visible = false
	return f


func _drawn() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


## The gameplay camera, behind the hunter looking at the monster.
var fixed_cam := {}                    # { yaw, mid }: the push-out pair keeps one camera


func _frame(f: HHFight, mon: String, hover: bool = false) -> void:
	f._draw(HHSim.TICK)
	if f.view.hull != null:
		f.view.hull.hover_id = mon if hover else ""
		for k in 4:
			f.view.hull.sync(f.sim, "p1", 0.1)
	var m := f.sim.unit(mon)
	var p := f.sim.unit("p1")
	var mid: Vector3 = (m.pos as Vector3) * 0.45 + (p.pos as Vector3) * 0.55
	var to := (p.pos as Vector3) - (m.pos as Vector3)
	f.camera.yaw = atan2(to.x, to.z) + 0.3
	if not fixed_cam.is_empty():
		f.camera.yaw = float(fixed_cam.yaw)
		mid = fixed_cam.mid
	f.camera.dist = DIST
	f.camera.pitch = deg_to_rad(PITCH)
	f.camera.follow(mid, true)


func _tick(f: HHFight, orders: Dictionary = {}) -> void:
	var ev := f.sim.step(orders)
	for e in ev:
		f._consume(e)


func _shot(key: String) -> void:
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	img.resize(SAVE.x, SAVE.y, Image.INTERPOLATE_LANCZOS)
	shots[key] = img
	order.append(key)
	img.save_png(_abs(out_dir).path_join(key + ".png"))
	print("hull_preview: ", key)


## The hunter `d` hexes from the monster's centre on open walkable ground,
## nearest the arena's player spawn.
func _place(f: HHFight, mon: String, d: int) -> void:
	var sim := f.sim
	var m := sim.unit(mon)
	var p := sim.unit("p1")
	var best: Vector2i = p.hex
	var bd := 1 << 30
	for h in sim.arena.ring(m.hex, d):
		if sim.arena.walkable(h) and sim.arena.kind(h) in ["floor", "pad", "sun", "shade"]:
			var dd := HHHex.distance(h, sim.arena.spawns.player[0])
			if dd < bd:
				bd = dd
				best = h
	p.hex = best
	p.prev = best
	p.crossed = best
	p.pos = sim.arena.stand(best)
	p.path = [] as Array[Vector2i]
	p.target = ""
	p.attacking = false
	sim._face_pos(p, m.pos)


func _monster(mon: String) -> void:
	var f := _fight(mon, "daggers")
	await process_frame
	_place(f, mon, 9)
	for k in 4:
		_tick(f)
		_frame(f, mon)
		await _drawn()
	await _shot("%s_hull" % mon)
	_frame(f, mon, true)
	await _shot("%s_ring_hover" % mon)
	_tick(f, { "p1": { "target": mon, "attack": true } })
	for k in 18:
		_tick(f)
		_frame(f, mon)
		await _drawn()
	await _shot("%s_ring_approach" % mon)
	f.queue_free()
	await process_frame
	if mon in ["spirewalker", "colambros"]:
		await _push(mon)


## A leap lands on the hunter: just before, and just after the slide.
func _push(mon: String) -> void:
	var f := _fight(mon, "lance")
	await process_frame
	_place(f, mon, 7)
	var sim := f.sim
	var m := sim.unit(mon)
	var p := sim.unit("p1")
	for k in 3:
		_tick(f)
		_frame(f, mon)
		await _drawn()
	var land: Vector2i = p.hex
	var to := (p.pos as Vector3) - (m.pos as Vector3)
	fixed_cam = { "yaw": atan2(to.x, to.z) + 0.3, "mid": (p.pos as Vector3) }
	sim.begin_leap(m, land, 14, Callable())
	m.leap["splash"] = "fire" if mon == "colambros" else "thunder"   # H269: the brains' splash (Lane P)
	f._consume({ "type": "leap", "id": mon, "to": land, "ticks": 14, "tick": sim.tick })
	for k in 7:
		_tick(f)
		_frame(f, mon)
		await _drawn()
	await _shot("%s_push_before" % mon)
	for k in 7:
		_tick(f)
	for k in 4:
		_tick(f)
		f._draw(1.0 / 60.0)
		_frame(f, mon)
		await _drawn()
	await _shot("%s_push_after" % mon)
	fixed_cam = {}
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
