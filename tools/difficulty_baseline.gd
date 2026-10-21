extends "res://tools/coop_bot.gd"
## Lane D (H245, spec section 10): win rate and median fight length per
## difficulty tier, per monster and per weapon, from N seeded solo bot fights
## on each monster's biome. The bot is coop_bot.gd's (attack, cast on
## cooldown, step out of a telegraph about to land, drink under 40%), alone:
## the numbers say how the tiers compare for the same simple player, not how
## hard a fight is for a person. Headless, pure sim (no nodes):
##   godot --headless --path . --script res://tools/difficulty_baseline.gd -- [--monsters a,b] [--weapons lance,bow,daggers]
##       [--tiers easy,normal] [--seeds 10] [--cap 300] [--pair fire,water] [--json <file>]
##   godot --headless --path . --script res://tools/difficulty_baseline.gd -- --merge a.json,b.json --md design/difficulty/baseline.md
## --cap is the time limit per fight in seconds (a fight still running then is a
## "timeout": not a win). Runs in parallel by splitting --monsters across
## processes, each with its own --json, then --merge writes the table.

const MONSTER_BIOME := { "swampfang": "pond", "colambros": "caldera", "rimeslithe": "cave", "spirewalker": "glade" }
var pair: Array = ["fire", "water"]   ## the bot's active / backup element (--pair)
var bot_kind := "dodge"               ## --bot dodge (coop_bot's bot) | facetank (H267 / H422: auto attacks only, walks INTO telegraphs)
var dmg_scale := 1.0                  ## --dmg-scale: calibration probe only, scales every monster telegraph's dmg_pct as it is issued


func _initialize() -> void:
	_main.call_deferred()


func _opt(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _main() -> void:
	var args := OS.get_cmdline_user_args()
	if "--merge" in args:
		var rows: Array = []
		for p in _opt(args, "--merge", "").split(","):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Array:
				rows.append_array(parsed)
		var md := report(rows, _opt(args, "--note", ""))
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
	var seeds := int(_opt(args, "--seeds", "10"))
	var cap := int(float(_opt(args, "--cap", "300")) * 30.0)
	pair = Array(_opt(args, "--pair", "fire,water").split(","))
	bot_kind = _opt(args, "--bot", "dodge")
	dmg_scale = float(_opt(args, "--dmg-scale", "1.0"))
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	for monster in monsters:
		for weapon in weapons:
			for tier in tiers:
				for s in range(1, seeds + 1):
					var r := run_one(monster, weapon, tier, s, cap)
					rows.append(r)
					print("[%s %s] %s %s %s seed %d: %s at %.1f s (monster %.0f%% left, hunter %.0f%%)  [%.0f s wall]" % [bot_kind, r.pair, monster, weapon, tier, s, r.outcome, r.seconds, r.monster_left_pct, r.hunter_left_pct, (Time.get_ticks_msec() - t0) / 1000.0])
	var out_json := _opt(args, "--json", "")
	if out_json != "":
		var f := FileAccess.open(out_json, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, " "))
		f.close()
		print("wrote ", out_json)
	else:
		print(report(rows, ""))
	quit(0)


## One solo fight: the bot against `monster` on its biome at `tier`.
func run_one(monster: String, weapon: String, tier: String, seed: int, cap: int) -> Dictionary:
	var arena := biome_arena(str(MONSTER_BIOME[monster]))
	var s := HHSim.new(arena, seed, tier)
	s.add_player("p1", arena.spawns.player[0], str(pair[0]), str(pair[1]), weapon)
	var brain: Object = load("res://src/monster/%s.gd" % monster).new()
	var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
	var m := s.add_monster(monster, arena.spawns.monster, HHTune.value("monster_hp"), 2, allowed)
	HHTierBrain.apply_own_resist(m)                    # H429: as the fight does
	s.brains[monster] = brain
	if brain.has_method("setup"):
		brain.setup(s, m)
	var bot := { "dodging": 0, "next_cast": 60, "next_rev": 0 }
	var ids := ["p1"]
	var scaled := {}
	while s.tick < cap and s.over == "":
		var o := _facetank(s, s.unit("p1"), m) if bot_kind == "facetank" else _decide(s, s.unit("p1"), m, bot, ids)
		s.step({ "p1": o } if not o.is_empty() else {})
		if dmg_scale != 1.0:
			for tg in s.telegraphs:
				if str(tg.owner) == monster and not scaled.has(int(tg.id)):
					scaled[int(tg.id)] = true
					tg.payload["dmg_pct"] = float(tg.payload.get("dmg_pct", 0.0)) * dmg_scale
	var outcome := s.over if s.over != "" else "timeout"
	return { "monster": monster, "weapon": weapon, "tier": s.difficulty, "seed": seed, "outcome": outcome,
		"seconds": snappedf(s.tick * HHSim.TICK, 0.1), "monster_left_pct": snappedf(100.0 * float(m.hp) / float(m.max_hp), 0.1),
		"cap_s": snappedf(cap * HHSim.TICK, 0.1), "pair": "%s/%s" % [pair[0], pair[1]], "bot": bot_kind,
		"hunter_left_pct": snappedf(100.0 * float(s.unit("p1").hp) / float(s.unit("p1").max_hp), 0.1) }


