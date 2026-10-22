class_name HHAbilityInfo
## Lane TT (H480-H489): what each ability does, for the lobby's tooltips
## ("I need tooltips on abilities to check before initiating the fight").
## Pure data, no nodes: `info(weapon, key, element, backup, upgrades)`
## returns { key, label, title, icon, lines: [{ text, kind }], values,
## sources } for key in KEYS (basic, q, w, e, r, dash, t) or "active" /
## "backup" (the picked elements); `upgrade_info(id)` the same for one
## upgrade; `summary(weapon)` the short kit card the weapon tile shows.
##
## Every number is read live: cooldowns and wind-ups from the weapon's
## skills() / its `_t` (HHTune "<weapon>_*"), damage through HHFormulas.hit
## (before the monster's resistance) or HHFormulas.tile_damage, combo and
## charge multiples from HHWeapons.combo_hit and the weapon's q_mult. The
## only text written here is the one-line "what it's for" (FOR), the
## element line templates (ELEMENT_LINE) and the upgrade number formats
## (UPGRADE_FACTS); the "what it does" line is the weapon's own
## skills().text, the upgrade line HHUpgrades' blurb. `sources` names the
## HHTune key behind each number (test_lobby_tooltips checks them).

const KEYS := ["basic", "q", "w", "e", "r", "dash", "t"]
const LABEL := { "basic": "RMB", "q": "Q", "w": "W", "e": "E", "r": "R", "dash": "Shift", "t": "T", "active": "", "backup": "W" }
const TICK := 30.0

## One plain line on what the ability is for (Claude, decided: H481).
const FOR := {
	"lance": {
		"basic": "Slow, heavy blows from two hexes out; the third in a row is a slam.",
		"q": "Tap to poke and paint; hold to brace and lunge for the big hit.",
		"e": "Raise it just before a blow lands; the counter punishes the hit.",
		"r": "Vault over danger or onto the monster, painting a wide patch.",
	},
	"daggers": {
		"basic": "Fast flicks up close; keep the string going for the leaping finisher.",
		"q": "Paint the ground round you; hold while you walk to grow it.",
		"e": "Your escape and gap-closer: leap out of a telegraph, painting a line.",
		"r": "All-in: stay on the monster, lay both elements, take more damage.",
	},
	"bow": {
		"basic": "Steady damage from seven hexes away; keep your distance.",
		"q": "Paint a long line from range; a full draw pierces everything in a wide band.",
		"e": "Drop a burst where the monster will be: it sees it coming, so lead it.",
		"r": "Untargetable in the air, then a wide storm of element where you land.",
	},
	"any": {
		"w": "Cast the other half of a reaction on the charge you already laid.",
		"dash": "Dodge through a blow: its first instant ignores damage.",
		"t": "Throw it where the party stands: everyone inside heals.",
	},
}

## What the picked elements do on each ability: {a} active, {b} backup.
const ELEMENT_LINE := {
	"lance": {
		"basic": "Lays {a} where each blow lands; the slam lays it round the blow.",
		"q": "Lays {a} on the line; holding makes it stronger and wider.",
		"e": "The counter lays {a} on its line.",
		"r": "Erupts {a} round where you land.",
	},
	"daggers": {
		"basic": "Lays {a} where each blow lands; the finisher lays it round the blow.",
		"q": "Lays {a} round you; a full charge lays it strongest in the middle.",
		"e": "Lays {a} on every hex you cross.",
		"r": "Lays {a}, then {b}, round your feet, turn about.",
	},
	"bow": {
		"basic": "Lays {a} on the hex the arrow hits.",
		"q": "Lays {a} on every hex the arrow passes.",
		"e": "Bursts {a} where it lands.",
		"r": "Rains {a} over the whole downfall.",
	},
	"any": {
		"w": "{a} becomes your backup and {b} your active element.",
	},
}

