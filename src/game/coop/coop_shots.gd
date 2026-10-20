extends SceneTree
## Review frames of Lane C's co-op screens (H900+). Needs a window:
##   godot --path . --script res://src/game/coop/coop_shots.gd -- --out design/coop [--shots fight_2p,downed,downed_local,lobby]
## fight_2p      two hunters in the pond: slot rings, nameplates, party frames
## downed        p2 forced downed (H53's `downed` field) with a revive ring at 55%
## downed_local  this machine's hunter down: the banner and the spectate-follow
## lobby         the host's lobby with a four-hunter party (fake in-process session)
## lobby_client  the same party from a guest's lobby (host-only tiles greyed)
## The save, last pick and run history point at scratch files for the run.

const SCRATCH := ["user://coop_shots_hunter.json", "user://coop_shots_last.json", "user://coop_shots_runs.json"]
const PLAYERS := [
	{ "peer": 1, "id": "p1", "name": "Ana", "weapon": "lance", "element": "fire", "backup": "water" },
	{ "peer": 2, "id": "p2", "name": "Bo", "weapon": "bow", "element": "ice", "backup": "thunder" },
]

var out_dir := "design/coop"
var shots: PackedStringArray = ["fight_2p", "downed", "downed_local", "lobby", "lobby_client"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		shots = args[i + 1].split(",")
	HHSave.path = SCRATCH[0]
	HHLobbyState.last_path = SCRATCH[1]
	HHLobbyState.runs_path = SCRATCH[2]
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))
	_run.call_deferred()


func _run() -> void:
	for s in shots:
		match s:
			"fight_2p": await _fight_shot(s, "", false)
			"downed": await _fight_shot(s, "p2", false)
			"downed_local": await _fight_shot(s, "p1", true)
			"lobby": await _lobby_shot(s, false)
			"lobby_client": await _lobby_shot(s, true)
	for p in SCRATCH:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	quit(0)


func _fight_shot(name: String, down: String, local_down: bool) -> void:
	var f := HHFight.new()
	root.add_child(f)
	f.setup_cfg({ "arena": "pond", "monster": "swampfang", "seed": 1, "players": PLAYERS, "local_id": "p1", "cam": "17,40" })
	f.sim.brains.clear()                                  # a still frame: the monster waits
	var p1 := f.sim.unit("p1")
	var p2 := f.sim.unit("p2")
	var to: Vector2i = p1.hex + Vector2i(3, -1)
	f.sim.step({ "p2": { "move": to, "move_pos": f.arena.stand(to) } })
	for k in 40:
		f.sim.step({})
	p1.hp = 2240.0
	p2.hp = 1310.0
	if down != "":
		var u := f.sim.unit(down)
		u.hp = 0.0
		u.downed = true
	f.camera.yaw = deg_to_rad(205.0)
	for k in 70:
		if down != "":
			f.revive[down] = { "frac": 0.55, "age": 0.0 }
		await process_frame
	await _save(name)
	f.queue_free()
	await process_frame


func _lobby_shot(name: String, as_guest: bool) -> void:
	var hub := HHCoopFakeHub.new()
	var hp := hub.peer(true)
	var lobby := HHLobby.new()
	lobby.coop.attach(hp[0], hp[1])
	lobby.setup({ "monster": "colambros", "arena": "caldera", "weapon": "lance", "element": "fire", "backup": "wind", "seed": 12 })
	root.add_child(lobby)
	lobby._name_edit.text = "Ana"
	lobby.coop.host_game("Ana")
	var guests := [["Bo", "bow", "ice", "thunder", true], ["Cy", "daggers", "dark", "light", true], ["Di", "lance", "water", "wind", false]]
	for g in guests:
		var gp := hub.peer(false)
		(gp[0] as HHCoopFakeNet).join("127.0.0.1")
		(gp[1] as HHCoopFakeSession).set_mine({ "name": g[0], "weapon": g[1], "element": g[2], "backup": g[3], "ready": g[4],
			"upgrades": { "q": [], "w": [], "e": [], "r": [] } })
	var shown: HHLobby = lobby
	if as_guest:                                   # Bo's lobby: the host's picks greyed, his own kit live
		var gl := HHLobby.new()
		gl.coop.attach(hub.sessions[1].net, hub.sessions[1])
		gl.setup({ "weapon": "bow", "element": "ice", "backup": "thunder" })
		gl.coop.role = "client"
		gl.coop.address = "192.168.1.10:%d" % HHParty.PORT
		gl.coop.ready = true
		lobby.visible = false
		root.add_child(gl)
		shown = gl
	lobby._refresh()
	shown._refresh()
	for k in 8:
		await process_frame
	await _save(name)
	if shown != lobby:
		shown.queue_free()
	lobby.queue_free()
	await process_frame


func _save(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://%s/%s.png" % [out_dir, name])
	img.save_png(path)
	print("saved ", path)
