# Hidden classes (Floor 1)

Code: `scripts/hidden_classes.gd` (rules, arts, deeds), `GameState.HIDDEN_CLASSES`
(stat bonus + perk text), `RecordState.unlock_hidden_class` / `GameState.unlock_hidden_class`
(the grant). One hidden class per character; they are not realm-limited (that is the
unique-skill system in `scripts/unique_skills.gd`).

A hidden class is found by doing something unusual, then an NPC who noticed opens a
quest nobody is told about. The deed is a hidden stat on the record / save (`"hidden"`),
which `Net.snapshot_for_client` strips, so clients never see or report progress. The
quest only enters the log once the NPC opens it (`QuestData` marks both `"hidden": true`).

| Class | Deed (hidden stat) | Rite (quest) | Perks | Arts |
|---|---|---|---|---|
| **Forgeborn** | craft 2 items | Haldor: "Trial of the Forge" (craft 5) | +3 STR +2 END; crafted gear rolls a rank higher more often | none |
| **Stillblade** | 8 parries in a row with no damage taken between them (`clean_parries`; any hit resets it) | Quartermaster Dain (Talven camp): "The Unmoving Edge", parry 10 more strikes anywhere | +2 AGI +2 END +1 STR; guard regenerates 1.6x faster | Still Water (slot 1): counter cut, castable only in the 1.5 s after a parry, lunges, 2.4x, 6 s cd. Breaking Wave (slot 2): 1.8x pommel strike that builds 1 posture (staggers a normal mob outright, one of three on a Guardian), 14 s cd |
| **Hearthwright** | 12 dishes cooked over 4 recipes, 5 fish landed, 3 harvests (`dishes`, `recipes`, `fish`, `harvests`) | Innkeeper Rook (after "A Pot for the Tavern"): "The Wandering Pot", bring Grilled Trout + Turnip Soup + Harvest Bread at once | +2 END +2 SPI +1 AGI; food buffs last 1.5x and are 1.25x stronger; cooks anywhere (interact with nothing near opens the field kitchen; the server accepts cooks without a fire) | Hearth Flare (slot 1): 1.5x in a full half-circle (range 3), landing it grants Hearth Glow (+3 HP/s, 10 s), 12 s cd |

## Bindings

| Slot | Keyboard | Gamepad |
|---|---|---|
| Class art 1 | `R` (`class_1`) | hold Target (LT) + Attack (X) |
| Class art 2 | `C` (`class_2`) | hold Target (LT) + Dash (B) |

Both actions are in the Controls remap list. The chord follows the unique-art pattern
(LT + RB/LB/RT); with LT held, Attack and Dash cast instead of swinging / dashing.

## Server authority

- Deeds: `Enemy._parried` -> `Net.note_hidden(peer, "parry")`; `Net.srv_damage` and
  `Player.take_damage` note `"hurt"`; `LifeData.cook` / `land_fish` and `Farms` harvest
  call `gs.note_hidden(...)` on whichever side runs them (GameState offline, RecordState on
  the server). `HiddenClasses.note` also advances the open Stillblade rite on a parry.
- Casts: the client sends `HiddenClasses.KIND_BASE + i` to `Enemy.net_hit`. The server
  checks `Net.srv_hidden_class(sender)` against the art's class, the art's cooldown, and
  for Still Water that `Player.last_parry_ms` (stamped where the server judged the parry)
  is within `COUNTER_WINDOW + COUNTER_LATENCY`. Hearth Flare's buff is put on the record by
  `Net.srv_class_buff` after a validated hit.
- Rites: run inside the NPC talk handlers (`world._dain_talk`, `world._hearth_talk`)
  on the RecordState, like every other quest.

## VFX hooks (all behind `has_method`)

- `VFX.class_art_cast(player, class_name, art_id)` on every class art cast.
- `VFX.hearth_glow(player)` when Hearth Flare lands offline / on the host (remote clients
  see the buff arrive through the patch).
- Breaking Wave reuses `VFX.stagger(enemy, secs)` through `Enemy.net_staggered`.

## Leftovers

- HUD / ring menu show no cooldown caps for `Player.class_cd` yet (hud.gd is owned by the
  visuals thread). Casting still gives sound, rumble and the swing fx.
- Soak bots do not earn classes; the smoke test covers the rules (`SMOKE_ONLY=classes`).
