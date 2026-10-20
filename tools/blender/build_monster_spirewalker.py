"""Spirewalker (kickoff nickname Spire, H11): the grassy-glade monster (H10),
built with rigkit plus the Spirewalker extension (monster_rig/ext_spirewalker.py,
monster_rig/shapes_mb.py).

    blender -b --factory-startup --python tools/blender/build_monster_spirewalker.py

Writes (never hand-edit; change this script and rebuild):
    art/monsters/spirewalker.glb        body + deform bones + sockets (no baked
                                        clips: HHSpirewalkerClips poses it at run time)
    art/monsters/spirewalker.glb.import Godot import stub (only if missing)
    art/monsters/monsters.json          its row replaced in place (other rows kept)
    art/monsters/blend/spirewalker.blend reference only

Kickoff: broad, flat and six-limbed, between a crab and a horned lizard. A
dense bed of tall copper reeds on its back, short bristles on both forearms.
Mustard and dusty ochre hide, copper reeds, violet arcs between the reeds
when charged. Reference: design/kickoff/ref/monster_spirewalker.png (a squat
"marsh frog": a low heavy toad body, a wide grinning head under a heavy brow,
short thick planted legs with big claws, a raised mound on the back carrying
the plant mass with broad fronds at its base, thorned whip vines trailing off
the back). Phase 3.5 gauntlet: design/art/monsters/SPIREWALKER.md.

Blender coordinates: Z up, faces -Y, left +X, metres. Radius-2 footprint;
about 7 m across the planted claws, 7.6 m nose to tail, the back at 2.1 m,
the mound at 2.6 m and the tallest reeds at 4.3 m.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "monster_rig"))
import rigkit  # noqa: E402
import shapes_mb as sh  # noqa: E402
import ext_spirewalker as ext  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "monsters", "spirewalker.glb")
JSON_OUT = os.path.join(ROOT, "art", "monsters", "monsters.json")
BLEND_OUT = os.path.join(ROOT, "art", "monsters", "blend", "spirewalker.blend")

VERSION = 2   # bump when bones, sockets or proportions change (2: Phase 3.5 toad body, mound, vines)

# palette (vertex COLOR; sRGB intent)
MUSTARD = (0.75, 0.58, 0.22)
OCHRE = (0.58, 0.40, 0.14)
SAND = (0.88, 0.78, 0.52)
MOUND = (0.46, 0.35, 0.13)
OLIVE = (0.40, 0.40, 0.15)
FROND = (0.48, 0.48, 0.15)
COPPER = (0.76, 0.40, 0.16)
BRISTLE = (0.50, 0.28, 0.12)
VIOLET = (0.62, 0.32, 0.96)
IVORY = (0.95, 0.93, 0.84)
AMBER = (0.98, 0.72, 0.16)
CLAW = (0.90, 0.88, 0.80)
HORN = (0.36, 0.26, 0.16)
MOUTH = (0.50, 0.16, 0.14)
BROW = (0.62, 0.44, 0.16)


def S(y, z, rx, rz, drop=0.0, role=None, flat=None, x=0.0):
    d = {"p": (x, y, z), "rx": rx, "rz": rz, "drop": drop}
    if role:
        d["role"] = role
    if flat is not None:
        d["flat"] = flat
    return d


def R(y, z, rx, rz, flat=1.0):
    return {"p": (0.0, y, z), "rx": rx, "rz": rz, "flat": flat}


def leg(lid, parent, sx, hip, knee, ankle, toe, radii, paw, claw_len, bulge=1.18, fingers=3):
    """A short, thick, planted limb on side sx (+1 left, -1 right): the
    elbow juts out level with the hip, the forearm drops to a broad paw."""
    m = lambda p: (sx * p[0], p[1], p[2])
    return {"id": lid, "parent": parent, "hip": m(hip), "knee": m(knee), "ankle": m(ankle), "toe": m(toe),
            "radii": radii, "sides": 10, "blend": 0.2,
            "limb": {"bulge": bulge, "fore_bulge": 1.12, "paw": paw, "fingers": fingers, "finger_len": 0.24,
                     "finger_r": 0.11, "claw_len": claw_len, "claw_r": 0.10, "fan_deg": 44.0}}


def vine(name, parent, pts, r0=0.11, r1=0.05):
    n = len(pts)
    st = [S(p[1], p[2], r0 + (r1 - r0) * i / (n - 1), r0 + (r1 - r0) * i / (n - 1), role="reed", x=p[0])
          for i, p in enumerate(pts)]
    return {"name": name, "parent": parent, "sides": 6, "blend": 0.25, "mottle": False, "belly": False,
            "cap_start": True, "cap_end": True, "stations": st,
            "bones": [("%s_%d" % (name, i), i, i + 1) for i in range(n - 1)]}


SPEC = {
    "id": "spirewalker",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": MUSTARD, "belly": SAND, "mound": MOUND, "frond": FROND, "reed": COPPER, "bristle": BRISTLE,
              "arc": VIOLET, "mouth": MOUTH, "teeth": IVORY, "eye": AMBER, "claw": CLAW},
    "mottle": {"role": "hide", "alt": OCHRE, "amount": 0.5},
    "belly": {"role": "belly", "below": -0.2},
    "chains": [
        {   # hips -> broad low toad body -> chest -> neck base
            "name": "spine", "parent": "root", "sides": 14, "blend": 0.5, "flat": 0.7, "mottle": True,
            "cap_start": False, "cap_end": False,
            "stations": [
                S(1.40, 1.00, 1.45, 0.80),
                S(0.50, 1.10, 1.90, 0.95),
                S(-0.50, 1.12, 1.95, 0.95),
                S(-1.40, 1.02, 1.70, 0.85),
                S(-2.05, 0.92, 1.30, 0.68),
            ],
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck -> the back of the skull (the wide toad skull is ext_spirewalker's)
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.3, "flat": 0.6, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": [
                S(-2.05, 0.92, 1.30, 0.68),
                S(-2.55, 0.90, 1.25, 0.60),
                S(-2.95, 0.88, 1.15, 0.52),
            ],
            "bones": [("neck", 0, 1), ("head", 1, 2)],
        },
        {   # short thick crocodile tail (the tail drag)
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.35, "flat": 0.9, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": [
                S(1.40, 1.00, 1.45, 0.80),
                S(2.20, 0.80, 0.95, 0.45),
                S(2.85, 0.62, 0.60, 0.28),
                S(3.40, 0.50, 0.28, 0.12),
            ],
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3)],
        },
        # the whip vines (the reed lash): two long ones trailing off the rear of
        # the mound, two shorter off its flanks; copper, so the charge and the
        # burn reach them like the reeds
        vine("vine_0", "spine_0", [(0.45, 0.95, 2.30), (0.70, 1.55, 2.95), (1.00, 2.30, 3.00), (1.30, 3.00, 2.65),
                                   (1.48, 3.50, 2.22), (1.42, 3.30, 2.50)], 0.075, 0.03),
        vine("vine_1", "spine_0", [(-0.45, 0.95, 2.30), (-0.70, 1.55, 2.95), (-1.00, 2.30, 3.00), (-1.30, 3.00, 2.65),
                                   (-1.48, 3.50, 2.22), (-1.42, 3.30, 2.50)], 0.075, 0.03),
        vine("vine_2", "spine_1", [(1.00, 0.20, 2.40), (1.60, 0.60, 3.05), (2.10, 1.30, 3.10), (2.40, 2.00, 2.75),
                                   (2.50, 2.50, 2.38), (2.36, 2.30, 2.62)], 0.07, 0.03),
        vine("vine_3", "spine_1", [(-1.00, 0.20, 2.40), (-1.60, 0.60, 3.05), (-2.10, 1.30, 3.10), (-2.40, 2.00, 2.75),
                                   (-2.50, 2.50, 2.38), (-2.36, 2.30, 2.62)], 0.07, 0.03),
    ],
    "extra_bones": [
        ("jaw", "head", (0.0, -2.75, 0.62), (0.0, -4.25, 0.55), rigkit.UP),
    ],
    # the wide flat toad skull, a flat palate at the grin line (~0.6 m)
    "skull": {"bone": "head", "sides": 12, "palate_below": -0.62, "rings": [
        R(-2.55, 0.98, 1.30, 0.62, 0.61),
        R(-3.05, 1.02, 1.42, 0.60, 0.70),
        R(-3.55, 0.92, 1.30, 0.48, 0.67),
        R(-3.95, 0.82, 1.08, 0.38, 0.58),
        R(-4.20, 0.76, 0.80, 0.28, 0.57),
    ]},
    "lower_jaw": {"bone": "jaw", "sides": 10, "teeth": 8, "tooth": 0.14, "mouth_above": 0.75, "belly_below": 0.0,
                  "rings": [R(-2.70, 0.38, 1.20, 0.24), R(-3.20, 0.34, 1.30, 0.28), R(-3.70, 0.38, 1.12, 0.24),
                            R(-4.05, 0.44, 0.86, 0.18), R(-4.25, 0.50, 0.60, 0.12)]},
    "upper_teeth": {"bone": "head", "at": (0.0, -2.85, 0.70), "width": 2.2, "length": 1.30, "tip_w": 0.5,
                    "teeth": 8, "tooth": 0.17},
    "brows": [
        {"bone": "head", "at": (0.82, -2.95, 1.62), "size": (0.44, 0.44, 0.22), "color": BROW},
        {"bone": "head", "at": (-0.82, -2.95, 1.62), "size": (0.44, 0.44, 0.22), "color": BROW},
    ],
    # the horned-lizard crown: raked back off the rear of the skull
    "horns": {"bone": "head", "length": 0.55, "back": 1.3, "role": "claw",
              "at": [(-1.05, -2.55, 1.22), (-0.62, -2.50, 1.42), (0.62, -2.50, 1.42), (1.05, -2.55, 1.22)]},
    "eyes": [
        {"bone": "head", "at": (0.96, -3.22, 1.42), "r": 0.19},
        {"bone": "head", "at": (-0.96, -3.22, 1.42), "r": 0.19},
    ],
    # the raised mound on the back (darker ochre): the reed bed grows out of it
    "mound": {"bones": ["hips", "spine_0", "spine_1", "chest"], "role": "mound", "sides": 14, "stations": [
        R(1.25, 1.75, 0.85, 0.22), R(0.55, 1.85, 1.45, 0.62), R(-0.35, 1.86, 1.52, 0.74), R(-1.20, 1.76, 1.15, 0.50),
        R(-1.75, 1.62, 0.60, 0.20)]},
    "reeds": {
        "role": "reed", "bead_role": "arc",
        "rows": [0.95, 0.60, 0.25, -0.10, -0.45, -0.80, -1.15],
        "per_row": 10, "span": 1.35, "length": (0.75, 1.75), "spire": (1.45, 1.25, -0.1), "lean_back": 0.06,
        "thick": 0.035, "beads": 9, "bead_r": 0.085, "bead_gap": 0.45,
        # (bone, parent, y from, y to): the bed folds flat by pitching these
        "bones": [("reed_0", "spine_0", 0.4, 1.3), ("reed_1", "spine_1", -0.4, 0.4), ("reed_2", "chest", -1.5, -0.4)],
    },
    # broad fronds splayed round the mound's base (the reference's leaf skirt)
    "fronds": {"bones": ["hips", "spine_0", "spine_1", "chest"], "role": "frond", "centre": (0.0, -0.15),
               "radius": (1.30, 1.30), "length": 2.0, "width": 0.95, "droop": 0.95,
               "angles": [-55.0, -15.0, 25.0, 65.0, 115.0, 155.0, 195.0, 235.0]},
    "thorns": {"chains": ["vine_0", "vine_1", "vine_2", "vine_3"], "role": "bristle", "length": 0.16},
    "legs": [
        # three pairs, short and thick, planted wide; the elbows jut out level.
        # Front pair = the forearms (bristles live on their knee->ankle segment).
        leg("fl", "chest", 1, (1.55, -1.60, 0.90), (2.30, -1.85, 0.95), (2.45, -2.15, 0.30), (2.55, -2.85, 0.06),
            (0.50, 0.42, 0.34), (0.86, 0.76, 0.26), 0.50),
        leg("fr", "chest", -1, (1.55, -1.60, 0.90), (2.30, -1.85, 0.95), (2.45, -2.15, 0.30), (2.55, -2.85, 0.06),
            (0.50, 0.42, 0.34), (0.86, 0.76, 0.26), 0.50),
        leg("ml", "spine_1", 1, (1.80, -0.30, 0.90), (2.65, -0.30, 0.92), (2.80, -0.35, 0.28), (3.05, -0.75, 0.06),
            (0.44, 0.36, 0.30), (0.72, 0.66, 0.24), 0.40),
        leg("mr", "spine_1", -1, (1.80, -0.30, 0.90), (2.65, -0.30, 0.92), (2.80, -0.35, 0.28), (3.05, -0.75, 0.06),
            (0.44, 0.36, 0.30), (0.72, 0.66, 0.24), 0.40),
        leg("hl", "hips", 1, (1.50, 1.10, 0.88), (2.30, 1.40, 0.92), (2.35, 1.75, 0.28), (2.50, 2.30, 0.06),
            (0.52, 0.40, 0.32), (0.76, 0.70, 0.24), 0.40, bulge=1.25),
        leg("hr", "hips", -1, (1.50, 1.10, 0.88), (2.30, 1.40, 0.92), (2.35, 1.75, 0.28), (2.50, 2.30, 0.06),
            (0.52, 0.40, 0.32), (0.76, 0.70, 0.24), 0.40, bulge=1.25),
    ],
    "bristles": [
        {"leg": "fl", "count": 5, "length": 0.28, "role": "bristle", "dirs": 2},
        {"leg": "fr", "count": 5, "length": 0.28, "role": "bristle", "dirs": 2},
    ],
    "sockets": {
        "mouth": ("head", (0.0, -4.05, 0.62)),
        "back": ("spine_1", (0.0, -0.40, 2.60)),
        "reeds": ("reed_1", (0.0, 0.00, 3.65)),
        "tail_tip": ("tail_2", (0.0, 3.35, 0.50)),
        "arm_l": ("knee_fl", (2.45, -2.15, 0.60)),
        "arm_r": ("knee_fr", (-2.45, -2.15, 0.60)),
        "head_top": ("head", (0.0, -3.00, 1.62)),
    },
}
SPEC["extra_bones"] += ext.reed_bones(SPEC)


def main():
    row = ext.build(SPEC, GLB_OUT, BLEND_OUT)
    row["generator"] = "tools/blender/build_monster_spirewalker.py"
    sh.append_manifest(JSON_OUT, row)
    print("STATS", {k: row[k] for k in ("tris", "verts", "length", "height", "width")})
    print("SOCKETS", sorted(row["sockets"].keys()))
    print("BONES", len(row["bones"]))
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT)
    assert row["tris"] < 7000, "tris over budget: %d" % row["tris"]


main()
