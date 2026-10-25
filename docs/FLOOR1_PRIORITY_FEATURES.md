# Floor 1 priority features: design plan

Written 2026-10-25 for Kyle's six priority features. This is a plan only; nothing here is built yet.
Everything is scoped to Floor 1 (Hollowbrook, Talven, the fields, the Labyrinth). Backlog entries with model tags are in HANDOFF.md under "Kyle's priority features".

## IP rule for this whole document
Kyle wants the menu and sounds **as close as possible** to the reference anime. We match its layout, animation timing, colours and sound *character* as closely as we can, but every pixel and every sample is our own: drawn or shader-made art, and sounds synthesized by us or built from CC0 material (Kenney, freesound CC0, OpenGameArt CC0). We never rip, trace or re-encode the show's or its games' assets. Roblox games doing it does not make it legal; those games get takedowns, and a standalone game on Steam is a much bigger target. Also keep the show's name out of code, asset names and file names (existing HANDOFF rule).

**Everything is swappable from one place.** All sound mappings already live in the `EVENTS` table in `autoload/audio.gd`; the menu's colours, icon atlas, timings and sounds will live in one new file, `scripts/ui/ring_menu_style.gd`. Changing a sound or the menu's look later is a one-file edit.

---

## 1. Ring menu (vertical swipe menu)

**What exists:** a pause modal in `scripts/hud.gd` (`_build_pause`, `_toggle_pause`; online the world keeps running), and finished screens we can reuse as panels: inventory, quest log, map, party/social, settings, cooking, storage. Input actions live in `autoload/input_setup.gd`.

