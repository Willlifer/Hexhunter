class_name HHResults
extends Control
## The results screen (Lane H, H48): VICTORY or FALLEN over a dimmed
## backdrop, the fight's time and damage dealt / taken, the drops as cards
## (name + blurb from HHUpgrades.TABLE when Lane U has merged, else the id),
## and Continue (click, Enter or Space) -> finished({ result: "continue" }).
##
## setup(cfg) takes { cfg: launch cfg, fight: the fight's finished payload
## { result, cfg, ticks, hp, monster_hp, ... } }. On a win it rolls
## HHDrops.roll(monster, rng) when that class exists and records the drops
## and the hunt in HHSave when that exists; both are found by class name,
## so the screen runs alone before either lane lands. `summarize()` is
## pure for tests.

signal finished(result: Dictionary)

const TICK := 1.0 / 30.0

var cfg := {}
var fight := {}
var summary := {}
var drops: Array = []
var drops_source: Variant = null        ## an object with roll(monster, rng); null = look up HHDrops
var save_source: Variant = null         ## an object with load_or_new(); null = look up HHSave
var record_run := true                  ## false: a preview that must not add to the run history
var _injected := false
var _setup_done := false
var _done := false


## Verdict and numbers from a fight payload. Max HPs come from the payload
## when the fight sends them, else from HHTune.
static func summarize(f: Dictionary) -> Dictionary:
	var verdict := str(f.get("result", "abort"))
	var ticks := int(f.get("ticks", 0))
	var hp := float(f.get("hp", 0.0))
	var mhp := float(f.get("monster_hp", 0.0))
	var max_hp := float(f.get("max_hp", HHTune.value("player_hp")))
	var mmax := float(f.get("monster_max_hp", HHTune.value("monster_hp")))
	return {
		"won": verdict == "win",
		"verdict": { "win": "VICTORY", "fallen": "FALLEN", "dead": "FALLEN" }.get(verdict, "ABANDONED"),
		"seconds": ticks * TICK,
		"dealt": maxf(0.0, mmax - mhp),
		"taken": maxf(0.0, max_hp - hp),
		"hp": hp, "max_hp": max_hp, "monster_hp": mhp, "monster_max_hp": mmax,
	}


## Tests: hand in fake HHDrops / HHSave stand-ins (null = "that lane is missing").
func inject(p_drops: Variant, p_save: Variant) -> void:
	drops_source = p_drops
	save_source = p_save
	_injected = true


func setup(p_cfg: Dictionary) -> void:
	if _setup_done:
		return
	_setup_done = true
	if p_cfg.has("fight"):
		cfg = p_cfg.get("cfg", {})
		fight = p_cfg.fight
	else:                                                  # a raw fight payload is fine too
		fight = p_cfg
		cfg = p_cfg.get("cfg", {})
	summary = summarize(fight)
	if not _injected:
		var ds := HHHuntFlow.script_named("HHDrops")
		drops_source = ds
		var ss := HHHuntFlow.script_named("HHSave")
		save_source = ss
	var sv: Variant = _load_save()
	if summary.won:
		drops = _roll(sv)
	_record(sv)
	if record_run and not cfg.is_empty():                  # L-19: the lobby's run history (Lane UI)
		HHLobbyState.record_run(HHLobbyState.run_entry(fight, cfg))
	_build()


func _load_save() -> Variant:
	if save_source == null or not (save_source as Object).has_method("load_or_new"):
		return null
	return save_source.load_or_new()


## R-U2: HHDrops.roll(monster, rng, weapon, save.owned) with a seeded rng
## (the launch seed + ticks: the fight payload carries no sim rng, and a
## replayed fight then rolls the same); [] when the class is missing.
func _roll(sv: Variant) -> Array:
	if drops_source == null or not (drops_source as Object).has_method("roll"):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("drops-%s-%d-%d" % [str(cfg.get("monster", "")), int(cfg.get("seed", 1)), int(fight.get("ticks", 0))])
	var who := str(fight.get("local_id", cfg.get("local_id", "")))
	if str(cfg.get("net", "solo")) in ["host", "client"] and who != "":   # H916: each hunter in a party rolls its own drops
		rng.seed = hash("drops-%s-%d-%d-%s" % [str(cfg.get("monster", "")), int(cfg.get("seed", 1)), int(fight.get("ticks", 0)), who])
	var owned: Array = []
	if sv != null:
		var o: Variant = sv.get("owned") if sv is Object else (sv as Dictionary).get("owned")
		if o is Array:
			owned = o
	var got: Variant = drops_source.roll(str(cfg.get("monster", "")), rng, str(cfg.get("weapon", "")), owned)
	var out: Array = []
	if got is Array:
		for id in got:
			out.append(str(id))
	return out


