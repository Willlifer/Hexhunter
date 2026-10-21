# Hexhunter
Bro its like every game but put together somehow

A co-op monster-hunting game in Godot 4.7 (GDScript, no plugins). A party of
one to four hunters with medieval weapons and elemental attunement hunts four
rampaging monsters across hex arenas: a third-person MMO camera, true-hex
movement, Q/W/E/R kiting, charged skills, dashes and combo strings, and
element reactions painted on the ground.

- **Weapons:** lance, dual daggers, bow.
- **Monsters:** Swampfang, Colambros, Rimeslithe, Spirewalker.
- **Co-op:** host-authoritative over LAN (ENet).

## Run
Open the folder in Godot 4.7 and run, or from a shell:

```
godot --path .                                   # the lobby
godot --path . -- --fight swampfang --weapon lance
godot --headless --path . -- --self-test         # all test suites
```

Co-op: `--host [--name X]` on one machine, `--join <address> [--name X]` on another.
In a fight, F1 opens the live tuning panel and F3 the debug read-out.

## Docs
Start with `CLAUDE.md` (the doc map), then `HANDOFF.md`, `PLAN.md` and `DECISIONS.md`.
The original brief is in `design/kickoff/`.
