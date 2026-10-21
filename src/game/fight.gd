class_name HHFight
extends Node3D
## The fight scene: owns an HHSim, steps it at 30 Hz, draws it (HHArenaView,
## bodies, HUD), and turns input into orders.
##   right-click    on the monster: target it and auto-attack from its Attack Ring / reach (H32, H252); on the
##                  ground: run to that exact point (free movement, H31)
##   left-drag      orbit the camera; a left click (sandbox) paints (H20)
##   Q              hold to charge, release to fire at the cursor (H56; a tap is level 1)
##   E / R          cast at the hex under the cursor; W swaps elements
##   1-7            (sandbox) pick the element to paint
##   Shift          dash toward the cursor (H56: 2 charges; the escape from a commit, H57);  Space  stop
##   T              throw a potion at the cursor: a heal zone (H40, H56)
##   F1             tune panel;  Esc / F10  abort back to the lobby (H48)
## `autoplay` runs a scripted walk, paint, attack and cast sequence for the
## smoke run and the capture tool, then quits (in a party: a small bot that
## fights and revives, each process driving its own hunter).
## `setup_cfg(cfg)` builds the fight from the launch config (guide/02, H48)
## and `finished` fires once with { result: "win"|"fallen"|"abort", cfg,
## ticks, hp, monster_hp, max_hp, monster_max_hp, local_id, net, hunters }
## when the sim ends (after `fight_end_hold_s`, so the VICTORY / FALLEN text
## shows) or on Esc / F10.
##
## Co-op (H52, H53; Lane C H900+): `cfg.players` puts every hunter in the sim
## (solo: one, "p1"), `cfg.local_id` is the one this machine's input drives
## and the camera follows. `cfg.net` picks one of three modes; the branching
## lives in `setup` (mirror or not, replicator or not), `_process` (step or
## apply) and `_flush_orders` (into the next step, or out to the host):
##   solo    steps its own sim; nothing on the network (exactly as before)
##   host    steps the only sim, merges each remote peer's orders under that
##           peer's hunter, publishes every tick through the replicator
##   client  never steps: a mirror sim (same arena and seed, no brains) that
##           the replicator overwrites; its `snapshot_applied(events)` feeds
##           the view, sfx and HUD exactly as the host's step does
## The replicator is Lane N's HHReplicator when src/net/replicator.gd exists,
## else HHCoopStubReplicator (same surface).

signal finished(result: Dictionary)

const ELEMENT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]
const NO_HEX := Vector2i(-9999, -9999)
const REPLICATOR_PATH := "res://src/net/replicator.gd"
const PLATE_LIFT := 0.55          ## nameplates float this far over the rig's head (m)

var sim: HHSim
var arena: HHArena
var asset: GKAsset
var view: HHArenaView
var camera: HHCameraRig
var hud: HHHud
var sfx: HHSfx
var debug: Label
var player_id := "p1"            ## the local hunter (cfg.local_id)
var weapon := "lance"        # --weapon lance | daggers | bow (the local hunter's)
var element := "fire"        # the hunter's active element (the lobby's pick, L-15)
var backup := "water"        # ... and backup
var upgrades: Dictionary = {}    # slotted upgrade ids per skill (cfg.upgrades, Lane U's R-U1)
var cfg: Dictionary = {}     # the launch config this fight came from (setup_cfg)
var headless := false        # cfg.headless: no view, camera, bodies or HUD (tests)
var monster_id := ""
var bodies := {}             # unit id -> Node3D
var monster_bodies := {}     # unit id -> Lane E body (duck-typed)
var player_body: Node3D = null   # the LOCAL hunter's Lane B body (duck-typed: build(weapon), play(clip, loop), update(delta))
var player_bodies := {}      ## hunter id -> body (every hunter in the party)
var party: Array = []        ## HHParty entries { peer, id, name, weapon, element, backup, upgrades }
var net_mode := "solo"       ## "solo" | "host" | "client" (cfg.net)
var replicator: Node = null  ## Lane N's HHReplicator, or the stub; null in solo
var net: Object = null       ## the shell's HHNet when there is one (host-left detection)
var marks := {}              ## hunter id -> HHHunterMark (slot ring, revive ring)
var revive := {}             ## downed hunter id -> { frac, age } from revive events
var downs := {}              ## hunter id -> times downed this fight
var spectating := ""         ## the ally the camera follows while the local hunter is down
var steps_taken := 0         ## sim.step calls this fight made (a client stays at 0)
var autoplay := false
var sandbox := false
var autoplay_seconds := 14.0
var paint_element := "fire"
var _acc := 0.0
var _pending := {}
var _script: Array = []
var _elapsed := 0.0
var _log := PackedStringArray()
var dmg_by_cause := {}       ## damage dealt to the monster, by cause (the autoplay summary; tuning)
var _over_for := -1.0        # seconds since sim.over was set; -1 while the fight runs
var _finished := false
var _host_left := false
var _down_prev := {}         # hunter id -> downed last frame
var _peer_unit := {}         # peer -> hunter id (host: whose orders go where)
var _bot_t := 0.0
var _drawn := {}             # unit id -> the position drawn last frame (client interpolation, H918)
var _slides := {}            # unit id -> { from: Vector3, t } a push-out slide being eased (H253, view only)
const SLIDE_S := 0.16        ## a push-out (H253) is drawn as a slide this long, not a jump
var hitstop := {}            ## unit id -> seconds its animation stays frozen (H57, view only)
var _q_held := false         ## H56: the local Q key is down
var _q_aim := Vector2i(-9999, -9999)
var _q_aim_tick := 0
var _bot_charge_until := -1.0    ## the bot's held Q releases at this _elapsed (-1: not holding)
var _bot_rng := RandomNumberGenerator.new()
const INTERP_S := 0.065     ## a client's bodies close this much of the gap to the mirror per e-fold (s): ticks land in bursts
const INTERP_SNAP_M := 4.0   ## farther than this (a leap, a full snapshot after a gap): jump, don't slide


