extends SceneTree
## H60 (Lane X) review renders of the melee strings, from the SIDE and the
## FRONT (the fight camera sits behind the hunter and hides the motion).
## Needs a window (not headless):
##   godot --path . --script res://tools/combo_preview.gd [-- --out design/feel/combo_anim --tag final --only lance]
## Per weapon with a string (lance, daggers) it runs a real HHSim string
## (three hits on a still target) and drives an HHPlayerBody through the
## sim's events exactly as HHFight does (60 fps, the 75 ms hit-stop on the
## finisher), then writes:
##   <w>_<tag>_side.png, <w>_<tag>_front.png  a 4 x 3 sheet: a row per hit
##       at anticipation (the coil) / contact (the strike tick) /
##       follow-through (mid recovery) / settle (the frame before the next
##       hit's wind-up: the ready loop, or the guard after the finisher)
##   <w>_<tag>_strip.png  the whole string from the side, every 2nd tick
##       (the lance every 3rd), 12 frames a row
## A red disc on the ground marks the target; the floor has a 1 m hex grid.

const TILE := Vector2i(520, 460)
const STRIP_W := 380
const ROW := 12
const DIST := { "lance": 2, "daggers": 1 }

var out_dir := "design/feel/combo_anim"
var tag := "final"
var only := ""
var world: Node3D
var cam: Camera3D
var label: Label
var target_disc: MeshInstance3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--tag")
	if i >= 0 and i + 1 < args.size():
		tag = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	root.size = TILE
	_build.call_deferred()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _build() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.9)
	sm.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.25)
	sm.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -60.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 120.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.8, 0.85, 1.0)
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.52, 0.36)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	world.add_child(_hex_grid(6))
	target_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = 0.03
	target_disc.mesh = cyl
	target_disc.material_override = HHLook.flat(Color(0.85, 0.2, 0.15, 0.55), true)
	world.add_child(target_disc)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 200.0
	world.add_child(cam)
	cam.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	label = Label.new()
	label.position = Vector2(10, 6)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 5)
	layer.add_child(label)
	_run()


func _hex_grid(r: int) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 0.26, 0.18)
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for h in HHHex.area(Vector2i.ZERO, r):
		var w := HHHex.to_world(h, 1.0)
		var cs := HHHex.corners(Vector3(w.x, 0.02, w.y), 1.0)
		for i in 6:
			im.surface_add_vertex(cs[i])
			im.surface_add_vertex(cs[(i + 1) % 6])
	im.surface_end()
	mi.mesh = im
	return mi


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	for w in ["lance", "daggers"]:
		if only != "" and w != only:
			continue
		await _weapon(w)
	print("combo_preview: done -> ", _abs(out_dir))
	quit(0)


## A sim with the hunter `DIST` hexes off a still 1-hex target, attacking.
func _string_sim(w: String) -> HHSim:
	var arena := HHArena.round_flat(1, 20.0, 0.0)
	var sim := HHSim.new(arena, 1)
	var u := sim.add_player("p1", Vector2i(10, 10), "fire", "water", w)
	sim.add_monster("m", Vector2i(10 + int(DIST[w]) + 1, 10), 1.0e7, 1)
	u.target = "m"
	u.attacking = true
	return sim


## Pass 1: the string's ticks per hit: { step: { w, s, r } } and the end.
func _timeline(w: String) -> Dictionary:
	var sim := _string_sim(w)
	var hits := {}
	var step := 0
	for k in 200:
		for e in sim.step({}):
			if str(e.get("id", "")) != "p1":
				continue
			match str(e.type):
				"windup":
					step = int(e.get("step", 1))
					if hits.has(step):
						return hits                 # the next string began
					hits[step] = { "w": sim.tick, "s": -1, "r": 0 }
				"strike":
					hits[step].s = sim.tick
				"recovery":
					hits[step].r = int(e.ticks)
	return hits


## The sheet's moments: per hit, [label, tick].
func _moments(hits: Dictionary) -> Array:
	var out: Array = []
	for step in [1, 2, 3]:
		var h: Dictionary = hits[step]
		var wu := int(h.s) - int(h.w)
		var nxt := int(hits[step + 1].w) if hits.has(step + 1) else int(h.s) + int(h.r)
		# the coil beat (B|W f8 of 14); the body runs a tick ahead of the event that started it
		out.append([step, "anticipation", int(h.w) + maxi(1, int(roundf(float(wu) * 8.0 / 14.0)) - 1)])
		out.append([step, "contact", int(h.s)])
		out.append([step, "follow-through", int(h.s) + maxi(2, int(h.r) / 2)])
		out.append([step, "settle", nxt - 1])
	return out


