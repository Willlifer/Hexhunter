extends SceneTree
## Lane FX review renders: every monster attack's wind-up at 0 %, 50 %, 90 %
## and contact, at the gameplay camera (30 m, 44 deg, FOV 40), on the
## monster's own biome, through the real fight (HHFight: sim, brain, body,
## arena view, the FX layer). The tool triggers each attack by calling the
## brain's own attack function (so shapes, clips and windows are the
## brain's), then steps the sim one tick per rendered frame.
## Needs a window (not headless):
##   godot --path . --script res://tools/fx_preview.gd [-- --only colambros] [--attack ember_spit] [--out dir]
## Writes <out>/<monster>_<attack>_<00|50|90|contact>.png, plus
## colambros_breath_vs_charge.png (both at 50 %) and ice_sequence.png
## (Rimeslithe's mist breath: wind at 50 %, frost at 90 %, contact).

const OUT := "design/visual_pass/FX"
const SAVE_SIZE := Vector2i(960, 600)
const BIOME := { "colambros": "caldera", "swampfang": "pond", "rimeslithe": "cave", "spirewalker": "glade" }
## [monster, attack id (file name), player distance in hexes, player behind?, extra setup]
const ATTACKS := [
	["colambros", "ember_spit", 7, false, ""],
	["colambros", "charge", 9, false, ""],
	["colambros", "charge_smoulder", 9, false, "smoulder"],
	["colambros", "bite", 4, false, ""],
	["colambros", "tail_lash", 4, true, ""],
	["colambros", "leap_stomp", 7, false, ""],
	["colambros", "back_roll", 5, false, "smoulder"],
	["swampfang", "dark_spray", 6, false, ""],
	["swampfang", "water_jet", 7, false, ""],
	["swampfang", "thrash_splash", 4, false, ""],
	["swampfang", "death_roll_spin", 4, false, ""],
	["swampfang", "darkness", 6, false, ""],
	["swampfang", "swim", 7, false, ""],
	["swampfang", "surface_lunge", 4, false, ""],
	["rimeslithe", "frost_beam", 8, false, ""],
	["rimeslithe", "cold_slam", 4, false, ""],
	["rimeslithe", "shoulder_charge", 7, false, ""],
	["rimeslithe", "bite", 4, false, ""],
	["rimeslithe", "arm_swipe", 4, false, ""],
	["rimeslithe", "mist_breath", 6, false, ""],
	["rimeslithe", "mist_wide", 6, false, ""],
	["rimeslithe", "meteor_drop", 7, false, ""],
	["rimeslithe", "freeze_pillar", 6, false, ""],
	["spirewalker", "forearm_punch", 4, false, ""],
	["spirewalker", "bite", 4, false, ""],
	["spirewalker", "leaping_squash", 7, false, ""],
	["spirewalker", "barb_throw", 7, false, ""],
	["spirewalker", "reed_lash", 6, false, ""],
	["spirewalker", "tail_drag", 4, true, ""],
	["spirewalker", "pollen_shake", 4, false, "charged"],
	["spirewalker", "thunder_breath", 6, false, ""],
	["spirewalker", "dark_breath", 6, false, ""],
	["spirewalker", "spore_spread", 4, false, ""],
	# the arena's own events (H51) and a reaction landing (H50)
	["swampfang", "env_swell", 6, false, ""],
	["colambros", "env_vent", 6, false, ""],
	["rimeslithe", "env_rockfall", 6, false, ""],
	["spirewalker", "env_sunbreak", 6, false, ""],
	["spirewalker", "env_gust", 6, false, ""],
	["colambros", "reaction", 6, false, ""],
	# the hunter's own (lance, fire): Pierce's wind-up and line, Eruption's ring burst
	["colambros", "player_pierce", 5, false, ""],
	["colambros", "player_eruption", 3, false, ""],
]
const MARKS := [["00", 0.0], ["50", 0.5], ["90", 0.9], ["contact", -1.0]]