**Target feel (as close as possible):**
- Open with a downward swipe: hold the menu button and flick the mouse down (or press it once; gamepad Select / Back). A two-finger-style gesture is faked with mouse flick speed > threshold.
- A **vertical column of round glassy buttons** drops in beside the player's right hand, one by one top to bottom (about 40 ms stagger, 180 ms ease-out-back each), with a soft open chime.
- Buttons: Status, Items, Skills, Quests, Map, Friends/Party, Messages, Settings, Log Out. Selected button glows; mouse wheel / stick moves the selection with a tick sound.
- Choosing a button slides out a **translucent white/silver panel** to the right with a thin orange/amber accent line and a header bar, then the content (the existing screen, restyled) fades in. Sub-menus slide out a second panel further right.
- A small character silhouette panel with equipment slots for Status/Items, like the reference.
- Closing reverses the animation bottom to top.
- Art: shader-drawn circles and panels (no textures needed), white-to-grey gradient, soft bloom edge, our own line icon set (CC0 icon packs like game-icons.net are CC-BY, so either credit them or draw our own; Kenney's game-icons pack is CC0).

**Build notes:** new `scripts/ui/ring_menu.gd` replaces the pause modal as the main menu entry point and opens the existing screens inside its panels. All timings, colours and sound event names live in `ring_menu_style.gd`. Must work with keyboard, mouse and gamepad focus (UITheme focus rings already exist). Ultra adds a background blur and bloom; Low skips blur.

## 2. UI, combat and progression sounds

**What exists:** `autoload/audio.gd` with ~60 named events (UI clicks, hits, crit, death, level_up, quest_complete, class_unlock, teleport...) mapped to Kenney CC0 files, pooled 2D/3D players, buses and per-event gain.

**Plan:** make an original "crystal interface" sound set that sounds as near as we can to the reference's character, and remap events to it.
- Menu open / close: bright two-note rising/falling glassy chime with a short shimmer tail.
- Selection tick, confirm, back, error: short sine/FM "glass" blips in the same key so they feel like one family.
- Level up: rising arpeggio plus sparkle burst and a soft choir-pad swell (about 1.5 s).
- Item get / rare drop: a lighter version of the level-up arpeggio; rarer items get a longer tail.
- Hit: crisp slash plus a high "digital" tick layered on the existing impact.
- Death shatter: glass-burst crunch with a falling sparkle tail (pairs with feature 3).
- Notification / message received / party invite: soft two-note ping.

**How:** synthesize with a small Python script (numpy additive/FM synthesis, envelopes, reverb) checked into `tools/sfx/` so every sound can be regenerated and tweaked, plus CC0 layers where synthesis sounds thin. Output .ogg into `assets/audio/crystal/`. New event names (`menu_open`, `menu_select`, `shatter`, `item_rare`...) are added to `EVENTS`; old names get remapped. No other code changes needed.

## 3. Hurt and death effects

**What exists:** `scripts/vfx.gd` (pooled slash arcs, impact flashes, sparks, rings, flash lights, a dissolve shader on death), enemy hit flash in `scripts/enemy.gd`, floating damage popups (`_popup`, crit is bigger), `shaders/hit_vignette.gdshader` for the player.

**Plan:**
- **Polygon shatter death** (the signature look): on death the model flashes white for ~0.15 s, freezes, then bursts into glowing triangular shards tinted by the mob's colour that fly out, spin and fade in ~0.8 s, with the shatter sound. Implemented as a GPU particle burst of triangle-shaped additive quads emitted from the mesh surface (emission shape from the mesh), not real mesh fracturing, so it is cheap on every preset (Low: 40 shards, Ultra: 250 plus light flash and bloom). Replaces the current dissolve for mobs; bosses get a bigger, slower version.
- **Player death:** same shatter on the player (other players see it), screen goes grey, a "You are dead" panel, respawn at the gate after a short timer. Server already owns death and respawn, so this is cosmetic on top of the existing `respawn` flow.
- **Hit feedback:** a thin red slash-line decal across the target where the blow lands, brief hit-stop (40-60 ms) on crits, the existing sparks, and HP bars that **drain with a delayed white chip bar**. HP bar goes green → yellow → red at 50% / 25%, like the reference.
- **Damage numbers:** restyle the existing popups (outlined font, pop and float, crit larger with a flash, healing in green, misses as "MISS").
- **Low HP:** red edge vignette pulse plus heartbeat sound under 25%.

## 4. Player-run life sim (shops, restaurants, farms, guilds)

**What exists:** buyable cottage (`scripts/life/home.gd`, furniture), cooking with buffs, fishing, herb fields, NPC trader shop (`scripts/ui/shop_screen.gd`), storage, life skill XP (`RecordState.add_life_xp`). All server-validated through `Net.request_action` → `RecordState`. **Missing:** any shared, server-wide state. The server only stores one JSON record per character (`user://server_db`, flushed every 60 s). Shops, guilds and plots need a **world database** (see the core under feature 5/6).

**Floor 1 scope, in build order:**
1. **Player stalls (shops).** 6 rentable stall plots in Hollowbrook market. Owner pays weekly rent in Col, stocks items from storage and sets prices. A stall keeper NPC sells while the owner is offline. Money goes to the owner's till, collected later. 5% market tax as a money sink.
2. **Restaurants.** A stall type that sells cooked dishes; dishes carry timed buffs, so there is demand. Owners can add seating props. Later: hire an NPC cook.
3. **Farms.** 8 farm plots outside Hollowbrook, rented like stalls. Plant seeds, water, crops grow in real time (hours), harvest into cooking ingredients. Crops wither if neglected for days.
4. **Guilds.** Found for a fee at level 10 at the Hollowbrook notice board: name, tag over head, ranks (Leader, Officer, Member), roster, guild chat, shared guild storage, guild-owned stall. Guild halls come on a later floor.

Every purchase, sale and storage move is an atomic server transaction in the world DB (escrow), so items and Col cannot be duplicated by disconnecting mid-trade.

## 5. Unique skills (one holder per server)

**Design:**
- A unique skill is a skill line only one player on the server can hold at a time. Floor 1 ships **one**, proposed name "Twin Fang" (dual wield, its own 3 Sword Arts). A second, e.g. a shield skill, can follow on a later floor.
- **How it is granted:** never bought or quested openly. The server watches hidden stats per player (for Twin Fang: highest reaction speed, measured as perfectly timed dodges/parries and fastest kill chains). When the skill is free and a player crosses the hidden threshold first, the server grants it, the skill tab shows a new entry, and the whole server sees an announcement. A "Legends board" in Hollowbrook lists current holders.
- **Server-authoritative ownership:** a registry in the world DB holds `skill_id → holder (account token + character), granted_at, last_seen`. Granting is atomic and **written to disk immediately**, not on the 60 s flush, so a crash cannot grant it twice. Every cast goes through the existing validated action path and is checked against the registry. It cannot be traded or dropped.
- **If the holder quits:** deleting the character frees it at once. If the holder is inactive for **14 days** (proposed), the skill returns to the pool and the race starts again; the holder gets a warning mail at 10 days. Logging back in after losing it does not restore it.
- **"Per server" meaning:** today one server = one floor instance. The registry should be keyed by **realm** (a group of floor servers sharing one world DB), so when Floor 2 opens a unique skill stays unique across all floors. For Floor 1 alone, realm = the single server.

## 6. Limited items and quests (1-3 holders per server)

**Design:** the same registry, generalized: `limited_id → cap (1, 2 or 3), holders[]`.
- **Limited quests:** accepting reserves a slot; if the player does not finish within a time limit (e.g. 2 hours online time) the slot frees up. Completing makes it permanent. Quest givers say "someone has already taken this" when slots are full. Floor 1 example: a hidden NPC in the Labyrinth gives a 1-holder quest whose reward is a Legendary-rank cloak.
- **Limited items:** each copy has a unique serial stored in the registry; on every record load the server checks serials against the registry, so duplicates are deleted and logged. **Bound to the character** for Floor 1 (cannot trade), which keeps the cap meaningful and avoids dupe exploits. Freed only on character delete or 30 days inactive (proposed).
- Floor 1 content: 3-4 limited items (one per terrace boss or hidden spot) plus 1-2 limited quests. Server announcement when the last slot is taken.

---

## The shared core (Fable-level)
Features 4, 5 and 6 all need the same thing that does not exist yet: a **realm world DB** with atomic claim/release, immediate durable writes for claims and trades, escrow transactions, and serial checks on load. Build it once, carefully, then everything else on top is routine. Recommended: Fable designs and builds this core (new architecture plus server authority, hard to change once real players own things), then Opus builds stalls, farms, guilds, the unique skill content and the limited items on top.

## Open questions for Kyle (defaults used until he says otherwise)
- Unique skill inactivity release: 14 days.
- Limited items tradeable or bound: bound.
- "Per server" = per realm (all floors), not per floor instance.