func _weapon(w: String) -> void:
	var hits := _timeline(w)
	print("combo_preview: %s timeline %s" % [w, hits])
	var moments := _moments(hits)
	var want := {}
	for m in moments:
		want[int(m[2])] = true
	var last := int(hits[3].s) + int(hits[3].r) + 2
	var every := 3 if w == "lance" else 2
	var sim := _string_sim(w)
	var body := HHPlayerBody.new()
	world.add_child(body)
	body.build(w)
	body.bind(sim, "p1")
	body.position = Vector3.ZERO
	body.rotation.y = 0.0
	var m := sim.unit("m")
	var p := sim.unit("p1")
	var reach := ((m.pos as Vector3) - (p.pos as Vector3)).length()
	target_disc.position = Vector3(0, 0.02, reach - 1.73)
	(target_disc.mesh as CylinderMesh).top_radius = 0.7
	(target_disc.mesh as CylinderMesh).bottom_radius = 0.7
	body.update(1.0 / 60.0)
	var side_tiles := {}
	var front_tiles := {}
	var strip: Array[Image] = []
	var hitstop := 0.0
	for k in last + 1:
		var tick := sim.tick + 1
		var events := sim.step({})
		for e in events:
			if str(e.get("id", "")) == "p1":
				body.on_event(e, sim)
				if str(e.type) == "strike" and bool(e.get("heavy", false)):
					hitstop = HHTune.value("fight_hitstop_s") if HHTune.has("fight_hitstop_s") else 0.075
		for sub in 2:
			var d := 1.0 / 60.0
			if hitstop > 0.0:
				hitstop -= d
				d = 0.0
			body.update(d)
		if want.has(tick):
			for mo in moments:
				if int(mo[2]) == tick:
					label.text = "%s  hit %d  %s  (tick %d, %s %.2f)" % [w, int(mo[0]), str(mo[1]), tick, body.clip, body.time]
					print(label.text)
			_side(reach)
			side_tiles[tick] = await _grab()
			_front(reach)
			front_tiles[tick] = await _grab()
		if k % every == 0:
			label.text = "%d" % tick
			_side(reach, 1.1)                       # centred on the figure and the first metres of its reach
			strip.append(await _grab())
	label.text = ""
	_sheet(moments, side_tiles, _abs(out_dir).path_join("%s_%s_side.png" % [w, tag]))
	_sheet(moments, front_tiles, _abs(out_dir).path_join("%s_%s_front.png" % [w, tag]))
	_strip(strip, _abs(out_dir).path_join("%s_%s_strip.png" % [w, tag]))
	body.queue_free()
	await process_frame


## From the hunter's right, square to the line of attack.
func _side(reach: float, mid_z: float = -1.0) -> void:
	var mid := Vector3(0.0, 1.05, reach * 0.4 if mid_z < 0.0 else mid_z)
	cam.position = mid + Vector3(-6.4, 0.6, 0.0)
	cam.look_at(mid, Vector3.UP)


## From in front, a little off the line and above (the target is a disc).
func _front(reach: float) -> void:
	var mid := Vector3(0.0, 1.1, 0.2)
	cam.position = mid + Vector3(0.8, 0.8, 4.6)
	cam.look_at(mid, Vector3.UP)


func _grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	return img


func _sheet(moments: Array, tiles: Dictionary, path: String) -> void:
	var first: Image = tiles.values()[0]
	var tw := first.get_width()
	var th := first.get_height()
	var img := Image.create(tw * 4, th * 3, false, first.get_format())
	for i in moments.size():
		var t := int(moments[i][2])
		if tiles.has(t):
			img.blit_rect(tiles[t], Rect2i(0, 0, tw, th), Vector2i(tw * (i % 4), th * (i / 4)))
	var err := img.save_png(path)
	print("combo_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])


func _strip(tiles: Array[Image], path: String) -> void:
	var tw := tiles[0].get_width()
	var th := tiles[0].get_height()
	var cw := mini(STRIP_W, tw)
	var x0 := (tw - cw) / 2
	var rows := int(ceil(float(tiles.size()) / float(ROW)))
	var img := Image.create(cw * ROW, th * rows, false, tiles[0].get_format())
	for i in tiles.size():
		img.blit_rect(tiles[i], Rect2i(x0, 0, cw, th), Vector2i(cw * (i % ROW), th * (i / ROW)))
	var err := img.save_png(path)
	print("combo_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
