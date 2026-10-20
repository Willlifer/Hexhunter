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

VERSION = 3   # bump when bones, sockets or proportions change (3, H650: brute-wyvern biped: torso up 35 deg, digitigrade legs, small arms held high, big head + horns)

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


# The biped stance (H650): the hips 1.95 m up over the rear legs, the torso
# rising ~35 deg to the shoulders, an S-neck carrying a big hyena skull at
# ~3.9 m, the tail sweeping down behind to rest its tip on the ground (the
# kangaroo's third support).
SPINE_ST = [
    S(0.40, 1.95, 0.80, 0.82),     # hips (over the rear legs): the biggest mass
    S(-0.35, 2.35, 0.82, 0.80),    # spine_0 (belly)
    S(-0.95, 2.78, 0.70, 0.68),    # spine_1
    S(-1.45, 3.15, 0.56, 0.55),    # chest
    S(-1.75, 3.45, 0.42, 0.42),    # neck base
]
NECK_ST = [
    S(-1.75, 3.45, 0.42, 0.42),
    S(-2.20, 3.75, 0.40, 0.40),
    S(-2.70, 3.86, 0.60, 0.52),    # skull (wide: the hyena's cheeks)
    S(-3.30, 3.68, 0.42, 0.32),    # snout
    S(-3.75, 3.55, 0.27, 0.19),    # nose
]
TAIL_ST = [
    S(0.40, 1.95, 0.80, 0.82),
    S(1.30, 1.42, 0.60, 0.56),
    S(2.25, 0.78, 0.44, 0.40),
    S(3.30, 0.40, 0.29, 0.26),
    S(4.30, 0.22, 0.15, 0.13),
]


def dorsal(st):
    return [(0.0, s["p"][1], s["p"][2] + s["rz"]) for s in st]


# the ridge: skull -> hips -> mid tail, as one polyline (forward first)
RIDGE = [dorsal(NECK_ST)[2], dorsal(NECK_ST)[1], dorsal(NECK_ST)[0]] + list(reversed(dorsal(SPINE_ST)[:-1])) + dorsal(TAIL_ST)[1:4]
N_QUILLS = 14
QUILL_NAMES = ["quill_%d" % i for i in range(N_QUILLS)]


def quill_len(u):
    # short on the skull, longest over the shoulders and hips, short on the tail
    import math
    return 0.30 + 0.75 * math.sin(math.pi * min(1.0, max(0.0, (u - 0.02) / 0.85))) ** 0.8


QUILLS = ext.quill_row(RIDGE, QUILL_NAMES, N_QUILLS, quill_len, rake=0.55, lift=0.04, start=0.04, end=0.92, width=0.13)


def quill_parent(it):
    y = it["base"][1]
    if y < -2.2:
        return "head"
    if y < -1.75:
        return "neck"
    if y < -1.45:
        return "chest"
    if y < -0.95:
        return "spine_1"
    if y < -0.35:
        return "spine_0"
    if y < 0.40:
        return "hips"
    if y < 1.30:
        return "tail_0"
    if y < 2.25:
        return "tail_1"
    return "tail_2"


def REAR(side):
    s = 1.0 if side == "l" else -1.0
    # digitigrade kangaroo leg: thigh forward-down, shin back-down to a high hock,
    # a long metatarsus forward-down to the ball of the foot, big splayed toes
    return {"id": "h" + side, "parent": "hips", "digi": True,
            "hip": (s * 0.66, 0.40, 1.80), "knee": (s * 0.86, -0.42, 1.22),
            "ankle": (s * 0.88, 0.50, 0.86), "toe": (s * 0.88, -0.02, 0.14),
            "radii": (0.52, 0.40, 0.26, 0.21), "thigh": (0.62, 0.78, 0.74, 0.40),
            "calf": (0.36, 0.52, 0.38, 0.30),
            "toes": 3, "toe_len": 0.70, "toe_w": 0.24, "toe_spread_deg": 40.0, "claw_len": 0.30,
            "sides": 8, "blend": 0.16}


def ARM(side):
    s = 1.0 if side == "l" else -1.0
    # the small arms, held up off the ground in front of the chest (vestigial)
    return {"id": "f" + side, "parent": "chest", "hip": (s * 0.50, -1.42, 2.88), "knee": (s * 0.66, -1.40, 2.36),
            "ankle": (s * 0.58, -1.86, 2.30), "toe": (s * 0.56, -2.08, 2.04), "radii": (0.16, 0.12, 0.09),
            "foot": (0.22, 0.30, 0.12), "claws": 3, "claw_len": 0.17, "sides": 6, "blend": 0.1, "hang": True}


