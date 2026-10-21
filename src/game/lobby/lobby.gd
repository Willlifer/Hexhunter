class_name HHLobby
extends Control
## The lobby (H47, H48; Gamers Gauntlet's lobby_screen pattern): a 1600x900
## canvas built in code. Three tile rows (Arena, Monster, Weapon) with
## thumbnails, an element strip of seven sockets (first click = active,
## second = backup; the row says which the next click sets), a card with
## the seed and dice, Fight / Hunt / Replay / New seed, the upgrades and the
## last runs, a gear that opens the F1 tune panel, and a ticker along the
## bottom that shows the blurb of whatever the mouse is over (or the last
## fight's result). Keys: 1-4 jump rows, Left / Right step the row's pick,
## Enter fights, Esc quits the app.
## Visual pass (Lane UI, H800+): the HUD's language throughout (dark plates
## with a gold trim, the serif face, glyph sockets), thumbnails and the run
## history (L-19).
## `setup(cfg)` prefills from cfg (the hunt loop passes `locked` keys, drawn
## greyed with a LOCK); `finished` emits { result: "fight", cfg } or
## { result: "quit" }. The picks live in HHLobbyState (testable headlessly).

signal finished(result: Dictionary)

# layout on the 1600x900 canvas
const CANVAS := Vector2(1600, 900)
const TITLE_POS := Vector2(24, 8)
const TITLE_SIZE := 50
const TILE_X := 150.0                 # tiles start right of the row labels
const TILE_SIZE := Vector2(250, 140)
const TILE_GAP := 14.0
const ROW_Y := [96.0, 262.0, 428.0]    # arena, monster, weapon rows
const ELEM_LABEL_Y := 590.0
const ELEM_Y := 606.0                 # the element sockets' top (their hover tag sits above the disc)
const ELEM_SIZE := Vector2(80, 140)
const ELEM_STEP := 110.0              # the axis group's spacing (H244)
const OP_X := 600.0                   # the OPERATORS group: discs from here (H244)
const OP_STEP := 88.0
const OP_COPY_X := 874.0              # ... and one line of copy per operator right of them
const OP_COPY_W := 332.0
const CARD := Rect2(1212, 96, 364, 784)   # the right card: seed, buttons, upgrades, runs
const TICKER := Rect2(24, 760, 1168, 54)
const HINT_Y := 838.0
const LABEL_SIZE := 18
const DIM := Color(1, 0.96, 0.88, 0.55)
const ROW_KEYS := ["1", "2", "3", "4"]
const ROW_NAMES := ["ARENA", "MONSTER", "WEAPON", "ELEMENTS"]
const RED := Color(0.5, 0.08, 0.06)

var state := HHLobbyState.new()
var _hunt_btn: Button = null
var _own_all: Button = null
var can_replay := false          # the shell sets this once a fight has run
var result_text := ""            # the last fight's result line for the ticker
var last_result := {}            # the last fight's payload (else read from an HHShell parent); recorded once into the run history
var rng := RandomNumberGenerator.new()

var _tiles := {}                 # kind -> Array[HHLobbyTile]
var _discs := {}                 # element id -> HHLobbyDisc
var _row_labels: Array = []
var _next_label: Label
var _ticker: Label
var _seed: SpinBox
var _pair: Label
var _replay: Button
var _new_seed: Button
var _ups_box: VBoxContainer
var _runs_box: VBoxContainer
var _tune: HHTunePanel
var _recorded := false
var _fight_btn: Button
var _dice: Button
var _tier_btns := {}             ## H243: tier id -> its toggle in the card's head
var _op_label: Label             ## H244: "OPERATORS" over Wind, Ice and Thunder
var _axis_label: Label           ## H266: "AXIS" over Fire, Water, Dark and Light
var _axis_copy: Label            ## ... and its one line
var _op_copy := {}               ## operator id -> its one line of copy

## Co-op (Lane C, H908-H912): the "Play together" section on the card.
var coop := HHLobbyCoop.new()    ## the party logic; the shell's net + session are attached in _ready
var coop_boot := {}              ## boot's --host / --join: { mode, address, name, autoplay, peers, seconds }
var _coop_solo: VBoxContainer    # name + Host, address + Join (shown when not in a party)
var _coop_party: VBoxContainer   # the party list, Ready, Leave (shown in a party)
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _coop_status: Label
var _party_box: VBoxContainer
var _ready_btn: Button
var _runs_head: Control
var _auto := {}                  # coop_boot when it asked for autoplay (two-process smoke test)
## Online through the relay (Lane R, H114): a LAN / Online switch over the
## same two rows; hosting online shows the room code big with Copy.
var online_mode := OS.has_feature("web")   ## the browser has no LAN play (H79)
var _mode_row: HBoxContainer
var _lan_btn: Button
var _online_btn: Button
var _host_btn: Button
var _join_btn: Button
var _code_box: HBoxContainer
var _code_label: Label


func setup(cfg: Dictionary) -> void:
	state.setup(cfg)
	rng.randomize()
	_record_last_run()
	if is_inside_tree():
		_refresh()