## Build the fight from a launch config (guide/02 "Launch config"). Keys
## beyond the contract that the flags pass through: sandbox, autoplay,
## autoplay_seconds, headless.
func setup_cfg(p_cfg: Dictionary) -> void:
	cfg = p_cfg.duplicate(true)
	var seed := int(cfg.get("seed", 1))
	party = HHParty.players_of(cfg)
	player_id = HHParty.local_id(cfg)
	net_mode = HHParty.mode(cfg)
	_peer_unit = HHParty.unit_of_peer(cfg)
	var me := HHParty.entry(cfg, player_id)
	weapon = str(me.weapon)
	element = str(me.element)
	backup = str(me.backup)
	upgrades = (me.upgrades as Dictionary).duplicate(true)
	sandbox = bool(cfg.get("sandbox", false))
	autoplay = bool(cfg.get("autoplay", false))
	autoplay_seconds = float(cfg.get("autoplay_seconds", autoplay_seconds))
	headless = bool(cfg.get("headless", false))
	var loaded := HHRegistry.load_arena(str(cfg.get("arena", "round")), seed)
	setup(loaded.arena, seed, str(cfg.get("monster", "")), loaded.asset)
	var cp := str(cfg.get("cam", "")).split(",")
	if camera != null and cp.size() == 2:
		camera.dist = float(cp[0])
		camera.pitch = deg_to_rad(float(cp[1]))


## Feel numbers the fight scene owns, registered under "fight_" so the F1
## panel edits them live (HHTune.value("fight_end_hold_s")).
const TUNE := {
	"end_hold_s": 2.0,       # seconds the VICTORY / FALLEN text holds before `finished` fires
	"revive_fade_s": 0.35,   # a revive ring with no progress event for this long empties (the reviver stepped off)
	"bot_think_s": 0.5,      # co-op autoplay: how often the bot re-picks fight or revive
	"charge_aim_every": 3,   # H56: while Q is held, the aim travels to the sim at most every this many ticks (when it changed)
	"hitstop_s": 0.075,      # H57: heavy hits freeze the attacker's and the target's animation this long (view only)
	"hitstop_kick": 0.22,    # ... and kick the camera this much
	"hitstop_heavy_pct": 10.0,  # a monster hit on a hunter of at least this pct of max HP counts as heavy
}


func setup(p_arena: HHArena, seed: int, monster: String = "", p_asset: GKAsset = null) -> void:
	HHTune.register("fight", TUNE)
	arena = p_arena
	asset = p_asset
	sim = HHSim.new(arena, seed, str(cfg.get("difficulty", "easy")))   # H240: the tier is fixed for the fight
	sim.sandbox = sandbox or autoplay
	if party.is_empty():                   # the old setup(arena, seed, ...) path: one hunter from the vars
		party = HHParty.players_of({ "weapon": weapon, "element": element, "backup": backup, "upgrades": upgrades })
		player_id = str(party[0].id)
	var start: Vector2i = arena.spawns.player[0]
	for p in party:
		var u := sim.add_player(str(p.id), start, str(p.element), str(p.backup), str(p.weapon), p.upgrades)
		_fan_out(u)
	if monster != "":
		monster_id = monster
		_add_monster(monster)
	if net_mode != "solo":
		_build_replicator()
	if headless:
		return
	view = HHArenaView.new()
	view.name = "ArenaView"
	add_child(view)
	view.build(arena, asset)
	camera = HHCameraRig.new()
	camera.name = "CameraRig"
	camera.follow_tuned = true      # H280: camera lag from HHTune
	add_child(camera)
	camera.clicked.connect(_on_click)
	camera.follow(sim.unit(player_id).pos, true)
	_build_bodies()
	_build_hud()
	sfx = HHSfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	if autoplay:
		_script = _autoplay_script()


## Stand-in for Lane S's spawn fan-out (H53): a hunter added on a hex another
## hunter already holds moves to the nearest free walkable hex around it.
## Once the sim fans out itself, nothing here fires.
func _fan_out(u: Dictionary) -> void:
	var taken := {}
	for p in sim.players():
		if p.id != u.id:
			taken[p.hex] = true
	if not taken.has(u.hex):
		return
	var seen := { u.hex: true }
	var frontier: Array = [u.hex]
	while not frontier.is_empty():
		var h: Vector2i = frontier.pop_front()
		for n in arena.walk_neighbors(h):
			if seen.has(n):
				continue
			seen[n] = true
			if not taken.has(n):
				u.hex = n
				u.prev = n
				u.crossed = n
				u.pos = arena.stand(n)
				return
			frontier.append(n)


## A monster by id: Lane E's brain and body when their scripts exist, else
## the stub (a footprint, HP, no brain). A client's mirror never gets a brain
## (H52: the host runs the only one).
func _add_monster(id: String) -> void:
	var brain_path := "res://src/monster/%s.gd" % id
	var allowed: Array = []
	var brain: Variant = null
	if ResourceLoader.exists(brain_path):
		var s: GDScript = load(brain_path)
		if s != null:
			brain = s.new()
			if brain.has_method("allowed_kinds"):
				allowed = brain.allowed_kinds()
	var hp := HHTune.value("monster_hp")
	var u := sim.add_monster(id, arena.spawns.monster, hp, 2, allowed)
	if brain != null and net_mode != "client":
		sim.brains[id] = brain
		if brain.has_method("setup"):
			brain.setup(sim, u)
		_log.append("brain: %s" % id)


## Host / client: Lane N's HHReplicator (R-N1) when the fight runs under a
## shell with an HHNet, else the stub (tests, captures).
func _build_replicator() -> void:
	net = _find_net()
	var r: Node = null
	if net is HHNet:
		r = HHReplicator.attach(self, sim, cfg)        # client: clears the mirror's brains / hooks
	if r == null:
		r = HHCoopStubReplicator.new()
		r.name = "Replicator"
		add_child(r)
		r.bind(sim, cfg, net)
	replicator = r
	if net_mode == "client":
		r.connect("snapshot_applied", _on_snapshot)
		if r.has_signal("lost"):
			r.connect("lost", _on_host_left)
	_log.append("net: %s as %s" % [net_mode, player_id])


