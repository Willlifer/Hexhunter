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

## The content lives under a CanvasLayer so it fills the viewport whatever
## the parent is (a shell Node has no size for anchors to follow).
func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 0.92)
	sb.border_color = Color(0.85, 0.72, 0.4) if summary.won else Color(0.6, 0.2, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(620, 0)
	panel.add_child(col)
	var verdict := HHHuntKit.label(str(summary.verdict), 72, Color(1.0, 0.85, 0.4) if summary.won else Color(0.95, 0.35, 0.3))
	col.add_child(verdict)
	var sub := HHHuntKit.label("%s in %s" % [HHHuntFlow.display_name(str(cfg.get("monster", ""))), HHHuntFlow.display_name(str(cfg.get("arena", "")))], 22, Color(0.85, 0.85, 0.85))
	col.add_child(sub)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 36)
	col.add_child(stats)
	_stat(stats, "TIME", "%d:%02d" % [int(summary.seconds) / 60, int(summary.seconds) % 60])
	_stat(stats, "DEALT", _num(float(summary.dealt)))
	_stat(stats, "TAKEN", _num(float(summary.taken)))
	_stat(stats, "HP LEFT", "%d%%" % int(round(100.0 * float(summary.hp) / maxf(1.0, float(summary.max_hp)))))
	var dl := HHHuntKit.label("DROPS" if summary.won else "NO SPOILS", 18, Color(0.7, 0.7, 0.7))
	col.add_child(dl)
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 12)
	col.add_child(cards)
	if drops.is_empty():
		var none := HHHuntKit.label("(no drops yet)" if summary.won else "The monster keeps its hide this time.", 18, Color(0.6, 0.6, 0.6))
		cards.add_child(none)
	for id in drops:
		cards.add_child(_card(str(id)))
	var btn := Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(200, 44)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(_continue)
	var bc := CenterContainer.new()
	bc.add_child(btn)
	col.add_child(bc)
	var hint := HHHuntKit.label("Enter / Space: continue to the map", 14, Color(0.55, 0.55, 0.55))
	col.add_child(hint)


func _stat(row: HBoxContainer, title: String, value: String) -> void:
	var v := VBoxContainer.new()
	v.add_child(HHHuntKit.label(value, 34))
	v.add_child(HHHuntKit.label(title, 13, Color(0.65, 0.65, 0.65)))
	row.add_child(v)


func _card(id: String) -> Control:
	var t := card_text(id)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.14, 0.1, 1.0)
	sb.border_color = Color(0.85, 0.72, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(170, 110)
	var v := VBoxContainer.new()
	p.add_child(v)
	var head := str(t.name) + (("  [%s]" % str(t.skill)) if str(t.skill) != "" else "")
	v.add_child(HHHuntKit.label(head, 18, Color(1.0, 0.9, 0.6)))
	var blurb := HHHuntKit.label(str(t.blurb), 13, Color(0.8, 0.8, 0.8))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(150, 0)
	v.add_child(blurb)
	return p


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