## Each upgrade's live numbers: [format, [[source, unit], ...]]. A source is a
## weapon TUNE key "<weapon>:<key>" (read through that weapon's _t) or
## "upgrade:<key>" (HHWeapons' "any" table). Units: "s" ticks shown in
## seconds, "n" a whole number, "pct" a percent, "stagger" a 0..1 strength
## shown as the hold it buys (HHFormulas.stagger_ticks).
const UPGRADE_FACTS := {
	"exchange_immune": ["Immune for {0}", [["upgrade:exchange_immune_ticks", "s"]]],
	"exchange_burst": ["Radius {0} round you, strength {1}", [["upgrade:exchange_burst_radius", "n"], ["upgrade:exchange_burst_steps", "n"]]],
	"energized_double": ["Strength {0} on a tap's line", [["bow:up_q_double_steps", "n"]]],
	"arcing_twice": ["Six bomblets {0} later, {1} max HP each", [["bow:up_e_echo_ticks", "s"], ["bow:up_e_echo_pct", "pct"]]],
	"daggerleap_homing": ["{0} knives, {1} damage each, home within {2} hexes", [["daggers:up_e_homing_count", "n"], ["daggers:up_e_homing_dmg", "n"], ["daggers:up_e_homing_range", "n"]]],
	"pierce_wide": ["{0} hexes wide", [["lance:up_q_width", "n"]]],
	"guard_stagger": ["The counter staggers for {0}", [["lance:up_e_stagger", "stagger"]]],
	"eruption_twice": ["Aftershock {0} later, {1} max HP", [["lance:up_r_echo_ticks", "s"], ["lance:up_r_echo_pct", "pct"]]],
	"flourish_twin": ["Backup at strength {0} on the outer ring", [["daggers:up_q_twin_steps", "n"]]],
	"knifedance_long": ["The dance lasts {0}", [["daggers:up_r_long_ticks", "s"]]],
	"arrowstorm_glaze": ["Ice at strength {0} over the downfall", [["bow:up_r_glaze_steps", "n"]]],
	"potion_cleanse": ["Clears burn, poison, slow and paralysis", []],
}


# ------------------------------------------------------------------ numbers

## A weapon number through the weapon's own reader (HHTune "<weapon>_<key>";
## the lance's base keys live in HHTune itself under the same names).
static func wv(weapon: String, key: String) -> float:
	var s := HHWeapons.script(weapon)
	return float(s._t(key)) if s != null else 0.0


## The HHTune key `wv` reads.
static func wkey(weapon: String, key: String) -> String:
	return "%s_%s" % [weapon, key]


## Ticks as seconds: "3 s", "1.5 s", "0.33 s".
static func secs(ticks: float) -> String:
	var s := ticks / TICK
	if absf(s - roundf(s)) < 0.005:
		return "%d s" % int(roundf(s))
	if absf(s * 10.0 - roundf(s * 10.0)) < 0.05:
		return "%.1f s" % s
	return "%.2f s" % s


## Seconds as text (for keys already in seconds).
static func secs_s(s: float) -> String:
	return secs(s * TICK)


## A blow's damage as the sim deals it before resistance (HHFormulas.hit).
static func blow(base: float, mult: float = 1.0) -> int:
	return int(HHFormulas.hit(base * mult, 1.0, 0.0).value)


static func _facts(parts: Array) -> String:
	return "  ·  ".join(parts.filter(func(p): return str(p) != ""))


# ------------------------------------------------------------------ abilities

## The tooltip for one ability of `weapon` (or "active" / "backup").
## `upgrades`: the slotted map { skill: [ids] } (cfg.upgrades).
static func info(weapon: String, key: String, element: String, backup: String, upgrades: Dictionary = {}) -> Dictionary:
	var out := { "key": key, "label": str(LABEL.get(key, key.to_upper())), "title": "", "icon": HHHud.skill_icon(weapon, key) if key in ["q", "w", "e", "r", "t"] else "",
		"lines": [], "values": {}, "sources": {} }
	var s := HHWeapons.script(weapon)
	if s == null:
		return out
	s._t("q_dmg")                                   # registers the weapon's TUNE with HHTune
	match key:
		"basic": _basic(out, weapon)
		"q": _q(out, weapon)
		"w": _w(out, weapon)
		"e", "r": _er(out, weapon, key)
		"dash": _dash(out)
		"t": _potion(out)
		"active", "backup": return element_info(weapon, key, element, backup)
	var does := str((HHWeapons.skills(weapon).get(key, {}) as Dictionary).get("text", "")) if key in ["q", "w", "e", "r"] else ""
	if does != "":
		_line(out, does, "does")
	var use := str((FOR.get(weapon, {}) as Dictionary).get(key, (FOR.any as Dictionary).get(key, "")))
	if use != "":
		_line(out, use, "for")
	var el := str((ELEMENT_LINE.get(weapon, {}) as Dictionary).get(key, (ELEMENT_LINE.any as Dictionary).get(key, "")))
	if el != "":
		_line(out, el.format({ "a": HHRegistry.name_of("element", element), "b": HHRegistry.name_of("element", backup) }), "element")
	var skill := "t" if key == "t" else key
	for id in upgrades.get(skill, []):
		if HHUpgrades.fits(str(id), weapon):
			_line(out, "+ %s: %s" % [HHUpgrades.name_of(str(id)), upgrade_facts(str(id))], "upgrade")
	return out


