extends RefCounted
## Lane TT (H480-H489): the lobby's ability tooltips. Every weapon's every
## ability has a tooltip with a name, a numbers line and a plain line; the
## numbers are the live HHTune values (a retune shows up in the text); the
## upgrades and the element pair read too; the ABILITIES card sits in the
## weapon row's free slot and opens the tip on hover.

const KEYS := ["basic", "q", "w", "e", "r", "dash", "t"]


func _weapons() -> Array:
	return HHRegistry.rows("weapon").map(func(r): return str(r.id))


func _text(info: Dictionary) -> String:
	var parts: Array = [str(info.get("title", ""))]
	for ln in info.get("lines", []):
		parts.append(str(ln.text))
	return "\n".join(parts)


func _kind(info: Dictionary, kind: String) -> Array:
	return (info.get("lines", []) as Array).filter(func(ln): return str(ln.kind) == kind)


func test_every_ability_has_a_tooltip(c: HHSelfTest.HHCheck) -> void:
	for w in _weapons():
		for k in KEYS:
			var i := HHAbilityInfo.info(w, k, "fire", "water")
			c.ok(str(i.title) != "", "%s %s: a name" % [w, k])
			c.ok(str(i.label) != "", "%s %s: a key" % [w, k])
			c.ok(_kind(i, "facts").size() == 1 and str(_kind(i, "facts")[0].text) != "", "%s %s: one numbers line" % [w, k])
			c.ok(not _kind(i, "for").is_empty() or not _kind(i, "does").is_empty(), "%s %s: a plain line" % [w, k])
			c.ok(not (i.values as Dictionary).is_empty(), "%s %s: live values" % [w, k])
			if k in ["q", "w", "e", "r"]:
				c.eq(str(i.title), str(HHWeapons.skills(w)[k].name), "%s %s: the weapon's own name" % [w, k])
				c.ok(_text(i).contains(str(HHWeapons.skills(w)[k].text)), "%s %s: the weapon's own text" % [w, k])
				c.ok(not _kind(i, "for").is_empty(), "%s %s: what it is for" % [w, k])
				c.ok(not _kind(i, "element").is_empty(), "%s %s: what the element does on it" % [w, k])
				c.ok(_text(i).contains("Cooldown"), "%s %s: shows the cooldown" % [w, k])
		for slot in ["active", "backup"]:
			var e := HHAbilityInfo.info(w, slot, "thunder", "fire")
			c.ok(_text(e).contains("Thunder") and _text(e).contains("Fire"), "%s %s: names both elements" % [w, slot])
			c.ok(_text(e).contains(str(HHRegistry.entry("element", "thunder" if slot == "active" else "fire").blurb)), "%s %s: the element's blurb" % [w, slot])
		var s := HHAbilityInfo.summary(w)
		c.eq((s.lines as Array).size(), 5, "%s: the kit card is five lines" % w)


## Every number a tooltip carries equals its HHTune source right now.
func test_values_are_the_live_tune(c: HHSelfTest.HHCheck) -> void:
	for w in _weapons():
		for k in KEYS:
			var i := HHAbilityInfo.info(w, k, "fire", "water")
			for name in i.values:
				var src := str(i.sources[name])
				c.ok(HHTune.has(src), "%s %s %s: source %s is a tune key" % [w, k, name, src])
				if src == "lance_counter_mult":
					c.near(float(i.values[name]), HHTune.value("lance_q_dmg") * HHTune.value("lance_counter_mult"), 0.001, "lance counter = q dmg x counter mult")
				else:
					c.near(float(i.values[name]), HHTune.value(src), 0.001, "%s %s %s = %s" % [w, k, name, src])
	for id in HHUpgrades.TABLE:
		var u := HHAbilityInfo.upgrade_info(str(id))
		c.ok(str(u.title) != "" and _text(u).contains(HHUpgrades.blurb_of(str(id))), "%s: name and blurb" % id)
		for name in u.values:
			c.near(float(u.values[name]), HHTune.value(str(u.sources[name])), 0.001, "%s: %s live" % [id, name])


