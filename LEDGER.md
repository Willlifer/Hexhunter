# LEDGER

One row per tracked item. An item belongs here only if it passes all four tests:
1. It's discrete.
2. It has a state that can change.
3. Forgetting it costs something.
4. No test already guards it.

States: BLOCKED / OWED / AWAITING PLAY / WATCH / DEFERRED. IDs never change.

## Live

| ID | Item | State | Unblocked by / note |
|----|------|-------|---------------------|
| L-10 | Phase 2 gate: the author plays each monster on its biome with each weapon | PASSED 2026-10-19 ("very fun, loved all of the fights"); fire burn "way too strong" -> fire_stand 3.0->1.2, fire_cross 1.5->0.6, burn 2.0->1.0 (H46) | dist\Hexhunt.exe + launchers/ |
| L-11 | Roared shapes are now huge (thrash 72 hexes, Colambros back-roll 65): intended per H41 but untested by a human | PASSED 2026-10-19: no complaint about size after play; stays | author |
| L-12 | Visual hooks the monster lanes asked for: Colambros quills glow when smouldering, Rimeslithe crystals tint by cold, Spirewalker reed arcs by charge; HUD icons for slow / freeze / poison / paralysis | SETTLED 2026-10-19 (Lane V, H600-H611) | - |
| L-13 | Hunter hood reads as a ring helmet from the front; Black | White weapon glbs in art/weapons/bw_temp still used by the body until the loader points at Lane A's coloured set | SETTLED 2026-10-19 (Lane V: cowl hood, coloured weapons, bw_temp deleted) | - |
| L-2 | Windowed checks (`--shot`, the sandbox) are not in CI; CI runs import, self-test and the headless smoke run only | WATCH | A software-rendering capture on CI is open; the local command is `run.bat --fight swampfang --shot design/art/shots --cam 30,42` |
| L-3 | Element shaders were tuned for a white tile (Black | White); on natural ground the dark face and the glaze read, fire and water read, light's dark ring may need retuning on grass | WATCH | Lane C / Lane P judge on the pond |
| L-4 | Tile-effect "cards" (standing flames, light column, dark tendrils) are copied in but not yet drawn by HHArenaView | SETTLED 2026-10-20 (Lane FX draws the standing cards) | - |
| L-8 | The autoplay bot does not dodge; smoke runs end with the player dead. Fine for a smoke test | CLOSED: the author has played all four fights (L-10) | - |
| L-6 | GitHub remote not created (H6: only when asked); `.github/workflows/ci.yml` is ready for it | DEFERRED | Author asks |

## Settled

