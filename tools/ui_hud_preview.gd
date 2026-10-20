extends SceneTree
## The HUD in states a short autoplay never reaches (Lane UI): every status
## icon, each monster state, low HP, no potions, each weapon, the end banner.
## The HUD paints over a real fight frame used as the backdrop. Needs a window:
##   godot --path . --script res://tools/ui_hud_preview.gd -- --bg <frame.png> --out <dir>
## Writes <dir>/hud_state_<n>.png, then quits.

const CASES := [
	{ "weapon": "lance", "element": "fire", "backup": "ice", "hp": 0.62, "monster": "colambros", "mstate": { "smoulder": true },
		"statuses": { "burn": 150, "poison": 420, "stagger": 20 }, "cd": { "q": 40, "r": 300 }, "guard": 30, "potions": 3, "mhp": 0.55 },
	{ "weapon": "daggers", "element": "thunder", "backup": "dark", "hp": 0.18, "monster": "spirewalker", "mstate": { "charge": 0.9 },
		"statuses": { "paralysis": 45, "slow": 200, "wet": 600, "freeze": 60 }, "cd": { "e": 100, "w": 20, "t": 500 }, "potions": 0, "mhp": 0.2 },
	{ "weapon": "bow", "element": "light", "backup": "wind", "hp": 1.0, "monster": "rimeslithe", "mstate": { "cold": 0.8 },
		"statuses": {}, "cd": {}, "potions": 5, "mhp": 0.0, "over": "win" },
]

var bg_path := ""
var out_dir := "design/visual_pass/UI"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--bg")
	if i >= 0 and i + 1 < args.size():
		bg_path = args[i + 1]
	i = args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	_run.call_deferred()


func _run() -> void:
	var abs := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	if bg_path != "":
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://" + bg_path) if not bg_path.is_absolute_path() else bg_path)
		if img != null and not img.is_empty():
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			layer.add_child(tr)
	for n in CASES.size():
		var c: Dictionary = CASES[n]
		var sim := HHSim.new(HHArena.round_flat(1, 25.0, 0.6), 1)
		var p := sim.add_player("p1", Vector2i(0, 0), str(c.element), str(c.backup), str(c.weapon))
		p.hp = float(p.max_hp) * float(c.hp)
		p.potions = int(c.potions)
		p.guard = int(c.get("guard", 0))
		for k in (c.cd as Dictionary):
			p.cooldowns[k] = int(c.cd[k])
		for s in (c.statuses as Dictionary):
			p.statuses[s] = { "ticks": int(c.statuses[s]) }
		var m := sim.add_monster(str(c.monster), Vector2i(6, 0), 20000.0, 2, [])
		m.hp = float(m.max_hp) * float(c.mhp)
		for k in (c.mstate as Dictionary):
			m[k] = c.mstate[k]
		sim.over = str(c.get("over", ""))
		var hud := HHHud.new()
		hud.sim = sim
		hud.player_id = "p1"
		hud.monster_id = str(c.monster)
		layer.add_child(hud)
		hud._ghost = minf(1.0, float(c.mhp) + 0.12)
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_viewport().get_texture().get_image()
		var path := abs.path_join("hud_state_%d.png" % n)
		print("ui_hud_preview: %s (%s)" % [path, error_string(shot.save_png(path))])
		hud.queue_free()
		await process_frame
	quit(0)
