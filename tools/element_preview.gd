extends SceneTree
## Lane EL review renders (spec sections 2-3, H360-H389): the element
## cash-ins through the real fight (HHFight: sim, bodies, arena view,
## HHReactionFx, HUD), the monster's brain removed so every frame is
## reproducible. Needs a window (not headless):
##   godot --path . --script res://tools/element_preview.gd [-- --out design/elements] [--only crystal,swirl]
## Writes crystal.png (four crystals: fire 3 / ice 3, water 1 / ice 1, dark 2
## / ice 2, light 3 / ice 1), swirl_before.png / swirl_mid.png /
## swirl_after.png, shatter.png, geyser.png, steam.png, eclipse.png,
## glint.png, flux.png and sheet.png. Pond (Swampfang) for most; the glade
## (Spirewalker) for the light / dark ones.

const OUT := "design/elements"
const SAVE := Vector2i(960, 600)

var out_dir := OUT
var only: Array = []
var shots := {}
var order: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = Array(args[i + 1].split(","))
	root.size = Vector2i(1280, 800)
	_run.call_deferred()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	if _want("crystal"):
		await _crystal()
	if _want("swirl"):
		await _swirl()
	if _want("shatter"):
		await _shatter()
	if _want("geyser"):
		await _burst("geyser", "water", "pond", "swampfang")
	if _want("steam"):
		await _steam()
	if _want("eclipse"):
		await _eclipse()
	if _want("glint"):
		await _burst("glint", "light", "glade", "spirewalker")
	if _want("flux"):
		await _burst("flux", "dark", "glade", "spirewalker")
	_sheet()
	print("element_preview: done -> ", _abs(out_dir))
	quit(0)


func _fight(arena: String, mon: String, el: String, backup: String) -> HHFight:
	var f := HHFight.new()
	f.setup_cfg({ "arena": arena, "monster": mon, "weapon": "lance", "element": el, "backup": backup, "seed": 1, "cam": "30,44" })
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


## Camera on `at` from the hunter's side, `dist` m, `pitch` deg.
func _cam(f: HHFight, at: Vector3, dist: float, pitch: float, yaw_off: float = 0.35) -> void:
	var p := f.sim.unit("p1")
	var to := (p.pos as Vector3) - at
	f.camera.yaw = atan2(to.x, to.z) + yaw_off
	f.camera.dist = dist
	f.camera.pitch = deg_to_rad(pitch)
	f.camera.follow(at, true)


## Step the sim (feeding every event to the view) and draw.
func _tick(f: HHFight, orders: Dictionary = {}) -> void:
	for e in f.sim.step(orders):
		f._consume(e)


func _paint(f: HHFight, hexes: Array, el: String, steps: int) -> Dictionary:
	f.sim.events = []
	var r := f.sim.paint(hexes, el, "p1", steps)
	for e in f.sim.events:
		f._consume(e)
	f.sim.events = []
	return r


## Draw `n` frames at `dt` each (particles advance by dt), camera fixed.
func _frames(f: HHFight, at: Vector3, dist: float, pitch: float, n: int, dt: float = 1.0 / 60.0) -> void:
	for k in n:
		f._draw(dt)
		_cam(f, at, dist, pitch)
		await _drawn()


func _shot(key: String) -> void:
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	img.resize(SAVE.x, SAVE.y, Image.INTERPOLATE_LANCZOS)
	shots[key] = img
	order.append(key)
	img.save_png(_abs(out_dir).path_join(key + ".png"))
	print("element_preview: ", key)


## The hunter `d` hexes from the monster on plain walkable ground, nearest the player spawn.
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
	sim._face_pos(p, m.pos)


## A hex `k` steps from the hunter toward the monster (on the line between them).
func _toward(f: HHFight, mon: String, k: int) -> Vector2i:
	var p := f.sim.unit("p1")
	var m := f.sim.unit(mon)
	var line := HHHex.line(p.hex, m.hex)
	return line[clampi(k, 0, line.size() - 1)]


