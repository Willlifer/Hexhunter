# 03 Mesh pipeline (H4)

## Rigs, weapons, monsters: Blender
Black | White's pattern, carried over: deterministic Blender Python under `tools/blender/`, run as
`blender -b --factory-startup --python tools/blender/build_weapons.py [-- --only lance,glaive]`.
Each script writes `art/<set>/<id>.glb` plus one JSON manifest per set (weapons: hands, socket, mount, tip, trail_base, length, aabb, tris). A reference `.blend` goes to `art/source/`. Generated files are never hand-edited.

Source to copy from: `..\Black White\game\tools\blender\build_weapons.py`, `build_base_rig.py`; the rig loader `src\game\character\character_rig.gd` (bones: root, hips, spine, chest, neck, head, shoulder/upper_arm/forearm/hand l+r, thigh/shin/foot l+r; sockets: socket_weapon_r, socket_offhand_l, socket_back, socket_chest, socket_hair, socket_hat). Rig height 2.2 m (HHLook.RIG_HEIGHT). Rig v2 (H80-H83) is the huntress: one welded smooth loft for torso and legs, 8 colour roles (skin, suit, plate, armor, leather, cape, hair, wrap), about 14.2k tris, armour faceted (flat-shaded, H102); `suit` and `cape` are tinted per player at run time (`HHPlayerBody.set_suit_color`). Review sheets against the reference: `tools/hunter_ref_shots.gd` (design/art/hunter_ref).

Comic ink outline (H84-H85): `HHInk.apply(model, scale)` gives any skinned body an inverted-hull outline (`shaders/ink_outline.gdshader`), on while HHTune `ink_on`; the hunter and the four monsters use it.

Lane E's Monster Rig Builder follows the same contract: a Blender script per monster, a glb, a manifest row with bone names, jaw bone, spine/tail chain, leg IK targets, sockets.

Every model: manifest row, preview render PNG (`design/art/<set>/`), a test in `tests/test_<set>_*.gd` that loads the glb and checks the manifest (tris budget, sockets present, aabb sane), and for a weapon an equip clip.

## Arenas and props: GKMesh
Gauntlet's kit, verbatim in `src/kit/`. `GKMesh` collects primitives (`box`, `tube`, `loft`, `cyl`, `lathe`, `sphere`, `extrude`, `quad`, `tri`) into one ArrayMesh with one surface per material role; `GKMaterials.apply(mi)` turns role names into the `gk_surface` shader. Roles live in `GKMaterials.ROLES`; add biome roles there (lilypad, pond_bed, basalt, ash, moss).

A generator is a `GKDef` subclass: `schema()` (sliders), `presets()`, `_build(p) -> GKAsset` (parts, markers, colliders, trimesh). The bench (Lane C) lists GKDefs, shows sliders, undo/redo, presets to `user://`, exports glb + JSON sidecar.

Winding: `GKMesh.tri` computes the face normal as `(c - a) x (b - a)`; a ground quad listed `p0 (x0,z0), p1 (x1,z0), p2 (x1,z1), p3 (x0,z1)` faces up.

## Painted hexes
`HHTileFX` maps an HHCharge entry to shader layers; `HHArenaView` places a flat hex mesh (circumradius 1) at each painted hex, lifted 4 cm, with instance uniforms `tier`, `seed`, `frost`, `crack`, `age`. The shaders are unshaded alpha-blended faces; they sit flush on any terrain.
