"""Spirewalker (kickoff nickname Spire, H11): the grassy-glade monster (H10),
built with rigkit plus the Spirewalker extension (monster_rig/ext_spirewalker.py).

    blender -b --factory-startup --python tools/blender/build_monster_spirewalker.py

Writes (never hand-edit; change this script and rebuild):
    art/monsters/spirewalker.glb        body + deform bones + sockets (no baked
                                        clips: HHSpirewalkerClips poses it at run time)
    art/monsters/spirewalker.glb.import Godot import stub (only if missing)
    art/monsters/monsters.json          its row appended (other rows kept)
    art/monsters/blend/spirewalker.blend reference only

Kickoff: broad, flat and six-limbed, between a crab and a horned lizard. A
dense bed of tall copper reeds on its back, short bristles on both forearms.
Mustard and dusty ochre hide, copper reeds, violet arcs between the reeds
when charged. Reference: design/kickoff/ref/monster_spirewalker.png.

Blender coordinates: Z up, faces -Y, left +X, metres. Radius-2 footprint;
about 7.3 m across the splayed legs, 7.9 m nose to tail, the carapace top at
1.9 m: the player rig (2.2 m) stands head and shoulders over its back, with
the reeds rising past 3.5 m.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "monster_rig"))
import rigkit  # noqa: E402
import ext_spirewalker as ext  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "monsters", "spirewalker.glb")
JSON_OUT = os.path.join(ROOT, "art", "monsters", "monsters.json")
BLEND_OUT = os.path.join(ROOT, "art", "monsters", "blend", "spirewalker.blend")

VERSION = 1   # bump when bones, sockets or proportions change

# palette (vertex COLOR; sRGB intent)
MUSTARD = (0.80, 0.64, 0.20)
OCHRE = (0.62, 0.42, 0.15)
SAND = (0.86, 0.76, 0.50)
COPPER = (0.76, 0.40, 0.16)
BRISTLE = (0.58, 0.30, 0.12)
VIOLET = (0.62, 0.32, 0.96)
IVORY = (0.95, 0.93, 0.84)
AMBER = (0.98, 0.72, 0.16)
HORN = (0.30, 0.22, 0.16)


def S(y, z, rx, rz, drop=0.0, role=None, flat=None):
    d = {"p": (0.0, y, z), "rx": rx, "rz": rz, "drop": drop}
    if role:
        d["role"] = role
    if flat is not None:
        d["flat"] = flat
    return d


def leg(lid, parent, sx, hip, knee, ankle, toe, radii, foot, claw_len, sides=7, blend=0.16):
    """A splayed crab leg on side sx (+1 left, -1 right): the knee rises
    above the hip and out, the shin drops to a wide stance."""
    m = lambda p: (sx * p[0], p[1], p[2])
    return {"id": lid, "parent": parent, "hip": m(hip), "knee": m(knee), "ankle": m(ankle), "toe": m(toe),
            "radii": radii, "foot": foot, "claws": 3, "claw_len": claw_len, "sides": sides, "blend": blend}


SPEC = {
    "id": "spirewalker",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": MUSTARD, "belly": SAND, "reed": COPPER, "bristle": BRISTLE, "arc": VIOLET,
              "teeth": IVORY, "eye": AMBER, "claw": HORN},
    "mottle": {"role": "hide", "alt": OCHRE, "amount": 0.45},
    "belly": {"role": "belly", "below": -0.25},
    "chains": [
        {   # hips -> broad flat carapace -> chest -> neck base
            "name": "spine", "parent": "root", "sides": 14, "blend": 0.5, "flat": 0.45, "mottle": True,
            "cap_start": False, "cap_end": False,
            "stations": [
                S(1.50, 1.00, 1.30, 0.62),
                S(0.60, 1.10, 1.95, 0.82),
                S(-0.50, 1.15, 2.05, 0.84),
                S(-1.50, 1.08, 1.70, 0.74),
                S(-2.20, 0.98, 1.05, 0.56),
            ],
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck -> wide horned-lizard skull -> blunt snout
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.3, "flat": 0.6, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": [
                S(-2.20, 0.98, 1.05, 0.56),
                S(-2.75, 0.95, 0.92, 0.50),
                S(-3.30, 0.92, 1.05, 0.46),
                S(-3.95, 0.82, 0.78, 0.32),
                S(-4.35, 0.74, 0.46, 0.20),
            ],
            "bones": [("neck", 0, 1), ("head", 1, 4)],
        },
        {   # short broad flat tail (the tail drag)
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.35, "flat": 0.9, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": [
                S(1.50, 1.00, 1.30, 0.62),
                S(2.30, 0.82, 1.00, 0.34),
                S(2.95, 0.66, 0.72, 0.20),
                S(3.45, 0.56, 0.40, 0.10),
            ],
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3)],
        },
    ],
    "extra_bones": [
        ("jaw", "head", (0.0, -3.25, 0.62), (0.0, -4.30, 0.52), rigkit.UP),
    ],
    "jaw": {"bone": "jaw", "width": 1.3, "length": 1.05, "height": 0.22, "tip_w": 0.5,
            "teeth": 4, "tooth": 0.13, "role": "belly", "teeth_role": "teeth"},
    "upper_teeth": {"bone": "head", "at": (0.0, -3.30, 0.62), "width": 1.36, "length": 0.98, "tip_w": 0.5,
                    "teeth": 4, "tooth": 0.14},
    # the horned-lizard crown: raked back off the rear of the skull
    "horns": {"bone": "head", "length": 0.7, "back": 1.6, "role": "claw",
              "at": [(-0.9, -2.8, 1.14), (-0.5, -2.7, 1.28), (0.0, -2.65, 1.34), (0.5, -2.7, 1.28), (0.9, -2.8, 1.14)]},
    "eyes": [
        {"bone": "head", "at": (1.0, -3.45, 1.1), "r": 0.21},
        {"bone": "head", "at": (-1.0, -3.45, 1.1), "r": 0.21},
    ],
    "legs": [
        # three pairs, crab-splayed: knees above the carapace line, feet ~3.4 m out.
        # Front pair = the forearms (bristles live on their knee->ankle segment).
        leg("fl", "chest", 1, (1.25, -1.70, 1.00), (2.35, -2.20, 1.80), (2.80, -2.40, 0.46), (3.00, -3.00, 0.06),
            (0.42, 0.34, 0.26), (0.56, 0.78, 0.2), 0.34, sides=8, blend=0.18),
        leg("fr", "chest", -1, (1.25, -1.70, 1.00), (2.35, -2.20, 1.80), (2.80, -2.40, 0.46), (3.00, -3.00, 0.06),
            (0.42, 0.34, 0.26), (0.56, 0.78, 0.2), 0.34, sides=8, blend=0.18),
        leg("ml", "spine_1", 1, (1.75, -0.35, 1.05), (2.80, -0.35, 1.90), (3.10, -0.25, 0.46), (3.35, -0.55, 0.06),
            (0.36, 0.28, 0.22), (0.46, 0.66, 0.18), 0.3),
        leg("mr", "spine_1", -1, (1.75, -0.35, 1.05), (2.80, -0.35, 1.90), (3.10, -0.25, 0.46), (3.35, -0.55, 0.06),
            (0.36, 0.28, 0.22), (0.46, 0.66, 0.18), 0.3),
        leg("hl", "hips", 1, (1.25, 1.15, 0.95), (2.30, 1.60, 1.70), (2.75, 1.90, 0.42), (2.95, 2.40, 0.06),
            (0.34, 0.26, 0.20), (0.44, 0.62, 0.16), 0.28),
        leg("hr", "hips", -1, (1.25, 1.15, 0.95), (2.30, 1.60, 1.70), (2.75, 1.90, 0.42), (2.95, 2.40, 0.06),
            (0.34, 0.26, 0.20), (0.44, 0.62, 0.16), 0.28),
    ],
    "bristles": [
        {"leg": "fl", "count": 6, "length": 0.36, "role": "bristle"},
        {"leg": "fr", "count": 6, "length": 0.36, "role": "bristle"},
    ],
    "reeds": {
        "chain": "spine", "role": "reed", "bead_role": "arc",
        "rows": [1.10, 0.70, 0.30, -0.10, -0.50, -0.90, -1.30],
        "per_row": 9, "span": 1.45, "length": (1.3, 2.0), "lean_back": 0.12, "thick": 0.035,
        "beads": 9, "bead_r": 0.085,
        # (bone, parent, y from, y to): the bed folds flat by pitching these
        "bones": [("reed_0", "spine_0", 0.5, 1.3), ("reed_1", "spine_1", -0.3, 0.5), ("reed_2", "chest", -1.5, -0.3)],
    },
    "sockets": {
        "mouth": ("head", (0.0, -4.20, 0.60)),
        "back": ("spine_1", (0.0, -0.40, 1.98)),
        "reeds": ("reed_1", (0.0, 0.10, 3.0)),
        "tail_tip": ("tail_2", (0.0, 3.45, 0.56)),
        "arm_l": ("knee_fl", (2.6, -2.35, 0.9)),
        "arm_r": ("knee_fr", (-2.6, -2.35, 0.9)),
        "head_top": ("head", (0.0, -3.3, 1.4)),
    },
}
SPEC["extra_bones"] += ext.reed_bones(SPEC)


def append_manifest(path, row):
    """Append (or replace) this monster's row; every other row and the
    existing order are kept (rigkit.write_manifest would put ours first)."""
    import json
    doc = None
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    if not isinstance(doc, dict) or "monsters" not in doc:
        doc = {"version": rigkit.RIGKIT_VERSION, "generator": "tools/blender/build_monster_*.py + monster_rig/rigkit.py",
               "space": "Godot model-local: origin at the ground under the hips, +Y up, +Z the monster's forward, "
                        "+X its left. Bones carry head/tail at rest; sockets are Node3D under BoneAttachment3D.",
               "monsters": {}}
    doc["monsters"][row["id"]] = row
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, sort_keys=False)
        fh.write("\n")


def main():
    row = ext.build(SPEC, GLB_OUT, BLEND_OUT)
    row["generator"] = "tools/blender/build_monster_spirewalker.py"
    append_manifest(JSON_OUT, row)
    print("STATS", {k: row[k] for k in ("tris", "verts", "length", "height", "width")})
    print("SOCKETS", sorted(row["sockets"].keys()))
    print("BONES", len(row["bones"]))
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT)
    assert row["tris"] < 7000, "tris over budget: %d" % row["tris"]


main()
