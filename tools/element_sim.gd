extends "res://tools/difficulty_baseline.gd"
## Lane EL (spec sections 1-3, 2.4): the element-pair harness. Solo seeded bot
## fights per element pair x monster x weapon x tier, with the damage the
## monster took split by cash-in, so a Thunder retune can be measured as "one
## cash-in among four". The bot is difficulty_baseline's (coop_bot's: attack,
## cast r / q / e on cooldown, step out of a telegraph about to land, drink
## under 40%) plus one habit: it lays its ACTIVE element for `--swap` basics,
## then swaps (W) and cashes in with the BACKUP for as many, and so on. Pairs
## are unordered; the active element is the one first in PAIR_ORDER (axis
## before operator), so fire/thunder lays fire and detonates with thunder.
## Headless, pure sim:
##   godot --headless --path . --script res://tools/element_sim.gd -- [--pairs all|fire/thunder,water/ice] [--monsters a,b]
##       [--weapons lance,bow,daggers] [--tiers easy,normal] [--seeds 4] [--cap 240] [--swap 3] [--json out.json]
##   godot --headless --path . --script res://tools/element_sim.gd -- --merge a.json,b.json [--before b1.json,b2.json] --md design/elements/sim.md
## --merge without --before writes one table; with --before it writes the
## before / after comparison (both sets of rows must cover the same cells).

const PAIR_ORDER := ["fire", "water", "light", "dark", "thunder", "ice", "wind"]
## Cash-in groups: hurt causes on the monster -> the column they count in.
const GROUPS := {
	"detonate": "detonate", "shatter": "shatter", "overfreeze": "shatter (old overfreeze)",
	"overheat": "overheat", "geyser": "geyser", "glint": "glint", "flux": "flux",
	"steam": "steam", "eclipse": "eclipse",
	"fire": "ground", "burn": "ground", "dark": "ground", "poison": "ground", "fire_cross": "ground",
}
const COLUMNS := ["weapon", "ground", "detonate", "shatter", "swirl", "overheat", "geyser", "glint", "flux", "steam", "eclipse"]
var swap_every := 3


func _main() -> void:
	var args := OS.get_cmdline_user_args()
	if "--merge" in args:
		var rows := _load_rows(_opt(args, "--merge", ""))
		var md := ""
		if "--before" in args:
			md = compare(_load_rows(_opt(args, "--before", "")), rows, _opt(args, "--note", ""))
		else:
			md = pair_report(rows, _opt(args, "--note", ""))
		var out := _opt(args, "--md", "")
		if out != "":
			var f := FileAccess.open(out, FileAccess.WRITE)
			f.store_string(md)
			f.close()
			print("wrote ", out)
		else:
			print(md)
		quit(0)
		return
	var monsters := _opt(args, "--monsters", "swampfang,colambros,rimeslithe,spirewalker").split(",")
	var weapons := _opt(args, "--weapons", "lance,bow,daggers").split(",")
	var tiers := _opt(args, "--tiers", "easy,normal").split(",")
	var seeds := int(_opt(args, "--seeds", "4"))
	var cap := int(float(_opt(args, "--cap", "240")) * 30.0)
	swap_every = int(_opt(args, "--swap", "3"))
	var pairs := all_pairs() if _opt(args, "--pairs", "all") == "all" else Array(_opt(args, "--pairs", "").split(","))
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	for pr in pairs:
		var ab: PackedStringArray = str(pr).split("/")
		pair = [ab[0], ab[1]]
		for monster in monsters:
			for weapon in weapons:
				for tier in tiers:
					for s in range(1, seeds + 1):
						var r := run_pair(monster, weapon, tier, s, cap)
						rows.append(r)
				print("%s %s %s: done [%.0f s wall]" % [pr, monster, ",".join(weapons), (Time.get_ticks_msec() - t0) / 1000.0])
	var out_json := _opt(args, "--json", "")
	if out_json != "":
		var f := FileAccess.open(out_json, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, " "))
		f.close()
		print("wrote ", out_json)
	else:
		print(pair_report(rows, ""))
	quit(0)


func _load_rows(list: String) -> Array:
	var rows: Array = []
	for p in list.split(","):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Array:
			rows.append_array(parsed)
	return rows