## R-U2: save.own(id) per drop, save.record_hunt(...), save.save(). A save
## object without those methods (or a plain dictionary) gets its `owned` /
## `hunts` arrays appended to instead.
func _record(sv: Variant) -> void:
	if sv == null:
		return
	var monster := str(cfg.get("monster", ""))
	var arena := str(cfg.get("arena", ""))
	var weapon := str(cfg.get("weapon", ""))
	var verdict := str(fight.get("result", ""))
	var is_obj := sv is Object
	if is_obj and sv.has_method("own"):
		for id in drops:
			sv.own(str(id))
	else:
		var owned: Variant = sv.get("owned") if is_obj else (sv as Dictionary).get("owned")
		if owned is Array:
			for id in drops:
				if not id in owned:
					owned.append(id)
	if is_obj and sv.has_method("record_hunt"):
		sv.record_hunt(monster, arena, weapon, verdict, float(summary.seconds))
	else:
		var hunts: Variant = sv.get("hunts") if is_obj else (sv as Dictionary).get("hunts")
		if hunts is Array:
			hunts.append({ "monster": monster, "arena": arena, "seed": int(cfg.get("seed", 1)), "weapon": weapon,
				"result": verdict, "ticks": int(fight.get("ticks", 0)), "drops": drops.duplicate() })
	if is_obj and sv.has_method("save"):
		sv.save()


## Name and blurb for an upgrade id from HHUpgrades.TABLE, else the id.
static func card_text(id: String) -> Dictionary:
	var up := HHHuntFlow.script_named("HHUpgrades")
	if up != null:
		var table: Variant = up.get("TABLE")
		if table is Dictionary and table.has(id):
			var row: Dictionary = table[id]
			return { "name": str(row.get("name", id)), "blurb": str(row.get("blurb", "")), "skill": str(row.get("skill", "")).to_upper() }
	return { "name": id.capitalize(), "blurb": "", "skill": "" }


# ------------------------------------------------------------------ build

## Visual pass (Lane UI, H809, H812): the HUD's language. A plate with gold trims
## under a portrait medallion (the monster's thumbnail), the verdict slammed
## in on a banner, four framed stat tiles, and the drop cards: each a plate
## with the skill's HUD icon in the cast element, the skill letter, the name
## and blurb, dealt one after another with a flash. Times live in REVEAL.
const REVEAL := { "verdict": 0.0, "stats": 0.35, "drops": 0.75, "drop_step": 0.3, "slam_s": 0.3, "card_s": 0.35 }
const CARD_SIZE := Vector2(210, 140)
const PLATE_W := 820.0

var _t := 0.0
var _anim: Array = []            # [{ node, at, dur, kind }] driven by `_process`
var _verdict_node: Control = null