## The shell's HHNet (Shell/Net, guide/02), when the fight runs under a shell that has one.
func _find_net() -> Object:
	if is_inside_tree():
		var hn := HHNet.find(self)
		if hn != null:
			return hn
	var p := get_parent()
	while p != null:
		var n: Variant = p.get("net")
		if n is Object and n != null:
			return n
		p = p.get_parent()
	return null


func _on_host_left() -> void:
	if _finished:
		return
	_host_left = true
	_log.append("the host left")
	_finish("abort")


func _build_bodies() -> void:
	for id in sim.order:
		var u: Dictionary = sim.units[id]
		var node: Node3D = null
		if u.kind == "monster" and ResourceLoader.exists("res://src/monster/monster_body.gd"):
			var s: GDScript = load("res://src/monster/monster_body.gd")
			var body: Node3D = s.new()
			for m in ["build", "load_monster", "setup", "load_id"]:
				if body.has_method(m):
					body.call(m, id)
					break
			monster_bodies[id] = body
			if body.has_method("bind"):
				body.bind(sim, id)              # H611: the body reads its unit each frame (state visuals)
			node = body
		if node == null:
			node = _placeholder(u)
		node.name = id
		add_child(node)
		bodies[id] = node
		if u.kind == "player" and party.size() > 1:   # H902: the slot ring under every hunter in a party
			var mk := HHHunterMark.new()
			mk.name = "Mark_%s" % id
			add_child(mk)
			mk.setup(HHParty.slot_color(str(id)))
			marks[id] = mk


func _placeholder(u: Dictionary) -> Node3D:
	if u.kind == "player" and ResourceLoader.exists("res://src/game/anim/player_body.gd"):
		var s: GDScript = load("res://src/game/anim/player_body.gd")      # Lane B: the rigged player
		var body: Node3D = s.new()
		if body.has_method("build"):
			body.build(str(u.weapon))
		if body.has_method("bind"):
			body.bind(sim, u.id)
		player_bodies[str(u.id)] = body
		if str(u.id) == player_id:
			player_body = body
		return body
	var mi := MeshInstance3D.new()
	if u.kind == "player":
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = HHLook.RIG_HEIGHT
		mi.mesh = cm
		mi.position.y = HHLook.RIG_HEIGHT * 0.5
		mi.material_override = HHLook.flat(Color(0.92, 0.92, 0.9))
		# a nose so facing reads
		var nose := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.2, 0.5)
		nose.mesh = bm
		nose.position = Vector3(0, 0.6, 0.5)
		nose.material_override = HHLook.flat(Color(0.9, 0.5, 0.2))
		mi.add_child(nose)
	else:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		mi.scale = Vector3(2.6, 1.6, 3.4)
		mi.position.y = 1.6
		mi.material_override = HHLook.flat(Color(0.3, 0.35, 0.6))
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var root := Node3D.new()
	root.add_child(mi)
	return root


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HHHud.new()
	hud.sim = sim
	hud.player_id = player_id
	hud.monster_id = monster_id
	hud.monster_body = monster_bodies.get(monster_id)
	if party.size() > 1:
		hud.party = party.map(func(p): return { "id": str(p.id), "name": str(p.name) })
	layer.add_child(hud)
	debug = Label.new()
	debug.position = Vector2(16, 60)
	debug.add_theme_font_size_override("font_size", 14)
	debug.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	debug.add_theme_constant_override("outline_size", 4)
	debug.visible = autoplay or sandbox                 # R-UI2: the debug read-out is F3 in a normal fight
	layer.add_child(debug)
	add_child(HHTunePanel.new())


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	_elapsed += delta
	if autoplay:
		_drive_autoplay(delta)
	_acc += delta
	var steps := 0
	while _acc >= HHSim.TICK and steps < 6:
		_acc -= HHSim.TICK
		steps += 1
		_charge_aim_tick()
		if net_mode == "client":                       # H52: a client never steps; snapshots move its mirror
			_flush_orders()
			continue
		var ev := sim.step(_flush_orders())
		steps_taken += 1
		for e in ev:
			_consume(e)
		if net_mode == "host" and replicator != null:
			replicator.publish(sim.tick, ev)
	_track_downed(delta)
	_draw(delta)
	_watch_over(delta)
	if autoplay and _elapsed >= autoplay_seconds:
		_finish_autoplay()


## This tick's orders for step(): the local input plus (host) every remote
## peer's queued order, each only ever under that peer's own hunter
## (HHReplicator.merge, R-N1). A client never gets here: its orders went
## out in `_order`.
func _flush_orders() -> Dictionary:
	var orders := _pending
	_pending = {}
	if net_mode == "client":
		return {}
	if net_mode == "host" and replicator != null:
		orders = replicator.merge(orders)
	return orders


## Client: a snapshot landed on the mirror; its events go where the host's go.
func _on_snapshot(events: Array) -> void:
	for e in events:
		if e is Dictionary:
			_consume(e)


## One sim event, the same on host, client and solo: the log and bodies,
## the effects layer (R-FX1), the sound.
func _consume(e: Dictionary) -> void:
	_note(e)
	if view != null:
		view.on_event(e, sim)
	if sfx != null:
		sfx.on_event(e, sim)


## Once the sim is over, hold `fight_end_hold_s` (the VICTORY / FALLEN text
## shows), then emit `finished` once. Autoplay runs keep quitting on their own.
func _watch_over(delta: float) -> void:
	if not _finished and net_mode == "client" and sim.over == "abort":    # H55: the host left the fight
		_finish("host_left")
		return
	if _finished or sim.over == "" or autoplay:
		return
	_over_for = maxf(_over_for, 0.0) + delta
	if _over_for >= HHTune.value("fight_end_hold_s"):
		_finish("win" if sim.over == "win" else "fallen")


func _finish(result: String) -> void:
	if _finished:
		return
	_finished = true
	if net_mode == "host" and replicator != null and sim.over == "":            # H55: tell the party before leaving
		sim.over = "abort"
		if replicator.has_method("publish_final"):
			replicator.publish_final([{ "type": "over", "result": "abort", "tick": sim.tick + 1 }])
	finished.emit(payload(result))


