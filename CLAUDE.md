# The Spire

Standalone 3D multiplayer anime life RPG in Godot 4 (target 4.3, also green on 4.7.2). Not Roblox. Players create a character and live in a floating tower of floors: combat with parry, Sword Arts, bosses with Last Attack bonuses, forging (ranks Normal to Myth, hidden classes), and a life sim (fishing, cooking, farming, stalls, guilds, a cottage, a tavern, a village forge). Multiplayer is server-authoritative ENet, with one server per floor. Inspired by Peroxide (Roblox), Aincrad-style floors and Satisfy-style crafting.

**Read HANDOFF.md first.** It covers architecture, gotchas, test commands and the prioritized backlog.

## Standing rules from Kyle (the owner)
- **Floor 1 only** until Kyle says it is complete. Floor 2 (Mirewood) is frozen.
- **Accuracy:** follow Aincrad (floors, Sword Arts, Last Attack, permadeath) and Satisfy (crafting ranks, hidden classes, request-driven smithing) as closely as is reasonable. Never use their IP names (SAO, Aincrad, Kirito, Asuna, Overgeared, Satisfy, Grid, Pagma) in code, assets or screenshots. Use only original, synthesized or CC0 art and sound; never ripped assets.
- **Visual bar:** it must look like a professionally made game. Placeholder-looking UI is not accepted. Use the Low/Medium/High/Ultra presets, with Ultra tuned for an RTX 5070.
- **Self-sufficiency:** don't bother Kyle with things you can solve. Check, retry and work around problems first. Ask only when a decision is genuinely his.
- **Model routing:** Opus does most of the work. Use Fable only for the hard, high-stakes parts (new netcode or architecture, anti-cheat designs, hard-to-undo data formats). These are marked "Fable-level" in the HANDOFF backlog. Cost matters.
- **Git:** commits are authored as Kyle, with no Claude co-author trailers and no model names:
  `git -c user.name=lordstudmuffin -c user.email=289346469+lordstudmuffin@users.noreply.github.com commit`

## Sync rule (cloud threads push to this repo too)
1. `git pull` before you start working.
2. Make small, focused commits and push them soon. Don't sit on a big local diff.
3. If a pull conflicts, keep both sides' intent and re-run the smoke test before you push.
4. scripts/asset_lib.gd: patch it additively only.

## Run and test
```
# after a fresh clone, or after adding a class_name file (slow the first time)
godot --headless --path . --import

# logic smoke test: expect "== Done: 0 failure(s)" and no "SCRIPT ERROR"
godot --headless --path . res://scenes/smoke_test.tscn
#   SMOKE_ONLY=boss|labyrinth|classes|duels|permadeath runs one block

# play: open project.godot in the Godot 4.3 editor and press F5 (main menu)

# local multiplayer: one server and clients (from the editor: Host / Join on the main menu)
godot --headless --path . -- --server --port 4381 --report
godot --path . -- --join 127.0.0.1 --port 4381 --name Someone
```
"Parameter m is null" spam, ALSA errors and "resources still in use" at exit are harmless headless noise.
