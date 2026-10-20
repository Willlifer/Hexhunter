"""Writes art/weapons/bw_temp/weapons.json from Black | White's manifest rows
(lance, karambit, recurve_bow, arrow). Temporary: Lane A's art/weapons/
weapons.json replaces this set with the same keys.

    python art/weapons/bw_temp/make_weapons_json.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
BW = "..\Black White/game/art/weapons"
bw = json.load(open(os.path.join(BW, "weapons.json")))
pr = json.load(open(os.path.join(BW, "projectiles", "projectiles.json")))
arrow = pr.get("projectiles", pr)["arrow"]
out = {
    "version": 1,
    "source": "Black | White game/art/weapons, copied verbatim; temporary until Lane A's art/weapons/<id>.glb + "
              "weapons.json land (same keys, so HHPlayerBody.WEAPON_DIR is the only change).",
    "space": bw["space"],
    "hands": bw["hands"],
    "weapons": {},
}
for hh, bwid in [("lance", "lance"), ("daggers", "karambit"), ("bow", "recurve_bow")]:
    w = dict(bw["weapons"][bwid])
    w.pop("aura_points", None)
    w["glb"] = "res://art/weapons/bw_temp/%s.glb" % bwid
    w["source_id"] = bwid
    if w.get("offhand_socket") and w["hands"] == "pair":
        w["offhand_glb"] = "res://art/weapons/bw_temp/%s.glb" % bwid   # no karambit_l in B|W: the pair is the same glb twice
    out["weapons"][hh] = w
a = dict(arrow)
a.pop("aura_points", None)
a["glb"] = "res://art/weapons/bw_temp/arrow.glb"
out["projectiles"] = {"arrow": a}
with open(os.path.join(HERE, "weapons.json"), "w", encoding="utf-8", newline="\n") as fh:
    json.dump(out, fh, indent=1)
    fh.write("\n")
print({k: (v["hands"], v["socket"], v.get("second_hand")) for k, v in out["weapons"].items()})
