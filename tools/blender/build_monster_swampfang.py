"""Swampfang: the Phase 1 monster (H5, H14), built from nothing with rigkit.

    blender -b --factory-startup --python tools/blender/build_monster_swampfang.py

Writes (never hand-edit these; change this script and rebuild):
    art/monsters/swampfang.glb        body + deform bones + sockets (no baked clips:
                                      HHSwampfangClips poses the skeleton at run time)
    art/monsters/swampfang.glb.import Godot import stub (only if missing)
    art/monsters/monsters.json        the manifest row (bones, chains, legs, sockets,
                                      aabb, tris, length, height, footprint_hexes)
    art/monsters/blend/swampfang.blend  reference only (.gdignore keeps Godot off it)

The kickoff (Lane E, Swampfang): a long, eel-bodied salamander with a frilled
gill collar, strong front legs, small weak hind legs, a flat paddle tail;
mottled blue and lavender, a red frill that flares when angry. Reference:
design/kickoff/ref/monster_swampfang.png (Feraligatr-style fanged wyvern).

Blender coordinates: Z up, faces -Y, left +X, metres. Radius-2-hex footprint
(hexes are 1 m), about 8.9 m nose to tail, shoulders 2.5 m high: the player
rig (2.2 m) stands as tall as its chest.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "monster_rig"))
import rigkit  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "monsters", "swampfang.glb")
JSON_OUT = os.path.join(ROOT, "art", "monsters", "monsters.json")
BLEND_OUT = os.path.join(ROOT, "art", "monsters", "blend", "swampfang.blend")

VERSION = 1   # bump when bones, sockets or proportions change

# palette (vertex COLOR; sRGB intent)
BLUE = (0.30, 0.50, 0.80)
LAVENDER = (0.64, 0.50, 0.84)
CREAM = (0.90, 0.86, 0.72)
RED = (0.86, 0.22, 0.20)
IVORY = (0.96, 0.94, 0.86)
AMBER = (0.98, 0.78, 0.18)
HORN = (0.22, 0.20, 0.26)


def S(y, z, rx, rz, drop=0.0, role=None):
    d = {"p": (0.0, y, z), "rx": rx, "rz": rz, "drop": drop}
    if role:
        d["role"] = role
    return d


SPEC = {
    "id": "swampfang",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": BLUE, "belly": CREAM, "frill": RED, "teeth": IVORY, "eye": AMBER, "claw": HORN},
    "mottle": {"role": "hide", "alt": LAVENDER, "amount": 0.42},
    "belly": {"role": "belly", "below": -0.3},
    "chains": [
        {   # hips -> shoulders -> neck base
            "name": "spine", "parent": "root", "sides": 12, "blend": 0.45, "flat": 0.62, "mottle": True,
            "cap_start": False, "cap_end": False,
            "stations": [
                S(1.30, 1.05, 0.95, 0.85),
                S(0.40, 1.22, 1.12, 1.02),
                S(-0.60, 1.38, 1.20, 1.10),
                S(-1.50, 1.52, 1.15, 1.05),
                S(-2.20, 1.62, 0.78, 0.72),
            ],
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck -> skull -> snout
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.35, "flat": 0.75, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": [
                S(-2.20, 1.62, 0.78, 0.72),
                S(-2.90, 1.66, 0.74, 0.68),
                S(-3.45, 1.70, 0.86, 0.70),
                S(-4.25, 1.52, 0.62, 0.40),
                S(-4.90, 1.42, 0.42, 0.24),
            ],
            "bones": [("neck", 0, 1), ("head", 1, 4)],
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
        ("jaw", "head", (0.0, -3.55, 1.32), (0.0, -4.80, 1.18), rigkit.UP),
        ("frill_l", "neck", (0.55, -3.0, 1.78), (1.10, -3.0, 1.95), rigkit.UP),
        ("frill_r", "neck", (-0.55, -3.0, 1.78), (-1.10, -3.0, 1.95), rigkit.UP),
    ],
    "jaw": {"bone": "jaw", "width": 1.0, "length": 1.30, "height": 0.32, "tip_w": 0.6,
            "teeth": 5, "tooth": 0.20, "role": "belly", "teeth_role": "teeth"},
    "upper_teeth": {"bone": "head", "at": (0.0, -3.62, 1.30), "width": 1.06, "length": 1.20, "tip_w": 0.6,
                    "teeth": 5, "tooth": 0.22},
    "frill": {"bones": ["frill_l", "frill_r"], "spikes": 5, "length": 1.3, "sweep": 0.6, "top_deg": 72.0,
              "bottom_deg": -28.0, "neck_rx": 0.72, "neck_rz": 0.66, "centre": (0.0, -3.0, 1.66), "web": 0.72,
              "thick": 0.035, "role": "frill"},
    "fins": [
        {"bone": "head", "base": (0.0, -3.30, 2.22), "tip": (0.0, -2.55, 2.95), "root_len": 0.7},
        {"bone": "chest", "base": (0.0, -1.75, 2.48), "tip": (0.0, -1.05, 3.40), "root_len": 0.9},
        {"bone": "spine_1", "base": (0.0, -0.60, 2.42), "tip": (0.0, 0.10, 3.25), "root_len": 0.9},
        {"bone": "spine_0", "base": (0.0, 0.45, 2.22), "tip": (0.0, 1.10, 2.95), "root_len": 0.8},
        {"bone": "tail_0", "base": (0.0, 1.85, 1.55), "tip": (0.0, 2.40, 2.15), "root_len": 0.6},
    ],
    "eyes": [
        {"bone": "head", "at": (0.78, -3.6, 1.92), "r": 0.17},
        {"bone": "head", "at": (-0.78, -3.6, 1.92), "r": 0.17},
    ],
    "legs": [
        # strong front legs (shoulders on the chest), small weak hind legs (on the hips)
        {"id": "fl", "parent": "chest", "hip": (0.85, -1.60, 1.45), "knee": (1.32, -1.95, 0.80),
         "ankle": (1.38, -1.65, 0.30), "toe": (1.38, -2.35, 0.06), "radii": (0.5, 0.37, 0.29),
         "foot": (0.66, 0.9, 0.24), "claws": 3, "claw_len": 0.36, "sides": 8},
        {"id": "fr", "parent": "chest", "hip": (-0.85, -1.60, 1.45), "knee": (-1.32, -1.95, 0.80),
         "ankle": (-1.38, -1.65, 0.30), "toe": (-1.38, -2.35, 0.06), "radii": (0.5, 0.37, 0.29),
         "foot": (0.66, 0.9, 0.24), "claws": 3, "claw_len": 0.36, "sides": 8},
        {"id": "hl", "parent": "hips", "hip": (0.62, 1.20, 0.85), "knee": (0.92, 0.92, 0.46),
         "ankle": (0.98, 1.35, 0.20), "toe": (0.98, 0.92, 0.04), "radii": (0.20, 0.15, 0.12),
         "foot": (0.30, 0.46, 0.12), "claws": 3, "claw_len": 0.20, "sides": 6, "blend": 0.12},
        {"id": "hr", "parent": "hips", "hip": (-0.62, 1.20, 0.85), "knee": (-0.92, 0.92, 0.46),
         "ankle": (-0.98, 1.35, 0.20), "toe": (-0.98, 0.92, 0.04), "radii": (0.20, 0.15, 0.12),
         "foot": (0.30, 0.46, 0.12), "claws": 3, "claw_len": 0.20, "sides": 6, "blend": 0.12},
    ],
    "sockets": {
        "mouth": ("head", (0.0, -4.60, 1.28)),
        "frill": ("neck", (0.0, -3.00, 1.95)),
        "back": ("spine_1", (0.0, -0.60, 2.45)),
        "tail_tip": ("tail_3", (0.0, 4.35, 0.58)),
        "head_top": ("head", (0.0, -3.45, 2.25)),
    },
}


def main():
    row = rigkit.build(SPEC, GLB_OUT, BLEND_OUT)
    row["generator"] = "tools/blender/build_monster_swampfang.py"
    rigkit.write_manifest(JSON_OUT, [row], "tools/blender/build_monster_*.py + monster_rig/rigkit.py")
    print("STATS", {k: row[k] for k in ("tris", "verts", "length", "height", "width")})
    print("SOCKETS", sorted(row["sockets"].keys()))
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT)
    assert row["tris"] < 6000, "tris over budget: %d" % row["tris"]


main()
