class_name GKMaterials
extends RefCounted
## Material roles for the Gauntlet Kit. A GKMesh surface is named after a role;
## this turns the role into a material (gk_surface.gdshader, cached and
## shared), or into a plain StandardMaterial3D for export to other tools.
## A role unknown here renders magenta and warns once, so a typo shows up in
## the first frame instead of silently looking grey.
##
## Role entry: a, b, c = colours (hex), rough, metal, spec, pat (see the
## shader), scale, amt, wear, world (environment roles: patterns in world
## space so neighbouring pieces line up), axis (grain / brushing direction),
## relief (G61: the pattern's height in metres, bent into the normal: grit on
## polymer, checkering, flecks), alpha (G61: a see-through role, drawn by
## gk_surface_clear.gdshader; the edges stay opaque).
## Lane ENV (H752): `emit` (a StandardMaterial3D that glows: lava, flames;
## emission = col_c x emit; the vertex tint multiplies the albedo only) and
## `blend` ("add" or "mix": an unshaded vertex-coloured sheet for light
## pools, lava glow, steam and clouds; the tint's alpha fades it).

const SHADER := "res://shaders/gk_surface.gdshader"
const SHADER_CLEAR := "res://shaders/gk_surface_clear.gdshader"   ## roles with `alpha` (G61): see-through polymer
const SHADER_FADE := "res://src/arena/shaders/gk_fade.gdshader"   ## roles with `fade: [near, far]` (H759): scenery that dissolves near the camera
const SHADER_GLOW_WEB := "res://shaders/gk_glow_web.gdshader"   ## Lane Z (H92): additive light pools on the web build
const PAT := { "plain": 0, "grain": 1, "plaster": 2, "blocks": 3, "cobble": 4, "siding": 5, "membrane": 6,
	"stipple": 7, "brushed": 8, "asphalt": 9, "grass": 10, "concrete": 11, "pavers": 12, "checker": 13, "speckle": 14 }