## The 21 unordered pairs, active first by PAIR_ORDER.
static func all_pairs() -> Array:
	var out: Array = []
	for i in PAIR_ORDER.size():
		for j in range(i + 1, PAIR_ORDER.size()):
			out.append("%s/%s" % [PAIR_ORDER[i], PAIR_ORDER[j]])
	return out


## One solo fight with the swapping bot; the row carries damage by cause.
func run_pair(monster: String, weapon: String, tier: String, seed: int, cap: int) -> Dictionary:
	var arena := biome_arena(str(MONSTER_BIOME[monster]))
	var s := HHSim.new(arena, seed, tier)
	s.add_player("p1", arena.spawns.player[0], str(pair[0]), str(pair[1]), weapon)
	var brain: Object = load("res://src/monster/%s.gd" % monster).new()
	var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
	var m := s.add_monster(monster, arena.spawns.monster, HHTune.value("monster_hp"), 2, allowed)
	s.brains[monster] = brain
	if brain.has_method("setup"):
		brain.setup(s, m)
	var bot := { "dodging": 0, "next_cast": 60, "next_rev": 0, "basics": 0 }
	var ids := ["p1"]
	var dmg := {}
	var taken := {}
	var counts := {}
	while s.tick < cap and s.over == "":
		var o := _decide_el(s, s.unit("p1"), m, bot, ids)
		var ev := s.step({ "p1": o } if not o.is_empty() else {})
		for e in ev:
			var t := str(e.type)
			if t in ["detonate", "overheat", "geyser", "glint", "flux", "steam", "eclipse", "shatter", "swirl", "crystal", "overfreeze", "douse", "gale"]:
				counts[t] = int(counts.get(t, 0)) + 1
			if t == "strike" and str(e.id) == "p1" and str(e.get("cause", "")) == "basic":
				bot.basics = int(bot.basics) + 1
			elif t == "swap" and str(e.id) == "p1":
				bot.basics = 0
			elif t == "hurt":
				var cause := str(e.cause)
				if str(e.id) == m.id:
					dmg[cause] = float(dmg.get(cause, 0.0)) + float(e.amount)
				elif str(e.id) == "p1":
					taken[cause] = float(taken.get(cause, 0.0)) + float(e.amount)
	var outcome := s.over if s.over != "" else "timeout"
	return { "monster": monster, "weapon": weapon, "tier": s.difficulty, "seed": seed, "outcome": outcome,
		"seconds": snappedf(s.tick * HHSim.TICK, 0.1), "monster_left_pct": snappedf(100.0 * float(m.hp) / float(m.max_hp), 0.1),
		"cap_s": snappedf(cap * HHSim.TICK, 0.1), "pair": "%s/%s" % [pair[0], pair[1]], "dmg": dmg, "taken": taken, "counts": counts }


## coop_bot's decision, plus the swap habit: after `swap_every` landed basics
## (and not while a telegraph is about to land on it), press W.
func _decide_el(s: HHSim, u: Dictionary, m: Dictionary, b: Dictionary, ids: Array) -> Dictionary:
	if s.alive(u) and not s.held(u) and int(b.basics) >= swap_every and int(u.cooldowns.get("w", 0)) <= 0 and not _threatened(s, u, ids):
		b.basics = 0
		return { "swap": true }
	return _decide(s, u, m, b, ids)


func _threatened(s: HHSim, u: Dictionary, ids: Array) -> bool:
	for tg in s.telegraphs:
		if str(tg.owner) in ids or int(tg.left) > 36:
			continue
		if u.hex in tg.hexes:
			return true
	return false


static func group_of(cause: String) -> String:
	if cause.begins_with("swirl"):
		return "swirl"
	return str(GROUPS.get(cause, "weapon"))


## Damage share by column for a set of rows: { column: fraction }.
static func shares(rows: Array) -> Dictionary:
	var tot := {}
	var all := 0.0
	for r in rows:
		var d: Dictionary = r.get("dmg", {})
		for k in d:
			var g := group_of(str(k))
			if g == "shatter (old overfreeze)":
				g = "shatter"
			tot[g] = float(tot.get(g, 0.0)) + float(d[k])
			all += float(d[k])
	var out := {}
	for g in tot:
		out[g] = float(tot[g]) / maxf(all, 1.0)
	return out


static func _pct(x: float) -> String:
	return "-" if x < 0.0005 else "%d%%" % roundi(100.0 * x)