## The finished payload: the local hunter's numbers at the top level (the
## results screen and run history read those), every hunter under `hunters`.
func payload(result: String) -> Dictionary:
	var p := sim.unit(player_id)
	var m := sim.unit(monster_id) if monster_id != "" else {}
	var out := { "result": result, "cfg": cfg, "ticks": sim.tick,
		"hp": float(p.get("hp", 0.0)), "monster_hp": float(m.get("hp", 0.0)),
		"max_hp": float(p.get("max_hp", HHTune.value("player_hp"))),
		"monster_max_hp": float(m.get("max_hp", HHTune.value("monster_hp"))),
		"local_id": player_id, "net": net_mode, "hunters": hunters() }
	if _host_left:
		out["host_left"] = true
	return out


## Per hunter: { id, peer, name, weapon, hp, max_hp, downed, downs }.
func hunters() -> Array:
	var out: Array = []
	for pe in party:
		var u := sim.unit(str(pe.id))
		out.append({ "id": str(pe.id), "peer": int(pe.peer), "name": str(pe.name), "weapon": str(pe.weapon),
			"hp": float(u.get("hp", 0.0)), "max_hp": float(u.get("max_hp", 0.0)),
			"downed": bool(u.get("downed", false)), "downs": int(downs.get(str(pe.id), 0)) })
	return out


static func is_downed(u: Dictionary) -> bool:
	return bool(u.get("downed", false))


## Downed transitions (H53 unit field `downed`, Lane S) counted and logged;
## revive rings fade when their events stop. Runs on host and client alike
## (a client reads the replicated field).
func _track_downed(delta: float) -> void:
	for pe in party:
		var id := str(pe.id)
		var d := is_downed(sim.unit(id))
		if d and not bool(_down_prev.get(id, false)):
			downs[id] = int(downs.get(id, 0)) + 1
			_log.append("t%d %s is DOWN" % [sim.tick, id])
		elif not d and bool(_down_prev.get(id, false)):
			_log.append("t%d %s is back up" % [sim.tick, id])
			revive.erase(id)
		_down_prev[id] = d
	for id in revive.keys():
		var r: Dictionary = revive[id]
		r.age = float(r.age) + delta
		if float(r.age) > HHTune.value("fight_revive_fade_s"):
			r.frac = maxf(0.0, float(r.frac) - delta * 2.0)


## Revive progress 0..1 for a downed hunter (0 when nobody is reviving).
func revive_frac(id: String) -> float:
	var u: Dictionary = sim.unit(id) if sim != null else {}
	if bool(u.get("downed", false)) and float(u.get("revive", 0.0)) > 0.0:   # H53: the unit carries it (and replicates); smooth every tick
		return clampf(float(u.revive) / maxf(1.0, HHTune.value("revive_ticks")), 0.0, 1.0)
	return float((revive.get(id, {}) as Dictionary).get("frac", 0.0))


## Where a unit is drawn this frame: its sim position, except on a client,
## where the mirror moves only when ticks land (up to 3-4 in one frame) and
## the drawn position eases toward it over ~INTERP_S (Lane N's report, H918).
func draw_pos(id: String, target: Vector3, delta: float) -> Vector3:
	var cur: Vector3 = _drawn.get(id, target)
	if _slides.has(id):                                  # H253: the slide out of a hull, eased
		var sl: Dictionary = _slides[id]
		sl.t = float(sl.t) + delta
		var k := clampf(float(sl.t) / SLIDE_S, 0.0, 1.0)
		if k >= 1.0:
			_slides.erase(id)
		cur = (sl.from as Vector3).lerp(target, 1.0 - (1.0 - k) * (1.0 - k))
		_drawn[id] = cur
		return cur
	if net_mode != "client" or cur.distance_to(target) > INTERP_SNAP_M:
		cur = target
	else:
		cur = cur.lerp(target, 1.0 - exp(-delta / INTERP_S))
	_drawn[id] = cur
	return cur


## Hunters whose peer has left the party mid-fight (their hunter stands idle
## on the host): the ids, for "DISCONNECTED" on the nameplate and party frame.
## Read from the session's members (the host drops a leaver and rebroadcasts).
func gone_ids() -> Dictionary:
	var out := {}
	if net == null or net_mode == "solo" or not net.has_method("is_online") or not net.is_online():
		return out
	var s: Variant = net.get("session")
	if not s is Object or s == null:
		return out
	var ms: Variant = s.get("members")
	if not ms is Dictionary or (ms as Dictionary).is_empty():
		return out
	for pe in party:
		if not (ms as Dictionary).has(int(pe.peer)):
			out[str(pe.id)] = true
	return out


## The unit the camera follows: the local hunter, or while it is down the
## nearest standing ally (spectate-follow).
func follow_id() -> String:
	var me := sim.unit(player_id)
	if me.is_empty() or not (is_downed(me) or (not sim.alive(me) and party.size() > 1)):
		return player_id
	var best := ""
	var bd := INF
	for pe in party:
		var u := sim.unit(str(pe.id))
		if u.is_empty() or str(pe.id) == player_id or is_downed(u) or not sim.alive(u):
			continue
		var d := (u.pos as Vector3).distance_squared_to(me.pos)
		if d < bd:
			bd = d
			best = str(pe.id)
	return best if best != "" else player_id


## H56: while Q is held, the local cursor's hex goes to the sim (at most
## every fight_charge_aim_every ticks, only when it changed) and to the aim
## preview every frame.
func _charge_aim_tick() -> void:
	if not _q_held or camera == null:
		return
	_q_aim_tick += 1
	var aim := _hex_under(get_viewport().get_mouse_position())
	if aim == NO_HEX or aim == _q_aim or _q_aim_tick < int(HHTune.value("fight_charge_aim_every")):
		return
	_q_aim_tick = 0
	_q_aim = aim
	_order({ "charge_aim": aim })


## H57: the animation time a body gets this frame (0 while its hit-stop holds).
func _body_delta(id: String, delta: float) -> float:
	var h := float(hitstop.get(id, 0.0))
	if h <= 0.0:
		return delta
	return 0.0