static func _line(out: Dictionary, text: String, kind: String) -> void:
	(out.lines as Array).append({ "text": text, "kind": kind })


static func _val(out: Dictionary, name: String, value: float, source: String) -> void:
	out.values[name] = value
	out.sources[name] = source


static func _basic(out: Dictionary, w: String) -> void:
	out.title = "Basic attack"
	var dmg := HHWeapons.basic_damage(w)
	_val(out, "damage", dmg, wkey(w, "basic_dmg"))
	_val(out, "windup", HHWeapons.basic_windup(w), wkey(w, "basic_windup"))
	_val(out, "every", HHWeapons.basic_ticks(w), wkey(w, "basic_ticks"))
	_val(out, "reach", HHWeapons.reach(w), wkey(w, "reach"))
	_line(out, _facts(["Every %s" % secs(HHWeapons.basic_ticks(w)), "Wind-up %s" % secs(HHWeapons.basic_windup(w)),
		"Damage %d" % blow(dmg), "Reach %d" % HHWeapons.reach(w)]), "facts")
	if HHWeapons.has_combo(w):
		var parts: Array = []
		for step in [1, 2, 3]:
			parts.append(str(blow(dmg, float(HHWeapons.combo_hit(w, step).mult))))
		_line(out, "String of three: %s damage, the third splashes" % " / ".join(parts), "tiers")
	else:
		_line(out, "Right-click a monster to shoot it; no string", "tiers")


static func _q(out: Dictionary, w: String) -> void:
	var s := HHWeapons.script(w)
	var sk: Dictionary = HHWeapons.skills(w).q
	out.title = str(sk.name)
	var dmg := wv(w, "q_dmg")
	_val(out, "cooldown", float(sk.cooldown), wkey(w, "q_cd"))
	_val(out, "windup", wv(w, "q_windup"), wkey(w, "q_windup"))
	_val(out, "damage", dmg, wkey(w, "q_dmg"))
	_line(out, _facts(["Cooldown %s" % secs(sk.cooldown), "Wind-up %s" % secs(wv(w, "q_windup")), "Damage %d" % blow(dmg)]), "facts")
	_line(out, "Hold Q: tap %d  ·  %s: %d  ·  %s: %d, fires itself" % [blow(dmg, s.q_mult(1)),
		secs_s(HHTune.value("charge_l2_s")), blow(dmg, s.q_mult(2)), secs_s(HHTune.value("charge_l3_s")), blow(dmg, s.q_mult(3))], "tiers")


static func _w(out: Dictionary, w: String) -> void:
	var sk: Dictionary = HHWeapons.skills(w).w
	out.title = str(sk.name)
	_val(out, "cooldown", float(sk.cooldown), "exchange_cd")
	_val(out, "windup", HHTune.value("exchange_windup"), "exchange_windup")
	_line(out, _facts(["Cooldown %s" % secs(sk.cooldown), "Wind-up %s" % secs(HHTune.value("exchange_windup")), "No damage"]), "facts")


