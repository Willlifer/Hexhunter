class_name HHMusic
extends Node
## The author's music (H431), owned by the shell (HHShell.ensure_music) so it
## outlives screens. Every loop is 4 bars at 120 BPM (~8 s); changes inside a
## state wait for the loop's end, a new screen crossfades at once.
##   lobby, world map   the build: drums -> chords + melody -> chords + bass
##                      -> full, one step per loop, then the full mix holds
##   ambush, hunt prep  prefight_a, with prefight_b every third loop
##   fight              the fight sting, then `fight`; `fight_enrage` from the
##                      next loop once the monster is below half HP or enraged
##                      (the NORMAL tier's enrage, H401)
##   victory            `victory` once, then the lobby build from its start
##   fallen             back to the drums
## The title sting plays once, on the first screen. Level: HHTune music_db on
## the Music bus (music_on 0 mutes).

const DIR := "res://audio/music/"
const LOBBY := ["lobby_1_drums", "lobby_2_chords_melody", "lobby_3_chords_bass", "lobby_4_full"]
const FADE_S := 0.8
const ENRAGE_HP := 0.5              ## the fight turns at this share of the monster's HP
const ENRAGE_TIER := 0.5            ## ... or this far up the NORMAL enrage ramp
const BUS := "Music"

var state := ""                     ## lobby | prefight | fight | victory | fallen
var track := ""                     ## the loop playing now
var step := 0                       ## lobby build step / prefight loop count
var enraged := false
var _screen: Node = null
var _players: Array[AudioStreamPlayer] = []
var _front := 0
var _fade := 1.0                    ## 0..1 crossfade progress toward the front player
var _last_pos := 0.0
var _pending := ""                  ## the loop to switch to at the next loop end
var _sting: AudioStreamPlayer
var _title_done := false
var _streams := {}


func _ready() -> void:
	_ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_sting = AudioStreamPlayer.new()
	_sting.bus = BUS
	add_child(_sting)


## Release every stream on the way out (a playing stream held at quit is
## reported as a leaked resource).
func _exit_tree() -> void:
	for p in _players + [_sting]:
		p.stop()
		p.stream = null
	_streams.clear()


static func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)


func stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := DIR + name + ".wav"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


## The shell calls this on every screen change.
func on_screen(s: Node) -> void:
	_screen = s
	if not _title_done:
		_title_done = true
		_play_sting("sting_title")
	if s is HHFight:
		state = "fight"
		enraged = false
		_play_sting("sting_fight")
		_switch("fight")
	elif s is HHAmbush or (s is HHLobby and _is_prep(s)):
		if state != "prefight":
			state = "prefight"
			step = 0
			_switch("prefight_a")
	elif s is HHResults:
		pass                            # the fight's ending already chose (victory / fallen)
	else:                               # the lobby, the world map
		if state != "lobby":
			state = "lobby"
			step = 0
			_switch(LOBBY[0])


## The hunt's prep lobby (arena and monster locked), not the free lobby.
static func _is_prep(s: Node) -> bool:
	var st: Variant = s.get("state")
	if not st is Object:
		return false
	var locked: Variant = (st as Object).get("locked")
	return locked is Array and not (locked as Array).is_empty()


func _process(delta: float) -> void:
	var p := _players[_front]
	var q := _players[1 - _front]
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / FADE_S)
		if _fade >= 1.0:
			q.stop()
	var on := HHTune.value("music_on") > 0.0
	var db := HHTune.value("music_db")
	p.volume_db = linear_to_db(maxf(_fade, 0.0001)) + db if on else -80.0
	q.volume_db = linear_to_db(maxf(1.0 - _fade, 0.0001)) + db if on else -80.0
	_sting.volume_db = db if on else -80.0
	if state == "fight":
		_watch_fight()
	# a loop end: the position wraps (or a one-shot finished)
	if p.playing:
		var pos := p.get_playback_position()
		if pos + 0.05 < _last_pos:
			_on_loop_end()
		_last_pos = pos
	elif track != "" and _fade >= 1.0:
		_on_loop_end()


func _watch_fight() -> void:
	var sim: HHSim = _screen.get("sim") if _screen != null and is_instance_valid(_screen) else null
	if sim == null:
		return
	if sim.over == "win" and state == "fight":
		state = "victory"
		_switch("victory")
		return
	if sim.over != "" and sim.over != "win" and state == "fight":
		state = "fallen"
		_switch(LOBBY[0])
		return
	if enraged:
		return
	for u in sim.units.values():
		if str(u.get("kind", "")) != "monster" or float(u.get("max_hp", 0.0)) <= 0.0:
			continue
		var tier: Dictionary = u.get("tier", {})
		if float(u.hp) / float(u.max_hp) <= ENRAGE_HP or float(tier.get("enrage", 0.0)) >= ENRAGE_TIER:
			enraged = true
			_pending = "fight_enrage"


func _on_loop_end() -> void:
	match state:
		"lobby":
			if step < LOBBY.size() - 1:
				step += 1
				_pending = LOBBY[step]
		"prefight":
			step += 1
			_pending = "prefight_b" if step % 3 == 2 else "prefight_a"
		"victory":
			state = "lobby"
			step = 0
			_pending = LOBBY[0]
	if _pending != "" and _pending != track:
		var next := _pending
		_pending = ""
		_switch(next, true)
	_pending = ""


## Start `name` on the back player and crossfade to it (`seam`: at a loop end,
## a hard swap: the loops share the tempo, so the bar lines meet).
func _switch(name: String, seam: bool = false) -> void:
	var s := stream(name)
	track = name
	_last_pos = 0.0
	if s == null:
		return
	_front = 1 - _front
	var p := _players[_front]
	if DisplayServer.get_name() == "headless":
		return                                        # no one listens; a loop still mixing at quit leaks its playback
	p.stream = s
	p.play()
	_fade = 0.97 if seam else 0.0


func _play_sting(name: String) -> void:
	var s := stream(name)
	if s != null and DisplayServer.get_name() != "headless":
		_sting.stream = s
		_sting.play()