static func _uniq(rows: Array, key: String) -> Array:
	var out: Array = []
	for r in rows:
		if not str(r[key]) in out:
			out.append(str(r[key]))
	return out


static func _header(rows: Array) -> String:
	var seeds := {}
	var cap := 0.0
	for r in rows:
		seeds[int(r.seed)] = true
		cap = maxf(cap, float(r.get("cap_s", 0.0)))
	return "%d fights: %d pairs x %s x %s x tiers %s, seeds 1-%d, %.0f s cap (timeout = not a win)." % [rows.size(), _uniq(rows, "pair").size(),
		"/".join(_uniq(rows, "monster")), "/".join(_uniq(rows, "weapon")), "/".join(_uniq(rows, "tier")), seeds.size(), cap]


## One run's table: per tier, then per pair with the cash-in shares.
static func pair_report(rows: Array, note: String) -> String:
	var L: Array = [_header(rows)]
	if note != "":
		L.append_array(["", note])
	L.append_array(["", "### Per tier", "", "| Tier | Win rate | Median length | Median win |", "|---|---|---|---|"])
	for t in HHSim.TIERS:
		var sub := rows.filter(func(r): return r.tier == t)
		if not sub.is_empty():
			L.append("| %s | %s |" % [t, _cell(sub)])
	L.append_array(["", "### Per pair (all monsters, weapons and tiers)", "",
		"| Pair | Win rate | Median length | Median win | " + " | ".join(COLUMNS) + " |",
		"|---|---|---|---|" + "---|".repeat(COLUMNS.size())])
	for p in _uniq(rows, "pair"):
		var sub := rows.filter(func(r): return r.pair == p)
		var sh := shares(sub)
		L.append("| %s | %s | %s |" % [p, _cell(sub), " | ".join(COLUMNS.map(func(c): return _pct(float(sh.get(c, 0.0)))))])
	return "\n".join(L) + "\n"


## Before / after: per tier, per tier x monster, then per pair.
static func compare(before: Array, after: Array, note: String) -> String:
	var L: Array = ["BEFORE: " + _header(before), "", "AFTER: " + _header(after)]
	if note != "":
		L.append_array(["", note])
	L.append_array(["", "Cells: win rate (wins/fights) | median fight length | median length of the wins.", "",
		"### Per tier", "", "| Tier | Before | After |", "|---|---|---|"])
	for t in HHSim.TIERS:
		var b := before.filter(func(r): return r.tier == t)
		var a := after.filter(func(r): return r.tier == t)
		if not (a.is_empty() and b.is_empty()):
			L.append("| %s | %s | %s |" % [t, _cell(b), _cell(a)])
	L.append_array(["", "### Per tier and monster", "", "| Monster | Tier | Before | After |", "|---|---|---|---|"])
	for mo in _uniq(after, "monster"):
		for t in HHSim.TIERS:
			var b := before.filter(func(r): return r.tier == t and r.monster == mo)
			var a := after.filter(func(r): return r.tier == t and r.monster == mo)
			if not a.is_empty():
				L.append("| %s | %s | %s | %s |" % [mo, t, _cell(b), _cell(a)])
	L.append_array(["", "### Per element pair (all monsters, weapons, tiers)", "",
		"| Pair | Before | After | Cash-in share before | Cash-in share after |", "|---|---|---|---|---|"])
	for p in _uniq(after, "pair"):
		var b := before.filter(func(r): return r.pair == p)
		var a := after.filter(func(r): return r.pair == p)
		L.append("| %s | %s | %s | %s | %s |" % [p, _cell(b), _cell(a), _share_text(shares(b)), _share_text(shares(a))])
	L.append_array(["", "### Damage share by column, every fight", "", "| Column | Before | After |", "|---|---|---|"])
	var sb := shares(before)
	var sa := shares(after)
	for c in COLUMNS:
		L.append("| %s | %s | %s |" % [c, _pct(float(sb.get(c, 0.0))), _pct(float(sa.get(c, 0.0)))])
	return "\n".join(L) + "\n"


static func _share_text(sh: Dictionary) -> String:
	var parts: Array = []
	for c in COLUMNS:
		if c in ["weapon", "ground"]:
			continue
		if float(sh.get(c, 0.0)) >= 0.005:
			parts.append("%s %s" % [c, _pct(float(sh[c]))])
	return ", ".join(parts) if not parts.is_empty() else "-"
