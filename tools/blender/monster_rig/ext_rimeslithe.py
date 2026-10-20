"""rigkit extension for Rimeslithe: a hunched, long-forearmed knuckle-walker
with ice-crystal clusters. rigkit.py is shared and read-only (H300); this
module adds to it from outside by installing two hooks before `rigkit.build`:

    import rigkit, ext_rimeslithe
    ext_rimeslithe.install()
    row = rigkit.build(SPEC, glb_path)

Hooks (looked up by rigkit.build through its module globals at call time):
  build_leg   a leg spec with "kind": "arm" becomes a knuckle-walking arm:
              shoulder ball, upper arm, elbow ball, long forearm, wrist ball,
              a fist block resting on its knuckles and claws curled under it.
              Bones are rigkit's leg bones (hip_ = shoulder, knee_ = elbow /
              forearm, ankle_ = wrist, toe_ = knuckles) so HHMonsterBody and
              the manifest need nothing new.
  build_eyes  after the eyes, `crystals` clusters: SPEC["crystals"] is a list of
              { name, bone, at, dir, n, length, radius, spread_deg, role,
                tip (rgb) } and each grows n hexagonal, pointed crystals
              around `dir`, leaning outward, deterministic (rigkit._hash01).

Everything else (chains, jaw, teeth, fins, sockets, manifest) is rigkit's.
Coordinates are Blender's: Z up, faces -Y, left +X, metres.
"""

import math

from mathutils import Matrix, Vector

import rigkit

EXT_VERSION = 1
UP = rigkit.UP
FORWARD = rigkit.FORWARD
V = rigkit.V


# ------------------------------------------------------------------ arms
def build_arm(mb, spec, leg):
    """A knuckle-walking arm from a leg spec (hip = shoulder, knee = elbow,
    ankle = wrist, toe = knuckles)."""
    lid = leg["id"]
    pts = [V(leg["hip"]), V(leg["knee"]), V(leg["ankle"])]
    radii = list(leg["radii"])
    names = ["hip_" + lid, "knee_" + lid, "ankle_" + lid]
    sides = int(leg.get("sides", 8))
    role = leg.get("role", "hide")
    # upper arm and forearm: one tube with ball-ish rings, weights to shoulder / forearm bones
    mb.tube(pts, radii, names[:2], float(leg.get("blend", 0.2)), sides, role)
    # shoulder mass (a deltoid ball) and the elbow knob
    mb.sphere(pts[0], radii[0] * float(leg.get("shoulder_ball", 1.25)), {names[0]: 1.0}, role, seg=8, rings=4)
    mb.sphere(pts[1], radii[1] * 1.08, {names[0]: 0.5, names[1]: 0.5}, role, seg=6, rings=3)
    # wrist ball on the wrist bone
    wrist = pts[2]
    mb.sphere(wrist, radii[2] * 1.1, {names[2]: 1.0}, role, seg=6, rings=3)
    # the fist: a block from the wrist down onto the knuckles, fingers folded under
    toe = V(leg["toe"])
    fw, fl, fh = leg.get("fist", (0.9, 0.85, 0.6))
    d = toe - wrist
    d.z = 0.0
    if d.length < 1e-6:
        d = FORWARD.copy()
    d = d.normalized()
    side = d.cross(UP).normalized()
    basis = Matrix((side, d, UP)).transposed()
    centre = Vector((toe.x, toe.y, 0.0)) - d * (fl * 0.15)
    centre.z = fh * 0.5 + 0.02
    wfist = {"toe_" + lid: 0.75, "ankle_" + lid: 0.25}
    mb.box(centre, (fw * 0.5, fl * 0.5, fh * 0.5), basis, wfist, role)
    # knuckle ridge: a lower, wider slab in front so the fist reads as curled fingers
    ridge_c = centre + d * (fl * 0.45)
    ridge_c.z = fh * 0.3 + 0.02
    mb.box(ridge_c, (fw * 0.46, fl * 0.22, fh * 0.3), basis, {"toe_" + lid: 1.0}, role)
    # claws curl down and under from the knuckle ridge
    n = int(leg.get("claws", 4))
    cl = float(leg.get("claw_len", 0.3))
    front = ridge_c + d * (fl * 0.22)
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        base_c = front + side * (u * fw * 0.8)
        base_c.z = fh * 0.42
        hw = fw * 0.36 / n
        base = [base_c + side * hw - UP * (fh * 0.2), base_c - side * hw - UP * (fh * 0.2),
                base_c - side * hw + UP * (fh * 0.2), base_c + side * hw + UP * (fh * 0.2)]
        tip = base_c + d * (cl * 0.75) - UP * (fh * 0.42)
        tip.z = max(tip.z, 0.02)
        mb.pyramid(base, tip, {"toe_" + lid: 1.0}, leg.get("claw_role", "claw"))