func _hitstop(ids: Array, kick: bool = true) -> void:
	var s := HHTune.value("fight_hitstop_s")
	for id in ids:
		if str(id) != "":
			hitstop[str(id)] = maxf(float(hitstop.get(str(id), 0.0)), s)
	if kick and camera != null:
		camera.shake(HHTune.value("fight_hitstop_kick"))


func _draw(delta: float) -> void:
	if headless:
		return
	for id in hitstop.keys():
		hitstop[id] = float(hitstop[id]) - delta
		if float(hitstop[id]) <= -0.5:
			hitstop.erase(id)
	if view != null and view.aim != null:
		view.aim.aim_hex = _hex_under(get_viewport().get_mouse_position()) if _q_held else NO_HEX
	if view != null and view.hull != null and camera != null and is_inside_tree():
		view.hull.hover_id = _monster_hit(get_viewport().get_mouse_position())   # H255: the Attack Ring on attack hover
	for id in bodies:
		var u: Dictionary = sim.units[id]
		var node: Node3D = bodies[id]
		node.position = draw_pos(str(id), u.pos, delta)
		node.rotation.y = float(u.facing)
		node.visible = sim.alive(u) or u.kind == "monster" or is_downed(u)
		if monster_bodies.has(id) and (monster_bodies[id] as Node).has_method("update"):
			monster_bodies[id].update(_body_delta(str(id), delta))
	for id in player_bodies:
		var body: Node3D = player_bodies[id]
		var u := sim.unit(str(id))
		if body.has_method("set_downed"):
			body.set_downed(is_downed(u))
		if body.has_method("update"):
			body.update(_body_delta(str(id), delta))
	for id in marks:
		var u := sim.unit(str(id))
		var mk: HHHunterMark = marks[id]
		mk.position = _drawn.get(str(id), u.pos)
		mk.visible = sim.alive(u) or is_downed(u)
		mk.set_downed(is_downed(u))
		mk.set_revive(revive_frac(str(id)))
	spectating = follow_id()
	if spectating == player_id:
		spectating = ""
	var p := sim.unit(player_id)
	camera.follow(_drawn.get(spectating if spectating != "" else player_id, p.pos))
	view.sync(sim, player_id, delta)
	_sync_hud_party()
	var lines := PackedStringArray()
	lines.append("tick %d  seed %d  hex %s%s%s" % [sim.tick, sim.seed, p.hex, "   [sandbox paint: %s]" % paint_element if sandbox else "",
		"   [%s as %s]" % [net_mode, player_id] if net_mode != "solo" else ""])
	if p.target != "":
		lines.append("target %s%s" % [p.target, "  attacking" if bool(p.attacking) else ""])
	for i in range(maxi(0, _log.size() - 7), _log.size()):
		lines.append(_log[i])
	debug.text = "\n".join(lines)


## The HUD's party data for this frame: nameplates where each hunter's head
## projects, revive fractions, who the camera spectates.
func _sync_hud_party() -> void:
	if hud == null or party.size() <= 1:
		return
	var plates: Array = []
	var rev := {}
	for pe in party:
		var id := str(pe.id)
		var u := sim.unit(id)
		if u.is_empty():
			continue
		rev[id] = revive_frac(id)
		if not (sim.alive(u) or is_downed(u)) or camera.cam == null:
			continue
		var head: Vector3 = (_drawn.get(id, u.pos) as Vector3) + Vector3(0, HHLook.RIG_HEIGHT * (0.62 if is_downed(u) else 1.0) + PLATE_LIFT, 0)
		if camera.cam.is_position_behind(head):
			continue
		plates.append({ "id": id, "pos": camera.cam.unproject_position(head) })
	hud.plates = plates
	hud.revive = rev
	hud.gone = gone_ids()
	hud.spectating = spectating


