# PLAN — Hexhunt

Phases with gates. The author checks each gate before the next phase starts.
Status: **Phase 3.5 visual pass built 2026-10-20: all five lanes merged (monsters MA/MB, effects FX, environment ENV, interface UI), plus reaction math H50 and arena events H51; 249/249. Awaiting the author's look (LEDGER L-22). Then Phase 4 co-op.**

## 0. Interview record

| Q | Answer |
|---|--------|
| a. Real time? | Yes. 30 Hz sim tick (H8). Right-click move, left-click target, Q/W/E/R weapon actions. |
| b. For whom? | Author's playtests, then shared online with friends (web export, Phase 5). |
| c. Co-op? | Possible at end build, not mandatory. Solo play must always work. Order-driven host-authoritative sim from day one; networking in Phase 4 (H7). |
| d. Deliverable? | A game. |
| e. Black \| White carry-over | Rules core (hex, formulas, tiles/charge math, phases) and meshes (Blender build scripts, base rig, weapon roster, tile shaders). |
| g. Monster is... | A boss with phases and telegraphed moves. Light AI (calm / aggravated / threatened states), not an opponent. |
| h. A hunt | Explore the world map, see a disturbance, monster bursts out, short cutscene, prep screen (weapon, skills, equippables, attunements), 50 m arena fight (H23) with projectiles to dodge, elements to paint, charges that interact with painted hexes, environment to exploit; victory gives equipment or a skill upgrade. |
| i. Smallest proof | A single fight in Godot: lance vs Swampfang in the pond (H5). That is Phase 1's gate. |
| Elements | Black \| White's seven (H2). |
| Map tooling | Seeded procedural generator per biome plus bench tool (H3). |
| Mesh pipeline | Blender for weapons/rigs, GKMesh for environment (H4). |
| Repo | <repo>, dev branch, worktree lanes (H6). |

## 1. Finish line

Four arenas, four monsters, three weapons with four skills each and three upgrade slots per skill, a hunt loop from world map to victory drop, 1-4 player co-op, exported for the web.

## 2. What is reused and from where

| Need | Source | Notes |
|------|--------|-------|
| Hex math | Black \| White `game/src/core/hex.gd` (BWHex) | Copied as `src/core/hex.gd`. Pointy-top odd-r, static. |
| Element math | Black \| White `tiles.gd`, `overheat.gd`, `overfreeze.gd`, `formulas.gd` | Copied into `src/core/`. Two charge axes plus three operators. Turn-based "cycles" become tick counts. |
| Phases | Black \| White `phases.gd` (BWPhases) | Triggers `hp_below`, `after`, `delay`. Monster states and enrage. |
| Tile shaders | Black \| White `game/shaders/tile_*.gdshader`, `tile_fx.gd` | Flush-with-terrain painted hexes. |
| Orbit camera | Black \| White `camera_rig.gd` | Player-centred follow, middle-drag orbit, wheel zoom, pitch clamp. |
| Self-test, CI | Black \| White `boot.gd`, `tests/self_test.gd`, `release.yml` | `-- --self-test` writes a JSON report, exit 0/1. |
| Player rig, weapons | Black \| White `tools/blender/build_base_rig.py`, `build_weapons.py`, `art/weapons/*.glb` | Glaive, karambit, dagger, lance, bows exist. Karambit rebuilt sword-sized (kickoff). |
| Animator | Black \| White `animator.gd`, `anim_*.gd` | Clip layering and transitions. |
| 30 Hz sim shape | Gauntlet `mmo_sim.gd`, `mmo_view.gd` | Orders per tick, interpolated view. |
| True-hex marker, click-to-move, walk-into-range | Gauntlet `osrs_sim.gd` (`path`, `path_to_reach`, `in_reach`), `osrs_view.gd` (`_true_tile`, `_click_at`) | Adapted from squares to BWHex. |
| Ground telegraphs, scorch, phase thresholds | Gauntlet Giant raid (`mmo_sim.gd` spells, `_sync_areas`) | Danger circles snapped to floor become hex sets. |
| Env meshes | Gauntlet `gk_mesh.gd`, `gk_def.gd`, `gk_asset.gd`, `gk_registry.gd`, kit bench | Arena props and the arena bench. |
| Heightfield | Gauntlet `gk_extract_forest.gd` (`height_at`) | 3 m grid heightfield, shrunk to 35 m and mapped onto hex centres. |
| Web shim | Gauntlet `web_instance_shim.gd`, `build_web.sh`, `shell.html` | Phase 5. |
| Sound effects | Gauntlet `game/audio/sfx` (elem_*, swing_*, hit_*, bow_*, step_stone) | Copied wav+ogg. |
| F1 tune panel | Gauntlet `mmo_tune.gd` / `osrs_tune_panel.gd` | Feel numbers in one cfg plus a live panel. |
| Tile-effect matrix, tag vocabulary | Temporal Sea `tile_effects.gd`, `tags.json` | Reference for authored scenery pairs and skill tagging. Not copied wholesale. |
| Elevation hex render | Temporal Sea `hex_terrain.gd` | Reference for `cell_top` and picking against stepped columns. |
| MIDI | `D:\Music Studio\Claude Playground\skills\groove-midi\groovekit.py` | Lane F. |

