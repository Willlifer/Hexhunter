class_name HHLobby
extends Control
## The lobby (H47, H48; Gamers Gauntlet's lobby_screen pattern): a 1600x900
## canvas built in code. Three tile rows (Arena, Monster, Weapon), an element
## strip of seven discs (first click = active, second = backup), a seed box
## with a dice, Fight / Replay / New seed, a gear that opens the F1 tune
## panel, and a ticker along the bottom that shows the blurb of whatever the
## mouse is over (or the last fight's result). Keys: 1-4 jump rows, Left /
## Right step the row's pick, Enter fights, Esc quits the app.
## `setup(cfg)` prefills from cfg (the hunt loop passes `locked` keys, drawn
## greyed with a LOCK); `finished` emits { result: "fight", cfg } or
## { result: "quit" }. The picks live in HHLobbyState (testable headlessly).

signal finished(result: Dictionary)

# layout on the 1600x900 canvas
const CANVAS := Vector2(1600, 900)
const TITLE_POS := Vector2(24, 10)
const TITLE_SIZE := 54
const TILE_X := 150.0                 # tiles start right of the row labels
const TILE_SIZE := Vector2(250, 140)
const TILE_GAP := 14.0
const ROW_Y := [96.0, 262.0, 428.0]    # arena, monster, weapon rows
const ELEM_Y := 620.0                 # the element discs' top
const ELEM_R := 34.0
const ELEM_STEP := 120.0
const CARD := Rect2(1212, 96, 364, 624)   # the right card: seed, buttons
const TICKER := Rect2(24, 745, 1168, 64)     # ends before the card, which may grow with the upgrade list
const HINT_Y := 822.0
const LABEL_SIZE := 18
const BG := Color(0.05, 0.06, 0.08)
const DIM := Color(1, 1, 1, 0.55)
const ROW_KEYS := ["1", "2", "3", "4"]
const ROW_NAMES := ["ARENA", "MONSTER", "WEAPON", "ELEMENTS   first click = active, second = backup"]

var state := HHLobbyState.new()
var _hunt_btn: Button = null
var _own_all: Button = null
var can_replay := false          # the shell sets this once a fight has run
var result_text := ""            # the last fight's result line for the ticker
var rng := RandomNumberGenerator.new()

var _tiles := {}                 # kind -> Array[HHLobbyTile]
var _discs := {}                 # element id -> HHLobbyDisc
var _row_labels: Array = []
var _ticker: Label
var _seed: SpinBox
var _pair: Label
var _replay: Button
var _new_seed: Button
var _ups_box: VBoxContainer
var _tune: HHTunePanel
var _font: Font


func setup(cfg: Dictionary) -> void:
	state.setup(cfg)
	rng.randomize()
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label("HEXHUNT", TITLE_POS, TITLE_SIZE, Color.WHITE)
	_label("pick an arena, a monster, a weapon and two elements, then Fight", Vector2(330, 36), 16, DIM)
	for i in 3:
		_build_row(i, HHLobbyState.ROWS[i], ROW_Y[i])
	_build_elements()
	_build_card()
	_build_ticker()
	_tune = HHTunePanel.new()
	add_child(_tune)
	_refresh()


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


func _build_row(i: int, kind: String, y: float) -> void:
	var rl := _label("%s  %s" % [ROW_KEYS[i], ROW_NAMES[i]], Vector2(24, y + 4), LABEL_SIZE, DIM)
	_row_labels.append(rl)
	var tiles: Array = []
	var rows := HHRegistry.rows(kind)
	for j in rows.size():
		var t := HHLobbyTile.make(self, Rect2(Vector2(TILE_X + j * (TILE_SIZE.x + TILE_GAP), y), TILE_SIZE), rows[j])
		t.pressed.connect(func(tile: HHLobbyTile): _pick(kind, tile.id))
		t.hovered.connect(func(tile: HHLobbyTile): _ticker.text = tile.blurb)
		t.mouse_exited.connect(_ticker_rest)
		tiles.append(t)
	_tiles[kind] = tiles


func _build_elements() -> void:
	var rl := _label("%s  %s" % [ROW_KEYS[3], ROW_NAMES[3]], Vector2(24, ELEM_Y - 30), LABEL_SIZE, DIM)
	_row_labels.append(rl)
	var rows := HHRegistry.rows("element")
	for j in rows.size():
		var d := HHLobbyDisc.new()
		d.id = str(rows[j].id)
		d.title = str(rows[j].name)
		d.blurb = str(rows[j].blurb)
		d.color = HHLook.element_color(d.id)
		d.position = Vector2(TILE_X + j * ELEM_STEP, ELEM_Y)
		d.size = Vector2(ELEM_R * 2, ELEM_R * 2 + 40)
		d.pressed.connect(func(disc: HHLobbyDisc): _pick_element(disc.id))
		d.hovered.connect(func(disc: HHLobbyDisc): _ticker.text = "%s: %s" % [disc.title, disc.blurb])
		d.mouse_exited.connect(_ticker_rest)
		add_child(d)
		_discs[d.id] = d