## The fight that just ended goes into the run history, once.
func _record_last_run() -> void:
	if _recorded or result_text == "":
		return
	var lr := last_result
	if lr.is_empty() and get_parent() is HHShell:
		lr = (get_parent() as HHShell).last_result
	if lr.is_empty():
		return
	_recorded = true
	HHLobbyState.record_run(HHLobbyState.run_entry(lr, state.cfg))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = make_theme()
	var bg := Backdrop.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := _label("HEXHUNT", TITLE_POS, TITLE_SIZE, HHHud.GOLD)
	title.add_theme_font_override("font", HHHud.serif())
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label("pick an arena, a monster, a weapon and two elements, then Fight", Vector2(300, 34), 16, DIM)
	for i in 3:
		_build_row(i, HHLobbyState.ROWS[i], ROW_Y[i])
	_build_elements()
	_build_card()
	_build_ticker()
	_tune = HHTunePanel.new()
	add_child(_tune)
	_attach_coop()
	_refresh()
	if not coop_boot.is_empty():
		_boot_coop.call_deferred()


func _exit_tree() -> void:
	coop.detach()


## The shell's net + session (made now if src/net exists). A test or the
## capture tool may attach fakes before adding the lobby; those are kept.
func _attach_coop() -> void:
	if coop.net == null and get_parent() is HHShell:
		var sh := get_parent() as HHShell
		sh.ensure_net()
		coop.attach(sh.net, sh.session)
	coop.note.connect(func(t: String):
		coop_note = t
		if not _auto.is_empty():
			print("[lobby] ", t)                  # the two-process smoke reads the room code here
		if _ticker != null:
			_ticker.text = t)
	coop.refreshed.connect(_on_coop_refreshed)
	coop.started.connect(_on_coop_started)
	coop.hunt_started.connect(_on_coop_hunt)


## boot --host / --join: open already hosting / joined.
func _boot_coop() -> void:
	var b := coop_boot
	if bool(b.get("autoplay", false)):
		_auto = b
	var nm := str(b.get("name", "Host" if str(b.get("mode", "")) == "host" else "Guest"))
	coop.port = int(b.get("port", HHParty.PORT))
	_name_edit.text = nm
	if bool(b.get("online", false)) or OS.has_feature("web"):   # --host --online / --join-code X
		_set_online(true)
		if str(b.get("mode", "")) == "host":
			coop.host_online(nm)
		elif str(b.get("mode", "")) == "join":
			_addr_edit.text = str(b.get("code", "")) if str(b.get("code", "")) != "" else str(b.get("address", ""))
			coop.join_online(_addr_edit.text, nm)
		_refresh()
		return
	if str(b.get("mode", "")) == "host":
		coop.host_game(nm)
	elif str(b.get("mode", "")) == "join":
		_addr_edit.text = str(b.get("address", ""))
		coop.join_game(_addr_edit.text, nm)
	_refresh()


# ------------------------------------------------------------------ look

## The lobby's theme: the body in a system serif, buttons as dark plates
## with a gold-dim rim (gold on hover), FIGHT in the orb's red.
static func make_theme() -> Theme:
	var t := Theme.new()
	var body := SystemFont.new()
	body.font_names = PackedStringArray(HHHud.SERIF_NAMES)
	body.fallbacks = [ThemeDB.fallback_font]
	t.default_font = body
	t.default_font_size = 16
	t.set_color("font_color", "Label", Color(1, 0.96, 0.88))
	t.set_stylebox("normal", "Button", _box(Color(0.13, 0.11, 0.09), HHHud.GOLD_DIM, 1))
	t.set_stylebox("hover", "Button", _box(Color(0.19, 0.16, 0.12), HHHud.GOLD, 1))
	t.set_stylebox("pressed", "Button", _box(Color(0.08, 0.07, 0.06), HHHud.GOLD, 2))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), HHHud.GOLD, 1))
	t.set_stylebox("disabled", "Button", _box(Color(0.08, 0.075, 0.07), Color(0.3, 0.28, 0.25), 1))
	t.set_font("font", "Button", HHHud.serif())
	t.set_color("font_color", "Button", Color(1, 0.94, 0.82))
	t.set_color("font_hover_color", "Button", Color(1, 0.98, 0.9))
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:   # rows, not buttons
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 4
		e.content_margin_top = 1
		e.content_margin_bottom = 1
		t.set_stylebox(st, "CheckBox", e)
	t.set_color("font_color", "CheckBox", Color(1, 0.96, 0.88, 0.9))
	t.set_color("font_disabled_color", "CheckBox", Color(1, 1, 1, 0.32))
	return t