SPEC = {
    "id": "colambros",
    "version": VERSION,
    "footprint_hexes": 2,
    "roles": {"hide": RUST, "belly": ASH, "quill": BONE, "teeth": IVORY, "eye": EMBER, "claw": HORN},
    "mottle": {"role": "hide", "alt": RUST_DARK, "amount": 0.36},
    "belly": {"role": "belly", "below": -0.25},
    "chains": [
        {   # hips -> chest -> neck base (the torso rising to the shoulders in the biped stance)
            "name": "spine", "parent": "root", "sides": 12, "blend": 0.45, "flat": 0.8, "mottle": True,
            "cap_start": True, "cap_end": True,   # closed: an open loft gets inward belly normals (H652)
            "stations": SPINE_ST,
            "bones": [("hips", 0, 1), ("spine_0", 1, 2), ("spine_1", 2, 3), ("chest", 3, 4)],
        },
        {   # neck -> hyena skull -> snout
            "name": "neck", "parent": "chest", "sides": 12, "blend": 0.35, "flat": 0.8, "mottle": True,
            "cap_start": False, "cap_end": True,
            "stations": NECK_ST,
            "bones": [("neck", 0, 1), ("head", 1, 4)],
        },
        {   # hips -> thick lizard tail sweeping down to the ground behind
            "name": "tail", "parent": "hips", "sides": 10, "blend": 0.4, "flat": 0.85, "mottle": True,
            "cap_start": False, "cap_end": True, "belly": False,
            "stations": TAIL_ST,
            "bones": [("tail_0", 0, 1), ("tail_1", 1, 2), ("tail_2", 2, 3), ("tail_3", 3, 4)],
        },
    ],
    "extra_bones": [
        ("jaw", "head", (0.0, -2.88, 3.56), (0.0, -3.75, 3.42), rigkit.UP),
    ] + ext.quill_bones(QUILLS, quill_parent),
    "jaw": {"bone": "jaw", "width": 0.86, "length": 0.92, "height": 0.30, "tip_w": 0.55,
            "teeth": 5, "tooth": 0.17, "role": "hide", "teeth_role": "teeth"},
    "upper_teeth": {"bone": "head", "at": (0.0, -2.94, 3.54), "width": 0.90, "length": 0.86, "tip_w": 0.55,
                    "teeth": 5, "tooth": 0.18},
    "quills": {"role": "quill", "tip": CHAR, "items": QUILLS},
    "masses": [
        # the rump: closes the seam where the spine and the tail lofts meet over the hips
        {"a": (0.0, 0.05, 2.15), "b": (0.0, 1.05, 1.75), "u": 0.5, "r": (0.76, 0.66, 0.74), "w": {"hips": 0.6, "tail_0": 0.4}},
        # the shoulder knot where the neck leaves the torso (closes the joint gap when the neck pitches)
        {"a": (0.0, -1.45, 3.15), "b": (0.0, -2.05, 3.65), "u": 0.5, "r": (0.46, 0.46, 0.44), "w": {"chest": 0.5, "neck": 0.5}},
        # the chest keel (the reference's barrel chest under the shoulders)
        {"a": (0.0, -0.75, 2.70), "b": (0.0, -1.55, 3.15), "u": 0.5, "r": (0.62, 0.62, 0.66), "w": {"spine_1": 0.6, "chest": 0.4},
         "role": "belly"},
        # the cheeks and brow of the big skull
        {"a": (0.0, -2.35, 3.95), "b": (0.0, -3.10, 3.82), "u": 0.42, "r": (0.70, 0.62, 0.58), "w": {"head": 1.0}},
    ],
    "horns": [
        # two ringed horns swept back off the skull (the reference's banded horns)
        {"bone": "head", "pts": [(0.32, -2.55, 4.20), (0.55, -2.25, 4.62), (0.74, -1.80, 4.82), (0.86, -1.30, 4.74), (0.90, -0.95, 4.52)],
         "radii": [0.22, 0.19, 0.15, 0.10], "colors": [BONE, HORN]},
        {"bone": "head", "pts": [(-0.32, -2.55, 4.20), (-0.55, -2.25, 4.62), (-0.74, -1.80, 4.82), (-0.86, -1.30, 4.74), (-0.90, -0.95, 4.52)],
         "radii": [0.22, 0.19, 0.15, 0.10], "colors": [BONE, HORN]},
    ],
    "fins": [
        # short hyena ears, low on the skull behind the eyes
        {"bone": "head", "base": (0.50, -2.55, 4.02), "tip": (0.78, -2.35, 4.28), "root_len": 0.26, "role": "hide"},
        {"bone": "head", "base": (-0.50, -2.55, 4.02), "tip": (-0.78, -2.35, 4.28), "root_len": 0.26, "role": "hide"},
    ],
    "eyes": [
        {"bone": "head", "at": (0.44, -2.98, 3.98), "r": 0.13},
        {"bone": "head", "at": (-0.44, -2.98, 3.98), "r": 0.13},
    ],
    "legs": [REAR("l"), REAR("r"), ARM("l"), ARM("r")],
    "sockets": {
        "mouth": ("head", (0.0, -3.70, 3.56)),
        "head_top": ("head", (0.0, -2.70, 4.40)),
        "back": ("spine_1", (0.0, -0.95, 3.46)),
        "hips_top": ("hips", (0.0, 0.40, 2.77)),
        "tail_tip": ("tail_3", (0.0, 4.30, 0.22)),
        "chest": ("chest", (0.0, -1.55, 2.70)),
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