const ROLES := {
	# ---- items (object space)
	"gunmetal": { "a": "#2a2b2d", "b": "#1e1f21", "rough": 0.38, "metal": 0.7, "pat": "brushed", "scale": 260.0, "amt": 0.16, "wear": 0.25 },
	"blued": { "a": "#1d1e21", "b": "#141517", "rough": 0.3, "metal": 0.75, "pat": "brushed", "scale": 300.0, "amt": 0.14, "wear": 0.25 },
	"steel": { "a": "#85888b", "b": "#6a6d70", "rough": 0.4, "metal": 1.0, "pat": "brushed", "scale": 300.0, "amt": 0.18 },
	"alloy_black": { "a": "#1c1b1a", "b": "#151414", "rough": 0.48, "metal": 0.5, "spec": 0.4, "pat": "stipple", "scale": 1600.0, "amt": 0.1, "relief": 0.00006, "wear": 0.3 },
	"polymer_black": { "a": "#171614", "b": "#111110", "rough": 0.66, "metal": 0.0, "spec": 0.35, "pat": "stipple", "scale": 1100.0, "amt": 0.15, "relief": 0.00016, "wear": 0.3 },
	"polymer_olive": { "a": "#56603c", "b": "#4a5436", "rough": 0.62, "metal": 0.0, "spec": 0.35, "pat": "stipple", "scale": 1100.0, "amt": 0.12, "relief": 0.00016, "wear": 0.3 },
	"rubber": { "a": "#1b1a19", "b": "#121212", "rough": 0.9, "metal": 0.0, "spec": 0.3, "pat": "stipple", "scale": 1100.0, "amt": 0.2, "relief": 0.00045, "wear": 0.2 },
	"glass_lens": { "a": "#0c161c", "b": "#06100f", "rough": 0.04, "metal": 0.0, "spec": 1.0, "pat": "plain", "scale": 30.0, "amt": 0.2 },
	"brass": { "a": "#b08d4a", "b": "#8a6a32", "rough": 0.3, "metal": 1.0, "pat": "brushed", "scale": 200.0, "amt": 0.2 },
	"orange_tip": { "a": "#e0601c", "b": "#c4521a", "rough": 0.6, "pat": "plain", "scale": 50.0, "amt": 0.1 },
	"wood_branch": { "a": "#5c4531", "b": "#30221a", "c": "#1e1610", "rough": 0.68, "pat": "grain", "scale": 30.0, "amt": 0.95, "axis": [0, 1, 0], "relief": 0.0003 },
	"wood_end": { "a": "#8a7055", "b": "#6a5440", "c": "#3a2a1c", "rough": 0.85, "pat": "plain", "scale": 60.0, "amt": 0.4 },
	"leather_black": { "a": "#1b1a19", "b": "#2a2725", "rough": 0.68, "pat": "stipple", "scale": 500.0, "amt": 0.6 },
	"felt_white": { "a": "#e8e4dc", "b": "#cfc9be", "rough": 1.0, "spec": 0.2, "pat": "stipple", "scale": 900.0, "amt": 0.8 },
	# ---- environments (world space)
	"plaster_white": { "a": "#c6c1b8", "b": "#9d978d", "c": "#b59e7c", "rough": 0.95, "pat": "plaster", "scale": 0.45, "amt": 0.3, "world": true },
	"plaster_ochre": { "a": "#d8ad68", "b": "#c0924f", "c": "#cdbfa6", "rough": 0.95, "pat": "plaster", "scale": 0.45, "amt": 0.22, "world": true },
	"sandstone": { "a": "#c4a273", "b": "#ad8a5c", "c": "#8f7451", "rough": 0.95, "pat": "blocks", "scale": 0.32, "amt": 0.4, "world": true },
	"sandstone_trim": { "a": "#cdb08a", "b": "#b89a72", "c": "#9c8260", "rough": 0.9, "pat": "plain", "scale": 2.0, "amt": 0.25, "world": true },
	"cobble": { "a": "#c9b597", "b": "#a99476", "c": "#8a7558", "rough": 0.92, "pat": "cobble", "scale": 0.42, "amt": 0.45, "world": true },
	"flagstone": { "a": "#c4b69c", "b": "#9f927c", "c": "#9a8c76", "rough": 0.9, "pat": "pavers", "scale": 0.55, "amt": 0.7, "world": true },
	"sandstone_render": { "a": "#c9a46c", "b": "#b38c58", "c": "#b89a74", "rough": 0.95, "pat": "plaster", "scale": 0.4, "amt": 0.35, "world": true },
	"wood_old": { "a": "#7b6248", "b": "#5c4632", "c": "#3b2d20", "rough": 0.9, "pat": "grain", "scale": 4.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"wood_pole": { "a": "#8a7253", "b": "#6a5640", "c": "#4a3b2a", "rough": 0.9, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"wood_door": { "a": "#5a6e78", "b": "#4a5a62", "c": "#3a3530", "rough": 0.85, "pat": "grain", "scale": 4.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"iron_rust": { "a": "#5e4a3e", "b": "#43352c", "rough": 0.85, "metal": 0.15, "pat": "plain", "scale": 6.0, "amt": 0.45, "world": true },
	"iron_dark": { "a": "#3a3b3c", "b": "#2a2b2c", "rough": 0.6, "metal": 0.7, "pat": "plain", "scale": 3.0, "amt": 0.3, "world": true },
	"canvas_awning": { "a": "#9aa5a8", "b": "#7c878a", "rough": 0.95, "pat": "plain", "scale": 3.0, "amt": 0.3, "world": true },
	"sign_blue": { "a": "#2f6f8e", "b": "#285f7a", "rough": 0.6, "pat": "plain", "scale": 4.0, "amt": 0.15, "world": true },
	"sign_white": { "a": "#e9e6df", "b": "#d8d4cb", "rough": 0.6, "pat": "plain", "scale": 4.0, "amt": 0.15, "world": true },
	"sign_red": { "a": "#c73a2c", "b": "#a52f24", "rough": 0.6, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	"cable": { "a": "#1a1a1a", "b": "#121212", "rough": 0.7, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	"window_dark": { "a": "#20262a", "b": "#2d3a40", "rough": 0.12, "spec": 0.9, "pat": "plain", "scale": 1.5, "amt": 0.4, "world": true },
	"window_frame": { "a": "#dcdad5", "b": "#c8c5be", "rough": 0.6, "pat": "plain", "scale": 3.0, "amt": 0.1, "world": true },
	"roof_membrane": { "a": "#3a4350", "b": "#333b47", "c": "#55606c", "rough": 0.9, "pat": "membrane", "scale": 3.0, "amt": 0.5, "world": true },
	"parapet_cap": { "a": "#cfd3d6", "b": "#b9bec2", "rough": 0.5, "metal": 0.4, "pat": "plain", "scale": 2.0, "amt": 0.2, "world": true },
	"siding_grey": { "a": "#4f5a66", "b": "#46505b", "rough": 0.7, "pat": "siding", "scale": 0.22, "amt": 0.3, "world": true },
	"siding_light": { "a": "#9aa2a8", "b": "#8a9298", "rough": 0.7, "pat": "siding", "scale": 0.22, "amt": 0.3, "world": true },
	"stucco_beige": { "a": "#d8c49a", "b": "#ccb68a", "c": "#c2ab80", "rough": 0.95, "pat": "plaster", "scale": 0.3, "amt": 0.04, "world": true },
	"brick_tan": { "a": "#d8c5a0", "b": "#ccb791", "c": "#bfae8c", "rough": 0.95, "pat": "blocks", "scale": 0.09, "amt": 0.2, "world": true },
	"brick_red": { "a": "#8a4a3a", "b": "#76402f", "c": "#b0a594", "rough": 0.95, "pat": "blocks", "scale": 0.09, "amt": 0.3, "world": true },
	"concrete": { "a": "#a7a49c", "b": "#959189", "c": "#76736c", "rough": 0.92, "pat": "concrete", "scale": 3.0, "amt": 0.4, "world": true },
	"concrete_light": { "a": "#c3c0b8", "b": "#b2aea5", "c": "#8f8b83", "rough": 0.92, "pat": "concrete", "scale": 1.6, "amt": 0.3, "world": true },
	"asphalt": { "a": "#4a4c4e", "b": "#3c3e40", "c": "#2c2d2f", "rough": 0.95, "pat": "asphalt", "scale": 0.4, "amt": 0.5, "world": true },
	"asphalt_lot": { "a": "#7f8081", "b": "#6c6d6e", "c": "#5a5b5c", "rough": 0.95, "pat": "asphalt", "scale": 0.4, "amt": 0.4, "world": true },
	"grass": { "a": "#8a9558", "b": "#76844a", "c": "#9a9468", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.45, "world": true },
	"hedge": { "a": "#3f5f2a", "b": "#2c4620", "c": "#4d6a32", "rough": 1.0, "pat": "grass", "scale": 2.0, "amt": 0.3, "world": true },
	"foliage": { "a": "#4f7a2e", "b": "#355a22", "c": "#6a8a3a", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.3, "world": true },
	"hvac_metal": { "a": "#8c9296", "b": "#767c80", "rough": 0.5, "metal": 0.6, "pat": "brushed", "scale": 40.0, "amt": 0.2, "axis": [0, 1, 0], "world": true },
	"fan_metal": { "a": "#6d7378", "b": "#5c6267", "rough": 0.62, "metal": 0.3, "pat": "brushed", "scale": 30.0, "amt": 0.2, "axis": [0, 1, 0], "world": true },
	"hvac_dark": { "a": "#4a5056", "b": "#3c4248", "rough": 0.5, "metal": 0.6, "pat": "plain", "scale": 6.0, "amt": 0.2, "world": true },
	"car_paint": { "a": "#2a2d33", "b": "#202328", "rough": 0.25, "metal": 0.6, "pat": "plain", "scale": 2.0, "amt": 0.1, "world": true },
	"tyre": { "a": "#1a1a1b", "b": "#141415", "rough": 0.9, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	# Gauntlet kit, Blender models (G43); gg_common.py ROLES carries the same names
	"steel_bright": { "a": "#bcc0c4", "b": "#969a9e", "rough": 0.26, "metal": 1.0, "pat": "brushed", "scale": 400.0, "amt": 0.22, "wear": 0.2 },
	"polymer_fde": { "a": "#9c8763", "b": "#8f7a58", "rough": 0.62, "metal": 0.0, "spec": 0.35, "pat": "stipple", "scale": 1100.0, "amt": 0.12, "relief": 0.00016, "wear": 0.3 },
	"anodized_fde": { "a": "#9c8562", "b": "#8a7654", "rough": 0.42, "metal": 0.45, "pat": "brushed", "scale": 300.0, "amt": 0.14, "wear": 0.25 },
	"polymer_speckle": { "a": "#4a4e55", "b": "#30333a", "c": "#a4a8ac", "rough": 0.72, "metal": 0.0, "spec": 0.35, "pat": "speckle", "scale": 1300.0, "amt": 0.55, "relief": 0.0002, "wear": 0.3 },
	"polymer_clear": { "a": "#3a3026", "b": "#2a221a", "rough": 0.12, "metal": 0.0, "spec": 0.9, "pat": "plain", "scale": 40.0, "amt": 0.1, "alpha": 0.42 },
	"polymer_checker": { "a": "#171614", "b": "#111110", "rough": 0.7, "metal": 0.0, "spec": 0.35, "pat": "checker", "scale": 820.0, "amt": 0.1, "relief": 0.0005, "wear": 0.3 },
	"paint_army": { "a": "#4d5a3c", "b": "#465236", "rough": 0.7, "metal": 0.1, "pat": "stipple", "scale": 60.0, "amt": 0.12 },
	"track_rubber": { "a": "#1c1d1e", "b": "#141516", "rough": 0.9, "pat": "stipple", "scale": 80.0, "amt": 0.2 },
	"roof_slate": { "a": "#5a5f66", "b": "#4c5158", "c": "#666b72", "rough": 0.85, "pat": "siding", "scale": 0.25, "amt": 0.35, "world": true },
	"roof_copper": { "a": "#5f8a78", "b": "#527a6a", "rough": 0.6, "metal": 0.4, "pat": "plain", "scale": 3.0, "amt": 0.25, "world": true },
	"stone_grey": { "a": "#a8a59c", "b": "#94918a", "c": "#7c7a74", "rough": 0.92, "pat": "blocks", "scale": 0.4, "amt": 0.35, "world": true },
	"path_concrete": { "a": "#bdb8ad", "b": "#aaa59a", "c": "#8f8b83", "rough": 0.92, "pat": "pavers", "scale": 1.2, "amt": 0.25, "world": true },
	"foliage_autumn": { "a": "#c8761e", "b": "#a85a16", "c": "#d89a30", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.35, "world": true },
	"foliage_red": { "a": "#a8381e", "b": "#86281a", "c": "#c4502a", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.35, "world": true },
	"foliage_gold": { "a": "#d0a020", "b": "#b08418", "c": "#e0bc40", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.35, "world": true },
	"bark": { "a": "#4a3a2c", "b": "#3a2c20", "c": "#5a4a3a", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"paint_splat": { "a": "#e0308a", "b": "#c02070", "rough": 0.5, "pat": "plain", "scale": 4.0, "amt": 0.1 },
	"net": { "a": "#2a2a2a", "b": "#1a1a1a", "rough": 0.9, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	# extraction forest (agent D gauntlet): a brick that holds up on a 15 m face at
	# 80 m (the fine `blocks` course aliases into moire there), and birch bark
	"brick_hall": { "a": "#8e4b3a", "b": "#7a3e30", "c": "#9a5a46", "rough": 0.95, "pat": "plaster", "scale": 0.7, "amt": 0.25, "world": true },
	"brick_ruin": { "a": "#84503f", "b": "#6c3e31", "c": "#8a7a68", "rough": 0.95, "pat": "blocks", "scale": 0.12, "amt": 0.45, "world": true },
	"bark_birch": { "a": "#e2ddd2", "b": "#8a857c", "c": "#2e2b27", "rough": 0.9, "pat": "plaster", "scale": 2.4, "amt": 0.55, "world": true },
	# Hexhunt pond (Lane C, H205): merged from HHPondGen.ROLES
	"pond_bed": { "a": "#9c8a62", "b": "#7e6d4a", "c": "#6a5a3c", "rough": 0.95, "pat": "stipple", "scale": 1.5, "amt": 0.4, "world": true },
	"water_shallow": { "a": "#0a3570", "b": "#082c5c", "rough": 0.05, "spec": 0.55, "pat": "plain", "scale": 2.0, "amt": 0.1, "world": true, "alpha": 0.84 },
	"lilypad": { "a": "#4f8a2e", "b": "#3a6a22", "c": "#7aa43a", "rough": 0.7, "spec": 0.5, "pat": "grass", "scale": 1.6, "amt": 0.3, "world": true },
	"lilypad_tall": { "a": "#3f7a2a", "b": "#2c5a1e", "c": "#6a9a3a", "rough": 0.75, "pat": "grass", "scale": 1.6, "amt": 0.3, "world": true },
	"reed": { "a": "#6f8a3a", "b": "#55702a", "c": "#8aa44a", "rough": 0.9, "pat": "plain", "scale": 2.0, "amt": 0.2, "world": true },
	"cattail": { "a": "#5a3e26", "b": "#3e2a18", "rough": 0.95, "pat": "stipple", "scale": 40.0, "amt": 0.3, "world": true },
	"pond_flower": { "a": "#e8c020", "b": "#c89a10", "c": "#f2d84a", "rough": 0.8, "pat": "plain", "scale": 4.0, "amt": 0.2, "world": true },
	"meadow_grass": { "a": "#5f9a30", "b": "#4a8226", "c": "#86b444", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.45, "world": true },
	# Hexhunt cave (Lane C/D, H222)
	"cave_floor": { "a": "#4e3e32", "b": "#3c2f26", "c": "#2a211b", "rough": 0.55, "pat": "plaster", "scale": 0.5, "amt": 0.4, "world": true },
	"cave_wall": { "a": "#2e2b29", "b": "#232120", "c": "#3c3836", "rough": 0.95, "pat": "blocks", "scale": 0.9, "amt": 0.4, "world": true },
	"stalagmite": { "a": "#6e5442", "b": "#4e3a2c", "c": "#86684e", "rough": 0.7, "pat": "plaster", "scale": 0.7, "amt": 0.45, "world": true },
	"cave_boulder": { "a": "#5a4434", "b": "#3e2e24", "c": "#6e5644", "rough": 0.8, "pat": "plaster", "scale": 0.6, "amt": 0.4, "world": true },
	"frost": { "a": "#cfeaf2", "b": "#a9cfdd", "c": "#e8f6fa", "rough": 0.3, "spec": 0.9, "pat": "speckle", "scale": 2.0, "amt": 0.25, "world": true },
	"torch_flame": { "a": "#ffb040", "b": "#ff7a18", "c": "#ffb050", "rough": 0.2, "pat": "plain", "scale": 4.0, "amt": 0.2, "emit": 3.0 },
	"torch_post": { "a": "#4a3626", "b": "#352618", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.4, "axis": [0, 1, 0] },
	# Hexhunt glade (Lane C/D, H222)
	"glade_grass": { "a": "#2a6a16", "b": "#1f5410", "c": "#4a9228", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.6, "world": true },
	"sun_grass": { "a": "#9ccc48", "b": "#86b63c", "c": "#c2e070", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.35, "world": true },
	"canopy": { "a": "#5a9a30", "b": "#427a24", "c": "#86bc48", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.35, "world": true, "fade": [10.0, 17.0] },
	"glade_trunk": { "a": "#5a4634", "b": "#43342a", "c": "#6e5a46", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"glade_flower": { "a": "#f0e0f8", "b": "#d8b8e8", "c": "#ffffff", "rough": 0.8, "pat": "plain", "scale": 4.0, "amt": 0.2, "world": true },
	"bush": { "a": "#3f6f2a", "b": "#2c5220", "c": "#558a36", "rough": 1.0, "pat": "grass", "scale": 2.0, "amt": 0.3, "world": true },
	# Hexhunt caldera (Lane C/D, H222)
	"basalt": { "a": "#2c2d31", "b": "#212226", "c": "#3c3d42", "rough": 0.95, "pat": "asphalt", "scale": 0.5, "amt": 0.35, "world": true },
	"ash": { "a": "#7d7873", "b": "#67625e", "c": "#938e88", "rough": 1.0, "pat": "stipple", "scale": 1.0, "amt": 0.35, "world": true },
	"snow": { "a": "#eef2f5", "b": "#d8e0e8", "c": "#ffffff", "rough": 0.7, "pat": "speckle", "scale": 1.5, "amt": 0.15, "world": true },
	"lava": { "a": "#ff6a1a", "b": "#ff3a08", "c": "#ff6a18", "rough": 0.4, "pat": "stipple", "scale": 0.8, "amt": 0.5, "world": true, "emit": 2.0 },
	"lava_crust": { "a": "#3a2a24", "b": "#2a1c18", "c": "#5a3a2c", "rough": 0.95, "pat": "blocks", "scale": 0.4, "amt": 0.4, "world": true },
	"vent_rim": { "a": "#4a3f3a", "b": "#372f2b", "c": "#6a5a50", "rough": 0.95, "pat": "stipple", "scale": 1.2, "amt": 0.4, "world": true },
	"scoria": { "a": "#3b3330", "b": "#2b2522", "c": "#4d4440", "rough": 0.98, "pat": "blocks", "scale": 0.35, "amt": 0.45, "world": true },
	# Lane ENV visual pass (H752-H760): light pools, steam, clouds, biome dressing, the world map
	"glow_warm": { "a": "#ffffff", "rough": 1.0, "pat": "plain", "blend": "add" },
	"steam": { "a": "#eef1f4", "rough": 1.0, "pat": "plain", "blend": "mix" },
	"cloud": { "a": "#f4f6fa", "rough": 1.0, "pat": "plain", "blend": "mix" },
	"conifer": { "a": "#1a3820", "b": "#122a17", "c": "#25482a", "rough": 1.0, "pat": "grass", "scale": 1.4, "amt": 0.3, "world": true, "fade": [16.0, 26.0] },
	"reed_tall": { "a": "#7fa040", "b": "#5f8030", "c": "#a8c060", "rough": 0.9, "pat": "grass", "scale": 3.0, "amt": 0.3, "world": true },
	"moss_rock": { "a": "#6c6a5c", "b": "#55574a", "c": "#5f7a3a", "rough": 0.95, "pat": "plaster", "scale": 0.8, "amt": 0.45, "world": true },
	"tube_rock": { "a": "#7a5434", "b": "#352318", "c": "#1a110b", "rough": 0.75, "pat": "grain", "scale": 0.35, "amt": 0.7, "world": true, "axis": [1, 0, 0.35] },
	"puddle": { "a": "#120d0a", "b": "#0c0907", "rough": 0.04, "spec": 1.0, "pat": "plain", "scale": 2.0, "amt": 0.1, "world": true },
	"leaf_young": { "a": "#7cb843", "b": "#5c9a30", "c": "#a2d060", "rough": 1.0, "pat": "grass", "scale": 1.0, "amt": 0.4, "world": true, "fade": [16.0, 26.0] },
	"leaf_shade": { "a": "#3d7428", "b": "#2c5a1e", "c": "#4f8a32", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.35, "world": true, "fade": [16.0, 26.0] },
	"bramble": { "a": "#4f8a2c", "b": "#386a22", "c": "#6aa03a", "rough": 1.0, "pat": "grass", "scale": 2.4, "amt": 0.4, "world": true },
	"dead_wood": { "a": "#6e5e4c", "b": "#4e4234", "c": "#857560", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"bark_fade": { "a": "#4a3a2c", "b": "#3a2c20", "c": "#5a4a3a", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0], "fade": [16.0, 26.0] },
	"tube_lip": { "a": "#7a5434", "b": "#352318", "c": "#1a110b", "rough": 0.75, "pat": "grain", "scale": 0.35, "amt": 0.7, "world": true, "axis": [1, 0, 0.35], "fade": [20.0, 30.0] },
	"drip": { "a": "#6e5442", "b": "#4e3a2c", "c": "#86684e", "rough": 0.7, "pat": "plaster", "scale": 0.7, "amt": 0.45, "world": true, "fade": [20.0, 30.0] },
	"flank_snow": { "a": "#eef2f5", "b": "#d8e0e8", "c": "#ffffff", "rough": 1.0, "spec": 0.15, "pat": "speckle", "scale": 0.4, "amt": 0.15, "world": true },
	"rim_rock": { "a": "#222329", "b": "#18191d", "c": "#303138", "rough": 0.95, "pat": "plaster", "scale": 0.25, "amt": 0.4, "world": true },
	"dirt_path": { "a": "#8a7656", "b": "#76644a", "c": "#9c8a68", "rough": 1.0, "pat": "stipple", "scale": 1.2, "amt": 0.35, "world": true },
	"ruin_stone": { "a": "#9c968a", "b": "#7e796e", "c": "#6a6a5a", "rough": 0.95, "pat": "blocks", "scale": 0.5, "amt": 0.4, "world": true },
	"water_river": { "a": "#24597e", "b": "#1d4a6a", "rough": 0.05, "spec": 1.0, "pat": "plain", "scale": 2.0, "amt": 0.1, "world": true, "alpha": 0.8 },
	"barrier": { "a": "#ff00ff", "b": "#ff00ff", "rough": 1.0, "pat": "plain", "scale": 1.0, "amt": 0.0, "world": true },
}

static var _cache := {}          # role -> ShaderMaterial
static var _std := {}            # role -> StandardMaterial3D
static var _warned := {}


static func has(role: String) -> bool:
	return ROLES.has(_base(role))


## "car_paint:#8a1e22" overrides the first colour (a, and b a step darker):
## one role, many paint jobs.
static func _base(role: String) -> String:
	var i := role.find(":")
	return role if i < 0 else role.substr(0, i)


static func _spec(role: String) -> Dictionary:
	var base := _base(role)
	if not ROLES.has(base):
		if not _warned.has(base):
			_warned[base] = true
			push_warning("GKMaterials: unknown role '%s' (magenta)" % base)
		return { "a": "#ff00ff", "b": "#ff00ff", "rough": 1.0, "pat": "plain" }
	var s: Dictionary = (ROLES[base] as Dictionary).duplicate()
	var i := role.find(":")
	if i >= 0:
		var c := Color(role.substr(i + 1))
		s["a"] = c.to_html(false)
		s["b"] = c.darkened(0.15).to_html(false)
	return s


static func get_material(role: String) -> Material:
	if _cache.has(role):
		return _cache[role]
	var s := _spec(role)
	if str(s.get("blend", "")) == "add" and _web() and ResourceLoader.exists(SHADER_GLOW_WEB):
		_cache[role] = _glow_web(s)                 # Lane Z (H92): light pools on the web
		return _cache[role]
	if s.has("blend") or s.has("emit"):
		_cache[role] = _special(s)
		return _cache[role]
	var m := ShaderMaterial.new()
	var web := _web()
	m.shader = load(_variant(SHADER_CLEAR if s.has("alpha") else SHADER, web))
	if s.has("fade") and ResourceLoader.exists(SHADER_FADE):    # H759: dissolves near the camera
		m.shader = load(_variant(SHADER_FADE, web))
		var fd: Array = s.fade
		m.set_shader_parameter("fade_near", float(fd[0]))
		m.set_shader_parameter("fade_far", float(fd[1]))
	m.set_shader_parameter("col_a", Color(str(s.a)))
	m.set_shader_parameter("col_b", Color(str(s.get("b", s.a))))
	m.set_shader_parameter("col_c", Color(str(s.get("c", s.get("b", s.a)))))
	m.set_shader_parameter("rough", float(s.get("rough", 0.8)))
	m.set_shader_parameter("metal", float(s.get("metal", 0.0)))
	m.set_shader_parameter("spec", float(s.get("spec", 0.5)))
	m.set_shader_parameter("pat", int(PAT.get(str(s.get("pat", "plain")), 0)))
	m.set_shader_parameter("scale", float(s.get("scale", 1.0)))
	m.set_shader_parameter("amt", float(s.get("amt", 0.2)))
	m.set_shader_parameter("wear", float(s.get("wear", 0.0)))
	m.set_shader_parameter("relief", float(s.get("relief", 0.0)))
	m.set_shader_parameter("alpha", float(s.get("alpha", 1.0)))
	m.set_shader_parameter("world", bool(s.get("world", false)))
	var ax: Array = s.get("axis", [0, 0, 1])
	m.set_shader_parameter("axis", Vector3(float(ax[0]), float(ax[1]), float(ax[2])))
	_cache[role] = m
	return m


## Lane Z (H90): on the Compatibility renderer (the web build) the shaders
## come in a *_web variant that sums ambient and sun in one pass (see
## HHWebLook); desktop keeps the originals.
static func _web() -> bool:
	if HHWebLook.active():
		HHWebLook.ensure_globals()
		return true
	return false


static func _glow_web(s: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_GLOW_WEB)
	m.set_shader_parameter("albedo", Color(str(s.a)))
	m.set_shader_parameter("whiten", HHTune.value("web_glow_whiten"))
	m.set_shader_parameter("gain", HHTune.value("web_glow_gain"))
	return m


static func _variant(path: String, web: bool) -> String:
	var w := path.replace(".gdshader", "_web.gdshader")
	return w if web and ResourceLoader.exists(w) else path


## H752: glowing roles (`emit`) and unshaded sheets (`blend`: add / mix).
static func _special(s: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(str(s.a))
	m.vertex_color_use_as_albedo = true
	m.roughness = float(s.get("rough", 0.8))
	if s.has("blend"):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if str(s.blend) == "add" else BaseMaterial3D.BLEND_MODE_MIX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.disable_receive_shadows = true
		m.disable_fog = str(s.blend) == "add"
	if s.has("emit"):
		m.emission_enabled = true
		m.emission = Color(str(s.get("c", s.a)))
		m.emission_energy_multiplier = float(s.emit)
	return m


## A plain PBR stand-in (colour, roughness, metallic): what a .glb carries
## to tools that don't run Godot shaders.
static func standard(role: String) -> StandardMaterial3D:
	if _std.has(role):
		return _std[role]
	var s := _spec(role)
	var m := StandardMaterial3D.new()
	m.resource_name = role
	m.albedo_color = Color(str(s.a))
	m.roughness = float(s.get("rough", 0.8))
	m.metallic = float(s.get("metal", 0.0))
	m.vertex_color_use_as_albedo = true
	if s.has("alpha"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = float(s.alpha)
	_std[role] = m
	return m


## Material every surface of `mi` by its surface name.
static func apply(mi: MeshInstance3D, plain := false) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var role := ""
		if mesh is ArrayMesh:
			role = (mesh as ArrayMesh).surface_get_name(i)
		mi.set_surface_override_material(i, standard(role) if plain else get_material(role))