static func _box(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


## The full-screen backdrop: a warm dark gradient, a gold rule under the
## title, a soft vignette.
class Backdrop:
	extends Control
	func _draw() -> void:
		var pt := HHHud.Paint.new(get_canvas_item())
		var s := get_viewport_rect().size
		pt.vgrad(Rect2(Vector2.ZERO, s), Color(0.085, 0.075, 0.065), Color(0.03, 0.03, 0.035))
		var g := HHHud.GOLD
		pt.poly_colors(PackedVector2Array([Vector2(24, 76), Vector2(900, 76), Vector2(900, 77.5), Vector2(24, 77.5)]),
			PackedColorArray([Color(g.r, g.g, g.b, 0.8), Color(g.r, g.g, g.b, 0.0), Color(g.r, g.g, g.b, 0.0), Color(g.r, g.g, g.b, 0.8)]))
		pt.poly(PackedVector2Array([Vector2(24, 72), Vector2(28.5, 76.75), Vector2(24, 81.5), Vector2(19.5, 76.75)]), g)


# ------------------------------------------------------------------ build

func _label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _row_label(i: int, y: float) -> Label:
	var rl := _label("%s  %s" % [ROW_KEYS[i], ROW_NAMES[i]], Vector2(24, y), LABEL_SIZE, DIM)
	rl.add_theme_font_override("font", HHHud.serif())
	_row_labels.append(rl)
	return rl


func _build_row(i: int, kind: String, y: float) -> void:
	_row_label(i, y + 4)
	var tiles: Array = []
	var rows := HHRegistry.rows(kind)
	for j in rows.size():
		var t := HHLobbyTile.make(self, Rect2(Vector2(TILE_X + j * (TILE_SIZE.x + TILE_GAP), y), TILE_SIZE), rows[j], kind)
		t.pressed.connect(func(tile: HHLobbyTile): _pick(kind, tile.id))
		t.hovered.connect(func(tile: HHLobbyTile): _ticker.text = tile.blurb)
		t.mouse_exited.connect(_ticker_rest)
		tiles.append(t)
	_tiles[kind] = tiles


## The element strip (H244, spec section 4): the four axis elements, a rule,
## then Wind, Ice and Thunder under OPERATORS with one line of copy each
## naming the operator's cash-in. Same discs, same picking; only the
## grouping and the labels are new.
func _build_elements() -> void:
	_row_label(3, ELEM_LABEL_Y - 8)
	_next_label = _label("", Vector2(24, ELEM_Y + 30.0), 14, HHLobbyDisc.ACTIVE)   # H266: under the row label
	_next_label.size = Vector2(TILE_X - 34.0, 80)
	_next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_axis_label = _label("AXIS", Vector2(TILE_X, ELEM_LABEL_Y - 8), LABEL_SIZE - 2, HHHud.GOLD_DIM)
	_axis_label.add_theme_font_override("font", HHHud.serif())
	_axis_copy = _label(HHLobbyState.AXIS_COPY, Vector2(TILE_X + 52.0, ELEM_LABEL_Y - 5), 13, Color(1, 0.96, 0.88, 0.8))
	var axis := HHLobbyState.AXIS
	var ops := HHLobbyState.OPERATORS
	for j in axis.size():
		_add_disc(str(axis[j]), Vector2(TILE_X + j * ELEM_STEP, ELEM_Y))
	var rule := ColorRect.new()
	rule.color = Color(HHHud.GOLD_DIM.r, HHHud.GOLD_DIM.g, HHHud.GOLD_DIM.b, 0.55)
	rule.position = Vector2(OP_X - 22.0, ELEM_LABEL_Y - 4.0)
	rule.size = Vector2(1, ELEM_Y + ELEM_SIZE.y - ELEM_LABEL_Y)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	_op_label = _label("OPERATORS", Vector2(OP_X, ELEM_LABEL_Y - 8), LABEL_SIZE - 2, HHHud.GOLD_DIM)
	_op_label.add_theme_font_override("font", HHHud.serif())
	_op_label.tooltip_text = "Operators work on charge already on the ground; each has a cash-in"
	for j in ops.size():
		var id := str(ops[j])
		_add_disc(id, Vector2(OP_X + j * OP_STEP, ELEM_Y))
		var line := _label(str(HHLobbyState.OPERATOR_COPY[id]), Vector2(OP_COPY_X, ELEM_Y + 22.0 + j * 30.0), 12,
			HHLook.element_color(id).lerp(Color(1, 0.96, 0.88), 0.55))
		line.size = Vector2(OP_COPY_W, 22)
		line.clip_text = true
		_op_copy[id] = line


func _add_disc(id: String, at: Vector2) -> void:
	var row := HHRegistry.entry("element", id)
	var d := HHLobbyDisc.new()
	d.id = id
	d.title = str(row.name)
	d.blurb = str(row.blurb)
	d.color = HHLook.element_color(d.id)
	d.position = at
	d.size = ELEM_SIZE
	d.pressed.connect(func(disc: HHLobbyDisc): _pick_element(disc.id))
	d.hovered.connect(func(disc: HHLobbyDisc):
		var copy := str(HHLobbyState.OPERATOR_COPY.get(disc.id, ""))
		var head := copy if copy != "" else disc.title
		_ticker.text = "%s. %s   (this click sets the %s element)" % [head, disc.blurb, disc.next_sets])
	d.mouse_exited.connect(_ticker_rest)
	add_child(d)
	_discs[d.id] = d


func _build_card() -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.055, 0.96)
	sb.border_color = HHHud.GOLD_DIM
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	p.position = CARD.position
	p.size = CARD.size
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var hl := Label.new()
	hl.text = "THE HUNT"
	hl.add_theme_font_override("font", HHHud.serif())
	hl.add_theme_font_size_override("font_size", 24)
	hl.add_theme_color_override("font_color", HHHud.GOLD)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var tiers := ButtonGroup.new()                         # H243: the tier switch, the LAN / Online toggle's style
	for t in HHLobbyState.LOBBY_TIERS:
		var tb := Button.new()
		tb.text = str(t).capitalize()
		tb.toggle_mode = true
		tb.button_group = tiers
		tb.custom_minimum_size = Vector2(62, 0)
		tb.add_theme_font_size_override("font_size", 13)
		tb.tooltip_text = str(HHLobbyState.TIER_BLURB[t])
		tb.pressed.connect(func(): _pick_tier(str(t)))
		tb.mouse_entered.connect(func(): _ticker.text = str(HHLobbyState.TIER_BLURB[t]))
		tb.mouse_exited.connect(_ticker_rest)
		head.add_child(tb)
		_tier_btns[str(t)] = tb
	var gear := Button.new()
	gear.text = "Tune (F1)"
	gear.tooltip_text = "Open the live tuning panel; values save to user://hexhunt_tune.cfg"
	gear.add_theme_font_size_override("font_size", 13)
	gear.pressed.connect(func(): _tune.open())
	head.add_child(gear)
	_pair = Label.new()
	_pair.add_theme_font_size_override("font_size", 15)
	_pair.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_pair)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	v.add_child(sh)
	var sl := Label.new()
	sl.text = "Seed"
	sl.add_theme_color_override("font_color", DIM)
	sh.add_child(sl)
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 999999
	_seed.step = 1
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.value_changed.connect(func(val: float):
		if state.set_seed(int(val)):
			_refresh())
	sh.add_child(_seed)
	var dice := Button.new()
	_dice = dice
	dice.text = "Dice"
	dice.tooltip_text = "Roll a random seed"
	dice.pressed.connect(func():
		if state.roll_seed(rng):
			_refresh())
	sh.add_child(dice)
	var fight := Button.new()
	fight.text = "FIGHT   (Enter)"
	fight.custom_minimum_size = Vector2(0, 56)
	fight.add_theme_font_size_override("font_size", 26)
	fight.add_theme_stylebox_override("normal", _box(RED, HHHud.GOLD, 2))
	fight.add_theme_stylebox_override("hover", _box(RED.lightened(0.15), Color(1, 0.88, 0.55), 2))
	fight.add_theme_stylebox_override("pressed", _box(RED.darkened(0.3), HHHud.GOLD, 3))
	fight.pressed.connect(_fight)
	v.add_child(fight)
	_fight_btn = fight
	_hunt_btn = Button.new()                              # H612: the hunt loop starts from the plain lobby
	_hunt_btn.text = "GO HUNTING   (H)"
	_hunt_btn.tooltip_text = "World map: find the stirring site, survive the ambush, prepare, fight, take the drops"
	_hunt_btn.custom_minimum_size = Vector2(0, 42)
	_hunt_btn.add_theme_font_size_override("font_size", 19)
	_hunt_btn.pressed.connect(_hunt)
	v.add_child(_hunt_btn)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 8)
	v.add_child(rr)
	_replay = Button.new()
	_replay.text = "Replay last"
	_replay.custom_minimum_size = Vector2(0, 34)
	_replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay.pressed.connect(_fight)
	rr.add_child(_replay)
	_new_seed = Button.new()
	_new_seed.text = "New seed"
	_new_seed.tooltip_text = "The same setup with the next seed"
	_new_seed.custom_minimum_size = Vector2(0, 34)
	_new_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_seed.pressed.connect(func():
		if state.set_seed(int(state.cfg.seed) + 1):
			_fight())
	rr.add_child(_new_seed)
	v.add_child(_section("UPGRADES", "tick to slot, 3 per skill"))
	_own_all = Button.new()                               # R-L1 (H613): try every upgrade before any hunt
	_own_all.text = "Unlock all upgrades (testing)"
	_own_all.tooltip_text = "Owns every upgrade in your save so you can slot and try them in any fight"
	_own_all.add_theme_font_size_override("font_size", 13)
	_own_all.pressed.connect(func():
		var n := state.own_all()
		_refresh()
		_ticker.text = "Unlocked %d upgrade(s): tick them to slot (3 per skill)" % n)
	v.add_child(_own_all)
	_ups_box = VBoxContainer.new()
	_ups_box.add_theme_constant_override("separation", 0)
	v.add_child(_ups_box)
	_build_coop(v)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_runs_head = _section("LAST RUNS", "")
	v.add_child(_runs_head)
	_runs_box = VBoxContainer.new()
	_runs_box.add_theme_constant_override("separation", 2)
	v.add_child(_runs_box)