# ------------------------------------------------------------------ crystals
def _ortho(d):
    """Two unit vectors orthogonal to d."""
    d = d.normalized()
    ref = UP if abs(d.dot(UP)) < 0.9 else Vector((1.0, 0.0, 0.0))
    a = (ref - d * ref.dot(d)).normalized()
    b = d.cross(a).normalized()
    return a, b


def crystal(mb, base, direction, length, radius, w, role, tip_color=None, base_color=None):
    """One pointed hexagonal crystal: a hex base, a shoulder ring at 62% of the
    length (slightly wider: the classic gem silhouette), an apex. Vertex
    colour brightens toward the tip when tip_color is given."""
    d = direction.normalized()
    a, b = _ortho(d)
    rot = rigkit._hash01(int(base.x * 100), int(base.y * 100), int(base.z * 100)) * math.pi / 3.0
    ring0 = []
    ring1 = []
    sh = base + d * (length * 0.62)
    for k in range(6):
        ang = rot + k * math.pi / 3.0
        off = a * math.cos(ang) + b * math.sin(ang)
        ring0.append(mb.add_vert(base + off * (radius * 0.9), w, role, base_color))
        ring1.append(mb.add_vert(sh + off * radius, w, role, tip_color))
    apex = mb.add_vert(base + d * length, w, role, tip_color)
    mb.faces.append((tuple(reversed(ring0)), role))
    for k in range(6):
        k2 = (k + 1) % 6
        mb.faces.append(((ring0[k], ring0[k2], ring1[k2], ring1[k]), role))
        mb.faces.append(((ring1[k], ring1[k2], apex), role))


def build_crystals(mb, spec):
    for c in spec.get("crystals", []):
        role = c.get("role", "crystal")
        bone = c["bone"]
        w = {bone: 1.0}
        at = V(c["at"])
        d = V(c.get("dir", (0.0, 0.0, 1.0))).normalized()
        n = int(c.get("n", 4))
        L = float(c.get("length", 1.0))
        R = float(c.get("radius", 0.2))
        spread = math.radians(float(c.get("spread_deg", 38.0)))
        foot = float(c.get("foot", 0.45))        # cluster footprint radius (m) the roots scatter over
        tip = c.get("tip")
        a, b = _ortho(d)
        salt = sum(ord(ch) for ch in c.get("name", bone))
        for i in range(n):
            h1 = rigkit._hash01(salt, i, 1)
            h2 = rigkit._hash01(salt, i, 2)
            h3 = rigkit._hash01(salt, i, 3)
            # the biggest crystal stands in the middle; the rest lean outward around it
            if i == 0:
                root = at
                direction = d
                length = L
                radius = R
            else:
                ang = (i - 1) * (2.0 * math.pi / max(1, n - 1)) + h1 * 0.9
                out = a * math.cos(ang) + b * math.sin(ang)
                root = at + out * (foot * (0.6 + 0.4 * h2)) - d * (R * 0.5)
                lean = spread * (0.6 + 0.4 * h3)
                direction = (d * math.cos(lean) + out * math.sin(lean)).normalized()
                length = L * (0.45 + 0.4 * h2)
                radius = R * (0.55 + 0.4 * h1)
            crystal(mb, root, direction, length, radius, w, role, tip_color=tip)


# ------------------------------------------------------------------ install
def install():
    """Patch rigkit's module-level builders (idempotent)."""
    if getattr(rigkit, "_ext_rimeslithe", False):
        return
    orig_leg = rigkit.build_leg
    orig_eyes = rigkit.build_eyes

    def build_leg(mb, spec, leg):
        if leg.get("kind") == "arm":
            build_arm(mb, spec, leg)
        else:
            orig_leg(mb, spec, leg)

    def build_eyes(mb, spec):
        orig_eyes(mb, spec)
        build_crystals(mb, spec)

    rigkit.build_leg = build_leg
    rigkit.build_eyes = build_eyes
    rigkit._ext_rimeslithe = True
