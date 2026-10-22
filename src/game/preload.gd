class_name HHPreload
extends Node
## The boot preload (lane LD, H460-H469). Author, 2026-10-22, after an online
## co-op test in the browser: "Once we got over the load times coop was
## seamless. Maybe bake in the load times before you enter lobby?" The first
## entry into 3D content in the browser costs minutes (WebGL compiles every
## shader pipeline on first draw; models, textures and music load on first
## use), and it was paid on the way into the hunt or a fight. This pays it
## once, at game open, behind HHLoading with a step count ("Preparing the
## hunt... 3/8"), before the first screen:
##
##   1  models, textures, music and sounds load into `cache` (kept alive, so
##      every later load() of them is a cache hit)
##   2  the region map is built in front of its camera
##   3+ each monster in its own arena is built as a real solo NORMAL fight
##      (the fight's own HHWarmup draws every shader; then the camera turns
##      to the monster, the NORMAL tier effects appear, and a tiny copy of
##      every mesh + material in the fight is drawn in front of the camera)
##   n  the ambush cutscene, scrubbed to the monster's burst
##
## Each 3D step holds HHTune preload_frames frames and is freed. The fight's
## own warm-up stays as the cheap per-fight fallback. Headless runs (the
## self-test, smoke runs) never preload; the desktop skips it by default
## (preload_on_desktop), the browser runs it (preload_on_web). `--preload` /
## `--no-preload` force it either way. Every step prints its time.

signal done()

const RES_DIRS := ["res://art", "res://audio"]
const RES_EXTS := ["glb", "gltf", "png", "jpg", "webp", "wav", "ogg", "mp3", "tres", "res"]
const SKIP_DIRS := ["blend"]
const WEAPON_CYCLE := ["lance", "daggers", "bow"]
const ELEMENT_PAIRS := [["fire", "water"], ["ice", "thunder"], ["wind", "dark"], ["light", "fire"]]
const LOAD_BUDGET_MS := 40           ## the resource step loads for this long per frame, then paints its count
const STEP_FRAME_CAP := 3000         ## a fight that never finishes its own loading is let go after this many frames

static var cache: Array[Resource] = []   ## everything step 1 loaded, alive for the whole run
static var ran := false
static var timings: Array = []           ## [{ label, ms }] from the last run

var _screen: HHLoading
var _stage: Node3D
var _look_cam: Camera3D = null           # while set, this camera looks at _look_at after everyone else moved it
var _look_at: Node3D = null
var _was_muted := false


## Should this run preload? Pure: the caller passes the platform.
static func wanted(args: PackedStringArray, is_web: bool, headless: bool) -> bool:
	if headless or "--self-test" in args or "--no-preload" in args:
		return false
	if "--shot" in args or "--shot-lobby" in args:    # the capture tool times its frames from boot
		return false
	if "--preload" in args:
		return true
	return HHTune.value("preload_on_web" if is_web else "preload_on_desktop") > 0.5


## The steps, in order. Pure (no nodes): [{ kind, label, cfg? }].
static func plan() -> Array:
	var steps: Array = [{ "kind": "resources", "label": "Loading models and music" },
		{ "kind": "map", "label": "Drawing the region map" }]
	var i := 0
	for m in HHRegistry.rows("monster"):
		var pair: Array = ELEMENT_PAIRS[i % ELEMENT_PAIRS.size()]
		var cfg := HHShell.default_cfg()
		cfg.arena = str(m.biome)
		cfg.monster = str(m.id)
		cfg.weapon = WEAPON_CYCLE[i % WEAPON_CYCLE.size()]
		cfg.element = pair[0]
		cfg.backup = pair[1]
		cfg.difficulty = "normal"                       # the tier effects are NORMAL only, and EASY draws a subset
		cfg.cam = "30,44"
		steps.append({ "kind": "fight", "label": "Waking %s in %s" % [m.name, _arena_name(str(m.biome))], "cfg": cfg })
		i += 1
	var first: Dictionary = HHRegistry.rows("monster")[0]
	steps.append({ "kind": "ambush", "label": "Rehearsing the ambush",
		"cfg": { "seed": 1, "monster": str(first.id), "arena": str(first.biome), "weapon": "lance" } })
	return steps


static func _arena_name(id: String) -> String:
	for a in HHRegistry.rows("arena"):
		if str(a.id) == id:
			var n := str(a.name)
			return n.replace("The ", "the ") if n.begins_with("The ") else "the " + n
	return "the " + id


## "Preparing the hunt... 3/8" over the step's own line.
static func progress_text(i: int, n: int, label: String, detail: String = "") -> String:
	var s := "Preparing the hunt... %d/%d\n%s" % [mini(i + 1, n), n, label]
	if detail != "":
		s += " (%s)" % detail
	return s