var out_dir := OUT
var only := ""
var only_attack := ""
var shots := {}
var reaction_pending := {}
var pending_order := {}                   # "<monster>_<attack>_<mark>" -> Image (kept for the composites)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	i = args.find("--attack")
	if i >= 0 and i + 1 < args.size():
		only_attack = args[i + 1]
	root.size = Vector2i(1280, 800)
	_run.call_deferred()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	for a in ATTACKS:
		if only != "" and a[0] != only:
			continue
		if only_attack != "" and a[1] != only_attack:
			continue
		await _shoot(a)
	if shots.has("colambros_ember_spit_50") and shots.has("colambros_charge_50"):
		_side_by_side([shots["colambros_ember_spit_50"], shots["colambros_charge_50"]], "colambros_breath_vs_charge.png", ["breath (ember_spit) 50%", "charge 50%"])
	if shots.has("rimeslithe_mist_breath_50"):
		var seq: Array = []
		for m in ["00", "50", "90", "contact"]:
			if shots.has("rimeslithe_mist_breath_" + m):
				seq.append(shots["rimeslithe_mist_breath_" + m])
		_grid(seq, "ice_sequence.png")
	_sheets()
	print("fx_preview: done -> ", _abs(out_dir))
	quit(0)


func _shoot(a: Array) -> void:
	var monster: String = a[0]
	var attack: String = a[1]
	var dist: int = a[2]
	var behind: bool = a[3]
	var extra: String = a[4]
	var f := HHFight.new()
	f.setup_cfg({ "arena": BIOME[monster], "monster": monster, "weapon": "lance", "element": "fire", "backup": "water", "seed": 1, "cam": "30,44" })
	root.add_child(f)
	f.set_process(false)
	await process_frame
	if f.debug != null:
		f.debug.visible = false
	var sim: HHSim = f.sim
	var u := sim.unit(monster)
	var p := sim.unit("p1")
	var brain: Object = sim.brains.get(monster)
	# put the hunter `dist` hexes off the monster's front (or behind it)
	# the spawn sits by the edge (the footprint barely fits there): stand it in
	# the open first, as it is mid-fight
	for c in [Vector2i(0, -4), Vector2i(2, -4), Vector2i(-2, -4), Vector2i(0, -2), Vector2i(0, -6)]:
		if brain.has_method("_fits") and bool(brain.call("_fits", sim, u, c, u.get("allowed_kinds", []), sim.blocked_for(u))):
			u.hex = c
			u.pos = sim.arena.stand(c)
			u.path = []
			break
	var mh: Vector2i = u.hex
	var at := _place(sim, mh, dist, brain, u, p, attack.begins_with("charge"))
	p.hex = at
	p.pos = sim.arena.stand(at)
	p.path = []
	var to := (p.pos as Vector3) - (u.pos as Vector3)
	u.facing = atan2(to.x, to.z) + (PI if behind else 0.0)
	if extra == "smoulder":
		brain.set("smouldering", true)
		u["smoulder"] = true
	if extra == "charged":
		u["charge"] = 0.9
	# settle a few frames (bodies pose, the camera snaps)
	for k in 6:
		_frame(f, monster)
		await _drawn()
	var before := {}
	for tg in sim.telegraphs:
		before[int(tg.id)] = true
	if not _trigger(brain, sim, u, p, attack):
		print("fx_preview: %s %s could not trigger" % [monster, attack])
		f.queue_free()
		await process_frame
		return
	var mine: Array = []
	for tg in sim.telegraphs:
		if not before.has(int(tg.id)):
			mine.append(int(tg.id))
	var total := 1
	var first := 1 << 30
	for tg in sim.telegraphs:
		if int(tg.id) in mine:
			first = mini(first, int(tg.left))
	total = first if first < (1 << 30) else 30
	print("fx_preview: %s %s window %d ticks, %d telegraphs" % [monster, attack, total, mine.size()])
	var t := 0
	var marks := MARKS.duplicate()
	var contact_at := -1
	while not marks.is_empty() and t < total + 60:
		_tick(f, monster)
		t += 1
		var live := 0
		for tg in sim.telegraphs:
			if int(tg.id) in mine:
				live += 1
		if live < mine.size() and contact_at < 0:
			contact_at = t
		var m: Array = marks[0]
		var want := float(m[1])
		var hit := false
		if want >= 0.0:
			hit = t >= maxi(2, int(round(want * total)))
		else:
			hit = contact_at >= 0 and t >= contact_at + 3
		await _drawn()
		if hit:
			var key := "%s_%s_%s" % [monster, attack, m[0]]
			var img := root.get_viewport().get_texture().get_image()
			shots[key] = img
			var small := img.duplicate() as Image
			small.resize(SAVE_SIZE.x, SAVE_SIZE.y, Image.INTERPOLATE_LANCZOS)
			small.save_png(_abs(out_dir).path_join(key + ".png"))
			print("fx_preview: ", key, " (t %d, sprites %d)" % [t, f.view.fxl.sprite_count()])
			marks.pop_front()
	f.queue_free()
	await process_frame