## The content lives under a CanvasLayer so it fills the viewport whatever
## the parent is (a shell Node has no size for anchors to follow).
func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = HHLobby.make_theme()
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.02, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var won := bool(summary.won)
	var accent := HHHud.GOLD if won else Color(0.86, 0.3, 0.26)
	var panel := PlateBox.new()
	panel.accent = accent
	panel.custom_minimum_size = Vector2(PLATE_W, 0)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(col)
	var medal := Medal.new()
	medal.tex = HHHud.thumb("monster", str(cfg.get("monster", "")))
	medal.ring = accent
	medal.grey = not won
	medal.custom_minimum_size = Vector2(0, 128)
	col.add_child(medal)
	var verdict := HHHuntKit.label(str(summary.verdict), 76, Color(1.0, 0.86, 0.45) if won else Color(0.95, 0.34, 0.28))
	verdict.add_theme_font_override("font", HHHud.serif())
	verdict.add_theme_constant_override("outline_size", 10)
	verdict.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.0, 0.95))
	col.add_child(verdict)
	_verdict_node = verdict
	_animate(verdict, REVEAL.verdict, REVEAL.slam_s, "slam")
	var sub := HHHuntKit.label("%s in %s" % [HHHuntFlow.display_name(str(cfg.get("monster", ""))), HHHuntFlow.display_name(str(cfg.get("arena", "")))], 22, Color(1, 0.94, 0.84))
	sub.add_theme_font_override("font", HHHud.serif())
	col.add_child(sub)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 12)
	col.add_child(stats)
	_stat(stats, "TIME", "%d:%02d" % [int(summary.seconds) / 60, int(summary.seconds) % 60])
	_stat(stats, "DEALT", _num(float(summary.dealt)))
	_stat(stats, "TAKEN", _num(float(summary.taken)))
	_stat(stats, "HP LEFT", "%d%%" % int(round(100.0 * float(summary.hp) / maxf(1.0, float(summary.max_hp)))))
	_animate(stats, REVEAL.stats, 0.3, "fade")
	col.add_child(_rule("DROPS" if won else "NO SPOILS", accent))
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 14)
	cards.custom_minimum_size = Vector2(0, CARD_SIZE.y)
	col.add_child(cards)
	if drops.is_empty():
		var none := HHHuntKit.label("(no drops yet)" if won else "The monster keeps its hide this time.", 18, Color(1, 0.94, 0.84, 0.55))
		none.add_theme_font_override("font", HHHud.serif())
		cards.add_child(none)
		_animate(none, REVEAL.drops, 0.4, "fade")
	for i in drops.size():
		var card := _card(str(drops[i]))
		cards.add_child(card)
		_animate(card, REVEAL.drops + i * REVEAL.drop_step, REVEAL.card_s, "deal")
	var btn := Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(220, 44)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(_continue)
	var bc := CenterContainer.new()
	bc.add_child(btn)
	col.add_child(bc)
	var hint := HHHuntKit.label("Enter / Space: continue to the map", 14, Color(1, 0.94, 0.84, 0.45))
	col.add_child(hint)
	_apply_anim()


