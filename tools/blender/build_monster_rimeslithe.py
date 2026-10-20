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

VERSION = 2   # bump when bones, sockets or proportions change (2, H652: taller hunch, dragon head, gorilla arms + fists, digitigrade hind legs, crest/fin blades)

# palette (vertex COLOR; sRGB intent)
SLATE = (0.21, 0.26, 0.37)       # hide: dark slate-blue
SLATE_DARK = (0.13, 0.16, 0.25)  # mottle
BELLY = (0.40, 0.46, 0.56)       # lighter slate underside
CRYSTAL = (0.34, 0.36, 0.42)     # smoky grey at rest (the cold glow is the body material's, later)
CRYSTAL_TIP = (0.50, 0.54, 0.62)
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
    # long, heavy gorilla forearms (H652): shoulder high on the hunch, elbow out and back,
    # a 2.3 m forearm down to a rounded fist resting on its knuckles far ahead of the chest
    return {
        "id": "f" + side, "kind": "arm", "parent": "chest",
        "hip": (s * 1.25, -2.05, 2.85), "knee": (s * 2.0, -1.55, 1.85),
        "ankle": (s * 1.95, -3.7, 0.75), "toe": (s * 1.85, -4.15, 0.1),
        "radii": (0.6, 0.5, 0.36), "sides": 8, "blend": 0.25,
        "fist": (1.0, 0.9, 0.78), "claws": 4, "claw_len": 0.34, "shoulder_ball": 1.3,
        "forearm_mass": (0.62, 1.0, 0.6, 0.42),
    }


def LEG(side):
    s = 1.0 if side == "l" else -1.0
    # digitigrade hind legs, lower than the shoulders (the hunch)
    return {
        "id": "h" + side, "parent": "hips", "digi": True,
        "hip": (s * 0.95, 1.85, 1.65), "knee": (s * 1.25, 1.0, 1.05),
        "ankle": (s * 1.3, 2.25, 0.75), "toe": (s * 1.3, 1.6, 0.12),
        "radii": (0.55, 0.40, 0.26, 0.22), "thigh": (0.62, 0.85, 0.72, 0.4),
        "toes": 3, "toe_len": 0.65, "toe_w": 0.26, "toe_spread_deg": 36.0, "claw_len": 0.3,
        "sides": 8, "blend": 0.18,
    }


def CLUSTER(name, bone, at, d, n, length, radius, foot=0.45, spread=48.0):
    return {"name": name, "bone": bone, "at": at, "dir": d, "n": n, "length": length, "radius": radius,
            "foot": foot, "spread_deg": spread, "role": "crystal", "tip": CRYSTAL_TIP}


def CREST(sx, pts, widths, normal, w, thick=0.09):
    """A swept crest / fin blade (shapes_ma.plate) in the crystal role, smoky grey
    darkening at the root to the paler tip; mirrored with sx."""
    P = [(sx * p[0], p[1], p[2]) for p in pts]
    n = (sx * normal[0], normal[1], normal[2])
    cols = [tuple(CRYSTAL[i] * 0.8 + (CRYSTAL_TIP[i] - CRYSTAL[i] * 0.8) * (k / float(len(P) - 1)) for i in range(3))
            for k in range(len(P))]
    return {"pts": P, "widths": widths, "normal": n, "w": w, "role": "crystal", "thick": thick, "colors": cols}