func _note(e: Dictionary) -> void:
	var eid := str(e.get("id", ""))
	if player_bodies.has(eid) and (player_bodies[eid] as Node).has_method("on_event"):
		player_bodies[eid].on_event(e, sim)
	match str(e.type):
		"push_out":
			_log.append("t%d %s slid out of %s's hull %s -> %s" % [e.tick, eid, str(e.get("by", "")), e.get("from"), e.get("to")])
			_slides[eid] = { "from": _drawn.get(eid, e.get("from_pos", Vector3.ZERO)), "t": 0.0 }
		"detonate": _log.append("t%d detonate %s x%.1f" % [e.tick, e.hex, float(e.get("mult", e.pct))])
		"reaction":
			_log.append("t%d REACTION on %s: %d (%d blast%s)" % [e.tick, e.id, int(e.amount), int(e.blasts), "" if int(e.blasts) == 1 else "s"])
			_hitstop([str(e.id)])                       # H57: reactions are heavy
		"telegraph_end":
			var hit: Array = e.get("hit", [])
			var owner := sim.unit(str(e.get("owner", "")))
			if str(owner.get("kind", "")) == "monster" and hit.any(func(h): return HHParty.IDS.has(str(h))):
				for h in hit:
					var hu := sim.unit(str(h))
					if not hu.is_empty() and hu.kind == "player" and int(hu.get("flinch", 0)) + int(hu.stagger) > 0:
						_hitstop([str(h), str(owner.id)], str(h) == player_id)
						break
		"combo":
			if int(e.step) >= 2:
				_log.append("t%d %s combo %d" % [e.tick, e.id, int(e.step)])
		"charge_release":
			_log.append("t%d %s releases Q at level %d" % [e.tick, e.id, int(e.level)])
		"dash":
			_log.append("t%d %s dashes (%d left)" % [e.tick, e.id, int(e.get("left", 0))])
		"interrupted":
			_log.append("t%d %s INTERRUPTED (%s)" % [e.tick, e.id, str(e.what)])
			if hud != null and str(e.id) == player_id:
				hud.interrupted(str(e.get("skill", "")))
		"exposed":
			_log.append("t%d %s EXPOSED %d ticks" % [e.tick, e.id, int(e.ticks)])
		"overheat": _log.append("t%d OVERHEAT %s" % [e.tick, e.hex])
		"overfreeze": _log.append("t%d OVERFREEZE %s" % [e.tick, e.hex])
		"douse": _log.append("t%d douse %s" % [e.tick, e.hex])
		"gale": _log.append("t%d gale %s" % [e.tick, e.hex])
		"strike":
			_log.append("t%d %s hits %s %d%s%s" % [e.tick, e.id, e.target, int(e.amount), " REAR" if bool(e.rear) else "",
				(" combo %d" % int(e.combo)) if int(e.get("combo", 0)) >= 2 else ""])
			if bool(e.get("heavy", false)):
				_hitstop([str(e.id), str(e.target)])     # H57: finishers and level-3 releases
			elif HHParty.IDS.find(str(e.id)) < 0 and str(e.target) != "" and sim.units.has(str(e.target)) \
					and float(e.amount) >= float(sim.unit(str(e.target)).max_hp) * HHTune.value("fight_hitstop_heavy_pct") / 100.0:
				_hitstop([str(e.id), str(e.target)])     # a big monster blow
			if camera != null and (str(e.id) == player_id or str(e.target) == player_id or HHParty.IDS.find(str(e.id)) < 0):
				camera.shake(0.08 + 0.12 * clampf(float(e.amount) / 200.0, 0.0, 1.0))   # impact (H34)
			_body_react(str(e.target), "hit_react")
		"hurt":
			if e.id == monster_id:
				dmg_by_cause[str(e.cause)] = float(dmg_by_cause.get(str(e.cause), 0.0)) + float(e.amount)
			if e.id == player_id:
				_log.append("t%d you -%d (%s)" % [e.tick, int(e.amount), e.cause])
				if camera != null and not str(e.cause) in ["fire", "burn", "poison", "dark", "fire_cross"]:
					camera.shake(0.25)
		"stagger":
			if e.id == player_id:
				_log.append("t%d staggered %d" % [e.tick, e.ticks])
			else:
				_body_react(str(e.id), "stagger")
		"death":
			if not player_bodies.has(eid):
				_body_react(eid, "death", true)
		"cast": _log.append("t%d %s (%s)" % [e.tick, e.name, e.element])
		"cast_refused": _log.append("t%d %s: %s" % [e.tick, str(e.skill).to_upper(), str(e.get("why", "cooldown"))])
		"potion": _log.append("t%d potion (%d left)" % [e.tick, int(e.left)])
		"guard_block": _log.append("t%d GUARD blocked, counter!" % e.tick)
		"telegraph": _log.append("t%d %s telegraphs %s (%d hexes)" % [e.tick, str(e.get("owner", e.get("id", ""))), str(e.get("name", (e.get("payload", {}) as Dictionary).get("clip", ""))), (e.hexes as Array).size()])
		"monster_state": _log.append("t%d %s is %s" % [e.tick, e.id, e.state])
		"monster_anim":
			if monster_bodies.has(e.id) and (monster_bodies[e.id] as Node).has_method("play"):
				var clips: Dictionary = monster_bodies[e.id].clips(str(e.id)) if (monster_bodies[e.id] as Node).has_method("clips") else {}
				monster_bodies[e.id].play(str(e.clip), bool((clips.get(str(e.clip), {}) as Dictionary).get("loop", false)), float(e.get("speed", 1.0)))
		"revive", "revive_progress":                   # Lane S (H53): an ally is reviving `id`
			revive[eid] = { "frac": revive_event_frac(e), "age": 0.0 }
		"revived":
			revive.erase(eid)
			_log.append("t%d %s revived%s" % [e.tick, eid, (" by %s" % str(e.by)) if e.has("by") else ""])
		"over": _log.append("t%d OVER: %s" % [e.tick, e.result])


## A revive event's progress 0..1: `frac`, else `ticks` / `total` (or HHTune
## revive_ticks), else `left` counting down.
static func revive_event_frac(e: Dictionary) -> float:
	if e.has("frac"):
		return clampf(float(e.frac), 0.0, 1.0)
	var total := float(e.get("total", HHTune.value("revive_ticks") if HHTune.has("revive_ticks") else 90.0))
	total = maxf(1.0, total)
	if e.has("ticks"):
		return clampf(float(e.ticks) / total, 0.0, 1.0)
	if e.has("left"):
		return clampf(1.0 - float(e.left) / total, 0.0, 1.0)
	return 0.0


## L-9: a reaction clip on a monster body, only when it is not mid-attack
## (a telegraphed wind-up must stay readable). `force` for death.
func _body_react(id: String, clip: String, force: bool = false) -> void:
	if not monster_bodies.has(id):
		return
	var body: Node = monster_bodies[id]
	if not body.has_method("play"):
		return
	var cur := str(body.get("clip"))
	var looping := bool(body.get("loop"))
	if force or looping or cur == "":
		body.play(clip, false)


# ------------------------------------------------------------------ input

func _on_click(button: int, screen_pos: Vector2) -> void:
	match button:
		MOUSE_BUTTON_RIGHT:
			var m := _monster_hit(screen_pos)
			if m != "":
				_order({ "target": m, "attack": true })
				return
			var p := _ground_under(screen_pos)
			var hex := arena.from_world(p) if p != HHSim.NO_POS else NO_HEX
			if hex != NO_HEX and arena.exists(hex):
				_order({ "move": hex, "move_pos": p })
		MOUSE_BUTTON_LEFT:
			if sandbox:
				var hex := _hex_under(screen_pos)
				if hex != NO_HEX:
					_order({ "paint": { "element": paint_element, "hex": hex, "steps": 1 } })


## The monster under the cursor: a ray against each living monster's body
## (a sphere over its footprint), then the hex fallback.
func _monster_hit(screen_pos: Vector2) -> String:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	for m in sim.monsters():
		if not sim.targetable(m):
			continue
		var radius := (float(m.size) + 0.5) * HHArena.HEX * 1.8
		var centre: Vector3 = (m.pos as Vector3) + Vector3(0, radius * 0.5, 0)
		var oc := o - centre
		var b := oc.dot(d)
		var cc := oc.dot(oc) - radius * radius
		if b * b - cc >= 0.0 and -b > 0.0:
			return m.id
	var hex := _hex_under(screen_pos)
	return _monster_at(hex) if hex != NO_HEX else ""