## "PLAY TOGETHER" (H908): solo shows a name field with Host and an address
## field with Join; in a party it shows where the party is, the party list
## (slot colour, name, weapon, element pair, ready tick), Ready and Leave.
func _build_coop(v: VBoxContainer) -> void:
	v.add_child(_section("PLAY TOGETHER", "up to 4"))
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 4)
	_mode_row.visible = not OS.has_feature("web")
	v.add_child(_mode_row)
	var group := ButtonGroup.new()
	_lan_btn = Button.new()
	_lan_btn.text = "LAN"
	_lan_btn.tooltip_text = "Same network: the host's address and port %d" % HHParty.PORT
	_online_btn = Button.new()
	_online_btn.text = "Online"
	_online_btn.tooltip_text = "Over the internet through the Hexhunt relay: share a five-letter room code"
	for bt in [_lan_btn, _online_btn]:
		bt.toggle_mode = true
		bt.button_group = group
		bt.custom_minimum_size = Vector2(84, 26)
		bt.add_theme_font_size_override("font_size", 13)
		_mode_row.add_child(bt)
	_lan_btn.pressed.connect(func(): _set_online(false))
	_online_btn.pressed.connect(func(): _set_online(true))
	_coop_status = Label.new()
	_coop_status.add_theme_font_size_override("font_size", 13)
	_coop_status.add_theme_color_override("font_color", Color(1, 0.96, 0.88, 0.8))
	_coop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_coop_status)
	_coop_solo = VBoxContainer.new()
	_coop_solo.add_theme_constant_override("separation", 5)
	v.add_child(_coop_solo)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	_coop_solo.add_child(r1)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "your name"
	_name_edit.text = coop.my_name
	_name_edit.max_length = 16
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 14)
	_name_edit.text_changed.connect(func(t: String): coop.my_name = HHLobbyCoop._clean_name(t))
	r1.add_child(_name_edit)
	_host_btn = Button.new()
	_host_btn.text = "Host"
	_host_btn.custom_minimum_size = Vector2(110, 0)
	_host_btn.pressed.connect(func():
		if online_mode:
			coop.host_online(_name_edit.text)
		else:
			coop.host_game(_name_edit.text)
		_refresh())
	r1.add_child(_host_btn)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	_coop_solo.add_child(r2)
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "host's address, e.g. 192.168.1.20"
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr_edit.add_theme_font_size_override("font_size", 14)
	_addr_edit.text_submitted.connect(func(_t: String): _join())
	r2.add_child(_addr_edit)
	_join_btn = Button.new()
	_join_btn.text = "Join"
	_join_btn.custom_minimum_size = Vector2(110, 0)
	_join_btn.pressed.connect(_join)
	r2.add_child(_join_btn)
	_coop_party = VBoxContainer.new()
	_coop_party.add_theme_constant_override("separation", 5)
	v.add_child(_coop_party)
	_code_box = HBoxContainer.new()                # online host: the room code, big, with Copy
	_code_box.add_theme_constant_override("separation", 10)
	_coop_party.add_child(_code_box)
	var cap := Label.new()
	cap.text = "ROOM"
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", HHHud.GOLD_DIM)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_code_box.add_child(cap)
	_code_label = Label.new()
	_code_label.add_theme_font_override("font", HHHud.serif())
	_code_label.add_theme_font_size_override("font_size", 34)
	_code_label.add_theme_color_override("font_color", HHHud.GOLD)
	_code_label.add_theme_constant_override("outline_size", 4)
	_code_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_code_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_code_label.tooltip_text = "Friends pick Online, type this code and Join"
	_code_box.add_child(_code_label)
	var copy := Button.new()
	copy.text = "Copy"
	copy.custom_minimum_size = Vector2(70, 30)
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.pressed.connect(func():
		if coop.share_code() != "":
			DisplayServer.clipboard_set(coop.share_code())
			_ticker.text = "Copied room code %s" % coop.share_code())
	_code_box.add_child(copy)
	_set_online(online_mode)
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 2)
	_coop_party.add_child(_party_box)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 8)
	_coop_party.add_child(r3)
	_ready_btn = Button.new()
	_ready_btn.toggle_mode = true
	_ready_btn.text = "Ready"
	_ready_btn.custom_minimum_size = Vector2(0, 34)
	_ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_btn.pressed.connect(func():
		coop.toggle_ready(state)
		_refresh())
	r3.add_child(_ready_btn)
	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(90, 34)
	leave.pressed.connect(func():
		coop.leave()
		_refresh())
	r3.add_child(leave)


