class_name HHRegistry
## The content tables the lobby and the launch config read (H48; the Gamers
## Gauntlet TourneyModules pattern, G66): static rows referenced by id, with
## the scripts behind them loaded lazily by path when a fight starts. Nothing
## here names a monster or weapon class, so the lobby opens without compiling
## a fight.
##
## Row keys: id, name, blurb (one line; the ticker shows it on hover), look:
## [tint_hex, TAG] (the tile's muted tint and the big faded word behind the
## name). Monsters also carry `biome` (H10). Elements use HHLook's colours.
## `check()` lists every id that does not resolve to a file; the self-test
## wants it empty.

const ARENAS: Array = [
	{ "id": "pond", "name": "Lilypad Pond",
		"blurb": "A shallow sunlit lake: wade anywhere, hide behind a lilypad or two; the water douses fire and the deep middle is the monster's.",
		"look": ["#2f5a4e", "POND"] },
	{ "id": "cave", "name": "The Cave",
		"blurb": "Dark, hex-terraced stone with ramps and cliffs; rock pillars break under your casts; cold shade in the corners.",
		"look": ["#3a3a4c", "CAVE"] },
	{ "id": "glade", "name": "Grassy Glade",
		"blurb": "Gentle grass with trees for cover and sunlit patches; the sun cells charge whatever sits in them.",
		"look": ["#4a6230", "GLADE"] },
	{ "id": "caldera", "name": "Volcanic Caldera",
		"blurb": "A snow-rimmed basalt bowl: heat vents that re-form fire, lava pools that never go out, boulders in the way.",
		"look": ["#5e3426", "CALDERA"] },
]

const MONSTERS: Array = [
	{ "id": "swampfang", "name": "Swampfang", "biome": "pond",
		"blurb": "Floats half-submerged, then rises and rushes you: water jets, dark spray, a death-roll; dives under the pads when hurt. Weak from behind.",
		"look": ["#2a4a3e", "FANG"] },
	{ "id": "colambros", "name": "Colambros", "biome": "caldera",
		"blurb": "The one fast monster: laps the arena, charges down a lit line, and after its first lap every charge burns a trail. Bald after a roll: hit it twice as hard.",
		"look": ["#6a3a22", "QUILL"] },
	{ "id": "rimeslithe", "name": "Rimeslithe", "biome": "cave",
		"blurb": "Huge and hunched, frosting over in the shade: frost beams, a planted-fist slam, a shoulder charge, and a freezing mist across the centre.",
		"look": ["#38506a", "RIME"] },
	{ "id": "spirewalker", "name": "Spirewalker", "biome": "glade",
		"blurb": "Sits soaking static with its reeds raised; squashes, lashes, throws barbs, and shakes a pollen cloud that slows, poisons, then paralyses.",
		"look": ["#5a4e26", "SPIRE"] },
]

const WEAPONS: Array = [
	{ "id": "lance", "name": "Glaive-lance",
		"blurb": "Q Pierce a line, E Guard and counter, R vault and erupt. Slow heavy basics with reach 2.",
		"look": ["#4c4458", "LANCE"] },
	{ "id": "daggers", "name": "Twin Karambits",
		"blurb": "Q Flourish round you, E Daggerleap with a trail, R Knifedance lays both elements under your feet. Fast basics, reach 1.",
		"look": ["#5a3246", "DAGGERS"] },
	{ "id": "bow", "name": "Winged Bow",
		"blurb": "Q Energized shot down a 10-hex line, E a lobbed bomb the monster can see coming, R Arrowstorm from the sky. Ranged basics, reach 7.",
		"look": ["#2e4a56", "BOW"] },
]

