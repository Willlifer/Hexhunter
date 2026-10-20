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
const ELEM_STEP := 120.0
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


func _build_elements() -> void:
	_row_label(3, ELEM_LABEL_Y - 8)
	_next_label = _label("", Vector2(TILE_X + 10, ELEM_LABEL_Y - 6), 15, HHLobbyDisc.ACTIVE)
	_next_label.position.x = 190
	var rows := HHRegistry.rows("element")
	for j in rows.size():
		var d := HHLobbyDisc.new()
		d.id = str(rows[j].id)
		d.title = str(rows[j].name)
		d.blurb = str(rows[j].blurb)
		d.color = HHLook.element_color(d.id)
		d.position = Vector2(TILE_X + j * ELEM_STEP, ELEM_Y)
		d.size = ELEM_SIZE
		d.pressed.connect(func(disc: HHLobbyDisc): _pick_element(disc.id))
		d.hovered.connect(func(disc: HHLobbyDisc): _ticker.text = "%s: %s   (this click sets the %s element)" % [disc.title, disc.blurb, disc.next_sets])
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
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(_section("LAST RUNS", ""))
	_runs_box = VBoxContainer.new()
	_runs_box.add_theme_constant_override("separation", 2)
	v.add_child(_runs_box)


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
	_label("In the fight: right-click moves / attacks, Q E R cast, W swaps elements, T potion, Esc back here", Vector2(TICKER.position.x, HINT_Y + 6), 14, DIM)


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


## "next click sets the ACTIVE element" / "... BACKUP ..." (the element row's hint).
func next_hint() -> String:
	if state.is_locked("element"):
		return "locked for this hunt"
	return "next click sets the %s element" % ("ACTIVE" if state.element_phase == 0 else "BACKUP")


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
	if _next_label != null:
		_next_label.text = next_hint()
		_next_label.add_theme_color_override("font_color", HHLobbyDisc.ACTIVE if state.element_phase == 0 else HHLobbyDisc.BACKUP)
	for i in _row_labels.size():
		(_row_labels[i] as Label).add_theme_color_override("font_color", HHHud.GOLD if i == state.row else DIM)
	_seed.set_value_no_signal(float(state.cfg.seed))
	_seed.editable = not state.is_locked("seed")
	_pair.text = "%s in %s with the %s\n%s, backup %s" % [
		HHRegistry.name_of("monster", str(state.cfg.monster)), HHRegistry.name_of("arena", str(state.cfg.arena)),
		HHRegistry.name_of("weapon", str(state.cfg.weapon)).to_lower(),
		HHRegistry.name_of("element", str(state.cfg.element)), HHRegistry.name_of("element", str(state.cfg.backup)).to_lower()]
	if _hunt_btn != null:
		_hunt_btn.visible = not _in_hunt()
	if _own_all != null:
		_own_all.visible = not _in_hunt()
	_replay.disabled = not can_replay
	_new_seed.disabled = not can_replay
	_refresh_upgrades()
	_refresh_runs()
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