func _join() -> void:
	if online_mode:
		coop.join_online(_addr_edit.text, _name_edit.text)
	else:
		coop.join_game(_addr_edit.text, _name_edit.text)
	_refresh()


## LAN or Online (H114): the same two rows, relabelled.
func _set_online(on: bool) -> void:
	online_mode = on or OS.has_feature("web")
	if _host_btn == null:
		return
	_lan_btn.set_pressed_no_signal(not online_mode)
	_online_btn.set_pressed_no_signal(online_mode)
	_host_btn.text = "Host online" if online_mode else "Host"
	_join_btn.text = "Join online" if online_mode else "Join"
	_host_btn.tooltip_text = ("Open a room on the Hexhunt relay; it gives you a code to share" if online_mode
		else "Open a party on this machine (port %d); your friends join with the address it shows" % HHParty.PORT)
	_addr_edit.placeholder_text = "room code, e.g. KMRTX" if online_mode else "host's address, e.g. 192.168.1.20"
	if _coop_status != null and _ready_btn != null:
		_refresh_coop()


## The party list and the co-op widgets from the coop state.
func _refresh_coop() -> void:
	if _coop_status == null:
		return
	var party := coop.in_party()
	_coop_solo.visible = not party and coop.role != "joining"
	_coop_party.visible = party
	match coop.role:
		"host":
			if coop.online:
				_coop_status.text = ("Room open: friends pick Online, type the code and Join. You pick the arena, monster and seed; FIGHT when everyone is ready."
					if coop.room != "" else "Opening a room on the relay (a sleeping relay takes up to a minute) ...")
			else:
				_coop_status.text = "Hosting on %s. You pick the arena, monster and seed; FIGHT when everyone is ready." % coop.address
		"client": _coop_status.text = "In the party at %s. The host picks the arena, monster and seed; you pick your own kit, then Ready." % coop.address
		"joining":
			_coop_status.text = ("Joining %s (a sleeping relay takes up to a minute) ..." % coop.address) if coop.online else ("Joining %s ..." % coop.address)
		_:
			_coop_status.text = ("Host online for a room code, or type a friend's code and Join online." if online_mode
				else "Host a party, or type a friend's address and Join.")
	_mode_row.visible = not coop.in_party() and coop.role != "joining" and not OS.has_feature("web")
	_code_box.visible = coop.share_code() != ""
	_code_label.text = coop.share_code()
	_ready_btn.set_pressed_no_signal(coop.ready)
	_ready_btn.visible = coop.role != "host"         # the host's FIGHT readies the host
	_ready_btn.text = "Ready (click to unready)" if coop.ready else "Ready up"
	for ch in _party_box.get_children():
		ch.queue_free()
	if party:
		for r in coop.party_rows():
			var row := PartyRow.new()
			row.entry = r
			row.custom_minimum_size = Vector2(0, PartyRow.H)
			_party_box.add_child(row)
	_runs_head.visible = not party
	_runs_box.visible = not party


