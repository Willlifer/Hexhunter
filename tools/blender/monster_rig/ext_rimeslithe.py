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
import shapes_ma

EXT_VERSION = 2   # 2 (H652): knuckle-walking fists (rounded fist + knuckle knobs), forearm mass,
                  # digitigrade hind legs (shapes_ma), muscle masses and swept crest plates
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
    # the forearm's gorilla bulk (H652)
    fm = leg.get("forearm_mass")
    if fm:
        shapes_ma.mass_along(mb, pts[1], pts[2], float(fm[3]) if len(fm) > 3 else 0.35, fm[0], fm[1], fm[2],
                             {names[1]: 1.0}, role, seg=8, rings=5)
    # the fist: a rounded mass from the wrist down onto the knuckles, a row of
    # knuckle knobs on the ground in front, claws curled under (not a box paw)
    toe = V(leg["toe"])
    fw, fl, fh = leg.get("fist", (0.9, 0.85, 0.6))
    d = toe - wrist
    d.z = 0.0
    if d.length < 1e-6:
        d = FORWARD.copy()
    d = d.normalized()
    side = d.cross(UP).normalized()
    wfist = {"toe_" + lid: 0.75, "ankle_" + lid: 0.25}
    centre = Vector((toe.x, toe.y, 0.0)) - d * (fl * 0.2)
    centre.z = fh * 0.55
    # the fist leans: its long axis runs from the wrist down to the knuckles
    axis = (Vector((toe.x, toe.y, 0.05)) - wrist)
    axis = axis.normalized()
    side2 = axis.cross(UP)
    side2 = side2.normalized() if side2.length > 1e-6 else side
    fwd2 = side2.cross(axis).normalized()
    shapes_ma.ellipsoid(mb, centre, side2 * (fw * 0.5), fwd2 * (fl * 0.5), axis * (fh * 0.62), wfist, role, seg=8, rings=5)
    n = int(leg.get("claws", 4))
    kr = fw / (n * 2.0) * 1.05
    front = Vector((toe.x, toe.y, 0.0)) + d * (fl * 0.18)
    cl = float(leg.get("claw_len", 0.3))
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        kc = front + side * (u * fw * 0.86) - d * (abs(u) * fl * 0.25)
        kc.z = kr * 0.95
        mb.sphere(kc, kr, {"toe_" + lid: 1.0}, role, seg=6, rings=3)
        # a claw curling down from the knuckle's front
        cb = kc + d * (kr * 0.7)
        hw = kr * 0.45
        base = [cb + side * hw - UP * hw, cb - side * hw - UP * hw, cb - side * hw + UP * hw, cb + side * hw + UP * hw]
        tip = cb + d * (cl * 0.6) - UP * (kc.z * 0.9)
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


# ------------------------------------------------------------------ extras (H652)
def build_extras(mb, spec):
    """spec["masses"]: [ { a, b, u, r: (side, len, fwd), w, role } ] muscle ellipsoids;
    spec["plates"]: [ { pts, widths, normal, w (dict or list per point), role, thick,
    colors } ] swept crest / fin plates (shapes_ma.plate)."""
    for m in spec.get("masses", []):
        r = m["r"]
        shapes_ma.mass_along(mb, m["a"], m["b"], float(m.get("u", 0.5)), r[0], r[1], r[2], m["w"],
                             m.get("role", "hide"), seg=int(m.get("seg", 10)), rings=int(m.get("rings", 6)))
    for pl in spec.get("plates", []):
        shapes_ma.plate(mb, pl["pts"], pl["widths"], pl["normal"], pl["w"], pl.get("role", "crystal"),
                        thick=float(pl.get("thick", 0.08)), colors=pl.get("colors"))


# ------------------------------------------------------------------ install
def install():
    """Patch rigkit's module-level builders (idempotent)."""
    shapes_ma.install_normal_fix(rigkit)
    if getattr(rigkit, "_ext_rimeslithe", False):
        return
    orig_leg = rigkit.build_leg
    orig_eyes = rigkit.build_eyes

    def build_leg(mb, spec, leg):
        if leg.get("kind") == "arm":
            build_arm(mb, spec, leg)
        elif leg.get("digi"):
            shapes_ma.digi_leg(mb, spec, leg, rigkit)
        else:
            orig_leg(mb, spec, leg)

    def build_eyes(mb, spec):
        orig_eyes(mb, spec)
        build_crystals(mb, spec)
        build_extras(mb, spec)

    rigkit.build_leg = build_leg
    rigkit.build_eyes = build_eyes
    rigkit._ext_rimeslithe = True
