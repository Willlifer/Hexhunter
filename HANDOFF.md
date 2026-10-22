# HANDOFF

## Where
`<repo>`, branch `dev`; GitHub `Willlifer/Hexhunter` (`origin`): push `dev` and `dev:main` (H78). Live: https://hexhunter.vercel.app (Vercel serves the committed `web/`, auto-deploys on push to `main`); co-op relay https://hexhunt-relay.onrender.com (Render free web service from `render.yaml`, sleeps after ~15 min idle). Playable: `dist\Hexhunt.exe` + `launchers/*.bat`. Commit identity is the GitHub no-reply; no usernames or local folder paths in committed files (use `<repo>`, `<godot>`).

## Where it stands (2026-10-22)
Phases 0-4 built; combat feel (H56-H59), spin combos (H60-H77), the huntress rebuilt toward the author's comic reference with a comic ink outline on hunters and monsters (H80-H107, renumbered rows H230-H237), browser look parity (H90-H93), online co-op through the relay (H110-H119), difficulty tiers EASY/NORMAL (H240-H246), the element picker AXIS/OPERATORS copy (H266), the monster hull + Attack Ring + push-out (H250-H259; 20% when a monster lands on you, 5% when your own leap/dash bumps it, H268-H281), camera lag (H280), the element pass (Swirl, Crystal/Shatter, Geyser, Glint/Flux, Steam on every contact, Eclipse 5 s, the 3.3 who-gets-hurt rule, contained actions; H360-H375, H420-H428), NORMAL-tier monsters (enrage, pulse, purge, avoidance, Fakeout/Sweep/Siphon/Rooting; H400-H419), Easy damage calibrated so a face-tank bot dies (H422), monsters resist their own elements 75% (H429), suit = backup element / weapon = active element / ring = player (H430), the author's music (H431). Then the 2026-10-22 play-notes pass (H436-H440, boot preload H460-H466, ice H470-H472). Then the evening pass: stagger bar H510-H518, idle stances H490-H495, lobby tooltips H480-H486. Self-test 61 suites green.

## Do this first
1. Author plays the browser build after the 2026-10-22 evening pass: the stagger bar and topple (L-61: 10 full water combos with the lance; does it feel right, and do fire / dark / light hunters need a way in?), the new idle stances (L-63: should the combat guard match too?), the lobby ability tooltips (L-64). Earlier the same day, still awaiting play: boot preload (L-59), the ice read (L-60), a new region each hunt, the light rule, the lobby sliders.
2. Their notes -> DECISIONS Author rows; retune on F1 (the "stagger bar" section; stances `stance_*`).
3. Open: NORMAL read "difficult" (L-58, WATCH); ambushes other than Swampfang's are not preloaded; the topple slump is the existing stagger clip held low (modest); daggers' blades flare like wings from the front in the new idle.
4. Known noise: test_hunt prints 8 pre-existing `HHMusic._switch` out-of-bounds SCRIPT ERROR lines (suites pass). A fresh worktree needs the main checkout's ignored `audio/music/*.wav.import` copied in or test_music fails. `reference/` (the author's pose references, third-party) is git-ignored.

## Run
`test.bat` / `--headless --path . -- --self-test [--only <suite>]`. `run.bat [--difficulty easy|normal] [--arena a --fight m --weapon w --element e --backup e --seed N]`; `--autoplay --seconds N` prints damage by cause. Co-op LAN `--host` / `--join <ip>`; online `--host --online`, `--join-code ABCDE`, `--relay <url>`. Bots: `tools/difficulty_baseline.gd` (`--bot facetank`), `tools/coop_bot.gd`. Previews: `tools/hull_preview.gd`, `tools/setpiece_preview.gd`, `tools/combo_preview.gd`, `tools/hunter_ref_shots.gd`. Web: `build_web.sh` -> commit `web/` -> push.

## Notes
- The player's files live in `%APPDATA%\Godot\app_userdata\Hexhunt`. Never touch them; lanes use an untracked `override.cfg` (custom user dir) and the self-test redirects.
- Local only (git-ignored): `.blend` sources, `Hexhunt.docx`, `design/art/hunter_ref/` (the comic reference: third-party art), `audio/source/` (the author's original music files).
- Never `taskkill /IM` Godot: parallel runs share the machine.
- EASY is pinned by `test_difficulty`'s EASY_BASELINE hashes: a change to EASY on purpose re-records them.
- Before a push: check the current tree and new commits' authors only (no full-history scans; author's request).