## A section rule: gold line, the title in serif caps, gold line.
func _rule(title: String, accent: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	for k in 3:
		if k == 1:
			var l := HHHuntKit.label(title, 15, accent)
			l.add_theme_font_override("font", HHHud.serif())
			h.add_child(l)
		else:
			var line := ColorRect.new()
			line.color = Color(accent.r, accent.g, accent.b, 0.6)
			line.custom_minimum_size = Vector2(0, 1)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(line)
	return h


func _stat(row: HBoxContainer, title: String, value: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.025, 0.02, 0.75)
	sb.border_color = HHHud.GOLD_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(150, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var val := HHHuntKit.label(value, 32, Color(1, 0.97, 0.9))
	val.add_theme_font_override("font", HHHud.serif())
	v.add_child(val)
	v.add_child(HHHuntKit.label(title, 12, Color(HHHud.GOLD.r, HHHud.GOLD.g, HHHud.GOLD.b, 0.85)))
	row.add_child(p)


func _card(id: String) -> Control:
	var t := card_text(id)
	var c := DropCard.new()
	c.title = str(t.name)
	c.blurb = str(t.blurb)
	c.skill = str(t.skill)
	c.weapon = str(cfg.get("weapon", ""))
	c.element = str(cfg.get("element", "fire"))
	c.custom_minimum_size = CARD_SIZE
	c.tooltip_text = "%s: %s" % [t.name, t.blurb]
	return c


func _animate(node: Control, at: float, dur: float, kind: String) -> void:
	_anim.append({ "node": node, "at": at, "dur": dur, "kind": kind })


func _process(delta: float) -> void:
	if _anim.is_empty():
		return
	_t += delta
	_apply_anim()


## Every animated node at time `_t` (a function of time only, so a capture
## and a test can jump with `reveal_at(t)`).
func _apply_anim() -> void:
	for a in _anim:
		var n: Control = a.node
		if not is_instance_valid(n):
			continue
		var k := clampf((_t - float(a.at)) / maxf(0.01, float(a.dur)), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		n.pivot_offset = n.size * 0.5
		match str(a.kind):
			"slam":
				n.modulate.a = e
				n.scale = Vector2.ONE * lerpf(1.8, 1.0, e)
			"deal":
				n.modulate.a = e
				n.scale = Vector2.ONE * lerpf(0.6, 1.0, e)
				if n is DropCard:
					(n as DropCard).flash = clampf(1.0 - absf(k - 0.75) * 4.0, 0.0, 1.0)
					n.queue_redraw()
			_:
				n.modulate.a = e


## Jump the reveal to `t` seconds (tests, captures).
func reveal_at(t: float) -> void:
	_t = t
	_apply_anim()


## The card's backing plate (HHHud.plate with an accent rule).
class PlateBox:
	extends PanelContainer
	var accent := HHHud.GOLD

	func _init() -> void:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 34
		sb.content_margin_right = 34
		sb.content_margin_top = 22
		sb.content_margin_bottom = 22
		add_theme_stylebox_override("panel", sb)

	func _draw() -> void:
		var pt := HHHud.Paint.new(get_canvas_item())
		var r := Rect2(Vector2(0, 52), size - Vector2(0, 52))
		HHHud.plate(pt, r, true, true)
		pt.frame(r.grow(-6.0), Color(accent.r, accent.g, accent.b, 0.35), 1.0)


## The monster medallion: a gold socket with the thumbnail cropped round.
class Medal:
	extends Control
	var tex: Texture2D = null
	var ring := HHHud.GOLD
	var grey := false

	func _draw() -> void:
		var pt := HHHud.Paint.new(get_canvas_item())
		var c := Vector2(size.x * 0.5, 62.0)
		var r := 58.0
		for i in 3:
			pt.ring(c, r + 6.0 + i * 3.0, Color(ring.r, ring.g, ring.b, 0.35 - i * 0.1), 2.0)
		HHHud.socket(pt, c, r + 4.0, ring)
		pt.circle(c, r, Color(0.12, 0.1, 0.09))
		HHHud.thumb_disc(pt, tex, c, r, 0.72)
		if grey:
			pt.circle(c, r, Color(0.05, 0.0, 0.0, 0.45))
		pt.ring(c, r, Color(0, 0, 0, 0.8), 2.0)


## A drop card: plate, the skill's HUD icon in the cast element with its
## letter, the upgrade's name and blurb; `flash` brightens it as it lands.
class DropCard:
	extends Control
	var title := ""
	var blurb := ""
	var skill := ""
	var weapon := ""
	var element := "fire"
	var flash := 0.0

	func _draw() -> void:
		var pt := HHHud.Paint.new(get_canvas_item())
		var r := Rect2(Vector2.ZERO, size)
		pt.rect(r.grow(2.0), Color(0, 0, 0, 0.9))
		pt.vgrad(r, Color(0.17, 0.14, 0.1), Color(0.06, 0.05, 0.04))
		var el := HHLook.element_color(element)
		pt.rect(Rect2(0, 0, size.x, 3), el)
		var icon_r := Rect2(12, 14, 52, 52)
		var key := skill.to_lower()
		var icon := HHHud.skill_icon(weapon, key) if key != "" else ""
		HHHud.slot(pt, icon_r, icon, HHHud._skill_bg(el) if key != "t" else Color(0.62, 0.1, 0.14), key)
		var serif := HHHud.serif()
		var x := icon_r.end.x + 10.0
		var words := title.split(" ")
		var line1 := title
		var line2 := ""
		if pt.text_width(title, 17, serif) > size.x - x - 8.0 and words.size() > 1:
			line1 = " ".join(words.slice(0, words.size() - 1))
			line2 = words[words.size() - 1]
		pt.text(Vector2(x, 34), line1, 17, Color(1, 0.88, 0.55), 0, 3, serif)
		if line2 != "":
			pt.text(Vector2(x, 54), line2, 17, Color(1, 0.88, 0.55), 0, 3, serif)
		if skill != "":
			pt.text(Vector2(x, 72 if line2 != "" else 54), "%s skill" % skill.to_upper(), 12, Color(el.lightened(0.45)), 0, 3)
		# the blurb, word-wrapped under the icon
		var font := ThemeDB.fallback_font
		var y := 96.0
		var line := ""
		for w in blurb.split(" "):
			var trial := w if line == "" else line + " " + w
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > size.x - 24.0 and line != "":
				pt.text(Vector2(12, y), line, 12, Color(1, 0.96, 0.9, 0.85), 0, 2, font)
				y += 15.0
				line = w
			else:
				line = trial
			if y > size.y - 6.0:
				break
		if line != "" and y <= size.y - 6.0:
			pt.text(Vector2(12, y), line, 12, Color(1, 0.96, 0.9, 0.85), 0, 2, font)
		pt.frame(r, HHHud.GOLD, 1.0)
		if flash > 0.0:
			pt.rect(r, Color(1, 0.95, 0.8, 0.45 * flash))
			for i in 3:
				pt.frame(r.grow(2.0 + i * 2.0), Color(1, 0.88, 0.5, (0.6 - i * 0.18) * flash), 2.0)


static func _num(v: float) -> String:
	if v >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(round(v)))


func _continue() -> void:
	if _done:
		return
	_done = true
	finished.emit({ "result": "continue", "drops": drops.duplicate(), "summary": summary })


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_continue()
