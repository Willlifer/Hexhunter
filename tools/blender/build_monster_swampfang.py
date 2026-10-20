"""Swampfang: the Phase 1 monster (H5, H14), built with rigkit plus the Lane MB
extension (monster_rig/ext_swampfang.py, monster_rig/shapes_mb.py).

    blender -b --factory-startup --python tools/blender/build_monster_swampfang.py

Writes (never hand-edit these; change this script and rebuild):
    art/monsters/swampfang.glb        body + deform bones + sockets (no baked clips:
                                      HHSwampfangClips poses the skeleton at run time)
    art/monsters/swampfang.glb.import Godot import stub (only if missing)
    art/monsters/monsters.json        its row replaced in place (other rows kept)
    art/monsters/blend/swampfang.blend  reference only (.gdignore keeps Godot off it)

The kickoff (Lane E, Swampfang): a long, eel-bodied salamander with a frilled
gill collar, strong front legs, small weak hind legs, a flat paddle tail;
mottled blue and lavender, a red frill that flares when angry. Reference:
design/kickoff/ref/monster_swampfang.png (Feraligatr-style fanged wyvern):
a heavy crocodilian skull and deep jaw, a cream throat and belly, thick
clawed forearms, raised scale plates, big swept red fins (Phase 3.5 gauntlet,
design/art/monsters/SWAMPFANG.md).

Blender coordinates: Z up, faces -Y, left +X, metres. Radius-2-hex footprint
(hexes are 1 m), about 9.7 m nose to tail, shoulders 2.8 m high: the player
rig (2.2 m) stands as tall as its chest.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "monster_rig"))
import rigkit  # noqa: E402
import shapes_mb as sh  # noqa: E402
import ext_swampfang as ext  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "monsters", "swampfang.glb")
JSON_OUT = os.path.join(ROOT, "art", "monsters", "monsters.json")
BLEND_OUT = os.path.join(ROOT, "art", "monsters", "blend", "swampfang.blend")

VERSION = 2   # bump when bones, sockets or proportions change (2: Phase 3.5 gauntlet head, arms, fins)

# palette (vertex COLOR; sRGB intent)
BLUE = (0.30, 0.50, 0.80)
LAVENDER = (0.64, 0.50, 0.84)
PLATE_BLUE = (0.24, 0.40, 0.70)
PLATE_LAV = (0.52, 0.40, 0.76)
CREAM = (0.92, 0.86, 0.66)
RED = (0.86, 0.22, 0.20)
FIN = (0.84, 0.30, 0.26)
MOUTH = (0.55, 0.12, 0.16)
IVORY = (0.96, 0.94, 0.86)
AMBER = (0.98, 0.78, 0.18)
CLAW = (0.82, 0.80, 0.72)


def S(y, z, rx, rz, drop=0.0, role=None):
    d = {"p": (0.0, y, z), "rx": rx, "rz": rz, "drop": drop}
    if role:
        d["role"] = role
    return d


def R(y, z, rx, rz, flat=1.0):
    return {"p": (0.0, y, z), "rx": rx, "rz": rz, "flat": flat}


def front_leg(lid, sx):
    m = lambda p: (sx * p[0], p[1], p[2])
    return {"id": lid, "parent": "chest", "hip": m((0.95, -1.65, 1.50)), "knee": m((1.50, -1.98, 0.90)),
            "ankle": m((1.56, -1.80, 0.34)), "toe": m((1.56, -2.60, 0.06)), "radii": (0.60, 0.46, 0.36),
            "sides": 10, "blend": 0.22,
            "limb": {"bulge": 1.2, "fore_bulge": 1.18, "paw": (0.98, 0.86, 0.30), "fingers": 3, "finger_len": 0.30,
                     "finger_r": 0.13, "claw_len": 0.52, "claw_r": 0.11, "fan_deg": 38.0}}


SPEC = {
    "id": "swampfang",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": BLUE, "belly": CREAM, "frill": RED, "fin": FIN, "mouth": MOUTH, "teeth": IVORY, "eye": AMBER,
              "claw": CLAW},
    "mottle": {"role": "hide", "alt": LAVENDER, "amount": 0.42},
    "belly": {"role": "belly", "below": -0.12},
    "chains": [
        {   # hips -> heavy shoulders -> neck base
            "name": "spine", "parent": "root", "sides": 12, "blend": 0.45, "flat": 0.62, "mottle": True,
            "cap_start": False, "cap_end": False,
            "stations": [
                S(1.30, 1.05, 0.95, 0.85),
                S(0.40, 1.20, 1.10, 1.00),
                S(-0.60, 1.40, 1.22, 1.12),
                S(-1.50, 1.60, 1.32, 1.18),
                S(-2.25, 1.66, 0.94, 0.86),
            ],
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck -> the back of the skull (the skull itself is ext_swampfang's)
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.35, "flat": 0.75, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": [
                S(-2.25, 1.66, 0.94, 0.86),
                S(-2.90, 1.72, 0.86, 0.80),
                S(-3.40, 1.76, 0.78, 0.66),
            ],
            "bones": [("neck", 0, 1), ("head", 1, 2)],
        },
        {   # hips -> paddle tail
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.4, "flat": 0.9, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": [
                S(1.30, 1.05, 0.95, 0.85),
                S(2.20, 0.95, 0.80, 0.58),
                S(3.00, 0.82, 0.66, 0.38),
                S(3.75, 0.68, 0.98, 0.22),
                S(4.35, 0.58, 0.82, 0.10),
            ],
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3), ("tail_3", 3, 4)],
        },
    ],
    "extra_bones": [
        # (name, parent, head, tail, roll hint)
        ("jaw", "head", (0.0, -3.35, 1.42), (0.0, -5.20, 1.30), rigkit.UP),
        ("frill_l", "neck", (0.55, -3.0, 1.82), (1.10, -3.0, 1.99), rigkit.UP),
        ("frill_r", "neck", (-0.55, -3.0, 1.82), (-1.10, -3.0, 1.99), rigkit.UP),
    ],
    # the heavy crocodilian skull: wide brow, long broad snout, flat palate
    "skull": {"bone": "head", "sides": 12, "palate_below": -0.62, "rings": [
        R(-2.95, 1.80, 0.86, 0.74, 0.50),
        R(-3.45, 1.88, 1.00, 0.66, 0.66),
        R(-3.95, 1.78, 0.90, 0.55, 0.62),
        R(-4.55, 1.62, 0.76, 0.42, 0.45),
        R(-5.05, 1.53, 0.66, 0.32, 0.34),
        R(-5.32, 1.48, 0.50, 0.24, 0.30),
    ]},
    # the deep lower jaw: red mouth on top, cream underneath, teeth on both lips
    "lower_jaw": {"bone": "jaw", "sides": 10, "teeth": 6, "tooth": 0.2, "mouth_above": 0.75, "belly_below": 0.05,
                  "rings": [R(-3.15, 1.14, 0.80, 0.32), R(-3.70, 1.08, 0.82, 0.38), R(-4.30, 1.13, 0.72, 0.32),
                            R(-4.85, 1.22, 0.58, 0.24), R(-5.22, 1.30, 0.48, 0.16)]},
    "upper_teeth": {"bone": "head", "at": (0.0, -3.60, 1.58), "width": 1.5, "length": 1.6, "tip_w": 0.55,
                    "teeth": 6, "tooth": 0.24},
    # the cream throat pouch, jaw hinge to chest
    "throat": {"bones": ["chest", "neck", "head"], "blend": 0.5, "belly_below": 0.8, "sides": 10, "rings": [
        R(-3.30, 1.12, 0.78, 0.42), R(-2.85, 1.02, 0.92, 0.62), R(-2.30, 1.08, 1.00, 0.68), R(-1.70, 1.18, 1.00, 0.62),
        R(-1.15, 1.26, 0.90, 0.50)]},
    "brows": [
        {"bone": "head", "at": (0.80, -3.50, 2.20), "size": (0.40, 0.48, 0.24), "color": PLATE_BLUE},
        {"bone": "head", "at": (-0.80, -3.50, 2.20), "size": (0.40, 0.48, 0.24), "color": PLATE_BLUE},
    ],
    "frill": {"bones": ["frill_l", "frill_r"], "spikes": 5, "length": 1.35, "sweep": 0.6, "top_deg": 72.0,
              "bottom_deg": -28.0, "neck_rx": 0.78, "neck_rz": 0.72, "centre": (0.0, -3.0, 1.70), "web": 0.72,
              "thick": 0.035, "role": "frill"},
    # the reference's swept red sails: a crest behind the brow, two dorsal sails, the tail sail
    "sails": [
        # the crest and the dorsal sails ride fold bones (fin_0..fin_2): calm and
        # submerged clips lay them flat so only the frill shows (kickoff: calm)
        {"ra": (0.0, -3.85, 2.20), "rb": (0.0, -3.10, 2.42), "tip": (0.0, -2.45, 3.25), "bones": ["head"],
         "bone": "fin_0", "parent": "head", "bow": 0.12, "hollow": 0.22},
        {"ra": (0.0, -2.05, 2.50), "rb": (0.0, -0.75, 2.45), "tip": (0.0, 0.70, 4.05),
         "bone": "fin_1", "parent": "spine_1", "bones": ["chest", "spine_1", "spine_0"], "bow": 0.12, "hollow": 0.24,
         "ribs": 3},
        {"ra": (0.0, -0.20, 2.32), "rb": (0.0, 0.95, 1.98), "tip": (0.0, 1.95, 3.55),
         "bone": "fin_2", "parent": "spine_0", "bones": ["spine_0", "hips"], "bow": 0.12, "hollow": 0.24, "ribs": 2},
        {"ra": (0.0, 1.90, 1.58), "rb": (0.0, 3.90, 0.80), "tip": (0.0, 4.40, 2.55),
         "bones": ["tail_0", "tail_1", "tail_2", "tail_3"], "blend": 0.5, "bow": 0.10, "hollow": 0.26, "ribs": 3},
    ],
    # raised scale plates flanking the sails, down the back and the tail
    "plates": [
        {"chain": "spine", "bones": ["hips", "spine_0", "spine_1", "chest"], "r": 0.22, "h": 0.07,
         "ys": [-2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0], "xs": [0.52, -0.52],
         "colors": [PLATE_BLUE, PLATE_LAV, PLATE_BLUE, PLATE_LAV, PLATE_LAV, PLATE_BLUE]},
        {"chain": "tail", "bones": ["tail_0", "tail_1", "tail_2"], "r": 0.16, "h": 0.06,
         "ys": [1.65, 2.15, 2.65, 3.15], "xs": [0.32, -0.32], "colors": [PLATE_BLUE, PLATE_LAV]},
        {"chain": "neck", "bones": ["neck", "chest"], "r": 0.2, "h": 0.1,
         "ys": [-2.45], "xs": [0.4, -0.4], "colors": [PLATE_LAV]},
    ],
    "eyes": [
        {"bone": "head", "at": (0.93, -3.64, 2.00), "r": 0.15},
        {"bone": "head", "at": (-0.93, -3.64, 2.00), "r": 0.15},
    ],
    "legs": [
        # strong front legs (shoulders on the chest), small weak hind legs (on the hips)
        front_leg("fl", 1),
        front_leg("fr", -1),
        {"id": "hl", "parent": "hips", "hip": (0.62, 1.20, 0.85), "knee": (0.92, 0.92, 0.46),
         "ankle": (0.98, 1.35, 0.20), "toe": (0.98, 0.92, 0.04), "radii": (0.20, 0.15, 0.12),
         "foot": (0.30, 0.46, 0.12), "claws": 3, "claw_len": 0.20, "sides": 6, "blend": 0.12},
        {"id": "hr", "parent": "hips", "hip": (-0.62, 1.20, 0.85), "knee": (-0.92, 0.92, 0.46),
         "ankle": (-0.98, 1.35, 0.20), "toe": (-0.98, 0.92, 0.04), "radii": (0.20, 0.15, 0.12),
         "foot": (0.30, 0.46, 0.12), "claws": 3, "claw_len": 0.20, "sides": 6, "blend": 0.12},
    ],
    "sockets": {
        "mouth": ("head", (0.0, -5.00, 1.42)),
        "frill": ("neck", (0.0, -3.00, 1.95)),
        "back": ("spine_1", (0.0, -0.60, 2.55)),
        "tail_tip": ("tail_3", (0.0, 4.35, 0.58)),
        "head_top": ("head", (0.0, -3.45, 2.50)),
    },
}
SPEC["extra_bones"] += ext.sail_bones(SPEC)


def main():
    row = ext.build(SPEC, GLB_OUT, BLEND_OUT)
    row["generator"] = "tools/blender/build_monster_swampfang.py"
    sh.append_manifest(JSON_OUT, row)
    print("STATS", {k: row[k] for k in ("tris", "verts", "length", "height", "width")})
    print("SOCKETS", sorted(row["sockets"].keys()))
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT)
    assert row["tris"] < 6000, "tris over budget: %d" % row["tris"]


main()
