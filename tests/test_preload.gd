extends RefCounted
## Lane LD (H460-H466): the boot preload's plan, gate and progress line, the
## resource and shader lists it walks, the shared runtime shaders, and
## HHWarmup's mesh + material proxies.


func test_plan_covers_every_monster_arena_weapon_element(c: HHSelfTest.HHCheck) -> void:
	var steps := HHPreload.plan()
	c.eq(str(steps[0].kind), "resources", "resources load first")
	c.eq(str(steps[steps.size() - 1].kind), "ambush", "the ambush is last")
	var kinds := steps.map(func(s): return str(s.kind))
	c.ok("map" in kinds, "the region map is a step")
	var monsters := {}
	var arenas := {}
	var weapons := {}
	var elements := {}
	for s in steps:
		if str(s.kind) != "fight":
			continue
		var cfg: Dictionary = s.cfg
		monsters[str(cfg.monster)] = true
		arenas[str(cfg.arena)] = true
		weapons[str(cfg.weapon)] = true
		elements[str(cfg.element)] = true
		elements[str(cfg.backup)] = true
		c.eq(str(cfg.difficulty), "normal", "%s preloads on NORMAL (the tier effects)" % cfg.monster)
		c.ok(not cfg.has("net") and not bool(cfg.get("autoplay", false)), "%s is a plain solo fight" % cfg.monster)
		c.ok(str(s.label) != "", "%s has a line" % cfg.monster)
	for m in HHRegistry.ids("monster"):
		c.ok(monsters.has(m), "%s is preloaded" % m)
	for a in HHRegistry.ids("arena"):
		c.ok(arenas.has(a), "the %s arena is preloaded" % a)
	for w in HHRegistry.ids("weapon"):
		c.ok(weapons.has(w), "the %s is preloaded" % w)
	for e in HHRegistry.ids("element"):
		c.ok(elements.has(e), "%s is on some preload hunter" % e)


func test_progress_line(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHPreload.progress_text(2, 8, "Drawing the region map"), "Preparing the hunt... 3/8\nDrawing the region map", "step 3 of 8")
	c.eq(HHPreload.progress_text(0, 8, "Loading models and music", "12/170"), "Preparing the hunt... 1/8\nLoading models and music (12/170)", "with a count")
	c.eq(HHPreload.progress_text(9, 8, "Ready"), "Preparing the hunt... 8/8\nReady", "never past the total")


func test_gate(c: HHSelfTest.HHCheck) -> void:
	var none := PackedStringArray()
	c.ok(HHPreload.wanted(none, true, false), "the browser preloads by default")
	c.ok(not HHPreload.wanted(none, false, false), "the desktop skips it by default")
	c.ok(not HHPreload.wanted(PackedStringArray(["--preload"]), true, true), "headless never preloads")
	c.ok(not HHPreload.wanted(PackedStringArray(["--self-test", "--preload"]), false, false), "the self-test never preloads")
	c.ok(HHPreload.wanted(PackedStringArray(["--preload"]), false, false), "--preload forces it on the desktop")
	c.ok(not HHPreload.wanted(PackedStringArray(["--no-preload"]), true, false), "--no-preload skips it in the browser")
	c.ok(not HHPreload.wanted(PackedStringArray(["--shot", "x", "--preload"]), false, false), "captures never preload")
	HHTune.set_value("preload_on_web", 0.0)
	c.ok(not HHPreload.wanted(none, true, false), "preload_on_web 0 turns it off")
	HHTune.set_value("preload_on_desktop", 1.0)
	c.ok(HHPreload.wanted(none, false, false), "preload_on_desktop 1 turns it on")
	HHTune.reset()


func test_resource_and_shader_lists(c: HHSelfTest.HHCheck) -> void:
	var res := HHPreload.resource_paths()
	c.ok("res://art/monsters/swampfang.glb" in res, "a monster model is cached")
	c.ok("res://art/characters/base_rig.glb" in res, "the hunter rig is cached")
	c.ok("res://audio/music/fight.wav" in res, "the music is cached")
	c.ok(res.filter(func(p): return "/blend/" in p).is_empty(), "blend sources are skipped")
	for p in res:
		c.ok(ResourceLoader.exists(p), "%s resolves" % p)
	var sh := HHWarmup.shader_paths()
	c.ok("res://shaders/telegraph.gdshader" in sh, "res://shaders is warmed")
	c.ok("res://src/arena/shaders/gk_fade.gdshader" in sh, "the arena's own shaders are warmed too")
	var web_only := sh.filter(func(p): return p.get_file().get_basename().ends_with("_web")).size()
	c.ok(web_only >= 3, "the *_web variants are listed (%d)" % web_only)
	c.eq(HHWarmup.shaders().size(), sh.size() - (0 if HHWebLook.active() else web_only) + 3,
		"plus the three runtime-built tier shaders; the *_web ones only on the Compatibility renderer")


func test_tier_shaders_are_shared(c: HHSelfTest.HHCheck) -> void:
	var a := HHTierFx.warm_shaders()
	var b := HHTierFx.warm_shaders()
	c.eq(a.size(), 3, "tile, ring, beam")
	for i in a.size():
		c.ok(a[i] == b[i], "shader %d is one object across fights" % i)
		c.eq(a[i].get_mode(), Shader.MODE_SPATIAL, "shader %d is spatial" % i)
	c.ok(a[0] != a[1] and a[1] != a[2], "three distinct shaders")


func test_proxies(c: HHSelfTest.HHCheck) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var top := Node3D.new()
	root.add_child(top)
	var box := BoxMesh.new()
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	var shown := _mesh(top, box, red, true)
	var hidden := _mesh(top, box, blue, false)
	var twin := _mesh(top, box, blue, false)          # same mesh + material: one proxy
	var parent := Node3D.new()
	parent.visible = false
	top.add_child(parent)
	_mesh(parent, SphereMesh.new(), red, true)          # visible itself, hidden by its parent
	var parts := CPUParticles3D.new()
	parts.mesh = box
	parts.visible = false
	top.add_child(parts)
	var empty := MeshInstance3D.new()                  # nothing to draw
	empty.visible = false
	top.add_child(empty)
	c.eq(HHWarmup.proxy_key(hidden), HHWarmup.proxy_key(twin), "same mesh + material, same key")
	c.ok(HHWarmup.proxy_key(hidden) != HHWarmup.proxy_key(shown), "another material, another key")
	c.eq(HHWarmup.proxy_key(empty), "", "no mesh: no key")
	var w := HHWarmup.new()
	top.add_child(w)
	c.eq(w.add_proxies(top, true), 3, "hidden only: the blue box, the sphere under a hidden parent, the particles")
	c.eq(w.add_proxies(top, false), 1, "then everything: the red box is the one left")
	c.eq(w.add_proxies(top, false), 0, "nothing twice")
	var mm := 0
	for ch in w.get_children():
		c.ok((ch as Node3D).visible, "%s draws" % ch.name)
		c.ok(absf((ch as Node3D).scale.x) < 0.1, "%s is tiny" % ch.name)
		if ch is MultiMeshInstance3D:
			mm += 1
			c.ok((ch as MultiMeshInstance3D).multimesh.use_colors and (ch as MultiMeshInstance3D).multimesh.use_custom_data, "particles warm the coloured custom-data layout")
	c.eq(mm, 1, "one particle proxy")
	top.free()


func _mesh(parent: Node, mesh: Mesh, mat: Material, vis: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = vis
	parent.add_child(mi)
	return mi