## One party member: slot colour bar, name (HOST / YOU tags), weapon, the
## element pair as two dots, and a ready tick (gold) or an empty ring.
class PartyRow:
	extends Control
	const H := 28.0
	var entry := {}

	func _draw() -> void:
		paint(HHHud.Paint.new(get_canvas_item()), size)

	func paint(pt: HHHud.Paint, sz: Vector2) -> void:
		var e := entry
		var cy := sz.y * 0.5
		var col := HHParty.slot_color(str(e.get("id", "")))
		pt.rect(Rect2(0, 1, sz.x, sz.y - 2), Color(1, 1, 1, 0.04) if not bool(e.get("me", false)) else Color(col.r, col.g, col.b, 0.1))
		pt.rect(Rect2(0, 1, 3, sz.y - 2), col)
		var serif := HHHud.serif()
		var tag := ("HOST" if bool(e.get("host", false)) else "") + ("  YOU" if bool(e.get("me", false)) else "")
		pt.text(Vector2(10, cy + 5), str(e.get("name", "")), 14, Color(1, 0.96, 0.88), 0, 3, serif)
		if tag != "":
			pt.text(Vector2(10 + pt.text_width(str(e.get("name", "")), 14, serif) + 6, cy + 4), tag.strip_edges(), 10, Color(col.r, col.g, col.b, 0.9), 0, 2)
		pt.text(Vector2(sz.x - 112, cy + 5), HHRegistry.name_of("weapon", str(e.get("weapon", ""))), 12, Color(1, 0.96, 0.88, 0.8), 2, 3)
		var ex := sz.x - 100.0
		for k in ["element", "backup"]:
			var r := 6.0 if k == "element" else 4.5
			pt.circle(Vector2(ex, cy), r, HHLook.element_color(str(e.get(k, ""))))
			pt.ring(Vector2(ex, cy), r, Color(0, 0, 0, 0.8), 1.0)
			ex += 14.0
		var c := Vector2(sz.x - 16, cy)
		if bool(e.get("ready", false)):
			pt.circle(c, 9.0, HHHud.GOLD)
			pt.polyline(PackedVector2Array([c + Vector2(-4.5, 0), c + Vector2(-1, 3.5), c + Vector2(5, -3.5)]), Color(0.08, 0.06, 0.04), 2.2)
		else:
			pt.ring(c, 8.0, Color(1, 0.96, 0.88, 0.35), 1.5)