## A retune shows in the text at once (nothing is a copied number).
func test_retune_changes_the_text(c: HHSelfTest.HHCheck) -> void:
	var cases := [
		["lance", "q", "lance_q_dmg", 333.0, "Damage 333"],
		["lance", "q", "lance_q_cd", 150.0, "Cooldown 5 s"],
		["lance", "q", "lance_q_windup", 15.0, "Wind-up 0.5 s"],
		["lance", "q", "lance_q_l3_mult", 4.0, "3 s: %d" % int(HHFormulas.hit(160.0 * 4.0, 1.0).value)],
		["lance", "basic", "lance_basic_dmg", 300.0, "Damage 300"],
		["daggers", "e", "daggers_e_land_dmg", 77.0, "Landing 77"],
		["daggers", "r", "daggers_r_ticks", 240.0, "Lasts 8 s"],
		["bow", "r", "bow_r_dmg", 250.0, "Damage 250"],
		["bow", "q", "bow_q_cd", 120.0, "Cooldown 4 s"],
		["bow", "w", "exchange_cd", 60.0, "Cooldown 2 s"],
		["lance", "dash", "dash_charges", 3.0, "3 charges"],
		["lance", "t", "potion_cd", 300.0, "Cooldown 10 s"],
	]
	for cs in cases:
		HHAbilityInfo.info(str(cs[0]), "q", "fire", "water")     # registers the weapon's keys
		var key := str(cs[2])
		var old := HHTune.value(key)
		var before := _text(HHAbilityInfo.info(str(cs[0]), str(cs[1]), "fire", "water"))
		HHTune.set_value(key, cs[3])
		var after := _text(HHAbilityInfo.info(str(cs[0]), str(cs[1]), "fire", "water"))
		HHTune.set_value(key, old)
		c.ok(after.contains(str(cs[4])), "%s %s: %s=%s shows '%s' (got: %s)" % [cs[0], cs[1], key, cs[3], cs[4], after.replace("\n", " | ")])
		c.ok(not before.contains(str(cs[4])), "%s %s: '%s' was not there before" % [cs[0], cs[1], cs[4]])
	HHAbilityInfo.upgrade_facts("pierce_wide")
	var old_w := HHTune.value("lance_up_q_width")
	HHTune.set_value("lance_up_q_width", 5.0)
	c.eq(HHAbilityInfo.upgrade_facts("pierce_wide"), "5 hexes wide", "an upgrade's number is live")
	HHTune.set_value("lance_up_q_width", old_w)


func test_slotted_upgrades_show_on_their_skill(c: HHSelfTest.HHCheck) -> void:
	var ups := { "q": ["pierce_wide"], "w": ["exchange_immune"], "t": ["potion_cleanse"] }
	var q := HHAbilityInfo.info("lance", "q", "fire", "water", ups)
	c.eq(_kind(q, "upgrade").size(), 1, "Q lists Broad Pierce")
	c.ok(_text(q).contains("Broad Pierce"), "by name")
	c.eq(_kind(HHAbilityInfo.info("lance", "e", "fire", "water", ups), "upgrade").size(), 0, "E lists none")
	c.ok(_text(HHAbilityInfo.info("lance", "w", "fire", "water", ups)).contains("Exchange Ward"), "W lists Exchange Ward")
	c.ok(_text(HHAbilityInfo.info("lance", "t", "fire", "water", ups)).contains("Clean Draught"), "the potion lists Clean Draught")


func test_secs(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHAbilityInfo.secs(90), "3 s", "whole seconds")
	c.eq(HHAbilityInfo.secs(45), "1.5 s", "one decimal")
	c.eq(HHAbilityInfo.secs(10), "0.33 s", "two decimals")


## The live lobby: the card sits in the weapon row's free slot, clear of the
## tiles and the right card, and a hover opens the tip with the picked kit.
func test_lobby_card_and_tip(c: HHSelfTest.HHCheck) -> void:
	HHSave.path = "user://test_lobby_tt_hunter.json"
	HHLobbyState.last_path = "user://test_lobby_tt_last.json"
	HHLobbyState.runs_path = "user://test_lobby_tt_runs.json"
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var lobby := HHLobby.new()
	lobby.setup({ "weapon": "daggers" })
	root.add_child(lobby)
	var strip: HHAbilityStrip = lobby._strip
	c.ok(strip != null, "the ABILITIES card exists")
	var r := strip.get_rect()
	c.ok(r.end.x <= HHLobby.CARD.position.x, "clear of the right card")
	for t in lobby._tiles["weapon"]:
		c.ok(not (t as HHLobbyTile).get_rect().intersects(r), "clear of the %s tile" % t.id)
	c.eq(strip.weapon, "daggers", "shows the picked weapon")
	c.eq(strip.rects().size(), 9, "Q W E R + basic, dash, potion, two elements")
	for k in strip.rects():
		c.ok(Rect2(Vector2.ZERO, strip.size).encloses(strip.rects()[k]), "%s inside the card" % k)
	strip.hovered.emit("r", strip.canvas_rect("r"))
	c.eq(lobby._tip.showing(), "r", "hovering R opens its tip")
	c.ok(lobby._tip.visible and str(lobby._tip.info.title) == "Knifedance", "with the daggers' R")
	c.ok(Rect2(Vector2.ZERO, HHLobby.CANVAS).encloses(lobby._tip.get_rect()), "on screen")
	lobby._pick("weapon", "bow")
	c.eq(str(lobby._tip.info.title), "Arrowstorm", "a new pick refreshes the open tip")
	strip.hovered.emit("", Rect2())
	c.ok(not lobby._tip.visible, "leaving closes it")
	lobby.show_tip("weapon:lance", Rect2(150, 428, 250, 140))
	c.ok(_text(lobby._tip.info).contains("Pierce"), "a weapon tile shows its kit card")
	lobby.show_tip("up:pierce_wide", Rect2(1230, 570, 300, 20))
	c.ok(lobby._tip.get_rect().end.x <= 1230.0, "an upgrade's tip opens left of the card")
	root.remove_child(lobby)
	lobby.free()
	for p in [HHSave.path, HHLobbyState.last_path, HHLobbyState.runs_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	HHSave.path = HHSave.DEFAULT_PATH
	HHLobbyState.last_path = HHLobbyState.LAST_PATH
	HHLobbyState.runs_path = HHLobbyState.RUNS_PATH