## 3. Phases

| Phase | Name | Mode | Gate (author checks) |
|-------|------|------|----------------------|
| 0 | Foundation | serial, one session | `godot --headless --path . --import` clean; `-- --self-test` exit 0 with report; an empty 50 m hex arena renders in a window with painted test hexes and the orbit camera. Doc set in place. |
| 1 | First fight | up to 3 lanes (P, C, E) + F | Lance vs Swampfang in the pond, playable start to finish: ambush, fight with telegraphs, stagger, element painting and reactions, death/victory. Author plays it and calls the feel. |
| 2 | Fan-out | 6 lanes (A-F) | Three weapons with all clips; four arenas; four monsters; music loops delivered. Each lane's own test green; self-test green on dev. |
| 3 | Hunt loop and progression | 4 lanes (L, H, U, V) | Lobby / prep screen (arena x monster x weapon x two elements x seed, replay), world map, disturbance, ambush cutscene, drops, three upgrade slots per skill with the kickoff examples implemented, monster state visuals and status icons. The exe opens on the lobby. |
| 4 | Co-op | 1 lane | 2-4 players over Godot high-level multiplayer, host-authoritative orders, one full hunt with two clients. |
| 5 | Balance, polish, web | 2 lanes | Web export via the shim, Vercel, friends play it; tune pass from playtest notes. |

### Phase 0 — Foundation (serial)
1. `git init`, branch `dev`; project.godot (Forward Plus, 4.7); folder layout `src/core`, `src/game`, `src/kit`, `src/arena`, `src/monster`, `src/weapons`, `art/`, `audio/`, `shaders/`, `tests/`, `tools/`, `design/`, `guide/`, `history/`.
2. Copy and adapt the rules core: hex, formulas, tiles, overheat, overfreeze, phases. Replace "cycles" with ticks. Seeded rng. One formulas module with breakdowns.
3. `boot.gd` with `--self-test`, `--seed`, `--arena <id>`, `--fight <monster>`, `--autoplay`. Self-test runner, JSON report, non-zero exit on failure.
4. Camera rig, tile shaders, BWHex-to-world, hex pick against a heightfield, true-hex outline.
5. `HexSim` skeleton: 30 Hz `step(orders)`, player entity with hex position, path over hexes with blocked cells, walk/run speeds in ticks per hex.
6. CI workflow: import, self-test, smoke run `--fight swampfang --autoplay` with no SCRIPT ERROR.
7. Doc set: CLAUDE.md, HANDOFF.md, LEDGER.md, DECISIONS.md, guide/ leaves (layout-and-run, core-contracts, mesh-pipeline, lanes).
8. Open-test list: anything that needs a window is listed with the exact local command.