const ELEMENTS: Array = [
	{ "id": "fire", "name": "Fire", "blurb": "Burns whoever stands or crosses; fire on fire 3 Overheats; meets water 2+ as Steam.", "look": ["#E8432E", "FIRE"] },
	{ "id": "water", "name": "Water", "blurb": "Slows at depth; water on water 3 erupts a Geyser; meets fire 2+ as Steam.", "look": ["#2E6FE8", "WATER"] },
	{ "id": "ice", "name": "Ice", "blurb": "Shatter: freezes charge into a crystal; a hit, a crush or overcharge breaks it.", "look": ["#5FD8F0", "ICE"] },
	{ "id": "thunder", "name": "Thunder", "blurb": "Detonate: cashes out the charge it lands on at once; paralyses on a status.", "look": ["#8B3DF0", "THUNDER"] },
	{ "id": "wind", "name": "Wind", "blurb": "Swirl: pulls the charge round where it lands inward and compresses it.", "look": ["#3CCB5A", "WIND"] },
	{ "id": "dark", "name": "Dark", "blurb": "Poisons and starves healing; dark on dark 3 Fluxes; meets light 2+ as Eclipse.", "look": ["#3A2A5C", "DARK"] },
	{ "id": "light", "name": "Light", "blurb": "Heals whoever stands in it; light on light 3 Glints; meets dark 2+ as Eclipse.", "look": ["#F5D23A", "LIGHT"] },
]

const KINDS := { "arena": ARENAS, "monster": MONSTERS, "weapon": WEAPONS, "element": ELEMENTS }


## The rows of one kind ("arena" | "monster" | "weapon" | "element").
static func rows(kind: String) -> Array:
	return KINDS.get(kind, [])


static func ids(kind: String) -> Array:
	var out: Array = []
	for r in rows(kind):
		out.append(str(r.id))
	return out


## The row for an id, {} when there is none.
static func entry(kind: String, id: String) -> Dictionary:
	for r in rows(kind):
		if str(r.id) == id:
			return r
	return {}


static func name_of(kind: String, id: String) -> String:
	var e := entry(kind, id)
	return str(e.get("name", id))


## The arena a monster lives in (H10); "" for an unknown monster.
static func biome_of(monster: String) -> String:
	return str(entry("monster", monster).get("biome", ""))


## Every id that does not resolve: arenas/<id>.json, src/monster/<id>.gd, a
## weapon HHWeapons knows, an element HHFormulas knows. Empty = all good.
static func check() -> Array:
	var problems: Array = []
	for r in ARENAS:
		if not FileAccess.file_exists("res://arenas/%s.json" % str(r.id)):
			problems.append("arena %s: no arenas/%s.json" % [r.id, r.id])
	for r in MONSTERS:
		if not ResourceLoader.exists("res://src/monster/%s.gd" % str(r.id)):
			problems.append("monster %s: no src/monster/%s.gd" % [r.id, r.id])
		if entry("arena", str(r.get("biome", ""))).is_empty():
			problems.append("monster %s: biome '%s' is not an arena" % [r.id, r.get("biome", "")])
	for r in WEAPONS:
		if not HHWeapons.WEAPONS.has(str(r.id)) or HHWeapons.script(str(r.id)) == null:
			problems.append("weapon %s: not in HHWeapons" % r.id)
	for r in ELEMENTS:
		if not str(r.id) in HHFormulas.ELEMENTS:
			problems.append("element %s: not in HHFormulas.ELEMENTS" % r.id)
	for el in HHFormulas.ELEMENTS:
		if entry("element", str(el)).is_empty():
			problems.append("element %s: in HHFormulas but not the registry" % el)
	return problems


## { arena: HHArena, asset: GKAsset | null } for an arena id (boot and the
## shell share this). A JSON with a "gen" block is rebuilt through
## src/arena/gen/<id>_gen.gd (build_both(params)) when that script exists, so
## the mesh matches the underlay; else the JSON's cells are used with the
## plain floor. "round" or an unknown id gives the Phase 0 round arena.
static func load_arena(id: String, seed: int) -> Dictionary:
	var path := "res://arenas/%s.json" % id
	if id != "round" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			if d.has("gen"):
				var gen: Dictionary = d.gen
				var gp := "res://src/arena/gen/%s_gen.gd" % str(gen.get("id", id))
				if ResourceLoader.exists(gp):
					var s: GDScript = load(gp)
					var both: Dictionary = s.build_both(gen.get("params", {}))
					var ar: HHArena = both.arena
					if ar.authored.is_empty():
						ar.authored = Array(d.get("authored", ar.spawns.get("authored", [])))
					return { "arena": ar, "asset": both.asset }
			return { "arena": HHArena.from_dict(d), "asset": null }
		push_warning("registry: arena '%s' failed to parse, using round" % id)
	return { "arena": HHArena.round_flat(seed), "asset": null }