func _crystal() -> void:
	var f := _fight("pond", "swampfang", "ice", "fire")
	await process_frame
	_place(f, "swampfang", 7)
	var c := _toward(f, "swampfang", 3)
	var ring := f.sim.arena.ring(c, 1)
	var spots := [c, ring[0], ring[2], ring[4]]
	var kinds := [["fire", 3, 3], ["water", 1, 1], ["dark", 2, 2], ["light", 3, 1]]
	for i in spots.size():
		_paint(f, [spots[i]], kinds[i][0], kinds[i][1])
		_tick(f)
		_paint(f, [spots[i]], "ice", kinds[i][2])
		_tick(f)
	await _frames(f, f.sim.arena.surface(c), 11.0, 36.0, 30)
	await _shot("crystal")
	f.queue_free()
	await process_frame


func _swirl() -> void:
	var f := _fight("pond", "swampfang", "wind", "fire")
	await process_frame
	_place(f, "swampfang", 6)
	var c := _toward(f, "swampfang", 3)
	var ring2 := f.sim.arena.ring(c, 2)
	var ring1 := f.sim.arena.ring(c, 1)
	_paint(f, [c], "fire", 1)
	for h in [ring1[1], ring2[3], ring2[7]]:
		_paint(f, [h], "fire", 1)
	_paint(f, [ring1[4]], "light", 1)
	_paint(f, [ring2[10]], "light", 1)
	_tick(f)
	var at := f.sim.arena.surface(c)
	await _frames(f, at, 13.0, 50.0, 20)
	await _shot("swirl_before")
	_tick(f)
	_paint(f, [c], "wind", 1)
	await _frames(f, at, 13.0, 50.0, 12)
	await _shot("swirl_mid")
	await _frames(f, at, 13.0, 50.0, 40)
	await _shot("swirl_after")
	f.queue_free()
	await process_frame


func _shatter() -> void:
	var f := _fight("pond", "swampfang", "ice", "fire")
	await process_frame
	_place(f, "swampfang", 4)
	var m := f.sim.unit("swampfang")
	var p := f.sim.unit("p1")
	var hx := f.sim.nearest_hex_of(m, p.hex)
	_paint(f, [hx], "fire", 3)
	_tick(f)
	_paint(f, [hx], "ice", 2)
	_tick(f)
	var at := f.sim.arena.surface(hx)
	await _frames(f, at, 12.0, 34.0, 16)
	await _shot("shatter_crystal")
	f.sim.events = []
	f.sim.strike(p, m, 220.0, hx, "basic")
	for e in f.sim.events:
		f._consume(e)
	await _frames(f, at, 12.0, 34.0, 7)
	await _shot("shatter")
	f.queue_free()
	await process_frame


func _burst(key: String, el: String, arena: String, mon: String) -> void:
	var f := _fight(arena, mon, el, "fire")
	await process_frame
	_place(f, mon, 6)
	var c := _toward(f, mon, 2)
	_paint(f, [c], el, 3)
	_tick(f)
	var at := f.sim.arena.surface(c)
	await _frames(f, at, 12.0, 30.0, 12)
	_paint(f, [c], el, 1)
	await _frames(f, at, 13.0, 24.0, 14)
	await _shot(key)
	f.queue_free()
	await process_frame


func _steam() -> void:
	var f := _fight("pond", "swampfang", "fire", "water")
	await process_frame
	_place(f, "swampfang", 6)
	var c := _toward(f, "swampfang", 2)
	_paint(f, [c], "water", 3)
	_tick(f)
	var at := f.sim.arena.surface(c)
	await _frames(f, at, 12.0, 30.0, 12)
	_paint(f, [c], "fire", 2)
	await _frames(f, at, 13.0, 24.0, 36)
	await _shot("steam")
	f.queue_free()
	await process_frame


func _eclipse() -> void:
	var f := _fight("glade", "spirewalker", "light", "dark")
	await process_frame
	_place(f, "spirewalker", 6)
	var c := _toward(f, "spirewalker", 2)
	_paint(f, [c], "dark", 3)
	_tick(f)
	var at := f.sim.arena.surface(c)
	await _frames(f, at, 12.0, 30.0, 12)
	_paint(f, [c], "light", 2)
	await _frames(f, at, 12.0, 30.0, 14)
	await _shot("eclipse")
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
