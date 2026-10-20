"""Colambros: the caldera monster (H10, H11), built with rigkit + ext_colambros.

    blender -b --factory-startup --python tools/blender/build_monster_colambros.py

Writes (never hand-edit these; change this script and rebuild):
    art/monsters/colambros.glb          body + deform bones + sockets (no baked
                                        clips: HHColambrosClips poses it at run time)
    art/monsters/monsters.json          its manifest row, appended beside the others
    art/monsters/blend/colambros.blend  reference only (.gdignore keeps Godot off it)

The kickoff (Lane E, Colambros): long and low, a hyena stretched into a
lizard; strong kangaroo rear legs, almost vestigial front legs; it likes to
walk on its rear legs (the REST POSE is that biped stance; the clips drop it
to all fours for the sprint); a ridge of long quills down the spine that
sways when it runs; rust-red hide, ash-white belly, bone quills darkening to
the tips. Reference: design/kickoff/ref/monster_colambros.png (a brute
wyvern standing tall on its hind legs, arms tucked, spiked tail out behind).

Blender coordinates: Z up, faces -Y, left +X, metres. Radius-2-hex footprint,
about 7.5 m nose to tail tip, hips 1.75 m up, head 2.6 m: the player rig
(2.2 m) looks it in the eye.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "monster_rig"))
import rigkit  # noqa: E402
import ext_colambros as ext  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "monsters", "colambros.glb")
JSON_OUT = os.path.join(ROOT, "art", "monsters", "monsters.json")
BLEND_OUT = os.path.join(ROOT, "art", "monsters", "blend", "colambros.blend")

VERSION = 2   # bump when bones, sockets or proportions change (2: forequarters raised, ankles lowered, arms lengthened)

# palette (vertex COLOR; sRGB intent)
RUST = (0.64, 0.24, 0.12)
RUST_DARK = (0.42, 0.14, 0.08)
ASH = (0.86, 0.83, 0.76)
BONE = (0.90, 0.85, 0.70)
CHAR = (0.16, 0.11, 0.09)
IVORY = (0.95, 0.93, 0.85)
EMBER = (1.0, 0.62, 0.12)
HORN = (0.20, 0.16, 0.14)


def S(y, z, rx, rz, drop=0.0, role=None):
    d = {"p": (0.0, y, z), "rx": rx, "rz": rz, "drop": drop}
    if role:
        d["role"] = role
    return d


# the dorsal line (top of the body loft) from the skull to mid-tail, for the quill row
SPINE_ST = [
    S(0.55, 1.75, 0.80, 0.78),     # hips (over the rear legs)
    S(-0.30, 2.05, 0.76, 0.74),    # spine_0
    S(-1.15, 2.38, 0.70, 0.68),    # spine_1
    S(-1.85, 2.62, 0.60, 0.60),    # chest
    S(-2.35, 2.74, 0.42, 0.42),    # neck base
]
NECK_ST = [
    S(-2.35, 2.74, 0.42, 0.42),
    S(-2.90, 2.92, 0.40, 0.40),
    S(-3.35, 3.00, 0.50, 0.46),    # skull
    S(-3.95, 2.90, 0.34, 0.28),    # snout
    S(-4.35, 2.82, 0.22, 0.17),    # nose
]
TAIL_ST = [
    S(0.55, 1.75, 0.80, 0.78),
    S(1.45, 1.42, 0.60, 0.52),
    S(2.25, 1.02, 0.42, 0.36),
    S(2.95, 0.62, 0.27, 0.24),
    S(3.45, 0.36, 0.14, 0.12),
]


def dorsal(st):
    return [(0.0, s["p"][1], s["p"][2] + s["rz"]) for s in st]


# the ridge: skull -> hips -> mid tail, as one polyline (forward first)
RIDGE = [dorsal(NECK_ST)[2], dorsal(NECK_ST)[0]] + list(reversed(dorsal(SPINE_ST)[:-1])) + dorsal(TAIL_ST)[1:3]
N_QUILLS = 14
QUILL_NAMES = ["quill_%d" % i for i in range(N_QUILLS)]


def quill_len(u):
    # short on the skull, longest over the shoulders and hips, short on the tail
    import math
    return 0.28 + 0.62 * math.sin(math.pi * min(1.0, max(0.0, (u - 0.02) / 0.9))) ** 0.8


QUILLS = ext.quill_row(RIDGE, QUILL_NAMES, N_QUILLS, quill_len, rake=0.6, lift=0.06, start=0.03, end=0.95, width=0.12)


def quill_parent(it):
    y = it["base"][1]
    if y < -2.95:
        return "head"
    if y < -2.35:
        return "neck"
    if y < -1.5:
        return "chest"
    if y < -0.7:
        return "spine_1"
    if y < 0.15:
        return "spine_0"
    if y < 1.0:
        return "hips"
    if y < 1.85:
        return "tail_0"
    return "tail_1"


SPEC = {
    "id": "colambros",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": RUST, "belly": ASH, "quill": BONE, "teeth": IVORY, "eye": EMBER, "claw": HORN},
    "mottle": {"role": "hide", "alt": RUST_DARK, "amount": 0.36},
    "belly": {"role": "belly", "below": -0.25},
    "chains": [
        {   # hips -> chest -> neck base (the long low body, angled up in the biped stance)
            "name": "spine", "parent": "root", "sides": 12, "blend": 0.45, "flat": 0.66, "mottle": True,
            "cap_start": False, "cap_end": False,
            "stations": SPINE_ST,
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck -> hyena skull -> snout
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.35, "flat": 0.8, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": NECK_ST,
            "bones": [("neck", 0, 1), ("head", 1, 4)],
        },
        {   # hips -> thick lizard tail, low behind, counterweight
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.4, "flat": 0.85, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": TAIL_ST,
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3), ("tail_3", 3, 4)],
        },
    ],
    "extra_bones": [
        ("jaw", "head", (0.0, -3.45, 2.74), (0.0, -4.35, 2.68), rigkit.UP),
    ] + ext.quill_bones(QUILLS, quill_parent),
    "jaw": {"bone": "jaw", "width": 0.80, "length": 0.95, "height": 0.26, "tip_w": 0.55,
            "teeth": 5, "tooth": 0.16, "role": "belly", "teeth_role": "teeth"},
    "upper_teeth": {"bone": "head", "at": (0.0, -3.51, 2.72), "width": 0.84, "length": 0.90, "tip_w": 0.55,
                    "teeth": 5, "tooth": 0.17},
    "quills": {"role": "quill", "tip": CHAR, "items": QUILLS},
    "fins": [
        # hyena ears: two short blades on the skull
        {"bone": "head", "base": (0.30, -3.20, 3.33), "tip": (0.42, -3.00, 3.73), "root_len": 0.3, "role": "hide"},
        {"bone": "head", "base": (-0.30, -3.20, 3.33), "tip": (-0.42, -3.00, 3.73), "root_len": 0.3, "role": "hide"},
    ],
    "eyes": [
        {"bone": "head", "at": (0.40, -3.57, 3.16), "r": 0.13},
        {"bone": "head", "at": (-0.40, -3.57, 3.16), "r": 0.13},
    ],
    "legs": [
        # kangaroo rear legs: thigh forward-down, shin back, long digitigrade foot forward
        # (the ankle sits low, 0.30 m, so rigkit's ground-snapped foot box meets the wrist ball: round 1 had floating feet)
        {"id": "hl", "parent": "hips", "hip": (0.50, 0.55, 1.65), "knee": (0.68, -0.25, 1.10),
         "ankle": (0.70, 0.60, 0.30), "toe": (0.70, -0.45, 0.07), "radii": (0.46, 0.32, 0.21),
         "foot": (0.48, 1.30, 0.20), "claws": 3, "claw_len": 0.34, "sides": 8, "toe_len": 0.4},
        {"id": "hr", "parent": "hips", "hip": (-0.50, 0.55, 1.65), "knee": (-0.68, -0.25, 1.10),
         "ankle": (-0.70, 0.60, 0.30), "toe": (-0.70, -0.45, 0.07), "radii": (0.46, 0.32, 0.21),
         "foot": (0.48, 1.30, 0.20), "claws": 3, "claw_len": 0.34, "sides": 8, "toe_len": 0.4},
        # vestigial arms, hanging off the chest, tucked (ext: "hang" keeps the paw at the wrist)
        {"id": "fl", "parent": "chest", "hip": (0.46, -1.80, 2.30), "knee": (0.58, -1.60, 1.75),
         "ankle": (0.60, -1.95, 1.30), "toe": (0.60, -2.32, 1.14), "radii": (0.17, 0.13, 0.10),
         "foot": (0.26, 0.40, 0.14), "claws": 3, "claw_len": 0.18, "sides": 6, "blend": 0.1, "hang": True},
        {"id": "fr", "parent": "chest", "hip": (-0.46, -1.80, 2.30), "knee": (-0.58, -1.60, 1.75),
         "ankle": (-0.60, -1.95, 1.30), "toe": (-0.60, -2.32, 1.14), "radii": (0.17, 0.13, 0.10),
         "foot": (0.26, 0.40, 0.14), "claws": 3, "claw_len": 0.18, "sides": 6, "blend": 0.1, "hang": True},
    ],
    "sockets": {
        "mouth": ("head", (0.0, -4.30, 2.74)),
        "head_top": ("head", (0.0, -3.35, 3.48)),
        "back": ("spine_1", (0.0, -1.15, 3.08)),
        "hips_top": ("hips", (0.0, 0.55, 2.55)),
        "tail_tip": ("tail_3", (0.0, 3.45, 0.36)),
        "chest": ("chest", (0.0, -1.85, 2.02)),
    },
}


def main():
    ext.install(rigkit)
    row = rigkit.build(SPEC, GLB_OUT, BLEND_OUT)
    row["generator"] = "tools/blender/build_monster_colambros.py"
    row["quills"] = QUILL_NAMES
    row["stance"] = "biped"
    row["arms"] = ["fl", "fr"]
    rigkit.write_manifest(JSON_OUT, [row], "tools/blender/build_monster_*.py + monster_rig/rigkit.py")
    print("STATS", {k: row[k] for k in ("tris", "verts", "length", "height", "width")})
    print("SOCKETS", sorted(row["sockets"].keys()))
    print("QUILLS", len(QUILL_NAMES))
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT)
    assert row["tris"] < 6000, "tris over budget: %d" % row["tris"]


main()
