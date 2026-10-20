class_name HHShell
extends Node
## The screen owner (H48; Gamers Gauntlet's tourney.gd `_swap` pattern). One
## screen lives under the shell at a time: a plain Node with `setup(cfg)` and
## `signal finished(result)`. `show_screen` frees the old one and adds the
## next; no change_scene. The shell keeps `last_cfg`, so Replay and New seed
## are one call, and routes by default: a lobby's `finished` starts the
## fight it describes, a fight's `finished` returns to the lobby with the
## result in the ticker. A caller (the hunt loop, Lane H) passes its own
## `on_finished` to drive the flow itself.

## Co-op (Lane C, H900+): the shell owns Lane N's HHNet at `Shell/Net` and
## the party's HHSession at `Shell/Session` (guide/02), made on first use by
## `ensure_net()` when src/net exists; tests and captures assign fakes to
## `net` / `session` instead. They outlive screens, so a party survives the
## lobby -> fight -> lobby round trip. `coop_boot` (boot's --host / --join)
## is handed to the next lobby once.

signal screen_changed(screen: Node)

const NET_PATH := "res://src/net/net.gd"
const SESSION_PATH := "res://src/net/session.gd"

var screen: Node = null
var last_cfg: Dictionary = {}
var last_result: Dictionary = {}
var fights_run := 0
var net: Node = null
var session: Node = null
var coop_boot := {}                ## { mode: "host"|"join", address, name, autoplay, peers, seconds }


## The cfg a fresh lobby starts from (guide/02 "Launch config").
static func default_cfg() -> Dictionary:
	return {
		"arena": "pond", "monster": "swampfang", "weapon": "lance",
		"element": "fire", "backup": "water", "seed": 1,
		"upgrades": { "q": [], "w": [], "e": [], "r": [], "t": [] },   # t = the potion (Lane U)
		"locked": [], "cam": "30,44",
	}


## Free the current screen, add `s`, call `s.setup(cfg)`, connect its
## `finished`. With no `on_finished` the shell's own routing applies.
func show_screen(s: Node, cfg: Dictionary, on_finished: Callable = Callable()) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = s
	add_child(s)
	if s.has_method("setup_cfg"):          # HHFight keeps the old setup(arena, seed, ...) for tests
		s.setup_cfg(cfg)
	elif s.has_method("setup"):
		s.setup(cfg)
	if s.has_signal("finished"):
		var cb := on_finished if on_finished.is_valid() else _route.bind(s)
		s.connect("finished", cb, CONNECT_ONE_SHOT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screen_changed.emit(s)


func _route(result: Dictionary, from: Node) -> void:
	if from is HHFight:
		last_result = result
		fights_run += 1
		go_lobby(last_cfg, result)
	elif str(result.get("result", "")) == "fight":
		play(result.get("cfg", last_cfg))
	elif str(result.get("result", "")) == "hunt":
		hunt(result.get("cfg", last_cfg))
	elif str(result.get("result", "")) == "quit":
		get_tree().quit(0)


## The lobby, prefilled with `cfg`, the last result (if any) in its ticker.
func go_lobby(cfg: Dictionary = last_cfg, result: Dictionary = {}) -> void:
	var lobby := HHLobby.new()
	lobby.name = "Lobby"
	lobby.can_replay = fights_run > 0
	lobby.result_text = result_line(result)
	if not coop_boot.is_empty():
		lobby.coop_boot = coop_boot
		coop_boot = {}
	show_screen(lobby, cfg)


## Make Shell/Net and Shell/Session from Lane N's scripts when they exist.
## True when both are there (made now, earlier, or assigned by a test).
func ensure_net() -> bool:
	if net != null and session != null:
		return true
	if not (ResourceLoader.exists(NET_PATH) and ResourceLoader.exists(SESSION_PATH)):
		return false
	if net == null:
		net = (load(NET_PATH) as GDScript).new()
		net.name = "Net"
		add_child(net)
	if session == null:
		session = (load(SESSION_PATH) as GDScript).new()
		session.name = "Session"
		if session.get("net") == null and "net" in session:
			session.set("net", net)
		add_child(session)
	return true


## Build and show the fight `cfg` describes. The hunt loop passes its own
## `on_finished` and gets the fight back (H612).
func play(cfg: Dictionary, on_finished: Callable = Callable()) -> Node:
	last_cfg = cfg.duplicate(true)
	var fight := HHFight.new()
	fight.name = "Fight"
	show_screen(fight, last_cfg, on_finished)
	return fight


## The hunt loop (Lane H): map -> ambush -> prep (this lobby, arena and
## monster locked) -> fight -> results -> map. Quitting the map returns here.
func hunt(cfg: Dictionary = last_cfg) -> void:
	var h: Node = HHHunt.start(self, { "seed": int(cfg.get("seed", 1)), "weapon": str(cfg.get("weapon", "lance")),
		"element": str(cfg.get("element", "fire")), "backup": str(cfg.get("backup", "water")) })
	h.connect("ended", func():
		go_lobby(last_cfg)
		var why := str(h.get("end_note")) if is_instance_valid(h) and h.get("end_note") != null else ""
		if why != "" and screen is HHLobby:              # H917: "the host left" stays in the ticker
			(screen as HHLobby).coop_note = why
			(screen as HHLobby)._ticker_rest(), CONNECT_ONE_SHOT)


func replay() -> void:
	if last_cfg.is_empty():
		last_cfg = default_cfg()
	play(last_cfg)


func new_seed() -> void:
	if last_cfg.is_empty():
		last_cfg = default_cfg()
	last_cfg.seed = int(last_cfg.get("seed", 1)) + 1
	play(last_cfg)


## "VICTORY in 84 s" / "FALLEN at 2:10" / "aborted at 0:31"; "" for no result.
static func result_line(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var secs := int(r.get("ticks", 0)) * HHSim.TICK
	var clock := "%d:%02d" % [int(secs) / 60, int(secs) % 60]
	match str(r.get("result", "")):
		"win": return "VICTORY in %d s" % int(secs)
		"fallen": return "FALLEN at %s" % clock
		"abort": return ("the host left at %s" if bool(r.get("host_left", false)) else "aborted at %s") % clock
	return str(r.get("result", ""))