static func _er(out: Dictionary, w: String, key: String) -> void:
	var sk: Dictionary = HHWeapons.skills(w)[key]
	out.title = str(sk.name)
	_val(out, "cooldown", float(sk.cooldown), wkey(w, key + "_cd"))
	var parts: Array = ["Cooldown %s" % secs(sk.cooldown)]
	match w + "_" + key:
		"lance_e":
			var c := HHTune.value("lance_q_dmg") * HHTune.value("lance_counter_mult")
			_val(out, "duration", HHTune.value("lance_e_ticks"), "lance_e_ticks")
			_val(out, "damage", c, "lance_counter_mult")
			parts += ["Instant", "Blocks %s" % secs(HHTune.value("lance_e_ticks")), "Counter %d" % blow(c)]
		"lance_r":
			_val(out, "air", HHTune.value("lance_r_air_ticks"), "lance_r_air_ticks")
			_val(out, "damage", HHTune.value("lance_r_dmg"), "lance_r_dmg")
			parts += ["Air %s" % secs(HHTune.value("lance_r_air_ticks")), "Damage %d" % blow(HHTune.value("lance_r_dmg")),
				"Range %d" % int(HHTune.value("lance_r_range"))]
		"daggers_e":
			_val(out, "air", wv(w, "e_air_ticks"), wkey(w, "e_air_ticks"))
			_val(out, "damage", wv(w, "e_land_dmg"), wkey(w, "e_land_dmg"))
			parts += ["Air %s" % secs(wv(w, "e_air_ticks")), "Landing %d" % blow(wv(w, "e_land_dmg")), "Range %d" % int(wv(w, "e_range"))]
		"daggers_r":
			_val(out, "duration", wv(w, "r_ticks"), wkey(w, "r_ticks"))
			_val(out, "vuln", wv(w, "r_vuln_pct"), wkey(w, "r_vuln_pct"))
			parts += ["Instant", "Lasts %s" % secs(wv(w, "r_ticks")), "You take +%d%%" % int(wv(w, "r_vuln_pct"))]
		"bow_e":
			var pct := wv(w, "e_dmg_pct")
			_val(out, "flight", wv(w, "e_ticks"), wkey(w, "e_ticks"))
			_val(out, "damage", pct, wkey(w, "e_dmg_pct"))
			parts += ["Lands after %s" % secs(wv(w, "e_ticks")),
				"Damage %s%% max HP (%d solo)" % [str(snappedf(pct, 0.1)), int(HHFormulas.tile_damage(HHTune.value("monster_hp"), pct).value)]]
		"bow_r":
			_val(out, "air", wv(w, "r_air_ticks"), wkey(w, "r_air_ticks"))
			_val(out, "damage", wv(w, "r_dmg"), wkey(w, "r_dmg"))
			parts += ["Air %s" % secs(wv(w, "r_air_ticks")), "Damage %d" % blow(wv(w, "r_dmg")), "Radius %d" % int(wv(w, "r_radius"))]
	_line(out, _facts(parts), "facts")


static func _dash(out: Dictionary) -> void:
	out.title = "Dash"
	_val(out, "charges", HHTune.value("dash_charges"), "dash_charges")
	_val(out, "recharge", HHTune.value("dash_recharge_s"), "dash_recharge_s")
	_val(out, "dodge", HHTune.value("dash_iframe_ticks"), "dash_iframe_ticks")
	_line(out, _facts(["%d charges" % int(HHTune.value("dash_charges")), "One back every %s" % secs_s(HHTune.value("dash_recharge_s")),
		"Dodge %s" % secs(HHTune.value("dash_iframe_ticks")), "%s m" % str(snappedf(HHTune.value("dash_m"), 0.1))]), "facts")
	_line(out, "Toward the cursor; cancels a charging Q (its cooldown still runs).", "does")


static func _potion(out: Dictionary) -> void:
	out.title = "Potion"
	var heal := HHTune.value("player_hp") * HHTune.value("potion_heal_pct") / 100.0
	_val(out, "cooldown", HHTune.value("potion_cd"), "potion_cd")
	_val(out, "windup", HHTune.value("potion_windup"), "potion_windup")
	_val(out, "count", HHTune.value("potion_count"), "potion_count")
	_val(out, "heal", HHTune.value("potion_heal_pct"), "potion_heal_pct")
	_line(out, _facts(["%d per fight" % int(HHTune.value("potion_count")), "Cooldown %s" % secs(HHTune.value("potion_cd")),
		"Wind-up %s" % secs(HHTune.value("potion_windup"))]), "facts")
	_line(out, "Heals %d (%d%%) over %s in a radius-%d zone, up to %d hexes away" % [int(heal), int(HHTune.value("potion_heal_pct")),
		secs_s(HHTune.value("potion_seconds")), int(HHTune.value("potion_radius")), int(HHTune.value("potion_range"))], "does")


## The picked ACTIVE or BACKUP element: its group's copy (H266), its blurb,
## and what it does on this weapon's kit.
static func element_info(weapon: String, slot: String, element: String, backup: String) -> Dictionary:
	var id := element if slot == "active" else backup
	var out := { "key": slot, "label": "W" if slot == "backup" else "", "title": "%s  %s" % [slot.to_upper(), HHRegistry.name_of("element", id)],
		"icon": id, "lines": [], "values": {}, "sources": {}, "element": id }
	var group := ("OPERATOR. " + str(HHLobbyState.OPERATOR_COPY.get(id, ""))) if HHLobbyState.is_operator(id) else ("AXIS. " + HHLobbyState.AXIS_COPY)
	_line(out, group, "tiers")
	_line(out, str(HHRegistry.entry("element", id).get("blurb", "")), "does")
	if slot == "active":
		_line(out, "Your basics, Q, E and R lay it. W swaps it for %s." % HHRegistry.name_of("element", backup), "element")
	else:
		_line(out, "W (Elemental Exchange) swaps it in for %s.%s" % [HHRegistry.name_of("element", element),
			"  Knifedance lays it too." if weapon == "daggers" else ""], "element")
	return out


