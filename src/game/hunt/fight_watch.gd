class_name HHHuntFightWatch
extends Node
## Lane H's stand-in for HHFight's `finished` signal until Lane L adds it:
## a child of the fight that watches `sim.over` and emits the Phase 3
## payload { result: "win"|"fallen"|"abort", cfg, ticks, hp, monster_hp,
## max_hp, monster_max_hp } once, after a short hold so the death or
## collapse clip is seen. F10 aborts (Esc already quits the whole tree in
## HHFight). Removed when the real signal lands; HHHunt prefers the signal
## when the fight node has one.

signal finished(result: Dictionary)

const HOLD_S := 1.6

var fight: Node = null
var cfg := {}
var _over_at := -1.0
var _t := 0.0
var _done := false


func bind(p_fight: Node, p_cfg: Dictionary) -> void:
	fight = p_fight
	cfg = p_cfg


func _process(delta: float) -> void:
	if _done or fight == null:
		return
	_t += delta
	var sim: Variant = fight.get("sim")
	if sim == null:
		return
	var over := str(sim.get("over"))
	if over == "":
		return
	if _over_at < 0.0:
		_over_at = _t
	if _t - _over_at >= HOLD_S:
		emit_now("win" if over == "win" else "fallen")


## The payload, from the fight's sim right now.
func payload(verdict: String) -> Dictionary:
	var out := { "result": verdict, "cfg": cfg, "ticks": 0, "hp": 0.0, "monster_hp": 0.0 }
	var sim: Variant = fight.get("sim") if fight != null else null
	if sim == null:
		return out
	out.ticks = int(sim.get("tick"))
	var pid := str(fight.get("player_id"))
	var p: Dictionary = sim.unit(pid)
	if not p.is_empty():
		out.hp = float(p.hp)
		out.max_hp = float(p.max_hp)
	var mid := str(fight.get("monster_id"))
	if mid != "":
		var m: Dictionary = sim.unit(mid)
		if not m.is_empty():
			out.monster_hp = float(m.hp)
			out.monster_max_hp = float(m.max_hp)
	return out


func emit_now(verdict: String) -> void:
	if _done:
		return
	_done = true
	finished.emit(payload(verdict))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F10:
		emit_now("abort")