## A section heading: serif caps in gold-dim, a note after it, a rule under.
func _section(title: String, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var l := Label.new()
	l.text = title + (("   " + note) if note != "" else "")
	l.add_theme_font_override("font", HHHud.serif())
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", HHHud.GOLD)
	box.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(HHHud.GOLD_DIM.r, HHHud.GOLD_DIM.g, HHHud.GOLD_DIM.b, 0.7)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	return box


## One CheckBox per upgrade that fits the picked weapon (Lane U's table):
## ticked = slotted, greyed = not owned yet (the hover says who drops it).
func _refresh_upgrades() -> void:
	for ch in _ups_box.get_children():
		ch.queue_free()
	if state.save == null:
		return
	for id in HHUpgrades.for_weapon(str(state.cfg.weapon)):
		var row: Dictionary = HHUpgrades.TABLE[id]
		var cb := CheckBox.new()
		cb.text = "%s  %s" % [str(row.skill).to_upper(), HHUpgrades.name_of(id)]
		cb.add_theme_font_size_override("font_size", 13)
		cb.button_pressed = state.is_slotted(id)
		cb.disabled = not state.save.owns(id) or state.is_locked("upgrades")
		var drops := ", ".join((row.get("drops_from", []) as Array).map(func(m): return HHRegistry.name_of("monster", str(m))))
		var line := "%s: %s%s" % [HHUpgrades.name_of(id), HHUpgrades.blurb_of(id), "" if state.save.owns(id) else "   (drops from %s)" % drops]
		cb.mouse_entered.connect(func(): _ticker.text = line)
		cb.mouse_exited.connect(_ticker_rest)
		cb.toggled.connect(func(_on: bool):
			if not state.toggle_upgrade(id):
				_ticker.text = "%s: slots full for %s (max %d)" % [HHUpgrades.name_of(id), str(row.skill).to_upper(), HHUpgrades.MAX_PER_SKILL]
			_refresh())
		_ups_box.add_child(cb)


## The last RUNS_SHOWN runs from the history file (L-19).
func _refresh_runs() -> void:
	if _runs_box == null:
		return
	for ch in _runs_box.get_children():
		ch.queue_free()
	var runs := HHLobbyState.load_runs()
	if runs.is_empty():
		var l := Label.new()
		l.text = "no runs yet: fight one"
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", DIM)
		_runs_box.add_child(l)
		return
	for i in mini(runs.size(), HHLobbyState.RUNS_SHOWN):
		var row := RunRow.new()
		row.entry = runs[i]
		row.custom_minimum_size = Vector2(0, RunRow.H)
		row.tooltip_text = RunRow.describe(runs[i])
		var e: Dictionary = runs[i]
		row.mouse_entered.connect(func(): _ticker.text = RunRow.describe(e))
		row.mouse_exited.connect(_ticker_rest)
		_runs_box.add_child(row)


## One run-history row: the monster's portrait, the verdict and clock, the
## weapon, the element pair as two dots, the seed.
class RunRow:
	extends Control
	const H := 26.0
	var entry := {}

	static func describe(e: Dictionary) -> String:
		return "%s: %s with the %s, %s / %s, seed %d%s" % [HHLobbyState.run_verdict(e), HHRegistry.name_of("monster", str(e.get("monster", ""))),
			HHRegistry.name_of("weapon", str(e.get("weapon", ""))).to_lower(), str(e.get("element", "")), str(e.get("backup", "")),
			int(e.get("seed", 1)), "  (hunt)" if bool(e.get("hunt", false)) else ""]

	func _draw() -> void:
		paint(HHHud.Paint.new(get_canvas_item()), size)

	func paint(pt: HHHud.Paint, sz: Vector2) -> void:
		var e := entry
		var cy := sz.y * 0.5
		var res := str(e.get("result", ""))
		var col := HHHud.GOLD if res == "win" else (Color(0.92, 0.36, 0.3) if res == "fallen" else Color(0.65, 0.62, 0.58))
		pt.rect(Rect2(0, 1, sz.x, sz.y - 2), Color(1, 1, 1, 0.03))
		pt.rect(Rect2(0, 1, 2, sz.y - 2), col)
		var c := Vector2(17, cy)
		pt.circle(c, 11.0, HHHud.PLATE_BOT)
		HHHud.thumb_disc(pt, HHHud.thumb("monster", str(e.get("monster", ""))), c, 10.0, 0.85)
		pt.ring(c, 11.0, HHHud.GOLD_DIM, 1.0)
		var serif := HHHud.serif()
		pt.text(Vector2(34, cy + 5), HHLobbyState.run_verdict(e), 13, col, 0, 3, serif)
		var wname := HHRegistry.name_of("weapon", str(e.get("weapon", "")))
		pt.text(Vector2(142, cy + 5), wname, 12, Color(1, 0.96, 0.88, 0.85), 0, 3)
		var ex := sz.x - 74.0
		for k in ["element", "backup"]:
			pt.circle(Vector2(ex, cy), 6.0 if k == "element" else 4.5, HHLook.element_color(str(e.get(k, ""))))
			pt.ring(Vector2(ex, cy), 6.0 if k == "element" else 4.5, Color(0, 0, 0, 0.8), 1.0)
			ex += 14.0
		pt.text(Vector2(sz.x - 4, cy + 5), "#%d" % int(e.get("seed", 1)), 12, Color(1, 0.96, 0.88, 0.6), 2, 3)


func _build_ticker() -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.055, 0.92)
	sb.border_color = HHHud.GOLD_DIM
	sb.border_width_top = 2
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 18
	p.add_theme_stylebox_override("panel", sb)
	p.position = TICKER.position
	p.size = TICKER.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	_ticker = Label.new()
	_ticker.add_theme_font_size_override("font_size", 19)
	_ticker.clip_text = true
	_ticker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_ticker)
	_label("1-4 jump rows  ·  Left / Right change the pick  ·  Enter fights  ·  F1 tune  ·  Esc quits", Vector2(TICKER.position.x, HINT_Y - 14), 14, DIM)
	_label("In the fight: right-click moves / attacks, hold Q to charge, E R cast, W swaps, Shift dashes, T throws a potion, Esc back here", Vector2(TICKER.position.x, HINT_Y + 6), 14, DIM)


# ------------------------------------------------------------------ state

func _pick(kind: String, id: String) -> void:
	if state.pick(kind, id):
		state.row = HHLobbyState.ROWS.find(kind)
		_refresh()
	elif state.coop_locks.has(kind) and not state.locked.has(kind):
		_ticker.text = "The host picks the %s" % kind
	else:
		_ticker.text = "%s is locked for this hunt" % kind.capitalize()


func _pick_tier(t: String) -> void:
	if state.set_difficulty(t):
		_refresh()
		_ticker.text = str(HHLobbyState.TIER_BLURB.get(t, t))
	else:
		_refresh()
		_ticker.text = "The host picks the difficulty"


func _pick_element(id: String) -> void:
	if state.pick_element(id):
		state.row = 3
		_refresh()
	else:
		_ticker.text = "The elements are locked for this hunt"


func _fight() -> void:
	if coop.in_party() or coop.role == "joining":   # H911: the host's FIGHT starts the party when the rest are ready
		if coop.role != "host":
			_ticker.text = "The host starts the fight once everyone is ready"
		elif not coop.start(state):
			_ticker.text = "Waiting for everyone to Ready up" if coop.party_rows().size() > 1 else "Waiting for someone to join (or Leave to fight solo)"
		return
	state.save_last()
	finished.emit({ "result": "fight", "cfg": state.launch_cfg() })