| ID | Item | Date |
|----|------|------|
| S-1 | Phase 0 foundation: import clean, self-test 35/35, smoke run clean, rendered frames captured | 2026-10-19 |
| S-2 | Phase 0 gate passed by the author (faster walk, 50 m arena, 3x tile life; left-click will be the auto-attack) | 2026-10-19 |
| S-4 | Phase 1 gate passed; notes H31-H41 applied (free movement, right-click act, own-element immunity, 3x HP, 3x tile life, wind-ups, repositioning, potions, wide roars) | 2026-10-19 |
| S-5 | Phase 2 build: lanes A, B, C/D, E x3 merged; 165/165 in 23 suites; every monster smoke-run on its biome; frames captured | 2026-10-19 |
| S-3 | Phase 1 build: lanes P, C, E, F merged to dev; self-test 71/71 in 11 suites; pond smoke run with the Swampfang brain clean; frames captured | 2026-10-19 |
| L-14 | Swampfang barely moves between attacks in play (reposition 70% / walk 10 ticks turns in place when the player stays close); the other three roam more. Author noted it without asking for a change | WATCH | Lane P, revisit with the next pond tune pass |
| L-15 | Every fight started the hunter on fire/water | SETTLED 2026-10-19: the lobby picks any two of seven (Lane L) | - |
| L-16 | Phase 3 gate: the author plays the lobby (every setup, Unlock all upgrades, slot some) and a full hunt (`Hunt.bat` or GO HUNTING): map, ambush, prep, fight, results, drops | PASSED 2026-10-19 ("damn actually very fun"); visual pass next (H49) | - |
| L-17 | Balance flags from Lane U: Exchange Nova paints 37 hexes on a 1 s cooldown with no wind-up (strongest upgrade); Hunting Knives add three 60-damage strikes every 6 s; Cluster Shot and Aftershock always land because brains do not dodge player telegraphs | AWAITING PLAY | author slots them; numbers are F1 keys `upgrade_*`, `daggers_up_*`, `bow_up_*`, `lance_up_*` |
| L-18 | Readability flags from Lane V: Colambros' smoulder glow is weak at 30 m on caldera ground; Rimeslithe's crystals read pale blue even at rest; Spirewalker charged turns the whole reed bed violet; the ward and projectile markers are covered only by headless tests | AWAITING PLAY (Lane FX: ember halo + trail, frost mist, copper reeds kept) | author looks |
| L-19 | Lobby picks blind: tiles are colour + name, no thumbnails; element strip's active/backup alternation is not shown until used; returning from a fight shows only a one-line result | SETTLED 2026-10-19 (Lane UI: thumbnails, element hint, run history, H800-H813) | - |
| L-20 | The world map is readable but sparse: four sites on rolling grass, no roads or landmarks | SETTLED 2026-10-19 (Lane ENV: paths, lake, tower, stones, forest edge) | - |
| L-21 | Map uses a x5 scaled parent because HHCameraRig clamps distance at 40 m (Lane H R-H4) | SETTLED 2026-10-19 (HHCameraRig.dist_max per instance, H761) | - |
| L-22 | Visual-pass gate: the author plays all four fights and a hunt on the new exe: monsters vs references, wind-up effects (ice wind-to-frost, Colambros breath vs charge), arena events, reaction numbers, HUD/lobby | PASSED 2026-10-20 ("No notes for now. Continue.") | - |
| L-23 | Rimeslithe only partly matches the reference (fins are few dark blades, not pale flowing shapes) and nearly vanishes on the dark cave floor | WATCH | next monster pass |
| L-24 | Cave worst-case frames dip to ~45 fps with every effect forced (average 78); weaker GPUs will do worse | WATCH | Lane FX tools/fx_perf.gd |
| L-25 | Quiet tells: generic dust attacks (bite, swipe, tail drag) differ only by footprint at 30 m; thin streaks (Pierce, death-roll vortex) shrink to a pixel; big ice areas wash the red out in the last fifth | WATCH | author's call after play |
| L-26 | Caldera snowline is a per-tile staircase; no water reflections; skill icons are drawn glyphs, not painted art | WATCH | polish phase |
| L-27 | Phase 4 gate: the author plays co-op with a friend on the same network (Host.bat on one PC, Join.bat with the shown address on the other), a fight and a hunt; also solo still feels the same | AWAITING PLAY | dist\Hexhunt.exe, Host.bat, Join.bat |
| L-28 | Internet play (not LAN) needs the host to forward UDP port 24631 or a relay; Windows may show a firewall prompt the first time someone hosts | WATCH | Phase 5 (web: WebSocket transport + a relay) |
| L-29 | A client's own movement has one round trip of lag (~60 ms on one machine, 120-200 ms over the internet); no client-side prediction yet | AWAITING PLAY | author feels it; prediction if it bothers |
| L-30 | Co-op rough edges: nothing points at a downed ally off-camera; the downed pose barely reads in water; results show HP and downs per hunter but not per-hunter damage (hurt events carry no source for skills and reactions); a lost delta stalls a client ~120 ms and its events are not replayed | OWED | next co-op pass |
| L-31 | Combat-feel gate: the author plays charged Q (tap / 1.5 s / 3 s) on all three weapons, the dash, the thrown potion, the lance and dagger combo strings, monster interrupts, exposed windows | AWAITING PLAY | dist\Hexhunt.exe |
| L-32 | Friction to tune after play (Lane W's read): hit 1 of the lance/dagger strings may feel sluggish at 9 ticks recovery (try 6 for hit 1 only); the rooted 3 s lance charge loses most melee trades to interrupts (lance_charge_guard 0.5, or let the brace ignore the flinch from small hits); the dash may be too little friction (dash_recharge_s 4.5, dash_recover_ticks 12) | AWAITING PLAY | F1 panel |
| L-33 | Combo strings reuse the existing strike/sweep/slam (lance) and strike/spin/jump_attack (daggers) clips; the close-up review renders came out from behind; dash pips are a thin arc over the HP orb | WATCH | next animation pass |