## H422: the author's "easy mode" test bot (H267). It only ever gives the
## attack order on the monster (auto attacks: no Q/W/E/R, no dash, no potion,
## no element swap) and never walks away. When a monster telegraph is shown
## within two steps and it is not already standing in one, it walks INTO it.
func _facetank(s: HHSim, u: Dictionary, m: Dictionary) -> Dictionary:
	if not s.alive(u) or s.held(u):
		return {}
	var danger := {}
	for tg in s.telegraphs:
		if str(tg.owner) != str(m.id):
			continue
		for h in tg.hexes:
			danger[h] = true
	if danger.has(u.hex):
		if not bool(u.attacking) and (u.path as Array).is_empty() and s.targetable(m) and s.in_attack_range(u, m):
			return { "target": m.id, "attack": true }    # in it and in reach: swing from here
		return {}                                        # standing in it: take it
	if not danger.is_empty():
		var blocked := s.blocked_for(u)
		var best: Vector2i = u.hex
		var best_d := 99
		var keys := danger.keys()
		keys.sort()
		for h in keys:
			var d: int = HHHex.distance(u.hex, h)
			if d <= 2 and d < best_d and s.arena.walkable(h) and not blocked.has(h):
				best = h
				best_d = d
		if best != u.hex:
			var path: Array = u.path
			if path.is_empty() or path.back() != best:
				return { "move": best, "move_pos": s.arena.stand(best) }
			return {}
	if s.targetable(m) and (str(u.target) != m.id or not bool(u.attacking)):
		return { "target": m.id, "attack": true }
	return {}


static func median(xs: Array) -> float:
	if xs.is_empty():
		return NAN
	var v := xs.duplicate()
	v.sort()
	var n := v.size()
	return float(v[n / 2]) if n % 2 == 1 else (float(v[n / 2 - 1]) + float(v[n / 2])) * 0.5


static func _cell(rows: Array) -> String:
	var n := rows.size()
	if n == 0:
		return "-"
	var wins := rows.filter(func(r): return str(r.outcome) == "win")
	var lens := rows.map(func(r): return float(r.seconds))
	var wl := wins.map(func(r): return float(r.seconds))
	return "%d%% (%d/%d) | %.1f s | %s" % [roundi(100.0 * wins.size() / n), wins.size(), n, median(lens),
		("%.1f s" % median(wl)) if not wl.is_empty() else "-"]


## The markdown table: per tier (all fights), per tier x monster, and per tier x monster x weapon.
static func report(rows: Array, note: String) -> String:
	var tiers: Array = []
	var monsters: Array = []
	var weapons: Array = []
	for r in rows:
		for pair in [[tiers, r.tier], [monsters, r.monster], [weapons, r.weapon]]:
			if not str(pair[1]) in pair[0]:
				(pair[0] as Array).append(str(pair[1]))
	var tier_order := HHSim.TIERS.filter(func(t): return t in tiers)
	var L: Array = []
	var seeds := {}
	var pairs := {}
	var cap := 0.0
	for r in rows:
		seeds[int(r.seed)] = true
		pairs[str(r.get("pair", "fire/water"))] = true
		cap = maxf(cap, float(r.get("cap_s", 0.0)))
	var bots := {}
	for r in rows:
		bots[str(r.get("bot", "dodge"))] = true
	L.append("Solo bot (%s; tools/difficulty_baseline.gd), each monster on its biome, element pair %s, seeds 1-%d per cell, %.0f s cap per fight (still running then = timeout, counted as not a win). %d fights." % [", ".join(bots.keys()), ", ".join(pairs.keys()), seeds.size(), cap, rows.size()])
	if note != "":
		L.append("")
		L.append(note)
	L.append("")
	L.append("Cells: win rate (wins/fights) | median fight length, all outcomes | median length of the wins.")
	L.append("")
	L.append("### Per tier")
	L.append("")
	L.append("| Tier | Win rate | Median length | Median win |")
	L.append("|---|---|---|---|")
	for t in tier_order:
		L.append("| %s | %s |" % [t, _cell(rows.filter(func(r): return r.tier == t))])
	L.append("")
	L.append("### Per tier and monster")
	L.append("")
	L.append("| Monster | Tier | Win rate | Median length | Median win | Outcomes |")
	L.append("|---|---|---|---|---|---|")
	for mo in monsters:
		for t in tier_order:
			var sub := rows.filter(func(r): return r.tier == t and r.monster == mo)
			L.append("| %s | %s | %s | %s |" % [mo, t, _cell(sub), _outcomes(sub)])
	L.append("")
	L.append("### Per tier, monster and weapon")
	L.append("")
	L.append("| Monster | Weapon | Tier | Win rate | Median length | Median win | Outcomes |")
	L.append("|---|---|---|---|---|---|---|")
	for mo in monsters:
		for w in weapons:
			for t in tier_order:
				var sub := rows.filter(func(r): return r.tier == t and r.monster == mo and r.weapon == w)
				L.append("| %s | %s | %s | %s | %s |" % [mo, w, t, _cell(sub), _outcomes(sub)])
	return "\n".join(L) + "\n"


static func _outcomes(rows: Array) -> String:
	var c := {}
	for r in rows:
		c[str(r.outcome)] = int(c.get(str(r.outcome), 0)) + 1
	var parts: Array = []
	for k in ["win", "dead", "timeout"]:
		if c.has(k):
			parts.append("%s %d" % [k, c[k]])
	return ", ".join(parts)