## The session started the fight: this peer launches its own cfg (H911).
func _on_coop_started(cfg: Dictionary) -> void:
	if _auto.is_empty():                       # a smoke run never touches the player's last pick
		state.save_last()
	var extras := {}
	if not _auto.is_empty():
		extras = { "autoplay": true, "autoplay_seconds": float(_auto.get("seconds", 30.0)) }
	finished.emit({ "result": "fight", "cfg": coop.launch_cfg(state, cfg, extras) })


## A client follows the host onto the world map (H913).
func _on_coop_hunt(data: Dictionary) -> void:
	if _in_hunt():
		return
	var c := state.launch_cfg()
	if data.has("seed"):
		c.seed = int(data.seed)
	finished.emit({ "result": "hunt", "cfg": c })


func _on_coop_refreshed() -> void:
	_refresh()
	if _auto.is_empty() or not coop.in_party():
		return
	if coop.role == "client" and not coop.ready:              # the smoke test: guests ready at once
		coop.toggle_ready(state)
	elif coop.role == "host" and coop.party_rows().size() >= int(_auto.get("peers", 2)) and coop.can_start():
		coop.start(state)


func _in_hunt() -> bool:
	return not (state.cfg.get("locked", []) as Array).is_empty()


func _hunt() -> void:
	if coop.role == "client":
		_ticker.text = "The host leads the hunt: you follow when they set out"
		return
	state.save_last()
	coop.broadcast_hunt({ "seed": int(state.cfg.seed) })      # H913: the party follows the host's map
	finished.emit({ "result": "hunt", "cfg": state.launch_cfg() })


var coop_note := ""              ## the last co-op message (hosting address, joined, host left): the ticker's resting line

func _ticker_rest() -> void:
	if coop_note != "":
		_ticker.text = coop_note
		return
	_ticker.text = result_text if result_text != "" else "hover a tile for what it does"


## "next click sets the ACTIVE element" / "... BACKUP ..." (the element row's hint).
func next_hint() -> String:
	if state.is_locked("element"):
		return "locked for this hunt"
	return "next click sets the %s element" % ("ACTIVE" if state.element_phase == 0 else "BACKUP")


func _refresh() -> void:
	state.coop_locks = coop.locks()
	coop.pull(state)
	coop.push(state)
	for kind in _tiles:
		for t in _tiles[kind]:
			t.selected = str(state.cfg[kind]) == t.id
			t.locked = state.is_locked(kind)
	for id in _discs:
		var d: HHLobbyDisc = _discs[id]
		d.slot = "active" if id == str(state.cfg.element) else ("backup" if id == str(state.cfg.backup) else "")
		d.locked = state.is_locked("element")
		d.next_sets = "active" if state.element_phase == 0 else "backup"
	if _next_label != null:
		_next_label.text = next_hint()
		_next_label.add_theme_color_override("font_color", HHLobbyDisc.ACTIVE if state.element_phase == 0 else HHLobbyDisc.BACKUP)
	for i in _row_labels.size():
		(_row_labels[i] as Label).add_theme_color_override("font_color", HHHud.GOLD if i == state.row else DIM)
	_seed.set_value_no_signal(float(state.cfg.seed))
	_seed.editable = not state.is_locked("seed")
	if _dice != null:
		_dice.disabled = state.is_locked("seed")
	var tier := str(state.cfg.get("difficulty", "easy"))
	for t in _tier_btns:
		var tb: Button = _tier_btns[t]
		tb.set_pressed_no_signal(t == tier)
		tb.disabled = state.is_locked("difficulty")
	_pair.text = "%s in %s with the %s\n%s, backup %s" % [
		HHRegistry.name_of("monster", str(state.cfg.monster)), HHRegistry.name_of("arena", str(state.cfg.arena)),
		HHRegistry.name_of("weapon", str(state.cfg.weapon)).to_lower(),
		HHRegistry.name_of("element", str(state.cfg.element)), HHRegistry.name_of("element", str(state.cfg.backup)).to_lower()]
	var party := coop.in_party() or coop.role == "joining"
	if _hunt_btn != null:
		_hunt_btn.visible = not _in_hunt() and coop.role != "client" and coop.role != "joining"
	if _own_all != null:
		_own_all.visible = not _in_hunt() and not party
	_replay.disabled = not can_replay
	_new_seed.disabled = not can_replay
	_replay.get_parent().visible = not party
	if _fight_btn != null:
		match coop.role:
			"host": _fight_btn.text = "FIGHT   (all ready)" if coop.can_start() else "FIGHT   (waiting)"
			"client", "joining": _fight_btn.text = "HOST STARTS"
			_: _fight_btn.text = "FIGHT   (Enter)"
		_fight_btn.disabled = party and not coop.can_start()
	_refresh_upgrades()
	_refresh_runs()
	_refresh_coop()
	_ticker_rest()


# ------------------------------------------------------------------ input

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if _tune != null and _tune.is_open():
		return
	match ev.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			state.row = ev.keycode - KEY_1
			_refresh()
		KEY_LEFT:
			state.step_row(-1)
			_refresh()
		KEY_RIGHT:
			state.step_row(1)
			_refresh()
		KEY_ENTER, KEY_KP_ENTER:
			_fight()
		KEY_H:
			if not _in_hunt():
				_hunt()
		KEY_ESCAPE:
			finished.emit({ "result": "quit" })
		_:
			return
	get_viewport().set_input_as_handled()
