"""Rimeslithe: the cave monster (H10), built with rigkit + ext_rimeslithe.

    blender -b --factory-startup --python tools/blender/build_monster_rimeslithe.py

Writes (never hand-edit these; change this script and rebuild):
    art/monsters/rimeslithe.glb          body + deform bones + sockets (clips are
                                         HHRimeslitheClips pose functions at run time)
    art/monsters/rimeslithe.glb.import   Godot import stub (only if missing)
    art/monsters/monsters.json           this monster's row APPENDED (other rows kept as they are)
    art/monsters/blend/rimeslithe.blend  reference only (.gdignore keeps Godot off it)

The kickoff (Lane E, Rimeslithe / "Reshiram"): huge, hunched and creepy-crawly,
long forearms, a dragon head; clusters of ice crystal grow from its shoulders
and back. Dark slate-blue hide; the crystals start smoky grey and turn bright
pale cyan as it chills (the body's crystal material, driven by u.cold, later).
Reference: design/kickoff/ref/monster_rimeslithe.jpg.

Blender coordinates: Z up, faces -Y, left +X, metres. Radius-2-hex footprint,
~9.3 m nose to tail, 3.5 m at the top of the shoulder hump; the knuckles rest
on the ground 4.4 m ahead of the hips; the player rig (2.2 m) stands below
its chin.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "monster_rig"))
import rigkit  # noqa: E402
import ext_rimeslithe  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "monsters", "rimeslithe.glb")
JSON_OUT = os.path.join(ROOT, "art", "monsters", "monsters.json")
BLEND_OUT = os.path.join(ROOT, "art", "monsters", "blend", "rimeslithe.blend")

VERSION = 1   # bump when bones, sockets or proportions change

# palette (vertex COLOR; sRGB intent)
SLATE = (0.21, 0.26, 0.37)       # hide: dark slate-blue
SLATE_DARK = (0.13, 0.16, 0.25)  # mottle
BELLY = (0.40, 0.46, 0.56)       # lighter slate underside
CRYSTAL = (0.40, 0.43, 0.50)     # smoky grey at rest (the cold glow is the body material's, later)
CRYSTAL_TIP = (0.56, 0.60, 0.68)
IVORY = (0.93, 0.92, 0.86)
CYAN = (0.55, 0.95, 1.0)         # eyes
HORN = (0.12, 0.12, 0.16)        # claws, horns


def S(y, z, rx, rz, drop=0.0, role=None):
    d = {"p": (0.0, y, z), "rx": rx, "rz": rz, "drop": drop}
    if role:
        d["role"] = role
    return d


def ARM(side):
    s = 1.0 if side == "l" else -1.0
    return {
        "id": "f" + side, "kind": "arm", "parent": "chest",
        "hip": (s * 1.15, -2.05, 2.6), "knee": (s * 2.0, -1.5, 1.8),
        "ankle": (s * 2.1, -3.85, 0.55), "toe": (s * 2.1, -4.35, 0.08),
        "radii": (0.5, 0.44, 0.36), "sides": 8, "blend": 0.25,
        "fist": (0.95, 0.9, 0.62), "claws": 4, "claw_len": 0.32, "shoulder_ball": 1.3,
    }


def LEG(side):
    s = 1.0 if side == "l" else -1.0
    return {
        "id": "h" + side, "parent": "hips",
        "hip": (s * 0.9, 1.7, 1.55), "knee": (s * 1.3, 2.6, 0.95),
        "ankle": (s * 1.35, 1.95, 0.35), "toe": (s * 1.35, 1.25, 0.05),
        "radii": (0.5, 0.36, 0.28), "foot": (0.56, 0.78, 0.22), "claws": 3, "claw_len": 0.26, "sides": 8, "blend": 0.18,
    }


def CLUSTER(name, bone, at, d, n, length, radius, foot=0.45, spread=38.0):
    return {"name": name, "bone": bone, "at": at, "dir": d, "n": n, "length": length, "radius": radius,
            "foot": foot, "spread_deg": spread, "role": "crystal", "tip": CRYSTAL_TIP}


SPEC = {
    "id": "rimeslithe",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": SLATE, "belly": BELLY, "crystal": CRYSTAL, "teeth": IVORY, "eye": CYAN, "claw": HORN},
    "mottle": {"role": "hide", "alt": SLATE_DARK, "amount": 0.38},
    "belly": {"role": "belly", "below": -0.3},
    "chains": [
        {   # hips -> the shoulder hump -> chest front: the hunch
            "name": "spine", "parent": "root", "sides": 12, "blend": 0.45, "flat": 0.7, "mottle": True,
            "cap_start": False, "cap_end": False,
            "stations": [
                S(1.9, 1.7, 0.95, 0.8),
                S(0.8, 2.2, 1.2, 1.0),
                S(-0.5, 2.55, 1.42, 1.1),
                S(-1.7, 2.6, 1.4, 1.05),
                S(-2.7, 2.35, 1.0, 0.82),
            ],
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck sloping down and forward from the hump -> dragon skull -> snout
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.35, "flat": 0.8, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": [
                S(-2.7, 2.35, 1.0, 0.82),
                S(-3.5, 2.2, 0.66, 0.58),
                S(-4.2, 2.12, 0.72, 0.62),
                S(-4.95, 1.98, 0.52, 0.42),
                S(-5.4, 1.86, 0.34, 0.26),
            ],
            "bones": [("neck", 0, 1), ("head", 1, 4)],
        },
        {   # hips -> a thick, shortish tail
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.4, "flat": 0.85, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": [
                S(1.9, 1.7, 0.95, 0.8),
                S(2.75, 1.45, 0.66, 0.55),
                S(3.35, 1.15, 0.46, 0.38),
                S(3.75, 0.85, 0.3, 0.24),
                S(3.95, 0.62, 0.16, 0.12),
            ],
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3), ("tail_3", 3, 4)],
        },
    ],
    "extra_bones": [
        # (name, parent, head, tail, roll hint)
        ("jaw", "head", (0.0, -4.3, 1.8), (0.0, -5.35, 1.68), rigkit.UP),
    ],
    "jaw": {"bone": "jaw", "width": 0.92, "length": 1.1, "height": 0.3, "tip_w": 0.55,
            "teeth": 5, "tooth": 0.17, "role": "belly", "teeth_role": "teeth"},
    "upper_teeth": {"bone": "head", "at": (0.0, -4.36, 1.78), "width": 0.98, "length": 1.0, "tip_w": 0.55,
                    "teeth": 5, "tooth": 0.19},
    "eyes": [
        {"bone": "head", "at": (0.54, -4.55, 2.34), "r": 0.15},
        {"bone": "head", "at": (-0.54, -4.55, 2.34), "r": 0.15},
    ],
    "legs": [ARM("l"), ARM("r"), LEG("l"), LEG("r")],
    "crystals": [
        CLUSTER("shoulder_l", "chest", (1.0, -1.85, 3.25), (0.55, 0.05, 1.0), 6, 1.35, 0.24, 0.5),
        CLUSTER("shoulder_r", "chest", (-1.0, -1.85, 3.25), (-0.55, 0.05, 1.0), 6, 1.35, 0.24, 0.5),
        CLUSTER("back_0", "spine_1", (0.0, -0.7, 3.42), (0.0, 0.2, 1.0), 5, 1.25, 0.22, 0.5),
        CLUSTER("back_1", "spine_0", (0.0, 0.55, 3.1), (0.0, 0.35, 1.0), 4, 1.0, 0.19, 0.45),
        CLUSTER("back_2", "hips", (0.0, 1.65, 2.45), (0.0, 0.45, 1.0), 3, 0.8, 0.16, 0.35),
        CLUSTER("tail", "tail_0", (0.0, 2.75, 1.95), (0.0, 0.5, 1.0), 2, 0.55, 0.12, 0.25),
        CLUSTER("crest", "head", (0.0, -3.95, 2.62), (0.0, 0.45, 1.0), 3, 0.55, 0.1, 0.22),
        # the horns: solid swept-back spikes in dark horn (ext crystals with the claw role)
        {"name": "horn_l", "bone": "head", "at": (0.45, -4.2, 2.5), "dir": (0.45, 0.75, 0.55), "n": 1, "length": 1.2, "radius": 0.17, "role": "claw"},
        {"name": "horn_r", "bone": "head", "at": (-0.45, -4.2, 2.5), "dir": (-0.45, 0.75, 0.55), "n": 1, "length": 1.2, "radius": 0.17, "role": "claw"},
    ],
    "sockets": {
        "mouth": ("head", (0.0, -5.3, 1.72)),
        "head_top": ("head", (0.0, -4.3, 2.7)),
        "back": ("spine_1", (0.0, -0.7, 3.5)),
        "shoulder_l": ("chest", (1.0, -1.85, 3.3)),
        "shoulder_r": ("chest", (-1.0, -1.85, 3.3)),
        "fist_l": ("toe_fl", (2.1, -4.35, 0.35)),
        "fist_r": ("toe_fr", (-2.1, -4.35, 0.35)),
        "tail_tip": ("tail_3", (0.0, 3.95, 0.62)),
    },
}


def append_row(path, row):
    """Append (or replace) this monster's row; every other row stays byte-for-byte in place."""
    doc = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    doc.setdefault("version", rigkit.RIGKIT_VERSION)
    doc.setdefault("generator", "tools/blender/build_monster_*.py + monster_rig/rigkit.py")
    doc.setdefault("space", "Godot model-local: origin at the ground under the hips, +Y up, +Z the monster's forward, "
                            "+X its left. Bones carry head/tail at rest; sockets are Node3D under BoneAttachment3D.")
    monsters = doc.setdefault("monsters", {})
    monsters[row["id"]] = row
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, sort_keys=False)
        fh.write("\n")


def main():
    ext_rimeslithe.install()
    row = rigkit.build(SPEC, GLB_OUT, BLEND_OUT)
    row["generator"] = "tools/blender/build_monster_rimeslithe.py"
    row["ext"] = {"module": "monster_rig/ext_rimeslithe.py", "version": ext_rimeslithe.EXT_VERSION}
    row["arms"] = ["fl", "fr"]
    row["crystals"] = {c["name"]: {"bone": c["bone"], "at": rigkit.gd(c["at"]), "n": int(c["n"])} for c in SPEC["crystals"]}
    append_row(JSON_OUT, row)
    print("STATS", {k: row[k] for k in ("tris", "verts", "length", "height", "width")})
    print("SOCKETS", sorted(row["sockets"].keys()))
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT)
    assert row["tris"] < 7000, "tris over budget: %d" % row["tris"]


main()