### Phase 1 — First fight
Lane P (play loop): player rig in, lance equipped, click-to-move, target and walk-into-range, basic attack, Q Pierce / W Elemental Exchange / E Guard / R Eruption as orders, cooldowns, stagger on hit, burn/poison/paralysis statuses, HUD bottom bar (Q/W/E/R, HP orb, active + backup element), F1 tune panel.
Lane C (pond): pond generator (shallow water floor, lilypads as cover hexes, flowers, grass skirt, sunny sky), hex underlay mapped onto the heightfield, water-depth interaction nodes for dive/surface, bench tool with sliders, presets, undo, JSON export, preview render, test.
Lane E (Swampfang): Monster Rig Builder; Swampfang model (eel salamander, frill, paddle tail, strong front legs); clips: calm float, aggravated idle, frill roar, hit react, stagger, collapse, death, walk, dark spray, water jet, thrash splash, death-roll spin, dive, swim, surface lunge, backward bite-miss. Monster sim: calm / aggravated / threatened states, attacks as telegraphed hex sets, weak point rear, dive-and-surface with ripple tell.
Lane F (audio): 4-5 drum loops at 120 BPM, 4 bars each, plus MIDI chord progressions. Sound-effect copy-in.
Integration: P owns `src/game/fight.gd`, the only file that reads all three.

### Phase 2 — Fan-out
Lane A weapons: dual daggers (sword-sized karambits), bow, glaive-style lance; each with model, manifest row, preview render, test, equip clip; "gauntlet-test" each against design/kickoff/ref.
Lane B weapon animation: per weapon wielded idle, forward strike, sweep, spin, jump, jump-attack; specials: dagger dive/corkscrew, bow kneeling shot, lance plant, lance slam, lance guard.
Lane C map tooling: cave (destructible pillars), caldera (heat vents, lava pools), glade (sunlit patches); telegraph layer API shared by all monsters.
Lane D maps: cave, grassy glade, volcanic caldera generated and tuned with presets.
Lane E monsters: Colambros, Rimeslithe, Spirewalker on the rig builder with the kickoff clip lists; per-monster calm idle, aggravated idle, enrage roar, hit reaction, stagger, collapse, death, walk.
Lane F: music handoff to the author; melody is the author's.

## 4. Verification standard
- Every lane: a `tests/test_<lane>_*.gd` suite in the self-test, a preview render PNG under `design/art/`, and a manifest row where a mesh is produced.
- Visual checks are real renders from the Godot binary (windowed or software). Never forged.
- Tests that cannot run headless are listed in LEDGER with the exact command.
- Feel numbers live in one cfg and a live F1 panel.

## 5. Open questions (resolved 2026-10-19)
- Arena edge: hard boundary, edge hexes unwalkable (H17).
- Element choice: any two of seven at the prep screen (H18).
- Stamina: HP only in Phase 1, HUD slot reserved (H19).

## 6. Lanes (defined now, started only after Phase 0; not before the kickoff §7 answer)

Each lane: its own worktree off `dev`, an owned file set, a reserved DECISIONS block. No lane edits another lane's files. Shared contracts live in `src/core` and `guide/core-contracts.md` and change only through the integrator (session 0 / Lane P).

| Lane | Owns | DECISIONS block | Phase |
|------|------|-----------------|-------|
| P Play loop (integrator) | `src/game/**`, `src/core/**`, `tests/test_play_*`, HUD, fight.gd | H400-H449 | 1 → |
| A Weapons | `tools/blender/build_weapons.py`, `art/weapons/**`, `tests/test_weapon_*`, `tools/weapon_preview.gd` | H100-H149 | 2 |
| B Weapon animation | `src/game/anim/weapon_*.gd`, `art/clips/weapons/**`, `tests/test_clip_*` | H150-H199 | 2 |
| C Map tooling | `src/arena/gen/**`, `src/arena/bench/**`, `src/arena/interact/**`, `tests/test_arena_*` | H200-H249 | 1 → |
| D Maps | `arenas/*.json` presets, `design/art/arenas/**`, `tests/test_map_*` | H250-H299 | 2 |
| E Units and monsters | `tools/blender/build_monster_*.py`, `src/monster/**`, `art/monsters/**`, `tests/test_monster_*` | H300-H349 | 1 → |
| F Audio | `D:\Music Studio\Claude Playground\hexhunt\**`, `audio/**` | H350-H399 | 1 |