## A walkable hex about `dist` from `mh` with the clearest line to it (for a
## charge: the longest charge line the brain itself would run).
func _place(sim: HHSim, mh: Vector2i, dist: int, brain: Object, u: Dictionary, p: Dictionary, charge: bool) -> Vector2i:
	var best := mh + Vector2i(0, dist)
	var best_s := -1
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var h := mh + (d as Vector2i) * dist
		if absi(d.x) + absi(d.y) == 2:
			h = mh + Vector2i(d.x * dist * 2 / 3, d.y * dist * 2 / 3)
		if not (sim.arena.exists(h) and sim.arena.walkable(h)):
			continue
		var s := 0
		if charge:
			var keep: Vector2i = p.hex
			p.hex = h
			s = (brain.call("_charge_line", sim, u, p) as Array).size()
			p.hex = keep
		else:
			for q in HHHex.line(mh, h):
				if sim.arena.exists(q) and sim.arena.walkable(q):
					s += 1
		if d == Vector2i(0, 1):
			s += 1                                   # prefer straight down the screen on a tie
		if s > best_s:
			best_s = s
			best = h
	return best


func _trigger(b: Object, sim: HHSim, u: Dictionary, p: Dictionary, attack: String) -> bool:
	match attack:
		"ember_spit": b.call("_ember_spit", sim, u, p)
		"charge", "charge_smoulder":
			var line: Array = b.call("_charge_line", sim, u, p)
			if line.is_empty():
				return false
			b.call("_charge", sim, u, p, line)
		"bite": b.call("_bite", sim, u, p)
		"tail_lash": b.call("_tail_lash", sim, u, p)
		"leap_stomp": return bool(b.call("_leap", sim, u, p))
		"back_roll": b.call("_back_roll", sim, u)
		"dark_spray": b.call("_dark_spray", sim, u, p)
		"water_jet": b.call("_water_jet", sim, u, p)
		"thrash_splash": b.call("_thrash", sim, u)
		"death_roll_spin": b.call("_death_roll", sim, u)
		"darkness": b.call("_darkness", sim, u, p)
		"swim": b.call("_start_swim", sim, u, p)
		"surface_lunge": b.call("_surface", sim, u)
		"frost_beam": b.call("_frost_beam", sim, u, p)
		"cold_slam": b.call("_cold_slam", sim, u)
		"shoulder_charge": b.call("_shoulder_charge", sim, u, p)
		"arm_swipe": b.call("_arm_swipe", sim, u, p)
		"mist_breath": b.call("_mist_breath", sim, u, p)
		"mist_wide": b.call("_mist_wide", sim, u)
		"meteor_drop": b.call("_meteor_drop", sim, u, p)
		"freeze_pillar": return bool(b.call("_freeze_pillar", sim, u, p))
		"forearm_punch": b.call("_punch", sim, u, p)
		"leaping_squash": b.call("_squash", sim, u, p)
		"barb_throw": b.call("_barb_throw", sim, u, p)
		"reed_lash": b.call("_reed_lash", sim, u, p)
		"tail_drag": b.call("_tail_drag", sim, u)
		"pollen_shake": b.call("_pollen", sim, u)
		"thunder_breath": b.call("_thunder_breath", sim, u, p)
		"dark_breath": b.call("_dark_breath", sim, u, p)
		"spore_spread": b.call("_spore_spread", sim, u)
		"env_swell": sim.env.call("_pond")
		"env_vent": sim.env.call("_caldera")
		"env_rockfall":
			# drop them where the camera looks: between the monster and the hunter
			var mid: Vector2i = HHHex.line(u.hex, p.hex)[HHHex.line(u.hex, p.hex).size() / 2]
			var drops: Array = []
			for c in [mid, mid + Vector2i(3, 0), mid + Vector2i(-3, 1)]:
				drops.append_array(sim.arena.area(c, 1))
			for c in [mid, mid + Vector2i(3, 0), mid + Vector2i(-3, 1)]:
				sim.env.call("_tg", "env_rockfall", sim.env.call("_inside", sim.arena.area(c, 1)), HHTune.value("env_warn_s"), "dark", 1, HHTune.value("env_cave_dmg_pct"), 0.35)
		"env_sunbreak":
			sim.env.count = 1
			sim.env.call("_glade")
		"env_gust":
			sim.env.count = 2
			sim.env.call("_glade")
		"player_pierce", "player_eruption":
			sim.telegraph("p1", [p.hex], 24, { "name": "fx_preview_marker" })
			pending_order = { "p1": { "cast": { "skill": "q" if attack == "player_pierce" else "r", "aim": u.hex } } }
		"reaction":
			# a stand-in telegraph so the capture marks run, and the events the
			# sim sends when a reaction lands on the monster
			sim.telegraph("p1", [p.hex], 12, { "name": "fx_preview_marker" })
			reaction_pending = { "id": u.id, "at": 10 }
		_:
			return false
	return true