## The exact ground point under the cursor (NO_POS when off the arena).
func _ground_under(screen_pos: Vector2) -> Vector3:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-4:
		return HHSim.NO_POS
	var p := o + d * (-o.y / d.y)
	for i in 6:
		var h := arena.height_at(p.x, p.z)
		var t := (h - o.y) / d.y
		if t <= 0.0:
			break
		p = o + d * t
	return p if arena.exists(arena.from_world(p)) else HHSim.NO_POS


func _monster_at(hex: Vector2i) -> String:
	for u in sim.unit_at(hex):
		if u.kind == "monster" and sim.targetable(u):
			return u.id
	# a near miss on a big body still counts
	for m in sim.monsters():
		if sim.targetable(m) and HHHex.distance(m.hex, hex) <= int(m.size) + 1:
			return m.id
	return ""


## Input only ever drives the local hunter (cfg.local_id). A client sends
## it to the host at once (R-N1).
func _order(o: Dictionary) -> void:
	if net_mode == "client":
		if replicator != null:
			replicator.send_order(o)
		return
	var cur: Dictionary = _pending.get(player_id, {})
	cur.merge(o, true)
	_pending[player_id] = cur


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var i := ELEMENT_KEYS.find(ev.keycode)
		if i >= 0 and sandbox:
			paint_element = HHFormulas.ELEMENTS[i]
		match ev.keycode:
			KEY_SPACE: _order({ "stop": true })
			KEY_T: _order({ "potion": { "aim": _cursor_hex() } })     # H56: thrown at the cursor
			KEY_F3:
				if debug != null:
					debug.visible = not debug.visible
			KEY_W: _order({ "swap": true })
			KEY_Q:                                     # H56: hold to charge
				_q_held = true
				_q_aim = _cursor_hex()
				_q_aim_tick = 0
				_order({ "charge": { "skill": "q", "aim": _q_aim } })
			KEY_E, KEY_R:
				_order({ "cast": { "skill": OS.get_keycode_string(ev.keycode).to_lower(), "aim": _cursor_hex() } })
			KEY_SHIFT:                                 # H56: a dash toward the cursor (H37's walk is gone)
				var g := _ground_under(get_viewport().get_mouse_position())
				_order({ "dash": g if g != HHSim.NO_POS else (sim.unit(player_id).pos as Vector3) })
			KEY_ESCAPE, KEY_F10:
				get_viewport().set_input_as_handled()
				_finish("abort")                     # the shell returns to the lobby (H48)
	if ev is InputEventKey and not ev.pressed and ev.keycode == KEY_Q and _q_held:
		_q_held = false
		_order({ "release": { "skill": "q", "aim": _cursor_hex() } })


## The hex under the mouse, or the local hunter's own hex off the arena.
func _cursor_hex() -> Vector2i:
	var aim := _hex_under(get_viewport().get_mouse_position()) if camera != null else NO_HEX
	return aim if aim != NO_HEX else sim.unit(player_id).hex


