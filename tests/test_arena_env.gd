extends RefCounted
## Lane ENV visual pass (H750-H761): the material kinds it added, the camera
## clamp per instance (L-21), and the world map's dressing (L-20).


func test_material_kinds(c: HHSelfTest.HHCheck) -> void:
	var fade := GKMaterials.get_material("conifer")
	c.ok(fade is ShaderMaterial and (fade as ShaderMaterial).shader.resource_path == GKMaterials.SHADER_FADE, "skirt trees dissolve near the camera (gk_fade)")
	var lava := GKMaterials.get_material("lava")
	c.ok(lava is StandardMaterial3D and (lava as StandardMaterial3D).emission_enabled, "lava glows")
	var pool := GKMaterials.get_material("glow_warm")
	c.ok(pool is StandardMaterial3D and (pool as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "light pools are additive")
	c.ok(not GKMaterials.ROLES.stalagmite.has("fade"), "cave pillars (destructible obstacles) never fade")
	c.ok(not GKMaterials.ROLES.glade_trunk.has("fade"), "glade tree trunks (obstacles) never fade")


func test_camera_clamp_per_instance(c: HHSelfTest.HHCheck) -> void:
	var a := HHCameraRig.new()
	a.dist = 500.0
	c.near(a.dist, HHCameraRig.DIST_MAX, 1e-6, "the fight's rig keeps its 40 m clamp")
	var b := HHCameraRig.new()
	b.dist_max = 260.0
	b.dist = 170.0
	c.near(b.dist, 170.0, 1e-6, "a rig with a raised clamp holds 170 m")
	a.free()
	b.free()


func test_map_dressing(c: HHSelfTest.HHCheck) -> void:
	for seed in [1, 2, 7]:
		var lay := HHWorldMap.layout(seed)
		var d1 := HHWorldMap.dress_layout(seed, lay.sites)
		var d2 := HHWorldMap.dress_layout(seed, lay.sites)
		c.eq(var_to_str(d1), var_to_str(d2), "seed %d: same dressing twice" % seed)
		c.eq((d1.paths as Array).size(), 4, "seed %d: a path to every site" % seed)
		for s in lay.sites:
			var sp := Vector2((s.pos as Vector3).x, (s.pos as Vector3).z)
			c.ok(sp.distance_to(d1.lake) > HHWorldMap.SITE_R + 15.0, "seed %d: the lake keeps off the %s" % [seed, s.biome])
			c.ok(sp.distance_to(d1.tower) > HHWorldMap.SITE_R, "seed %d: the tower keeps off the %s" % [seed, s.biome])
		c.ok((d1.clusters as Array).size() >= 4, "seed %d: tree clusters placed (%d)" % [seed, (d1.clusters as Array).size()])
	var map := HHWorldMap.new()
	map.setup({ "seed": 1 })
	c.ok(map.camera.get_parent() == map, "the map's rig is not under a scaled parent any more (L-21)")
	c.near(map.camera.dist, HHHuntKit.t("map_cam_dist"), 1e-3, "the map camera orbits at map_cam_dist in world metres")
	map.free()