SPEC = {
    "id": "rimeslithe",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": SLATE, "belly": BELLY, "crystal": CRYSTAL, "teeth": IVORY, "eye": CYAN, "claw": HORN},
    "mottle": {"role": "hide", "alt": SLATE_DARK, "amount": 0.38},
    "belly": {"role": "belly", "below": -0.6},
    "chains": [
        {   # hips -> the high shoulder hump -> chest front: the hunch (shoulders ~1.2 m above the hips)
            "name": "spine", "parent": "root", "sides": 12, "blend": 0.45, "flat": 0.88, "mottle": True,
            "cap_start": True, "cap_end": True,   # closed: an open loft gets inward belly normals (H652)
            "stations": [
                S(1.85, 1.80, 0.92, 0.80),
                S(0.75, 2.40, 1.15, 1.00),
                S(-0.45, 2.95, 1.38, 1.15),
                S(-1.55, 3.05, 1.35, 1.10),
                S(-2.45, 2.75, 0.95, 0.85),
            ],
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck sloping down and forward from the hump -> a long dragon skull -> snout
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.35, "flat": 0.8, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": [
                S(-2.45, 2.75, 0.95, 0.85),
                S(-3.25, 2.50, 0.80, 0.74),
                S(-4.00, 2.30, 0.62, 0.55),
                S(-4.75, 2.08, 0.42, 0.34),
                S(-5.35, 1.94, 0.24, 0.19),
            ],
            "bones": [("neck", 0, 1), ("head", 1, 4)],
        },
        {   # hips -> a long tapering tail
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.4, "flat": 0.85, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": [
                S(1.85, 1.80, 0.92, 0.80),
                S(2.75, 1.55, 0.64, 0.54),
                S(3.55, 1.20, 0.44, 0.36),
                S(4.20, 0.85, 0.28, 0.23),
                S(4.70, 0.60, 0.14, 0.11),
            ],
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3), ("tail_3", 3, 4)],
        },
    ],
    "extra_bones": [
        # (name, parent, head, tail, roll hint)
        ("jaw", "head", (0.0, -4.1, 2.02), (0.0, -5.45, 1.86), rigkit.UP),
    ],
    "jaw": {"bone": "jaw", "width": 0.86, "length": 1.35, "height": 0.30, "tip_w": 0.5,
            "teeth": 6, "tooth": 0.16, "role": "hide", "teeth_role": "teeth"},
    "upper_teeth": {"bone": "head", "at": (0.0, -4.2, 2.0), "width": 0.9, "length": 1.25, "tip_w": 0.5,
                    "teeth": 6, "tooth": 0.17},
    "eyes": [
        {"bone": "head", "at": (0.47, -4.35, 2.52), "r": 0.13},
        {"bone": "head", "at": (-0.47, -4.35, 2.52), "r": 0.13},
    ],
    "legs": [ARM("l"), ARM("r"), LEG("l"), LEG("r")],
    "masses": [
        # the brow ridge over the eyes (the dragon's scowl)
        {"a": (0.0, -3.75, 2.62), "b": (0.0, -4.6, 2.5), "u": 0.45, "r": (0.6, 0.55, 0.26), "w": {"head": 1.0}},
        # the shoulder blades under the hump, where the long arms hang from
        {"a": (1.0, -1.2, 3.3), "b": (1.3, -2.3, 2.7), "u": 0.5, "r": (0.6, 0.8, 0.6), "w": {"chest": 1.0}},
        {"a": (-1.0, -1.2, 3.3), "b": (-1.3, -2.3, 2.7), "u": 0.5, "r": (0.6, 0.8, 0.6), "w": {"chest": 1.0}},
    ],
    "crystals": [
        CLUSTER("shoulder_l", "chest", (1.05, -1.75, 3.65), (0.6, 0.1, 1.0), 8, 1.5, 0.26, 0.62),
        CLUSTER("shoulder_r", "chest", (-1.05, -1.75, 3.65), (-0.6, 0.1, 1.0), 8, 1.5, 0.26, 0.62),
        CLUSTER("back_0", "spine_1", (0.0, -0.45, 3.95), (0.0, 0.2, 1.0), 7, 1.4, 0.24, 0.6),
        CLUSTER("back_1", "spine_0", (0.0, 0.75, 3.3), (0.0, 0.35, 1.0), 6, 1.1, 0.2, 0.5),
        CLUSTER("back_2", "hips", (0.0, 1.75, 2.55), (0.0, 0.45, 1.0), 4, 0.85, 0.16, 0.4),
        CLUSTER("tail", "tail_0", (0.0, 2.6, 2.05), (0.0, 0.5, 1.0), 3, 0.6, 0.12, 0.25),
    ],
    "plates": [
        # the swept horn crest: two blades from the brow back past the neck
        CREST(1, [(0.35, -4.15, 2.68), (0.55, -3.5, 3.1), (0.78, -2.8, 3.45), (0.95, -2.15, 3.85), (1.02, -1.75, 4.35)],
              [0.40, 0.52, 0.44, 0.28, 0.0], (1.0, 0.0, 0.12), {"head": 1.0}),
        CREST(-1, [(0.35, -4.15, 2.68), (0.55, -3.5, 3.1), (0.78, -2.8, 3.45), (0.95, -2.15, 3.85), (1.02, -1.75, 4.35)],
              [0.40, 0.52, 0.44, 0.28, 0.0], (1.0, 0.0, 0.12), {"head": 1.0}),
        # the shoulder fins: a long blade off each shoulder sweeping up and back
        CREST(1, [(1.45, -2.2, 3.05), (1.8, -1.5, 3.7), (2.05, -0.7, 4.1), (2.2, 0.1, 4.3), (2.25, 0.7, 4.9)],
              [0.6, 0.8, 0.62, 0.38, 0.0], (1.0, 0.0, -0.55), {"chest": 1.0}),
        CREST(-1, [(1.45, -2.2, 3.05), (1.8, -1.5, 3.7), (2.05, -0.7, 4.1), (2.2, 0.1, 4.3), (2.25, 0.7, 4.9)],
              [0.6, 0.8, 0.62, 0.38, 0.0], (1.0, 0.0, -0.55), {"chest": 1.0}),
        # the hip fins: a shorter blade off each haunch, trailing back (the reference's flowing flanks)
        CREST(1, [(1.0, 1.2, 2.45), (1.3, 1.9, 2.85), (1.5, 2.6, 3.0), (1.6, 3.2, 3.35)],
              [0.45, 0.55, 0.36, 0.0], (1.0, 0.0, -0.6), {"hips": 1.0}),
        CREST(-1, [(1.0, 1.2, 2.45), (1.3, 1.9, 2.85), (1.5, 2.6, 3.0), (1.6, 3.2, 3.35)],
              [0.45, 0.55, 0.36, 0.0], (1.0, 0.0, -0.6), {"hips": 1.0}),
        # the tail fin: a dorsal blade along the tail, highest mid-way, trailing past the tip
        CREST(1, [(0.0, 2.75, 2.35), (0.0, 3.4, 2.2), (0.0, 4.0, 1.9), (0.0, 4.6, 1.75)],
              [0.5, 0.9, 0.8, 0.0], (1.0, 0.0, 0.0), [{"tail_0": 1.0}, {"tail_1": 1.0}, {"tail_2": 1.0}, {"tail_3": 1.0}]),
    ],
    "sockets": {
        "mouth": ("head", (0.0, -5.3, 1.92)),
        "head_top": ("head", (0.0, -4.0, 2.85)),
        "back": ("spine_1", (0.0, -0.45, 4.1)),
        "shoulder_l": ("chest", (1.05, -1.75, 3.7)),
        "shoulder_r": ("chest", (-1.05, -1.75, 3.7)),
        "fist_l": ("toe_fl", (1.85, -4.15, 0.35)),
        "fist_r": ("toe_fr", (-1.85, -4.15, 0.35)),
        "tail_tip": ("tail_3", (0.0, 4.7, 0.6)),
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