## Every file under `dir` (recursive) with one of `exts`, skipping SKIP_DIRS.
## ResourceLoader.list_directory lists an exported build's resources by
## their source names (.import / .remap resolved).
static func list_files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	for e in ResourceLoader.list_directory(dir):
		var name := str(e)
		if name.ends_with("/"):
			if not name.trim_suffix("/") in SKIP_DIRS:
				out.append_array(list_files(dir.path_join(name.trim_suffix("/")), exts))
		elif name.get_extension().to_lower() in exts:
			out.append(dir.path_join(name))
	return out


static func resource_paths() -> Array[String]:
	var out: Array[String] = []
	for d in RES_DIRS:
		out.append_array(list_files(d, RES_EXTS))
	return out


# ------------------------------------------------------------------ run

func _init() -> void:
	name = "Preload"
	process_priority = 1000                 # after the fight and its camera rig: the look-at override wins


## Run every step behind the loading screen, then emit `done` and free.
func run() -> void:
	_screen = HHLoading.new()
	add_child(_screen)
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	_was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)          # a woken monster roars behind the screen otherwise
	timings = []
	var t_all := Time.get_ticks_msec()
	var steps := plan()
	for i in steps.size():
		var st: Dictionary = steps[i]
		_say(i, steps.size(), str(st.label))
		await _frames(2)                       # paint the line before the step's long frame
		var t0 := Time.get_ticks_msec()
		match str(st.kind):
			"resources": await _resources(i, steps.size(), str(st.label))
			"map": await _map()
			"fight": await _fight(st.cfg)
			"ambush": await _ambush(st.cfg)
		var ms := Time.get_ticks_msec() - t0
		timings.append({ "label": str(st.label), "ms": ms })
		print("preload: %d/%d %s: %d ms" % [i + 1, steps.size(), st.label, ms])
	print("preload: done in %d ms (%d resources cached)" % [Time.get_ticks_msec() - t_all, cache.size()])
	ran = true
	AudioServer.set_bus_mute(0, _was_muted)
	_say(steps.size() - 1, steps.size(), "Ready")
	done.emit()
	queue_free()


func _say(i: int, n: int, label: String, detail: String = "") -> void:
	if _screen != null:
		_screen.set_text(progress_text(i, n, label, detail))
		_screen.set_progress(float(i) / float(maxi(n, 1)))


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _process(_delta: float) -> void:
	if _look_cam != null and is_instance_valid(_look_cam) and _look_at != null and is_instance_valid(_look_at):
		var at := _look_at.global_position + Vector3(0, 1.5, 0)
		_look_cam.look_at_from_position(at + Vector3(0, 9, 14), at)


func _resources(i: int, n: int, label: String) -> void:
	var paths := resource_paths()
	var t := Time.get_ticks_msec()
	for k in paths.size():
		var r := load(paths[k])
		if r != null:
			cache.append(r)
		if Time.get_ticks_msec() - t > LOAD_BUDGET_MS:
			_say(i, n, label, "%d/%d" % [k + 1, paths.size()])
			await get_tree().process_frame
			t = Time.get_ticks_msec()


func _hold(cam: Camera3D, root: Node) -> void:
	if cam == null:
		return
	var w := HHWarmup.new()
	w.name = "PreloadWarm"
	w.frames = int(HHTune.value("preload_frames"))
	cam.add_child(w)
	w.position = Vector3(0, 0, -2.0)
	w.begin(cam.global_position)
	var got := w.add_proxies(root, false)
	print("preload:   %d mesh/material proxies under %s" % [got, root.name])
	await w.done


func _map() -> void:
	var m := HHWorldMap.new()
	m.name = "PreloadMap"
	_stage.add_child(m)
	m.setup({ "seed": 1, "weapon": "lance" })
	await _frames(int(HHTune.value("preload_frames")))
	await _hold(m.camera.cam if m.camera != null else null, m)
	m.queue_free()
	await get_tree().process_frame


func _fight(cfg: Dictionary) -> void:
	var f := HHFight.new()
	f.name = "PreloadFight"
	_stage.add_child(f)
	f.setup_cfg(cfg)
	var k := 0
	while f.loading and k < STEP_FRAME_CAP:     # its own HHWarmup: every shader, lit, in this arena
		await get_tree().process_frame
		k += 1
	var cam: Camera3D = f.camera.cam if f.camera != null else null
	for b in f.monster_bodies.values():          # the skinned monster in view, whatever the spawn layout
		if b is Node3D:
			_look_cam = cam
			_look_at = b
	await _frames(int(HHTune.value("preload_frames")))   # the sim steps: NORMAL's tier effects appear
	await _hold(cam, f)
	_look_cam = null
	_look_at = null
	f.queue_free()
	await get_tree().process_frame


func _ambush(cfg: Dictionary) -> void:
	var a := HHAmbush.new()
	a.name = "PreloadAmbush"
	_stage.add_child(a)
	a.setup(cfg)
	a.scrub(HHAmbush.peak_time())
	a.paused = true
	await _frames(int(HHTune.value("preload_frames")))
	await _hold(a.camera.cam if a.camera != null else null, a)
	a.queue_free()
	await get_tree().process_frame