## One sim tick through the fight's own event handling, then a draw.
func _tick(f: HHFight, monster: String) -> void:
	var ev := f.sim.step(pending_order)
	pending_order = {}
	if not reaction_pending.is_empty():
		reaction_pending.at = int(reaction_pending.at) - 1
		if int(reaction_pending.at) <= 0:
			var m := f.sim.unit(str(reaction_pending.id))
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1)]:
				ev.append({ "type": "detonate", "hex": (m.hex as Vector2i) + d, "mult": 2.4, "pct": 2.4, "mix": "fire_water", "tick": f.sim.tick })
			ev.append({ "type": "reaction", "id": m.id, "amount": 1872.0, "blasts": 3, "cause": "overheat", "tick": f.sim.tick })
			reaction_pending = {}
	for e in ev:
		f._note(e)
		f.view.on_event(e, f.sim)
	_frame(f, monster)


func _frame(f: HHFight, monster: String) -> void:
	f._draw(HHSim.TICK)
	var u := f.sim.unit(monster)
	var p := f.sim.unit("p1")
	var mid: Vector3 = ((u.pos as Vector3) + (p.pos as Vector3)) * 0.5
	var to := (p.pos as Vector3) - (u.pos as Vector3)
	f.camera.yaw = atan2(to.x, to.z)
	f.camera.dist = 30.0
	f.camera.pitch = deg_to_rad(44.0)
	f.camera.follow(mid, true)


func _drawn() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _side_by_side(imgs: Array, name: String, labels: Array) -> void:
	var w := 0
	var h := 0
	for im in imgs:
		w += (im as Image).get_width()
		h = maxi(h, (im as Image).get_height())
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x := 0
	for im in imgs:
		var src := (im as Image)
		src.convert(Image.FORMAT_RGBA8)
		out.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(x, 0))
		x += src.get_width()
	out.fill_rect(Rect2i(imgs[0].get_width() - 2, 0, 4, h), Color(0, 0, 0))
	out.save_png(_abs(out_dir).path_join(name))
	print("fx_preview: ", name, " ", labels)


## Review aid: one sheet per monster, a row per attack (0 / 50 / 90 / contact).
func _sheets() -> void:
	var tw := 320
	var th := 200
	for monster in BIOME:
		var rows: Array = []
		for a in ATTACKS:
			if a[0] == monster and shots.has("%s_%s_00" % [monster, a[1]]):
				rows.append(a[1])
		if rows.is_empty():
			continue
		var out := Image.create(tw * 4, th * rows.size(), false, Image.FORMAT_RGBA8)
		for r in rows.size():
			var c := 0
			for m in ["00", "50", "90", "contact"]:
				var key := "%s_%s_%s" % [monster, rows[r], m]
				if shots.has(key):
					var src := (shots[key] as Image).duplicate() as Image
					src.convert(Image.FORMAT_RGBA8)
					src.resize(tw, th, Image.INTERPOLATE_BILINEAR)
					out.blit_rect(src, Rect2i(0, 0, tw, th), Vector2i(c * tw, r * th))
				c += 1
		out.save_png(_abs(".fxtmp").path_join("sheet_%s.png" % monster))
		print("fx_preview: sheet ", monster, " ", rows)


func _grid(imgs: Array, name: String) -> void:
	if imgs.is_empty():
		return
	var cw := (imgs[0] as Image).get_width() / 2
	var ch := (imgs[0] as Image).get_height() / 2
	var out := Image.create(cw * 2, ch * 2, false, Image.FORMAT_RGBA8)
	for i in imgs.size():
		var src := (imgs[i] as Image).duplicate() as Image
		src.convert(Image.FORMAT_RGBA8)
		src.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(src, Rect2i(0, 0, cw, ch), Vector2i((i % 2) * cw, (i / 2) * ch))
	out.save_png(_abs(out_dir).path_join(name))
	print("fx_preview: ", name)