# ------------------------------------------------------------------ upgrades

## An upgrade's live numbers as one short line.
static func upgrade_facts(id: String) -> String:
	var spec: Array = UPGRADE_FACTS.get(id, ["", []])
	var vals: Array = []
	for src in spec[1]:
		var v := upgrade_value(str(src[0]))
		match str(src[1]):
			"s": vals.append(secs(v))
			"pct": vals.append("%s%%" % str(snappedf(v, 0.1)))
			"stagger": vals.append(secs(HHFormulas.stagger_ticks(v).value))
			_: vals.append(str(int(roundf(v))))
	return str(spec[0]).format(vals)


## One upgrade source's live value ("bow:up_e_echo_pct", "upgrade:exchange_immune_ticks").
static func upgrade_value(src: String) -> float:
	var kv := src.split(":")
	if kv[0] == "upgrade":
		return HHWeapons._t(kv[1])
	return wv(kv[0], kv[1])


## The HHTune key behind one upgrade source.
static func upgrade_key(src: String) -> String:
	var kv := src.split(":")
	return "%s_%s" % [kv[0], kv[1]]


## The tooltip for one upgrade: its skill, name, blurb (HHUpgrades), live
## numbers, and who drops it.
static func upgrade_info(id: String, owned: bool = true) -> Dictionary:
	var row: Dictionary = HHUpgrades.TABLE.get(id, {})
	var skill := str(row.get("skill", ""))
	var out := { "key": "up:" + id, "label": skill.to_upper(), "title": HHUpgrades.name_of(id), "icon": "", "lines": [], "values": {}, "sources": {} }
	for src in (UPGRADE_FACTS.get(id, ["", []]) as Array)[1]:
		_val(out, str(src[0]), upgrade_value(str(src[0])), upgrade_key(str(src[0])))
	_line(out, upgrade_facts(id), "facts")
	_line(out, HHUpgrades.blurb_of(id), "does")
	var drops := ", ".join((row.get("drops_from", []) as Array).map(func(m): return HHRegistry.name_of("monster", str(m))))
	_line(out, ("Slots into %s on any weapon. " % skill.to_upper() if str(row.get("weapon", "")) == "any" else "")
		+ ("Drops from %s." % drops if not owned else "Owned: tick to slot."), "for")
	return out


# ------------------------------------------------------------------ the weapon card

## The weapon tile's hover card: one short line per ability, live numbers.
static func summary(weapon: String) -> Dictionary:
	var out := { "key": "weapon:" + weapon, "label": "", "title": HHRegistry.name_of("weapon", weapon), "icon": "", "lines": [], "values": {}, "sources": {} }
	if HHWeapons.script(weapon) == null:
		return out
	var sk := HHWeapons.skills(weapon)
	var dmg := HHWeapons.basic_damage(weapon)
	_line(out, "Basic   %d every %s, reach %d%s" % [blow(dmg), secs(HHWeapons.basic_ticks(weapon)), HHWeapons.reach(weapon),
		", a string of three" if HHWeapons.has_combo(weapon) else ""], "facts")
	for key in ["q", "e", "r"]:
		var i := info(weapon, key, "fire", "water")
		var bits := ""
		if (i.values as Dictionary).has("damage"):
			var d: float = i.values.damage
			if weapon == "bow" and key == "e":
				bits = "  ·  %s%% max HP" % str(snappedf(d, 0.1))
			elif weapon == "lance" and key == "e":
				bits = "  ·  counter %d" % blow(d)
			elif key == "q":
				bits = "  ·  %d, full charge %d" % [blow(d), blow(d, HHWeapons.script(weapon).q_mult(3))]
			else:
				bits = "  ·  %d" % blow(d)
		_line(out, "%s   %s  ·  %s%s" % [key.to_upper(), str(sk[key].name), secs(float(sk[key].cooldown)), bits], "facts")
	_line(out, "Pick it, then hover ABILITIES for each one.", "for")
	return out