func _build_card() -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.position = CARD.position
	p.size = CARD.size
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var hl := Label.new()
	hl.text = "HUNT"
	hl.add_theme_font_size_override("font_size", 26)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var gear := Button.new()
	gear.text = "Tune (F1)"
	gear.tooltip_text = "Open the live tuning panel; values save to user://hexhunt_tune.cfg"
	gear.pressed.connect(func(): _tune.open())
	head.add_child(gear)
	_pair = Label.new()
	_pair.add_theme_font_size_override("font_size", 16)
	_pair.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_pair)
	var sl := Label.new()
	sl.text = "Seed"
	sl.add_theme_color_override("font_color", DIM)
	v.add_child(sl)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	v.add_child(sh)
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
	dice.text = "Dice"
	dice.tooltip_text = "Roll a random seed"
	dice.pressed.connect(func():
		if state.roll_seed(rng):
			_refresh())
	sh.add_child(dice)
	var fight := Button.new()
	fight.text = "FIGHT   (Enter)"
	fight.custom_minimum_size = Vector2(0, 60)
	fight.add_theme_font_size_override("font_size", 26)
	fight.pressed.connect(_fight)
	v.add_child(fight)
	_hunt_btn = Button.new()                              # H612: the hunt loop starts from the plain lobby
	_hunt_btn.text = "GO HUNTING   (H)"
	_hunt_btn.tooltip_text = "World map: find the stirring site, survive the ambush, prepare, fight, take the drops"
	_hunt_btn.custom_minimum_size = Vector2(0, 44)
	_hunt_btn.add_theme_font_size_override("font_size", 20)
	_hunt_btn.pressed.connect(_hunt)
	v.add_child(_hunt_btn)
	_replay = Button.new()
	_replay.text = "Replay last fight"
	_replay.custom_minimum_size = Vector2(0, 38)
	_replay.pressed.connect(_fight)
	v.add_child(_replay)
	_new_seed = Button.new()
	_new_seed.text = "New seed, same setup"
	_new_seed.custom_minimum_size = Vector2(0, 38)
	_new_seed.pressed.connect(func():
		if state.set_seed(int(state.cfg.seed) + 1):
			_fight())
	v.add_child(_new_seed)
	var ul := Label.new()
	ul.text = "Upgrades (drops; tick to slot)"
	ul.add_theme_color_override("font_color", DIM)
	v.add_child(ul)
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
	_ups_box.add_theme_constant_override("separation", 2)
	v.add_child(_ups_box)
	var keys := Label.new()
	keys.text = "In the fight: right-click moves / attacks, Q E R cast, W swaps, T potion, Esc back here"
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", DIM)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(keys)


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


func _build_ticker() -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 18
	p.add_theme_stylebox_override("panel", sb)
	p.position = TICKER.position
	p.size = TICKER.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	_ticker = Label.new()
	_ticker.add_theme_font_size_override("font_size", 20)
	_ticker.clip_text = true
	_ticker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_ticker)
	_label("1-4 jump rows  ·  Left / Right change the pick  ·  Enter fights  ·  F1 tune  ·  Esc quits", Vector2(TICKER.position.x, HINT_Y), 14, DIM)


# ------------------------------------------------------------------ state

func _pick(kind: String, id: String) -> void:
	if state.pick(kind, id):
		state.row = HHLobbyState.ROWS.find(kind)
		_refresh()
	else:
		_ticker.text = "%s is locked for this hunt" % kind.capitalize()


func _pick_element(id: String) -> void:
	if state.pick_element(id):
		state.row = 3
		_refresh()
	else:
		_ticker.text = "The elements are locked for this hunt"


func _fight() -> void:
	state.save_last()
	finished.emit({ "result": "fight", "cfg": state.launch_cfg() })


func _in_hunt() -> bool:
	return not (state.cfg.get("locked", []) as Array).is_empty()


func _hunt() -> void:
	state.save_last()
	finished.emit({ "result": "hunt", "cfg": state.launch_cfg() })


func _ticker_rest() -> void:
	_ticker.text = result_text if result_text != "" else "hover a tile for what it does"


func _refresh() -> void:
	for kind in _tiles:
		for t in _tiles[kind]:
			t.selected = str(state.cfg[kind]) == t.id
			t.locked = state.is_locked(kind)
	for id in _discs:
		var d: HHLobbyDisc = _discs[id]
		d.slot = "active" if id == str(state.cfg.element) else ("backup" if id == str(state.cfg.backup) else "")
		d.locked = state.is_locked("element")
		d.next_sets = "active" if state.element_phase == 0 else "backup"
	for i in _row_labels.size():
		(_row_labels[i] as Label).add_theme_color_override("font_color", Color.WHITE if i == state.row else DIM)
	_seed.set_value_no_signal(float(state.cfg.seed))
	_seed.editable = not state.is_locked("seed")
	_pair.text = "%s on %s with the %s\n%s / %s" % [
		HHRegistry.name_of("monster", str(state.cfg.monster)), HHRegistry.name_of("arena", str(state.cfg.arena)),
		HHRegistry.name_of("weapon", str(state.cfg.weapon)).to_lower(),
		HHRegistry.name_of("element", str(state.cfg.element)), HHRegistry.name_of("element", str(state.cfg.backup))]
	if _hunt_btn != null:
		_hunt_btn.visible = not _in_hunt()
	if _own_all != null:
		_own_all.visible = not _in_hunt()
	_replay.disabled = not can_replay
	_new_seed.disabled = not can_replay
	_refresh_upgrades()
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
