extends SceneTree
## Lane V (L-12): review renders of each monster's reactive state at the
## gameplay camera (30 m, 44 deg, FOV 40, the fight's defaults with --cam
## 30,44) and in close-up. For every monster two bodies stand side by side,
## the left at rest and the right fed its state dictionary through
## set_state, so the glow can be judged against the plain body at the
## distance the player sees it. Needs a window (not headless):
##   godot --path . --script res://tools/monster_state_preview.gd [-- --out design/art/shots/visuals/state]
## Writes <out>/<id>_<state>_far.png and <out>/<id>_<state>_near.png.

const STATES := {
	"colambros":   [{ "name": "smoulder", "u": { "smoulder": true } }],
	"rimeslithe":  [{ "name": "cold_half", "u": { "cold": 0.5 } }, { "name": "cold_full", "u": { "cold": 1.0 } }],
	"spirewalker": [{ "name": "charged", "u": { "charge": 0.9 } }, { "name": "reeds_burnt", "u": { "charge": 0.0, "reeds_burnt": true } }],
	"swampfang":   [{ "name": "darkness", "cue": "darkness" }],
}
const FAR := { "dist": 30.0, "pitch": 44.0 }
const NEAR := { "dist": 12.0, "pitch": 22.0 }

var out_dir := "design/art/shots/visuals/state"
var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	root.size = Vector2i(1280, 800)
	_build.call_deferred()


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
	e.glow_enabled = false                      # the arenas run without glow (stage.gd)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.52, 0.36)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 300.0
	world.add_child(cam)
	cam.make_current()
	_shoot_all()


func _aim(dist: float, pitch_deg: float, target: Vector3) -> void:
	var p := deg_to_rad(pitch_deg)
	cam.position = target + Vector3(0.0, sin(p), cos(p)) * dist
	cam.look_at(target, Vector3.UP)


func _shoot_all() -> void:
	var abs := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs)
	for id in STATES:
		for st in STATES[id]:
			var rest := HHMonsterBody.new()
			var live := HHMonsterBody.new()
			world.add_child(rest)
			world.add_child(live)
			if not rest.build(id) or not live.build(id):
				print("monster_state_preview: no body for ", id)
				continue
			rest.position = Vector3(-5.0, 0.0, 0.0)
			live.position = Vector3(5.0, 0.0, 0.0)
			rest.rotation.y = deg_to_rad(200.0)          # three-quarter from behind, as the fight camera sees a monster facing you
			live.rotation.y = deg_to_rad(200.0)
			rest.play("aggravated_idle")
			live.play("aggravated_idle")
			if st.has("u"):
				var u: Dictionary = (st.u as Dictionary).duplicate()
				u["id"] = id
				live.set_state(u)
			if st.has("cue"):
				live.cue(str(st.cue), 30.0)
			for k in 12:                                   # let the pulses and arcs settle to a representative frame
				rest.update(0.05)
				live.update(0.05)
				await process_frame
			_aim(float(FAR.dist), float(FAR.pitch), Vector3(0, 1.0, 0))
			await _save(abs.path_join("%s_%s_far.png" % [id, st.name]))
			_aim(float(NEAR.dist), float(NEAR.pitch), live.position + Vector3(0, 1.6, 0))
			await _save(abs.path_join("%s_%s_near.png" % [id, st.name]))
			rest.queue_free()
			live.queue_free()
			await process_frame
	print("monster_state_preview: done -> ", abs)
	quit(0)


func _save(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("monster_state_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