Merge rule: lane branch → `dev` by the integrator after that lane's suite and the full self-test pass. `main` moves only at a phase gate.

### Phase 3 lanes (2026-10-19)

| Lane | Owns | Block | Delivers |
|------|------|-------|----------|
| L Lobby | `src/game/shell.gd`, `src/game/registry.gd`, `src/game/lobby/**`, `src/game/boot.gd`, `src/game/fight.gd` (setup_cfg + finished only), `tests/test_lobby*.gd` | H450-H499 | Gauntlet-pattern lobby: tiles per arena / monster / weapon, element pair pick (any two of seven), seed field, Play / Replay / New seed, gear -> F1 tune panel, `HHShell`, `HHRegistry`, `setup_cfg`, exe boots to the lobby, flags still launch a fight directly |
| H Hunt loop | `src/game/hunt/**`, `tests/test_hunt*.gd`, `design/hunt/**` | H500-H549 | world map with four biome sites, disturbance marker, approach -> ambush cutscene, prep via the lobby (locked arena/monster), results screen with drops, back to the map |
| U Upgrades | `src/progress/**`, `src/weapons/**`, `tests/test_upgrade*.gd`, `tests/test_play_daggers/bow/lance` (extend), small `src/core/sim.gd` hooks (logged) | H550-H599 | `HHUpgrades` table with the six kickoff examples implemented, three slots per skill, `HHDrops` per monster, `HHSave` |
| V Visuals | `src/monster/monster_body.gd`, `src/monster/*_clips.gd` view hooks, `src/game/anim/player_body.gd`, `src/game/hud.gd`, `src/game/arena_view.gd` (status/state only), `tests/test_visual*.gd` | H600-H649 | L-12 (quill glow, crystal tint, reed arcs, HUD status icons), L-13 (hood, coloured weapon glbs on the body), L-4 tile cards if cheap |

### Phase 3.5 — Visual pass (2026-10-19)

| Lane | Owns | Block | Delivers |
|------|------|-------|----------|
| MA Monsters A | Colambros + Rimeslithe: `tools/blender/build_monster_{colambros,rimeslithe}.py`, `tools/blender/monster_rig/ext_{colambros,rimeslithe}.py`, new `monster_rig/shapes_ma.py`, `art/monsters/{colambros,rimeslithe}.*` + their monsters.json rows, `src/monster/{colambros,rimeslithe}_clips.gd`, their previews, design docs, tests | H650-H674 | gauntlet-tested models + clips |
| MB Monsters B | Swampfang + Spirewalker: same set for those two, new `monster_rig/shapes_mb.py` | H675-H699 | gauntlet-tested models + clips |
| FX Effects | new `src/game/fx/**`, `src/monster/monster_body.gd`, `src/game/arena_view.gd`, `src/game/tile_fx.gd`, `shaders/**`, `tests/test_fx*.gd` | H700-H749 | wind-up effects for every monster attack (body + air + ground), breath vs charge, player skill wind-ups and impacts, L-4 standing cards, L-18 readability |
| ENV Environment | `src/arena/**`, `arenas/*.json`, `src/kit/gk_materials.gd`, `src/game/hunt/world_map.gd`, `tests/test_arena_*.gd` | H750-H799 | arenas gauntlet-tested against `ref/arena_*.jpg`, world map landmarks and paths (L-20) |
| UI Interface | `src/game/hud.gd`, `src/game/lobby/**`, `src/game/hunt/results.gd`, `src/game/hunt/ambush.gd` (title card only), `art/ui/**`, `tools/ui_*.gd`, `tests/test_lobby*.gd`, `tests/test_ui*.gd` | H800-H849 | HUD gauntlet-tested against `ref/ui_hud.jpg`, lobby thumbnails + element hint + run history (L-19), results polish |