## The hex under a screen point: the camera ray marched onto the heightfield.
func _hex_under(screen_pos: Vector2) -> Vector2i:
	var r := camera.ray(screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-4:
		return NO_HEX
	var p := o + d * (-o.y / d.y)
	for i in 6:
		var h := arena.height_at(p.x, p.z)
		var t := (h - o.y) / d.y
		if t <= 0.0:
			break
		p = o + d * t
	var hex := arena.from_world(p)
	return hex if arena.exists(hex) else NO_HEX


# ------------------------------------------------------------------ autoplay

## True when autoplay runs the party bot rather than the solo script.
func _bot_mode() -> bool:
	return party.size() > 1 or net_mode != "solo"


## A scripted run: paint every reaction, then target the monster, auto-attack,
## Pierce, Guard, Eruption. The smoke run and the capture see all of it.
## In a party the bot (`_drive_bot`) plays instead; the script is empty.
func _autoplay_script() -> Array:
	if _bot_mode():
		return []
	var start: Vector2i = arena.spawns.player[0]
	var a := start + Vector2i(2, -2)
	var b := start + Vector2i(-3, 0)
	var c := start + Vector2i(0, -3)
	var m: Vector2i = arena.spawns.monster
	var s: Array = [
		{ "at": 0.2, "order": { "move": a, "move_pos": arena.stand(a) } },
		{ "at": 1.0, "order": { "paint": { "element": "fire", "hex": b, "steps": 3 } } },
		{ "at": 1.5, "order": { "paint": { "element": "fire", "hex": b, "steps": 1 } } },
		{ "at": 2.5, "order": { "paint": { "element": "water", "hex": b, "steps": 2 } } },
		{ "at": 3.5, "order": { "paint": { "element": "light", "hex": c, "steps": 2 } } },
		{ "at": 4.0, "order": { "paint": { "element": "thunder", "hex": c, "steps": 1 } } },
		{ "at": 5.0, "order": { "paint": { "element": "water", "hex": a, "steps": 2 } } },
		{ "at": 5.5, "order": { "paint": { "element": "ice", "hex": a, "steps": 1 } } },
		{ "at": 6.0, "order": { "paint": { "element": "ice", "hex": a, "steps": 1 } } },
		{ "at": 7.0, "order": { "paint": { "element": "dark", "hex": start, "steps": 3 } } },
		{ "at": 7.5, "order": { "paint": { "element": "wind", "hex": start, "steps": 1 } } },
		{ "at": 8.0, "order": { "swap": true } },
	]
	if monster_id != "":
		var pos_a := arena.stand(a)
		s.append_array([
			{ "at": 8.5, "order": { "target": monster_id, "attack": true, "run": true } },
			{ "at": 9.0, "order": { "dash": pos_a + Vector3(3.0, 0.0, -3.0) } },                     # H56: dash toward the monster side
			{ "at": 9.4, "order": { "potion": { "aim": start } } },                                  # H56: a thrown zone
			{ "at": 10.2, "order": { "charge": { "skill": "q", "aim": m }, "release": { "skill": "q", "aim": m } } },   # a tapped Q
			{ "at": 10.6, "order": { "target": monster_id, "attack": true } },
			{ "at": 11.4, "order": { "cast": { "skill": "e", "aim": m } } },
			{ "at": 12.0, "order": { "dash": pos_a } },                                              # an escape from whatever is committed
			{ "at": 12.4, "order": { "cast": { "skill": "r", "aim": m + Vector2i(3, 2) } } },
			{ "at": 14.0, "order": { "charge": { "skill": "q", "aim": m } } },                       # a full hold: releases itself at 3 s
			{ "at": 17.5, "order": { "target": monster_id, "attack": true } },
		])
	else:
		s.append({ "at": 8.5, "order": { "move": start + Vector2i(4, 2), "move_pos": arena.stand(start + Vector2i(4, 2)) } })
	return s


func _drive_autoplay(delta: float = 0.0) -> void:
	if _bot_mode():
		_drive_bot(delta)
		return
	while not _script.is_empty() and float(_script[0].at) <= _elapsed:
		_order((_script.pop_front() as Dictionary).order)


## The party bot (co-op autoplay, one per process, H907): run to a downed ally
## and stand beside it, else attack the monster and cast Q / E / R at it in
## turn when they are off cooldown. Only ever orders the local hunter.
func _drive_bot(delta: float) -> void:
	_bot_t -= delta
	if _bot_t > 0.0:
		return
	_bot_t = HHTune.value("fight_bot_think_s")
	var me := sim.unit(player_id)
	if me.is_empty() or is_downed(me) or not sim.alive(me):
		return
	for pe in party:
		var u := sim.unit(str(pe.id))
		if str(pe.id) != player_id and is_downed(u):
			if HHHex.distance(me.hex, u.hex) > 1:
				var to: Vector2i = u.hex
				for n in arena.walk_neighbors(u.hex):
					to = n
					break
				_order({ "move": to, "move_pos": arena.stand(to) })
			else:
				_order({ "stop": true })
			return
	if monster_id == "" or not sim.alive(sim.unit(monster_id)):
		return
	var m := sim.unit(monster_id)
	# H56: a held Q releases when its time is up (a tap or a full hold, picked at the press)
	if _bot_charge_until >= 0.0:
		if _elapsed >= _bot_charge_until or not sim.charging(me):
			if sim.charging(me):
				_order({ "release": { "skill": "q", "aim": m.hex } })
			_bot_charge_until = -1.0
		return
	# H56/H57: dash out of a monster telegraph about to land (also the escape from a commit)
	if int(me.get("dash_charges", 0)) > 0:
		for tg in sim.telegraphs:
			if str(tg.owner) == monster_id and me.hex in tg.hexes and int(tg.left) <= 20:
				var away: Vector3 = (me.pos as Vector3) - (m.pos as Vector3)
				away.y = 0.0
				_order({ "dash": (me.pos as Vector3) + away.normalized() * 4.0 })
				return
	if float(me.hp) < 0.45 * float(me.max_hp) and int(me.get("potions", 0)) > 0 and int(me.cooldowns.get("t", 0)) <= 0:
		_order({ "potion": { "aim": me.hex } })
		return
	if str(me.target) != monster_id:
		_order({ "target": monster_id, "attack": true, "run": true })
		return
	if int((me.cooldowns as Dictionary).get("q", 0)) <= 0 and not sim.held(me):
		_bot_rng.seed = hash(player_id) + sim.tick
		var holds := [0.0, 0.0, 1.8, 3.2]
		var hold: float = holds[_bot_rng.randi() % 4]     # sometimes a tap, sometimes a level 2, sometimes full
		_order({ "charge": { "skill": "q", "aim": m.hex } })
		_bot_charge_until = _elapsed + hold
		return
	for k in ["e", "r"]:
		if int((me.cooldowns as Dictionary).get(k, 0)) <= 0:
			_order({ "cast": { "skill": k, "aim": m.hex } })
			return


func _finish_autoplay() -> void:
	autoplay = false
	var p := sim.unit(player_id)
	print("HHFight autoplay done: tick %d, player hp %d at %s, hash %d, log %d lines" % [sim.tick, int(p.hp), p.hex, sim.state_hash(), _log.size()])
	if net_mode != "solo" or party.size() > 1:
		print("  party: %s as %s, %d hunter(s), %d steps taken here" % [net_mode, player_id, party.size(), steps_taken])
		for h in hunters():
			print("  %s %s (%s): hp %d / %d%s, downed %d time(s)" % [h.id, h.name, h.weapon, int(h.hp), int(h.max_hp), "  DOWN" if bool(h.downed) else "", int(h.downs)])
		var net := HHNet.find(self)
		if net != null and net.api.multiplayer_peer != null:          # Lane R: bandwidth in the smoke summary
			var secs := maxf(0.001, (Time.get_ticks_msec() - int(net.stats.since_ms)) / 1000.0)
			var rp := net.api.multiplayer_peer as HHRelayPeer
			print("  net: %s; sent %d B = %.1f KB/s, received %d B = %.1f KB/s over %.0f s%s" % ["relay room %s" % net.room if rp != null else "ENet",
				int(net.stats.sent_total), net.stats.sent_total / secs / 1024.0, int(net.stats.recv_total), net.stats.recv_total / secs / 1024.0, secs,
				"; relay frames out %d (%d B), in %d (%d B)" % [int(rp.stats.frames_out), int(rp.stats.bytes_out), int(rp.stats.frames_in), int(rp.stats.bytes_in)] if rp != null else ""])
	if monster_id != "":
		var m := sim.unit(monster_id)
		print("  %s hp %d / %d" % [monster_id, int(m.hp), int(m.max_hp)])
		var causes := dmg_by_cause.keys()
		causes.sort_custom(func(a, b): return float(dmg_by_cause[a]) > float(dmg_by_cause[b]))
		for c in causes:
			print("  dealt by %s: %d" % [c, int(dmg_by_cause[c])])
	for l in _log:
		print("  ", l)
	get_tree().quit(0)
