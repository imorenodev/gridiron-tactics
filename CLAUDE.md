# CLAUDE.md — Gridiron Tactics (Defold)

> **Read this file at the start of every prompt.** It encodes the architectural decisions and conventions for this project. If a request conflicts with this doc, surface the conflict before writing code.

## Project context

Gridiron Tactics is a Marvel Snap-style card game with a football theme, being ported from a single-file HTML/JS prototype to Defold for iOS and Android release. The HTML version is the living spec; this repo is the production rewrite.

- **Engine:** Defold (latest stable, currently 1.10.x). Lua scripting.
- **Target platforms:** iOS first via TestFlight, then Android. Single codebase.
- **Bundle ID:** `com.imoreno.gridirontactics`
- **Design resolution:** 1170×2532 portrait. Scales to device via fit-to-shortest-axis with letterboxing.
- **Game name:** Gridiron Tactics. No rebrand planned.

## Phase log

- **Phase 0: complete (vertical slice).** Defold project skeleton, menu ↔ match collection-proxy flow, hardcoded test card driving a yards counter, and a save/load smoke test that persists `total_taps` across launches. See "Phase 0 — Vertical slice notes" at the bottom of this file for details and stubs left for later phases.
- **Phase 0.6.5: complete (render script fix-up — reverted to default render).** The Phase 0 custom render script broke `gui.pick_node`; reverted to `/builtins/render/default.renderc` and deleted the custom files. Letterboxing is deferred to a post-TestFlight phase.
- **Phase 1: complete (architecture slice).** Three lanes, hardcoded 5-card hand, drag-to-play, one drive, END DRIVE → resolution animation → summary panel → return-to-menu, with `total_drives_played` persisted across launches. No AI, no scoring, no modifiers/synergies/perks, no deck cycle, no real assets. See "Phase 1 — Architecture slice notes" at the bottom of this file.
- **Phase 2: complete (AI side + reveal mechanic).** AI has its own 5-card hand and 12 energy; `cpu.lua` heuristic ported from the HTML picks AI plays at END DRIVE. Both sides play face-down; END DRIVE triggers a `revealing` phase that flips cards one-by-one with a 280 ms stagger and rolls each lane's pills as it reveals. Net yards formula now uses both sides: `floor(off_sum/2.5) − floor(opp_def_sum/2.5)`. Still no scoring, no abilities (no-op `try_apply_snap_ability` hook), no modifiers, no deck cycle, no real assets. See "Phase 2 — AI side notes" at the bottom of this file.
- **Phase 2.5: complete (polish pass — input gate, reduced-motion infra, asset migration).** Phase transitions now broadcast `HUD_PHASE_CHANGED` so the HUD blocks drag-start outside `"play"` (a `"resolving"` phase was added between `"revealing"` and `"ended"` so the gate spans the yard-fill animation). `meta_state.lua` is the new home for persistent player settings; `animate_helper.lua` short-circuits `go.animate` / `gui.animate` when `meta_state.is_reduced_motion()` is on. `R` toggles the flag (dev only — Settings screen lands in a later phase). `src/assets/` PNGs are now under `assets/images/ui/`. See "Phase 2.5 — Polish pass notes" at the bottom of this file.
- **Phase 3: complete (scoring — TD, safety, PAT, 2pt, pick-6, FG).** Ball positions ≥ 100 score a TD (6); auto-PAT (+1) if a Kicker is revealed in that lane; 2-pt conversion modal with a 3D coin flip when the scoring side has more revealed OFF than the defender has revealed DEF. Ball ≤ 0 scores safety (+2) or pick-6 (+6) for the defender (4+ revealed DBs = pick-6). The `try_apply_snap_ability` dispatcher is wired with one ability — Clutch Kicker (FG +3 if past midfield at reveal). After every score, the lane resets: cards cleared, both balls re-kickoff (15-35 normally, 5% chance of 40-60 big return). Score bursts animate per event at ~1.8s with the top-bar score pulsing. Match still ends after one drive. See "Phase 3 — Scoring notes" at the bottom of this file.
- **Phase 4: complete (multi-drive cycle + deck cycle).** Match is now 8 drives. Each side has a 30-card deck (with-replacement from `cards.lua`'s 18-card pool) + a discard pile that's filled with unplayed hand cards at drive end. Deck reshuffles from the discard when it empties. Energy escalates: drive N grants N energy on top of any carryover (capped at MAX_ENERGY_BANK=10); a "+N CARRIED" toast appears when carryover happens; the orb pulses when at cap. Cards played to the field stay in the lane between drives but their `cur_off`/`cur_def` get zeroed by `consume_drive_cards()` so they don't keep contributing yards across drives. Discard and draw both have arc animations (cards rotate/scale/fade out to the discard badge; new cards arc in from the deck badge); "RESHUFFLING DECK" text + a discard-badge bump signals when the deck refills. Deck/discard count badges show remaining cards with a bump animation on change; tapping the discard badge opens a text modal listing per-drive discards. AI's deck cycle runs silently. Scoring still works across drives. See "Phase 4 — Multi-drive notes" at the bottom of this file.
- **Phase 5: complete (asset integration — atlases, card frames, portraits, coin upgrade).** Five atlases built from the 37 PNGs in `assets/images/ui/`: `field.atlas`, `ui_chrome.atlas`, `cards.atlas`, `icons.atlas`, `portraits.atlas`. Stadium photo behind the lanes, painted endzones (red top, green bottom) per lane, broadcast scoreboard frame with 9-slice on the top bar, button chrome with 9-slice on CONCEDE / END DRIVE, badge backgrounds on the energy orb + deck + discard, team rings behind the score numbers, power circles behind both pills per lane, football icon in the scoreboard center, real card frames (8 rarity × side variants) on hand cards via runtime `gui.play_flipbook`, per-card portrait + position icon + ability star sub-nodes on hand cards (QB portrait PNG; everything else falls back to a POSITION_COLOR box), and a real coin flip using two synchronized sprite nodes (`coin_heads` + `coin_tails`, rotation.y offset by 180°). The menu screen now uses the football-field photo background with a dark vignette overlay. Default font kept (real fonts ship in Phase 5.5). See "Phase 5 — Asset integration notes" at the bottom of this file.

## Hard rules — non-negotiable

These were debated and settled in earlier conversations. Do not re-litigate.

1. **One responsibility per script file.** A `.script` does one thing. If it grows past ~200 lines, split it. The HTML version was a single 4000-line file; this is the opposite of that.
2. **Single currency (Cash) only.** No premium currency, ever. Future monetization is cosmetics for real money.
3. **No card upgrades.** Progression is via perks only. Cards stay vanilla.
4. **Three equipped perk slots, always.** What scales with level is the perk pool size, never the slot count.
5. **Permadeath season runs.** Lose = season ends. No mulligans, no second chances.
6. **CPU plays vanilla.** No perks for AI.
7. **No PvP in v1.** IAP-gated multiplayer is a future concern; do not architect for it now.
8. **Portrait-only orientation.** Don't add landscape support.
9. **No third-party Lua libraries** unless explicitly approved. Defold's stdlib + the project's own modules only. Exception: lightweight, well-known utilities like `defold-tween` may be considered case-by-case.
10. **No Lua `loadstring` or `require()` of dynamic paths.** Defold builds bundle resources statically; dynamic loading breaks builds.
11. **Custom render scripts are a known footgun.** Use `/builtins/render/default.renderc` unless we have a specific, tested reason to customize. Any custom render script must verify that `gui.pick_node` correctly registers taps on visible GUI buttons before being merged. The Phase 0 letterbox attempt broke input picking even though rendering looked correct.

## File layout

```
gridiron-tactics-defold/
├── game.project              # Project config, resolution, bundle ID
├── input/
│   └── game.input_binding    # Input mappings
├── render/                   # Reserved. Currently empty; we use /builtins/render/default.renderc.
├── main/
│   ├── main.collection       # Root scene
│   ├── match/                # In-match game objects and scripts
│   │   ├── match.script      # Match state machine
│   │   ├── lane.script
│   │   ├── card.script
│   │   ├── card.factory
│   │   └── deck_manager.script
│   ├── data/                 # Pure-data Lua modules
│   │   ├── cards.lua
│   │   ├── modifiers.lua
│   │   ├── synergies.lua
│   │   ├── teams.lua
│   │   └── perks.lua
│   ├── state/                # Stateful Lua modules
│   │   ├── match_state.lua   # Active match state
│   │   ├── meta_state.lua    # Cash, XP, perks, locker room
│   │   ├── save.lua          # Persistence layer
│   │   └── messages.lua      # Pre-computed hash constants
│   ├── ai/
│   │   └── cpu.lua           # CPU decision logic (pure module)
│   └── ui/                   # GUI scenes and scripts
│       ├── hud.gui
│       ├── hud.gui_script
│       ├── menu.gui
│       ├── menu.gui_script
│       ├── locker.gui
│       ├── locker.gui_script
│       ├── draft.gui
│       ├── draft.gui_script
│       ├── summary.gui
│       └── summary.gui_script
├── assets/
│   ├── ui.atlas              # Packed UI sprites (scoreboard, buttons, badges)
│   ├── cards.atlas           # Card frames + portrait images
│   ├── field.atlas           # Field, endzones, stadium bg
│   ├── icons.atlas           # Position icons, modifier icons (sliced from grids)
│   ├── fonts/                # .font files
│   └── images/               # Source PNGs (used as atlas inputs)
└── CLAUDE.md                 # This file
```

## Code conventions

### Naming

- **snake_case** for everything: variables, functions, files, message names, hash IDs. This is Lua/Defold convention. The HTML version's camelCase does not carry over.
- **SCREAMING_SNAKE_CASE** for constants and pre-computed hashes.
- **Files:** `kebab-case` is also acceptable for Defold filenames if it improves readability (e.g., `match-state.lua`), but snake_case is preferred.
- **Functions:** verb_noun (`play_card`, `resolve_drive`, `apply_modifier`). Predicates end with `_p` or use `is_`/`has_` prefixes.

### Module structure

Every Lua module that exports anything follows this shape:

```lua
-- main/state/match_state.lua
local M = {}

-- Module-local state. Never expose directly.
local current_drive = 0
local your_score = 0
local ai_score = 0

function M.get_drive()
    return current_drive
end

function M.advance_drive()
    current_drive = current_drive + 1
    return current_drive
end

return M
```

No bare globals. No exposing internal state. If a caller needs read access, write a getter. The discipline matters because Defold's hot-reload preserves module state on script changes, and module-local state is what survives cleanly.

### Hashes

`hash()` calls in hot paths (per-frame, per-message-receive) are a measurable perf cost. Pre-compute every hash you'll reuse:

```lua
-- Top of every script that uses messages
local MSG_CARD_PLAYED = hash("card_played")
local MSG_DRIVE_STARTED = hash("drive_started")

function on_message(self, message_id, message, sender)
    if message_id == MSG_CARD_PLAYED then
        -- ...
    end
end
```

Shared message hashes live in `main/state/messages.lua` and are imported where used.

### Messages

Naming: `category.event` where category is the sending domain.

- `match.drive_started`
- `match.drive_resolved`
- `match.ended`
- `lane.card_played`
- `lane.modifier_revealed`
- `hud.energy_changed`
- `hud.score_changed`
- `card.flipped`

Avoid generic names like `update`, `change`, `done`. Be specific. A reader of `match.script` should be able to see every message it handles and understand the match flow from the names alone.

### Comments

- Comment **why**, not what. `-- recompute synergies because a card was just played` is useful. `-- loop through cards` is noise.
- Top of each file: 1-3 line summary of what it does and what it depends on.
- Surface footguns: if a function must be called in a specific order, say so at the top of the function.

### Animations

Use `go.animate` and `gui.animate`. Do not roll your own per-frame easing in `update()` unless you have a reason. The built-in playback modes (`ONCE_FORWARD`, `LOOP_PINGPONG`, etc.) and easing curves cover almost everything.

For sequenced animations (A then B then C), use the completion callback pattern:

```lua
go.animate("#sprite", "position.y", go.PLAYBACK_ONCE_FORWARD,
    100, go.EASING_OUTQUAD, 0.3,
    0, -- delay
    function(self)
        -- onComplete: kick off the next animation
        go.animate(...)
    end)
```

Don't nest more than 2-3 deep. If you need a real sequence, write a small coroutine-based helper or use `timer.delay`.

### Reduced motion

The HTML version respects `prefers-reduced-motion`. Defold has no OS-level equivalent. Implement a `reduced_motion` boolean in `meta_state.lua` with a settings toggle. All animation helpers check this flag and shortcut to either no animation or a 0.1s fade. This is a v1 feature, not a "later" feature — accessibility ships with the product.

### Save/load

- Save format is a single Lua table serialized via `sys.save`.
- **Every save has a `version` integer field.** Current version: `1`.
- Schema changes require a migration function in `main/state/save.lua`. Never silently drop or rename fields.
- Save path: `sys.get_save_file("gridiron_tactics", "save.dat")`.
- Auto-save triggers: end of match, end of draft pick, perk equip change. Never auto-save mid-drive.
- Corrupted save (decode fails): fall back to default state and surface a toast. Never silently wipe.

## Things I would NOT do

A non-exhaustive list of patterns that have come up in this project and been rejected:

- **Don't build a giant `game.lua` "global state" module.** State is split by domain (match, meta, save). One god-module re-creates the HTML mess we're escaping.
- **Don't use Defold's "factories spawn factories spawn factories" pattern for cards.** Cards spawn from a single card factory. Their internal visual children (portrait, frame, badges) are part of the prefab, not factory-spawned at runtime.
- **Don't put game logic in `.gui_script` files.** GUI scripts handle GUI events and animations only. They post messages to game-world scripts for actual logic.
- **Don't write a custom render script unless we hit a specific limitation.** Start with the default and our minimal scaling override. Custom render scripts are a debugging black hole.
- **Don't add a debug menu or cheat codes to the shipping build.** Use Defold's build profiles to strip debug-only code at bundle time.
- **Don't hand-author `.collection` or `.gui` files for anything complex.** Use the Defold editor for visual scene authoring; commit the resulting text files. Hand-authoring is fine for trivial collections with 2-3 objects.
- **Don't call `msg.post` from `init()` on the same frame as `acquire_input_focus`.** Order matters; some messages won't be received by the target until next frame. Use `final()` for teardown, not `init()`.
- **Don't rely on `gui.set_position` for layout that should be anchored.** Use node anchors (`gui.set_pivot`, parent anchoring) so layouts respond correctly to different aspect ratios.

## Performance budget

- **60fps target on iPhone 11 and newer.** This is the floor. Most devices will be newer.
- **iPhone SE (2nd gen) tested at 60fps** before TestFlight. SE has the weakest CPU in the modern lineup.
- **Memory:** keep total runtime memory under 200MB. A card game should be well under this.
- **Build size:** under 100MB initial download. Currently the HTML version's assets total well under 10MB so this is generous; reserve room for future content.

## Things that are deliberately deferred

These exist in the HTML version or are planned roadmap items, but are not v1 scope:

- **Smarter AI scaling by tier.** CPU is a greedy heuristic in v1; tier difficulty comes from card pool quality, not strategy depth.
- **IP rebrand.** Decision made: ship as Gridiron Tactics. Replace NFL team codes and real player surnames with fictional equivalents in `main/data/teams.lua`. This is a one-time data migration during the port.
- **Phase B/C/D/E/F leveling features.** Trophies, daily quests, season pass, Tier 3 perks, cosmetics shop — all post-v1.
- **Cowork / AI mode variations.** Not in scope.
- **Music.** SFX must be sourced/generated; music is post-v1.

## Asset pipeline

- Source PNGs live in `assets/images/`.
- Defold's atlas editor packs them into `.atlas` files in `assets/`.
- Reference sprites by atlas + sprite name: `gui.set_texture(node, "ui")` then `gui.play_flipbook(node, "scoreboard_frame")`.
- Sprite grids (position icons, modifier icons) are sliced by adding each named region to the atlas. The HTML version's CSS `background-position` math becomes per-sprite atlas entries.
- 9-slice borders (the HTML version's `border-image` chrome) become Defold's `slice9` property on the sprite/box node.

## iOS build pipeline

Documented in detail in `defold-orientation.md` (the design doc that preceded this CLAUDE.md). Sequence:

1. Apple Developer Portal: App ID with bundle `com.imoreno.gridirontactics`.
2. Provisioning profiles (dev + distribution).
3. Defold `game.project` bundle ID set.
4. Build signed `.ipa` via Defold's bundle dialog.
5. Upload via Transporter to App Store Connect.
6. TestFlight internal testing.

Icons and launch screen are required before first TestFlight build. Use placeholder icon for vertical slice; real icon before any TestFlight upload.

## When in doubt

- **Read this file first.**
- **Match existing patterns in the codebase** over inventing new ones.
- **Ask before adding dependencies.**
- **Ask before adding new top-level folders.**
- **Ask before changing message names** once they're in use — they're an interface contract between scripts.

## Phase 0 — Vertical slice notes

The Phase 0 prompt (`defold-phase-0-vertical-slice-prompt.md`) produced a runnable but deliberately-thin Defold project. None of this is gameplay — it exists to prove the engine, build, render, input, and persistence pipelines all work end-to-end.

### What was built

- **Project config** (`game.project`): 1170×2532 portrait, 60Hz, bundle `com.imoreno.gridirontactics`, render via `/builtins/render/default.renderc` (a custom render script was attempted and reverted — see Phase 0.6.5 below).
- **Input bindings** (`input/game.input_binding`): `MOUSE_BUTTON_LEFT`, `TOUCH_MULTI` → `touch`; `KEY_ESC` → `back`.
- **Root scene** (`main/main.collection` + `main/loader.go` + `main/loader.script`): one `loader` GO that owns two collection proxies (`#proxy_menu`, `#proxy_match`) and the in-memory `save_data` table.
- **Menu** (`main/ui/menu.collection` + `menu.gui` + `menu.gui_script`): title, subtitle, total-taps counter, single PLAY button. Posts `show_match` to the loader on tap.
- **Match** (`main/match/match.collection` + `lane.go`/`lane.script` + `card_factory.go` + `card.go`/`card.script` + `main/ui/hud.gui`/`hud.gui_script`): one lane, one card spawned via factory, HUD with a TEST CARD button that drives a yards counter through the lane.
- **Shared hashes** (`main/state/messages.lua`): all message hashes used by Phase 0 are pre-computed here per CLAUDE.md's hash rule.
- **Persistence** (`main/state/save.lua`): single `{ version = 1, total_taps = N }` table via `sys.save`. Loader credits this on match-end (return to menu), and pushes the latest value to the menu via a `total_taps_changed` message after the menu proxy loads.

### Conventions established in Phase 0 (not previously in this doc)

- **Collection sockets are named after the screen.** `main.collection` → `main`, `menu.collection` → `menu`, `match.collection` → `match`. Cross-screen URLs use that name as the socket: `main:/loader#script`, `menu:/gui#gui`. Future screens follow the same rule.
- **Screen-swap pattern.** The loader sequences `disable → final → unload` on the outgoing proxy, then `load → init → enable` on the incoming proxy on the `proxy_unloaded` / `proxy_loaded` callbacks. Don't bypass this — Defold's collection proxy requires the full handshake.
- **GUI-component id on screen GOs is `"gui"`.** Both `menu.collection` and `match.collection` embed a game object with `components { id: "gui" component: "/path/to.gui" }`. Cross-collection messages from the loader go to `socket:/gui#gui`. Keep this id stable.
- **GUI scripts contain no game state.** They listen for input, post messages to game-world scripts, and re-render on incoming state messages (e.g., `hud.yards_changed`, `total_taps_changed`). Match this when adding new screens.
- **Lane owns its card.** `lane.script` calls `factory.create` on its sibling `card_factory#factory` in `init`, stores the URL, and is the only thing that posts `card.play`. When real card spawning from hand arrives, this becomes "lane owns the cards currently in it" but the ownership direction stays the same.
- **`shared_state = 1` is set in `game.project`.** Required so the same `require`'d module (e.g., `main.state.messages`, `main.state.save`) is the same instance across scripts. Future Lua modules can assume shared state.

### Intentional stubs left for later phases

- `main/match/card.go` has **no visual** — the player-facing "card" is the HUD's TEST CARD box node. Real card visuals (atlas sprite + frame + portrait + badges) come in a later phase. Until then `card.script:on_message(card.play)` is a no-op move.
- **No real match logic.** `lane.script` adds a hardcoded 10 yards per play; there's no opponent, no turns, no power math, no synergies.
- **No CPU.** `main/ai/` is empty.
- **No card data, modifier data, perk data, or teams.** `main/data/` is empty.
- **No real assets.** Everything is solid-color GUI box nodes + Defold's built-in default font. The HTML-prototype PNGs were relocated to `assets/images/ui/` in Phase 2.5 but are **not yet wired up** — atlas building and sprite integration is a dedicated future phase.
- **No reduced-motion flag** yet. CLAUDE.md mandates it ships in v1; Phase 0 has no animations, so the flag has nothing to gate. Add `meta_state.reduced_motion` when the first animation lands.
- **No save migration logic.** `save.lua` checks `version == 1` but has no migration table because there's only one schema. Add migrations the first time the schema changes.

### Known repo-state quirk

(Resolved in Phase 2.5: the HTML-prototype PNGs were moved to `assets/images/ui/` and the `src/` tree removed. The "known repo-state quirk" no longer applies; the entry stays here for historical context.)

### Phase 0.6.5 — Render script lesson learned

After Phase 0 was first committed, testing revealed that `gui.pick_node` was returning false for taps on visible GUI buttons — the menu's PLAY button and the HUD's TEST CARD and MENU buttons all failed to register reliably.

- **What broke:** The custom render script (`render/gridiron.render_script`) implemented fit-to-shortest-axis letterboxing — full-window clear to `#0a1410`, then a centered viewport sized to the design resolution with an orthographic projection of `(0, design_width, 0, design_height)`. Rendering looked correct.
- **Why it broke input:** Defold's GUI input pipeline derives `action.x` / `action.y` from the window in a way that assumes the default render's view/projection. The custom projection + offset viewport combination didn't align with that transform, so the coordinates fed to `gui.pick_node` lived in a different space than the node bounds. Picking silently failed.
- **Fix:** Reverted `[bootstrap] render` in `game.project` to `/builtins/render/default.renderc`. Deleted `render/gridiron.render_script` and `render/gridiron.render`. The `render/` folder stays as a reserved `.gitkeep`-only directory; CLAUDE.md's file layout note was updated to reflect that.
- **Trade-off accepted:** The default render auto-stretches the viewport to the window. iPhone 11+ are all within ~5% of the 1170×2532 design aspect ratio, so the visible distortion is minimal and acceptable for v1. The right time to revisit letterboxing is post-TestFlight, when we have real-device data and can do a controlled re-introduction with a verified `gui.pick_node` test.
- **Codified as hard rule #11** in the "Hard rules" section above: any future custom render script must demonstrate that `gui.pick_node` still works for taps on visible GUI nodes before merge.

## Phase 1 — Architecture slice notes

Phase 1 (`defold-phase-1-architecture-slice-prompt.md`) ported the architectural pattern for cards, lanes, and a single match drive. No real gameplay depth — the point was to lock in the shape that Phase 2+ (AI, scoring, multiple drives, modifiers, synergies, deck/draw, assets) extends without restructuring.

### What's in (by sub-phase)

- **1.1 Data / state foundation.**
    - `main/data/cards.lua` — 15-card static pool (10 off, 5 def), `M.POOL` plus `M.get_by_id(id)` and `M.random_hand(size)` (Fisher-Yates on indices, clones returned so callers can attach `uid` and mutate freely).
    - `main/state/match_state.lua` — module-local state for the current match (`drive`, `phase`, `energy`, `hand` array of 5 with empty-sentinel slots, `lanes` array of 3, `drive_summary`). Exports: `new_match`, `reset`, `get_drive`, `get_phase`, `set_phase`, `get_energy`, `spend_energy`, `get_hand` (shallow copy), `get_lane(idx)` (0/1/2), `get_lane_count`, `get_hand_size`, `play_card`, `resolve_drive`, `get_drive_summary`. Net yards = `floor(you_off_sum / 2.5)` (theirLaneDEF=0 in Phase 1). Lane cap = 8 cards (unreachable from a 5-card hand; kept as a forward-compat guard).
    - `main/state/messages.lua` — Phase 0 vocabulary replaced with the Phase 1 set (`MATCH_PLAY_CARD`, `MATCH_END_DRIVE`, `MATCH_DRIVE_RESOLVED`, `MATCH_DRIVE_COMPLETED`, `MATCH_ENDED`, `MATCH_RETURN_TO_MENU`, `LANE_RESOLVE`, `CARD_SPAWN`, `HUD_HAND_CHANGED`, `HUD_ENERGY_CHANGED`, `HUD_LANE_UPDATED`, `HUD_LANE_RESOLVED`, `HUD_MATCH_ENDED`, `DRIVES_PLAYED_CHANGED`). All hashed at module load.
    - `main/state/save.lua` — default save now `{ version = 1, total_drives_played = 0 }`. `M.load()` merges defaults over loaded data so older saves get missing fields filled in without a migration.

- **1.2 Three-lane layout (visual + scaffold).**
    - `main/match/match.collection` rebuilt: `match` GO holding `match.script`, three lane GOs (`lane_left` / `lane_middle` / `lane_right` at x=195/585/975, y=1400, each with an `idx` script-property override), `card_factory` GO, and the embedded `hud` GO with the GUI component.
    - `main/match/match.go` + `main/match/match.script` — match state machine. `init` calls `match_state.new_match()` then pushes a full HUD render via `HUD_HAND_CHANGED`, `HUD_ENERGY_CHANGED`, and `HUD_LANE_UPDATED × LANE_COUNT`.
    - `main/match/lane.script` — stub holding the `idx` property; Phase 2's modifier/synergy hooks land here.
    - `main/ui/hud.gui` rebuilt: top bar (YOU/DRIVE/CPU/MENU), three lane visual regions (root box + label + yardage bar bg + left-pivoted fill + position text + gold pill + cards counter), 5 hand-card visuals (root + cost + pos + name + stat), action bar (CONCEDE + energy orb + END DRIVE), drag ghost (disabled at start), match-end summary overlay (disabled at start). Lane-region rectangles for drop detection are duplicated in `hud.gui_script`'s `LANE_REGION_RECT` constant.
    - `main/ui/hud.gui_script` rebuilt: pure presentation. Caches node references in `init`, renders state from `HUD_*` messages, no game-state mutation.

- **1.3 Drag-to-play + card spawning.**
    - `main/match/card.go` + `main/match/card.script` — game-object prefab with `card.script` and **no visual components**. Properties: `card_uid`, `lane_idx`, `slot_idx`, all set by `factory.create`. The script is a stub for Phase 2 ability triggers.
    - `main/match/card_factory.go` — factory component (`#factory`, prototype `/main/match/card.go`) plus `card_factory.script`.
    - `main/match/card_factory.script` — handles `CARD_SPAWN`: maps `(lane_idx, slot_idx)` to a design-space position (lane x mirrors HUD: 195/585/975; slot stacking starts at y=1200, +80 per slot) and calls `factory.create`.
    - `match.script.on_message(MATCH_PLAY_CARD)` — calls `match_state.play_card(card_uid, lane_idx)`. On success: posts `CARD_SPAWN` to the factory, then re-pushes hand/energy/lane state to the HUD.
    - `hud.gui_script.on_input` — drag implementation. `action.pressed` over a hand slot starts a drag (only if affordable). Drag in progress moves the ghost node and highlights the hovered lane. `action.released` over a lane posts `MATCH_PLAY_CARD`; off-lane animates the ghost back to the source slot via `gui.animate`. Non-drag releases route through `handle_button_taps` (MENU/CONCEDE/END DRIVE, or the summary panel's RETURN TO MENU when visible).

- **1.4 Drive resolution + persistence.**
    - `match.script.on_message(MATCH_END_DRIVE)` — phase check prevents double-tap; sets phase `"resolving"`, calls `match_state.resolve_drive()`, posts `HUD_LANE_RESOLVED × LANE_COUNT`, then `timer.delay(1.0, false, ...)` posts `HUD_MATCH_ENDED`, sets phase `"ended"`, and posts `MATCH_DRIVE_COMPLETED` to the loader.
    - `hud.gui_script` — `HUD_LANE_RESOLVED` animates the yard-fill's `size.x` via `gui.animate` (0.6s easing). `HUD_MATCH_ENDED` enables the summary overlay and writes the per-lane lines into `summary_text`.
    - `loader.script` — drops the Phase 0 yards tracking, gains `MATCH_DRIVE_COMPLETED` (increments `total_drives_played` and saves). The menu-load handshake now pushes `DRIVES_PLAYED_CHANGED { drives_played }` instead of `total_taps`.
    - `menu.gui` / `menu.gui_script` — renamed `total_taps` node to `drives_played`, renders "DRIVES PLAYED: N".

### Key architectural choices to preserve in later phases

- **Hand cards are GUI nodes, played cards are game objects.** They run in parallel — the GO has no visual in Phase 1; the HUD's "lane region" shows played-card *aggregate* state (count + net-yards pill), not per-card visuals. Asset integration will move per-card visuals onto the GO and tear out the HUD's per-card representation. Until then, every played card creates *both* a GO and (eventually) a HUD entry.
- **Single match state machine, single source of truth.** `match.script` is the only thing that calls `match_state` mutators. GUI scripts read via push messages only — they never `require` `match_state` directly. Lane and card scripts are stubs whose job is to grow into ability/modifier hooks.
- **Three match phases.** `"play"` (accepting input), `"resolving"` (animations running, no input accepted), `"ended"` (summary visible). Phase checks at the top of `MATCH_PLAY_CARD` and `MATCH_END_DRIVE` are how we prevent races.
- **Lane x-coordinates are duplicated in two places intentionally.** `hud.gui_script` knows where lanes are for drop detection; `card_factory.script` knows where to spawn cards. They must stay in sync (currently `{195, 585, 975}` design x). If you move the lanes, update both.
- **Net yards = `floor(off_sum / 2.5)`.** Phase 1's `theirLaneDEF = 0`, so `floor((off - 0) / 2.5)` collapses to division. The full formula has the same shape, so the function signature doesn't change when Phase 2 adds AI defense.
- **Empty hand slots use a sentinel `{ empty = true }`, not `nil`.** Lua arrays with embedded nils break `ipairs` and confuse msg.post serialization. The hand stays positional (slot 1..5) for the entire match.

### Intentionally stubbed in Phase 1

- **AI plays nothing.** `theirLaneDEF` doesn't even exist as a field — lane records carry only `you_*` state. The CPU score in the top bar is hardcoded "0 CPU".
- **No scoring.** Ball positions can pass 100 yards (clamped, but no touchdown / PAT / safety / pick-six logic fires).
- **No modifiers, synergies, perks.** `lane.script` and `card.script` are stubs with TODO comments noting where Phase 2 hooks land.
- **No deck cycle.** Hand is hardcoded 5 cards drawn once at `new_match`; nothing redraws. `cards.lua` exposes the pool but has no deck construction.
- **No real assets.** Everything is colored box nodes + the built-in default font. Played card game-objects are intentionally invisible — their HUD-level representation is the lane's CARDS counter and net-yards pill.
- **No reduced-motion flag.** Two animations exist now (`HUD_LANE_RESOLVED` yard-fill tween and the ghost snap-back). When we add `meta_state.reduced_motion`, both should short-circuit to instant.

### Phase 2 follow-ups

- AI plays cards. Mirror the player flow: AI side of each lane gets a `their_cards` array, `their_def_sum`, and the net-yards formula changes to `floor((off - def) / 2.5)`. Decision logic lives in `main/ai/cpu.lua` (greedy heuristic per CLAUDE.md).
- Multi-drive loop. A match becomes ~8 drives; `match.script` advances `drive` and resets per-drive state without resetting `you_pos` or scores.
- Deck / draw / discard cycle. Hand size becomes dynamic; `cards.lua` grows a deck-construction API.
- Scoring system. Touchdowns at 100 yards, PATs, safeties, pick-sixes. Adds `you_score` / `cpu_score` to `match_state` and a real `HUD_MATCH_ENDED` summary.
- Reduced motion flag. `meta_state.lua` gets the boolean, all animation paths gate on it.
- Asset integration. Pack `assets/images/ui/` into Defold atlases under `assets/`, swap colored boxes for sprites, move per-card visuals onto the GO and remove the parallel HUD representation.

### Conventions established in Phase 1

- **Game objects are at the same design-space x as their HUD nodes** (lanes at 195/585/975). When asset integration moves card visuals to the GO, the visual will line up with where the lane appears on screen without re-doing layout math.
- **`factory.create` properties carry `card_uid` as a hash, not a string.** The string uid lives in `match_state.hand`; the GO's `self.card_uid` is `hash(uid_string)` because `factory.create` properties must be primitives that match the script's declared property types.
- **Match → HUD is push, HUD → Match is post.** The HUD never reads `match_state` directly; `match.script` pushes via `HUD_*` messages whenever state changes. The HUD posts intent (`MATCH_PLAY_CARD`, `MATCH_END_DRIVE`, `MATCH_RETURN_TO_MENU`) and waits to be told what to render.

## Phase 2 — AI side notes

Phase 2 (`defold-phase-2-ai-prompt.md`) mirrored the player flow for the AI and added a reveal mechanic. After Phase 2, both sides play face-down during the drive; END DRIVE triggers a `revealing` phase that flips cards one at a time with a Marvel-Snap-style stagger, then the existing drive resolution + summary path runs.

### What's in

- **AI state** (`main/state/match_state.lua`): `ai_hand` (5 cards from the same pool as player), `ai_energy = 12`, `ai_played_uids`. Each lane now carries `ai_cards`, `ai_pos` (kickoff = 25), `ai_off_sum`, `ai_def_sum`, `ai_net_yards`, plus `you_def_sum` on the player side for symmetry. Net yards per side counts revealed cards only.
- **`pending_plays`** (in `match_state.lua`): the source of truth between play phase and reveal phase. `play_card` / `ai_play_card` push entries `{ card_uid, lane_idx, side, slot_idx }`. `reveal_pending_plays()` returns this in winner-first order; `reveal_single_play(play)` flips one entry, recomputes that lane's sums, and returns them. `resolve_drive()` clears `pending_plays`.
- **`main/ai/cpu.lua`**: heuristic ported verbatim from the HTML's `aiMakePlays()` — sort hand by `off+def` desc, score each affordable card across all three lanes (offensive cards weight on `ai_pos`/`you_def_sum`/kicker positioning; defensive cards weight on `you_pos` threat, near-own-endzone safety guard, and DB stacking), pick the highest score. Returns a 1-indexed `{ card, lane_idx }` array; `match.script` converts to 0-indexed at the boundary.
- **Face-down play model** (`match_state.play_card`, `ai_play_card`): card moves into `you_cards` / `ai_cards` with `revealed = false`, lane sums stay at 0 (no revealed cards yet contribute), energy deducts, hand slot empties. The HUD's net-yards pill stays at `+0` for both sides during the play phase — this is the intended bluff/anticipation behavior, not a bug.
- **Reveal sequence** (`match.script`): on `MATCH_END_DRIVE` we set `phase = "revealing"`, run the CPU heuristic, spawn AI cards face-down via the factory (now with a `side` property), `timer.delay(0.4)` to let AI cards settle visually, then walk `reveal_pending_plays()` one entry at a time with `timer.delay(0.28)` between steps. Each step posts `HUD_REVEAL_CARD` (flip animation) and `HUD_LANE_SUMS_UPDATED` (progressive pill update). After the list is drained, `resolve_drive()` runs and the existing `HUD_LANE_RESOLVED → HUD_MATCH_ENDED → MATCH_DRIVE_COMPLETED` chain takes over.
- **HUD card slots** (`main/ui/hud.gui`): each lane now has 5 player slots stacking up from the bottom and 5 AI slots stacking down from the top. Each slot is two nodes (box + text); face-down = dark gray box with empty text, face-up = side-tinted box (khaki for player, red-tinted for AI) with `"POS cN STAT V"` compact text. Slots default to `enabled: false` and are turned on by the HUD when a card lands there.
- **Two yardage bars + two net-yards pills per lane**: player bars/pill live in the bottom half of the lane region; AI bars/pill live above the AI cards in the top half. Lane label `"LANE N"` and the pos/yard meta sit in the central band.
- **Card factory** (`main/match/card_factory.script`): now takes a `side` property in `CARD_SPAWN`. Player cards spawn at `y = 1200 + slot_idx*80` (stack up), AI cards at `y = 2100 - slot_idx*80` (stack down). Same `LANE_X = {195, 585, 975}` mirror of the HUD.

### Key architectural choices to preserve

- **Cards always play face-down.** Both player and AI. Reveal happens only at END DRIVE. Don't restore Phase 1's progressive net-yards behavior — the design relies on the bluff window.
- **Lane sums count revealed cards only.** `recompute_lane_sums` walks `lane.you_cards` / `ai_cards` filtering by `c.revealed`. Cards in the lane with `revealed = false` don't appear in sums. This is what lets the reveal animation feel progressive — each flip is when its card contributes.
- **Reveal order is "winner reveals first".** `reveal_pending_plays` computes `player_first = you_score >= ai_score`. Phase 2 keeps `you_score = ai_score = 0` as module-locals (scoring lands in Phase 3) so the tied case (player-first) always wins. When real scoring arrives, only the assignments to `you_score`/`ai_score` change — the reveal order code is already correct.
- **Card-abilities hook is `try_apply_snap_ability(card)`** inside `reveal_single_play`. It's a no-op for Phase 2 with a TODO comment. When abilities ship, plug them in there without restructuring the reveal loop.
- **`pending_plays` is the source of truth between play and reveal.** Lane card arrays carry full card data (so the HUD can render them face-down before reveal), but the reveal order is driven by `pending_plays` so each card's flip moment is exact. Don't reverse this — having the lane arrays drive reveal order would silently re-order things if cards are inserted out of strict play order later.
- **HUD slot count is 5 per side.** State allows 8 (the HTML cap), but with 5-card hands neither side can play more than 5 to a single lane. If/when deck cycle lifts hand size in Phase 3+, expand the HUD slot count to match.
- **`match.script` orchestrates everything during END DRIVE.** It owns the timer cadence, the spawn calls, the per-step HUD posts, and the eventual call to `resolve_drive`. The HUD doesn't initiate any of this — it only reacts to messages.
- **AI cards spawn position on the GO is the AI slot's screen position** (top-down stacking). When asset integration moves visuals onto the GO, the GO is already in the right spot — the HUD slot at that screen position just stops being drawn.

### Intentionally stubbed in Phase 2

- **Card abilities (SNAP, on-reveal, on-played).** The reveal loop's `try_apply_snap_ability` is a no-op; `card.script` has a TODO for ability routing.
- **Scoring.** No TD / safety / PAT / conversion / pick-6 / FG. Ball position can pass 100 or go below 0; we don't react. `you_score` and `ai_score` stay 0 in `match_state.lua` but are wired into the reveal-order comparison so Phase 3 only needs to make them actually change.
- **Modifiers / synergies / perks.** `lane.script` and `card.script` are still stubs.
- **Multi-drive cycle.** Match still ends after one drive.
- **Deck / draw / discard.** Hand is hardcoded 5 cards at `new_match`, no refill.
- **Real audio.** Web Audio synths from the HTML don't port; silent for Phase 2.
- **Real card visuals.** Played cards still render as HUD GUI box+text (face-down dark gray or side-tinted face-up). The card.go game-object is invisible. Asset integration will move per-card visuals onto the GO.
- **Reduced-motion flag.** Now genuinely needed — the reveal sequence, flip animations, and yard-fill tweens are all animation paths that should short-circuit when the player has reduced motion enabled. `meta_state.reduced_motion` still hasn't landed; add it before TestFlight.

### Phase 3 follow-ups

- **Scoring.** Drive across endzone → touchdown; lane safety; AI yard-line ≤ 0 from player offense → defensive touchdown / pick-6. Score changes drive the reveal order naturally.
- **Multi-drive cycle.** A match becomes ~8 drives; drive number scales energy; the cycle stops on TD-difference or final-drive resolution.
- **Deck / draw / discard.** `cards.lua` grows a deck-construction API; hand size becomes dynamic; drawn cards stream into `hand` between drives.
- **Card abilities** plugged into `try_apply_snap_ability` and (eventually) `card.script`'s `on_message`.

### Conventions established in Phase 2

- **Per-side prefixes in node ids.** `lane_{idx}_p_*` for player nodes, `lane_{idx}_ai_*` for AI nodes. Slot ids follow `lane_{idx}_{side_prefix}_slot_{slot_idx}` and `..._text`. The HUD script's `self.slots[lane_idx][side][slot_idx]` table mirrors this — keep both naming schemes in sync.
- **Card record fields added during play / reveal**: `revealed` (bool), `_base_off` / `_base_def` (set at reveal, hooks for modifier work that compares modified vs base), `cur_off` / `cur_def` (post-modifier values; equal to base in Phase 2). When mutating cards in the lane, treat `revealed`/`cur_*` as the read surface; modifiers will rewrite `cur_*` between reveal and `recompute_lane_sums`.
- **`HUD_LANE_UPDATED` payload is the lane render snapshot.** `match_state.lane_render_copy(idx)` returns the full thing (positions, sums, pills, both card arrays) and the HUD re-renders the whole lane each time. This costs a few dozen node updates per message but keeps state-out-of-sync bugs impossible.
- **CPU heuristic uses 1-indexed lane references; everything else uses 0-indexed.** `cpu.lua` returns `lane_idx = 1..3`; `match.script` converts to 0..2 at the boundary before calling `match_state.ai_play_card`. Keep this conversion at the single call site — don't push 1-indexed lanes further into state.

## Phase 2.5 — Polish pass notes

Phase 2.5 (`defold-phase-2-5-polish-prompt.md`) was a focused polish pass — no new features. It landed three carry-over items from Phase 2: a phase-aware input gate in the HUD, infrastructure for a reduced-motion accessibility mode, and a long-overdue file move of the HTML-prototype PNGs.

### What's in

- **Phase-aware input gate.** `match.script` now wraps every phase transition in a `transition_phase(p)` helper that calls `match_state.set_phase` and posts `HUD_PHASE_CHANGED { phase = p }`. The HUD tracks `self.input_enabled` (true only when `phase == "play"`) and rejects drag-starts otherwise. Button taps (MENU / CONCEDE / END DRIVE / summary RETURN) bypass the gate — only hand-card drag-start is blocked. If the phase changes mid-drag (shouldn't happen in normal play, but the path stays robust), `cancel_drag(self)` hides the ghost, restores the source card's opacity, and clears `self.dragging`.
- **A new `"resolving"` phase.** Phase 2 jumped directly from `"revealing"` to `"ended"` once `resolve_drive` returned. Phase 2.5 inserts `"resolving"` between them so the gate spans the yard-fill animation window. `resolve_drive` no longer mutates `phase`; `match.script.finish_drive` calls `transition_phase("resolving")` before invoking it, then `transition_phase("ended")` in the post-resolve `timer.delay` callback.
- **`main/state/meta_state.lua`** — new home for player-level persistent settings. Today it carries one field (`reduced_motion`); Phase 3+ extends it with cash, XP, perks, etc. Module-locals only (`local data`), exported via `M.load(save_data)`, `M.serialize()`, `M.is_reduced_motion()`, `M.toggle_reduced_motion()`.
- **`main/animation/animate_helper.lua`** — `animate_go` / `animate_gui` wrappers that short-circuit to `go.set` / `gui.set` when `meta_state.is_reduced_motion()` is true, then fire the (optional) callback via `timer.delay(0.001, ...)` so reduced-motion callbacks stay asynchronous (preserves callback ordering vs. the normal animation path).
- **`save.lua` extension.** Default save shape now carries `meta = {}`. `save.load()` delegates to `meta_state.load(data)`; `save.save(data)` pulls `meta_state.serialize()` into `data.meta` before writing. Callers (loader.script) don't need to know meta_state is the source of `data.meta`.
- **KEY_R dev toggle.** `input/game.input_binding` binds `KEY_R → toggle_reduced_motion`. `loader.script.on_input` handles it: `meta_state.toggle_reduced_motion()`, `save.save(self.save_data)`, print the new state. Explicitly marked `TODO Phase TBD: replace with Settings screen toggle` — this is dev-only.
- **`src/assets/` migration.** 38 PNGs moved from `src/assets/{ui/,}*.png` and `src/assets/ui/26_portraits/qb_black_navy.png` to `assets/images/ui/` (with the portraits subdirectory preserved). Used `git mv` so history follows. `src/` deleted. No code referenced the old paths, so no `.lua` / `.gui` / `.script` files were touched. CLAUDE.md and AGENTS.md references were updated to the new path.

### Key architectural choices to preserve

- **`meta_state.lua` is the home for player-level persistent settings.** Cash, XP, perks, audio prefs, accessibility prefs — all land here. Match-scoped state stays in `match_state.lua`; the two never touch each other directly.
- **`animate_helper` for all new animations.** Don't call `go.animate` / `gui.animate` directly from new code. The reduced-motion check belongs in one place, not sprinkled at call sites.
- **The 280 ms reveal stagger is preserved under reduced motion.** Reduced motion turns off the *per-card animation* (the scale.x flip and yard-fill tweens) but does NOT collapse the sequence into instant. The dramatic pacing — each card "lands" with a beat — is part of the design even for accessibility users. The stagger lives in `match.script`'s `timer.delay(REVEAL_STAGGER)` which is sequencing, not animation, so it isn't affected by the helper.
- **HUD's `input_enabled` defaults to `true`.** If a `HUD_PHASE_CHANGED` message is somehow missed (race on first frame, etc.), the player isn't soft-locked into a permanently un-draggable hand. The first phase message from `match.script` clamps the state correctly on the next frame.
- **The KEY_R dev toggle is intentionally hidden.** It's not in any in-game UI — only in the input binding. The real on-ramp is a Settings screen with a Reduced Motion toggle, which lands when we have a Settings screen at all.
- **Phase machine vocabulary**: `"play"` → `"revealing"` → `"resolving"` → `"ended"`. Drag is allowed only in `"play"`. END DRIVE is allowed only in `"play"` (phase check in match.script). CONCEDE / MENU / summary RETURN are allowed in every phase.

### Intentionally still stubbed

- **Settings screen.** The `R` key is the only way to flip `reduced_motion` today. A real UI is a Phase 3+ task.
- **Atlas building and sprite integration.** PNGs are sitting in `assets/images/ui/` ready to be packed into the atlases listed in this doc's file layout. Phase 2.5 deliberately did not generate atlas files or reference any of the relocated assets in code.
- **Reduced-motion coverage for future animations.** Today's animated surfaces (flip, yard fill, ghost snap-back) go through `animate_helper`. Any new animation must go through the helper too — there's no global "enumerate all animations" path that lists what's covered, so the rule is at the call site.

## Phase 3 — Scoring notes

Phase 3 (`defold-phase-3-scoring-prompt.md`) is the largest gameplay phase yet. The single-drive match now ends with real scores. After Phase 3 the player can: drag cards face-down, END DRIVE, watch the reveal animate, see ball positions advance, watch any scoring lane animate its burst (TOUCHDOWN / SAFETY +2 / PICK SIX +6 / FIELD GOAL +3 / PAT GOOD +1 / 2-PT CONVERSION!), pulse the top-bar score, optionally make a 2-pt decision through a coin-flip modal, then see the lane reset to a fresh kickoff. Match still ends after one drive — multi-drive cycling is Phase 4.

### What's in (by sub-phase)

- **3.1 — Scoring state foundation.**
    - `match_state.lua` gained: `you_score`, `ai_score`, `score_events`, `pending_two_pt` (module-locals); per-lane `you_def_sum` added in Phase 2 stays.
    - New exports: `check_lane_for_scoring(idx)` (TD when `pos ≥ 100`, safety/pick-6 when opposite ball ≤ 0, pick-6 = 4+ revealed CBs/S in the defender's lane; clamps positions), `apply_score_event`, `check_pat` (auto-applies +1 if a revealed Kicker sits in the lane), `check_two_pt_eligibility` (scorer's revealed OFF > defender's revealed DEF), `apply_two_pt_conversion(side, lane_idx, call, coin)` (auto-applies +2 on match), `reset_lane_after_score(lane_idx)` (wipe both `*_cards`, both balls re-kickoff via `kickoff_return`), `kickoff_return` (95% [15-35], 5% [40-60]), `cancel_pending_plays_for_lane(idx)`, `get_you_score`, `get_ai_score`.
    - `try_apply_snap_ability(card, lane_idx, side)` promoted from no-op stub to public dispatcher. Now called by `match.script` (not `reveal_single_play`) because mid-reveal scoring requires the surrounding animation orchestration.
    - `cards.lua` audited up to 18 cards: 5 DBs total (3 CB + 2 S) so the pick-6 path can plausibly fire in playtest. `k_01` carries the first ability (`ability = "SNAP: 3-pt FG if past midfield"`, `desc = "snapFieldGoal"`) and now has `off = 0` to match the design (kickers don't move the ball — their value is the PAT + FG ability).
    - New message hashes in `messages.lua`: `MATCH_SCORE_LANE`, `MATCH_PAT_RESULT`, `MATCH_TWO_PT_CHOICE`, `MATCH_CARD_SPAWNED`, `HUD_SCORE_BURST`, `HUD_SCORE_UPDATED`, `HUD_LANE_RESET`, `HUD_TWO_PT_PROMPT`, `HUD_TWO_PT_RESULT`.

- **3.2 — Score bursts + top bar + lane reset.**
    - `hud.gui` gained a centered `score_burst_text` node (scale baseline 6.0, default font, color w=0, enabled=false).
    - `hud.gui_script` gained `show_score_burst(self, type, points)` (~1.8s sequence: scale OUTBACK from 0.3 → 1.0 of base + alpha 0 → 1 over 0.3s, hold 0.9s, fade out 0.5s — `gui.set_enabled(false)` intentionally NOT called at the end so back-to-back bursts don't race), `pulse_score_node` (±30% scale around the base scale 2.2), `animate_lane_reset` (clears the lane's slot text/colors, tweens both yard fills to the new kickoff positions, resets both pills to "+0").
    - `card_factory.script` now posts `MATCH_CARD_SPAWNED { game_object_id, lane_idx, slot_idx, side }` back to match.script after every `factory.create`. Match.script accumulates these in `self.spawned_cards_by_lane[lane_idx]` so `delete_spawned_cards_in_lane` can clean them up at reset.
    - `match.script` post-reveal flow restructured: `finish_drive` calls `resolve_drive` and posts `HUD_LANE_RESOLVED`, waits 0.6s for yard fills to settle, then `start_scoring_pipeline(self)` collects events from `check_lane_for_scoring` across all lanes and walks them serially. Each event flows through `process_scoring_event` → `after_score_burst` → (TD only) `after_pat` → (eligible only) modal-prompt or AI-auto-decide → `reset_lane_and_continue` → `process_next_score`. After all events drain, `finalize_drive` transitions to `"ended"` and posts `HUD_MATCH_ENDED` + `MATCH_DRIVE_COMPLETED`.

- **3.3 — Clutch Kicker ability + dispatcher.**
    - `try_apply_snap_ability(card, lane_idx, side)` now branches on `card.desc == "snapFieldGoal"` and calls `try_field_goal`, which checks `card.pos == "K"` + `lane[side]_pos ≥ 50` and applies a +3 FG event. All other desc values fall through to `return nil` — the dispatcher pattern is established for future abilities.
    - `match.script.step_reveal` calls the dispatcher after each card flips. If it returns an event, `handle_reveal_score` runs: burst + score update, 1.8s wait, then `cancel_pending_plays_for_lane(lane_idx)`, `reset_lane_after_score(lane_idx)`, delete spawned game objects in that lane, post `HUD_LANE_RESET`, then `remove_future_plays_for_lane` to skip the now-orphaned queue entries before resuming the reveal chain at `reveal_index + 1`.
    - The "scoring mid-reveal" path is rare in Phase 3 since lane positions only update at `resolve_drive`; the FG only triggers when kickoff happened to land at 40-60 (5% chance) and the Clutch Kicker is in that lane. The dispatcher pattern is the point, not the trigger rate.

- **3.4 — 2-pt conversion modal.**
    - Modal lives inside `hud.gui` under `conversion_root` (full-screen 0.75-alpha dark overlay, enabled=false) → `conversion_panel` (700×900 centered, inherit_alpha=false so it stays opaque against the dimmed overlay). State-specific nodes (`go_for_2_btn`/`kick_pat_btn`, `heads_btn`/`tails_btn`, `coin`+`coin_face`, `result_text`+`result_hint`) all parented under the panel, individually toggled by `set_conversion_state`.
    - State machine in `hud.gui_script`: `{ state = "hidden" | "initial" | "calling" | "flipping" | "result" }`. `HUD_TWO_PT_PROMPT { side, lane_idx }` shows the modal in `initial`. Tap "GO FOR 2" → `calling`. Tap HEADS/TAILS → coin_result rolled, `flipping`, `gui.animate` rotation.y 0 → 720° over 1.4s, mid-flip text swap via `timer.delay(0.7)`, then `on_flip_complete` → `result`. Tap to dismiss → posts `MATCH_TWO_PT_CHOICE { result, side, lane_idx, call, outcome }` back to match.script. "KICK PAT" path is an immediate `result = "skip"` post and close.
    - AI auto-decision (no modal): `match.script.ai_decide_two_pt` rolls a 50/50 attempt × 50/50 success (~25% conversion rate end-to-end, matching the HTML).
    - While the modal is visible, `hud.gui_script.on_input` consumes ALL touch input — drag-start, button taps, even the summary panel are blocked.

### Key architectural choices to preserve

- **Score events queue serially.** Multi-lane scoring within a single drive plays out one event at a time via `match.script.scoring_queue` and `process_next_score`. The HUD never sees parallel bursts — easier to reason about, easier for the player to track.
- **Lane reset is symmetric.** Both sides' cards are wiped, BOTH balls re-kickoff (not just the side that scored). Phase 4's multi-drive system will keep this — a score ends a drive, not just one ball's possession.
- **`try_apply_snap_ability` is the single dispatch site.** Adding a new ability is one `elseif card.desc == "snapXxx" then return try_xxx(card, lane_idx, side)` away. Don't sprinkle ability logic across other modules — every ability goes through the dispatcher so the call surface stays narrow.
- **`cancel_pending_plays_for_lane` + `remove_future_plays_for_lane` together cover the mid-reveal lane reset case.** The first removes entries from `match_state.pending_plays` (for state correctness if anyone reads it later); the second removes entries from `match.script.reveal_list` (for animation queue correctness so we don't try to flip cards that no longer exist). Both must be called.
- **Spawned card game objects are tracked per-lane in `self.spawned_cards_by_lane`.** Lane reset calls `go.delete` on each. Don't try to walk the collection's GO tree to find cards — the tracking table is the source of truth.
- **The 2-pt modal lives in `hud.gui_script`, not a separate scene.** Fewer collection proxies (one less load/init cycle), and the modal's state machine has access to the same `self` and helpers as the rest of the HUD. The trade-off is that `hud.gui_script` is now larger; if it grows beyond ~600 lines split the conversion modal out.
- **AI 2-pt is a synchronous decision; player 2-pt is asynchronous.** `match.script.after_pat` either calls `ai_decide_two_pt` (which runs immediately and chains into `reset_lane_and_continue`) or sets `self.waiting_for_two_pt` and posts the prompt. The latter pauses the scoring pipeline until `MATCH_TWO_PT_CHOICE` arrives, at which point the handler resumes via `reset_lane_and_continue`. Don't try to unify these — async resume from a GUI modal is fundamentally different from a synchronous coin flip.
- **`gui.set_enabled(false)` on the score_burst is intentionally absent.** Sequential bursts (TD → PAT → 2pt) have overlapping fade-out timers. A late `set_enabled(false)` from an earlier burst would hide a later one mid-animation. `alpha = 0` is sufficient — the node is enabled but invisible between bursts.
- **Kicker `off = 0`.** Clutch Kicker doesn't contribute to lane offense; its value is the PAT after a TD plus the FG ability. Future kicker variants should follow the same `off = 0` baseline.

### Intentionally still stubbed

- **Multi-drive cycle.** A match is still one drive. Even if a lane scores and resets mid-drive, the match ends at the same point Phase 2 ended (after the post-resolve animations complete).
- **Other card abilities.** Only `snapFieldGoal` is wired. All other `desc` values fall through to `return nil` in the dispatcher.
- **Deck cycle.** Hand stays hardcoded at 5 cards drawn once per match. Cards cancelled during a mid-reveal lane reset just disappear; no discard pile.
- **AI scoring smarts.** `cpu.lua` heuristic is unchanged — the AI doesn't know about scoring opportunities; it scores plays purely on power + position bonuses inherited from Phase 2.
- **Real audio.** No SFX on any score event yet. Web Audio synths from the HTML don't port.
- **Game-over splash.** The match summary panel from Phase 2 still renders the per-lane yards summary; the score numbers in the top bar show real values but there's no dedicated win/lose presentation.

### Phase 4 follow-ups

- **Multi-drive cycling** (the big one): 8 drives per match, energy scales by drive number, hands refresh between drives via deck/draw/discard.
- **Deck cycle:** `cards.lua` grows a deck-construction API; cards have a discard pile; drawing happens between drives.
- **AI scoring awareness:** the heuristic learns about score state — defending a lane the player is about to TD on, abandoning lanes that are out of reach, etc.
- **More card abilities** plugged into the dispatcher.

### Conventions established in Phase 3

- **Score-event types are strings**: `"td"`, `"safety"`, `"pick6"`, `"fg"`, `"pat"`, `"2pt"`. These appear in event tables and in `BURST_TEXT_BY_TYPE` / `BURST_COLOR_BY_TYPE` lookups in `hud.gui_script`. Adding a new event type requires entries in both maps + a handler in `process_scoring_event` / `after_score_burst` if it has bespoke flow.
- **`MATCH_TWO_PT_CHOICE` payload shape**: `{ result, side, lane_idx, call, outcome }`. `result ∈ { "converted" | "failed" | "skip" }`. `call` and `outcome` are nil for `"skip"`. Match.script's handler ignores `call`/`outcome` for non-`"converted"` results.
- **Card spawn tracking lives in `match.script`, not `match_state.lua`.** Game-object IDs are runtime-only — they don't belong in match_state because that module is meant to be testable / inspectable without a Defold runtime.
- **Lane reset only via `match_state.reset_lane_after_score`.** Don't write directly to lane fields when clearing — go through the helper so the (you_pos, ai_pos) kickoff handoff stays consistent.

## Phase 4 — Multi-drive notes

Phase 4 (`defold-phase-4-multi-drive-prompt.md`) ported the full drive-cycle architecture. Match is now 8 drives with a real deck/discard/reshuffle loop and escalating energy. Single-drive scoring from Phase 3 still works inside this loop unchanged.

### What's in (by sub-phase)

- **4.1 — Deck state foundation.**
    - `match_state.lua` extended with `you_deck` / `you_discard` (and AI counterparts), `you_energy_carried`, `max_drives = 8`, `MAX_ENERGY_BANK = 10`, `DECK_SIZE = 30`.
    - `cards.lua` gained `M.build_deck(size)` — samples with replacement from POOL and Fisher-Yates shuffles.
    - `M.new_match()` now seeds 30-card decks per side via `seed_side`, draws the opening 5-card hands from the deck (not from POOL directly), and sets `energy = DRIVE1_ENERGY = 1` (matching HTML — drive 1 grants 1).
    - New `match_state` exports: `draw_cards_to_hand(side, count)` (returns `{ drawn, reshuffled }`; reshuffles mid-draw if the deck runs dry), `reshuffle_discard_into_deck(side)`, `discard_hand(side)` (tags each card with `discarded_on_drive = drive`), `advance_drive` (increments drive, computes per-side carryover and gain, capped at MAX_ENERGY_BANK), `is_match_over` (returns `drive >= max_drives`), `get_discard_summary(side)`, `get_deck_count(side)`, `get_discard_count(side)`, `get_max_drives()`, `consume_drive_cards()`.
    - 9 new message hashes for the multi-drive flow.

- **4.2 — Multi-drive cycle + scoreboard.**
    - `match.script.finalize_drive` now branches: `is_match_over` → `end_match` (existing summary path); else → `start_drive_transition` (new chain).
    - `hud.gui`'s drive text updated to "DRIVE 1 OF 8" and scales for the longer string.
    - `hud.gui_script.HUD_DRIVE_CHANGED` handler updates the text and runs a brief scale pulse on change (`pulse_drive_node`).

- **4.3 — Energy escalation + toast + cap pulse.**
    - `hud.gui` gained `carried_toast` (text node, hidden) above the energy orb.
    - `hud.gui_script.show_carried_toast` animates: fade in + rise 12px (200ms), hold (850ms), fade out + rise another 10px (250ms), reset position + disable.
    - `start_orb_pulse` / `stop_orb_pulse` run a recursive ping-pong on the energy orb's scale (1.0 ↔ 1.08, 500ms each leg). The pulse explicitly checks `meta_state.is_reduced_motion()` at start — without that guard the helper's 1ms-each instant-set callbacks would tight-spin.
    - `match.script` posts `HUD_ENERGY_AT_CAP` after every energy change (drive transition + card play). The HUD's handler starts or stops the pulse based on the boolean.

- **4.4 — Deck/discard badges + reshuffle visual.**
    - `hud.gui` gained `deck_badge` (lower-left) and `discard_badge` (lower-right), each with a label and a count text child, plus `reshuffle_text` between them (hidden by default).
    - `hud.gui_script.bump_badge` (scale 1.0 → 1.18 → 1.0 over 220ms) is shared between the deck and discard count handlers.
    - `show_reshuffle_visual` fades the "RESHUFFLING DECK" text in (300ms) + holds (400ms) + fades out (300ms), and also bumps the discard badge symbolically (it's the one emptying).
    - The discard badge is now tappable via `handle_button_taps` (checked first so the modal can open in any phase, even mid-reveal — matches HTML).

- **4.5 — Discard arc animation.**
    - `HUD_START_DISCARD_ANIM` iterates the current hand and animates every non-empty `hand_N_root` to the discard badge: position → badge, rotation.z → 30°, scale → 0.4, color.w → 0, duration 600ms with 40ms stagger, EASING_INQUAD. Children (cost/pos/name/stat) inherit the parent's transform and alpha automatically.
    - `match.script.start_drive_transition` posts `HUD_START_DISCARD_ANIM`, then `timer.delay(0.8)` to wait for the visual to settle before mutating state. The 0.8s = 0.6s base + 0.04s × 4 stagger + ~40ms buffer.

- **4.6 — Draw arc animation.**
    - `HUD_START_DRAW_ANIM { drawn_cards }` resets each `hand_N_root` to the deck-badge position (scale 0.4, alpha 0.35, rotation 0), renders the new card via `render_hand_slot`, then animates position → natural slot, scale → 1, alpha → 1 over 400ms with 80ms stagger, EASING_OUTQUAD. Empty slots (when fewer than 5 were drawn) are reset instantly to the natural slot with empty render.
    - `match.script.after_optional_reshuffle` posts the new deck counts, then `HUD_START_DRAW_ANIM`, then `timer.delay(0.75)` before `after_draw_anim`.
    - `after_draw_anim` calls `match_state.consume_drive_cards()` (zeroes previous drive's cards' `cur_off`/`cur_def` so they don't keep contributing) BEFORE pushing the lane snapshots — so the HUD pills snap back to "+0" cleanly. Then `advance_drive`, post drive/energy/toast/at-cap, transition to `"play"`.

- **4.7 — Discard text modal.**
    - `hud.gui` gained `discard_modal_root` (full-screen 0.7-alpha overlay) + `_panel` (centered 850×1100 opaque) + `_title` + `_body` + `_hint`.
    - `hud.gui_script.show_discard_modal` reads `match_state.get_discard_summary("you")` directly (deviation from the strict GUI-doesn't-read-state rule — see "Conventions" below), formats per-drive lines, sets the body text, enables the overlay with a scale 0.9 → 1.0 pop-in.
    - The modal blocks ALL other input while visible. `on_input` short-circuits to `hide_discard_modal` on any touch release.

### Key architectural choices to preserve

- **30-card deck per side, sampled with replacement from the 18-card pool.** The HTML version uses a larger deck (50ish); 30 was chosen so the reshuffle happens around drive 6 and is observable in playtest. Expand when balance work begins.
- **Cards played to the field are consumed, not returned to deck/discard.** Lane reset (via scoring) deletes their game objects through the existing `go.delete` path. Drive transition doesn't touch cards on the field — they stay visible (subject to LANE_CARD_CAP=8), but `consume_drive_cards()` zeros their `cur_off`/`cur_def` so they don't keep pushing the ball.
- **`HUD_HAND_CHANGED` fires AFTER the draw animation completes.** The draw anim itself renders the new cards into their slots; the trailing `HUD_HAND_CHANGED` is a state-sync no-op (same content). Don't move it earlier — it would cause render_hand_slot to overwrite the anim's start state.
- **Drive transition runs entirely within `phase = "resolving"`.** Drag input is gated by `input_enabled` (set by `HUD_PHASE_CHANGED`); phase only flips back to `"play"` after `after_draw_anim` completes. Don't add a new "drawing" or "transitioning" phase — the existing machine covers it.
- **AI deck cycle is silent.** No animations, no HUD messages for AI hand changes. The player can't see the AI's hand, so animating it would be wasted CPU and a distraction.
- **`MAX_ENERGY_BANK = 10` is hard-coded in two places** (`match_state.lua` constant + a local in `match.script`'s `post_at_cap`). Keep them in sync; consider exposing via `match_state.get_max_energy_bank()` if it ever needs to vary by mode.
- **Halftime tracking is deliberately omitted.** The HTML version tracks "comeback from halftime" stats for the leveling system. We don't have leveling yet; adding the data hook now would be premature.
- **Discard modal is text-only.** The HTML has a grid view of discarded cards with portraits. We ship text-only because we don't have card art yet. The grid modal lands during asset integration.

### Intentionally still stubbed

- **Card abilities beyond Clutch Kicker.** Dispatcher pattern unchanged from Phase 3.
- **Lane modifiers, card synergies, perks.** Card slots still have `_base_off` / `cur_off` etc. fields ready for modifier work; nothing reads them yet beyond consume_drive_cards.
- **Audio.** No SFX for discard, draw, reshuffle, carryover, or cap-reach.
- **Discard pile grid modal.** Text summary only.
- **Game-over splash.** Match summary panel still uses the Phase 1/2 layout — just with real cumulative scores.
- **Halftime comeback tracking.** Deliberate omission per design doc.
- **Season / draft / locker room modes.** Out of scope.

### Phase 5+ follow-ups

- More card abilities via the existing dispatcher (`elseif card.desc == "snapXxx" then ...`).
- Lane modifiers (modify `cur_off`/`cur_def` of cards based on lane state).
- Card synergies (multi-card bonuses within a side of a lane).
- Perks (player-level passive bonuses set in the locker room).
- Discard grid modal during asset integration.
- Game-over splash + leveling/summary screen.

### Conventions established in Phase 4

- **HUD imports `match_state` for ONE read-only call**: `match_state.get_discard_summary("you")` inside `show_discard_modal`. This is a narrow exception to AGENTS.md's "GUI scripts shouldn't access game logic modules" — the alternative is a `HUD_MODAL_DATA` round-trip that adds modal-open latency for no semantic benefit. Read-only display queries are OK; mutations are NOT.
- **Drive transition is a chain of timer-driven helpers** in `match.script`: `start_drive_transition → after_discard_anim → after_optional_reshuffle → after_draw_anim`. Each helper is forward-declared at the top of the file. Don't try to flatten into one function — the chain is what lets the HUD play its animations between state mutations.
- **`consume_drive_cards()` must run AFTER the draw animation completes** (so the consumed lane sums don't briefly render at 0 while the previous drive's cards are still visually on screen) and BEFORE `advance_drive()` runs (so the drive counter pulse and energy update happen with the fresh state).
- **`MATCH_DRIVE_COMPLETED` still fires once per match**, not once per drive. The save counter `total_drives_played` increments by 1 per match — semantically more like "matches played" but kept under the existing name. If this becomes meaningfully wrong, rename in a future polish phase rather than retro-counting.
- **`hud.gui_script` grew past 1000 lines.** Phase 3 flagged a 600-line threshold for splitting the conversion modal out; Phase 4 pushed past it. A future polish phase should split into `hud_match.gui_script` (lanes, hand, drag, score bursts), `hud_conversion.gui_script` (the 2-pt modal), and `hud_meta.gui_script` (deck/discard badges, reshuffle, toast, discard modal). For now it stays one file — splitting requires GUI scene rewiring that's not worth the churn until asset integration anyway.
- **`hand_N_root` is a movable node, not a fixed scaffold.** Phase 4 animations move it across the screen (to discard badge, to deck badge, back to hand slot). The position in `hud.gui` is just the "natural slot" position — runtime code is the source of truth. Any new feature that uses `hand_N_root` should be aware that its position/rotation/scale/color may not be at baseline.

## Phase 5 — Asset integration notes

Phase 5 (`defold-phase-5-assets-prompt.md`) was the visual transformation. No gameplay changes — every `match_state.lua` / `cpu.lua` / `match.script` line is untouched. The PNGs that have been sitting in `assets/images/ui/` since Phase 2.5 are now wired in via five atlases.

### Atlases built

| Atlas                  | Sprites | Notes                                                                                          |
|------------------------|---------|------------------------------------------------------------------------------------------------|
| `assets/field.atlas`   | 4       | `stadium_bg`, `endzone_red`, `endzone_green`, `football_field_bg`.                              |
| `assets/ui_chrome.atlas` | 14    | Scoreboard + buttons (9-slice consumers) + pills (3-piece) + energy orb + rings + power circles + badges + star. |
| `assets/cards.atlas`   | 8       | One frame per (rarity × side): common/uncommon/rare/legendary × off/def.                       |
| `assets/icons.atlas`   | 36      | football_icon + football_scoreboard + coin_heads + coin_tails + 12 sliced position icons + 20 sliced modifier icons (atlas-only; Phase 6 wires the modifiers). |
| `assets/portraits.atlas` | 1     | `qb_black_navy` only. Other positions fall back to `POSITION_COLOR`.                            |

All atlases have `sprite_trim_mode: SPRITE_TRIM_MODE_OFF`, `margin: 0`, `extrude_borders: 2`, `inner_padding: 0`. Every sprite is declared as an `animations { id: "..." }` block with `playback: PLAYBACK_ONCE_FORWARD` so the sprite name is explicit (independent of the source PNG filename).

### Grid slicing script

`28_position_icons_grid.png` (1200×896, 4 cols × 3 rows) and `29_modifier_icons_grid.png` (1152×928, 5 cols × 4 rows) are sliced offline by `.claude/skills/defold-project-setup/scripts/slice_icon_grids.py` (uses Pillow). Output goes to `assets/images/ui/icons/{pos_*,mod_*}.png`. Re-run if the source grids change. Tile sizes are floored (300×298 and 230×232) — last-pixel rows/columns may be cut slightly; visually verify on first build.

The row-major name order in the slicing script matches the prompt's expected layout (QB, RB, WR, TE / OL, K, CB, S / LB, DE, DT, ST and the 20 modifier ids in the HTML's `LANE_MODIFIERS` order). If the actual grid layout differs, edit `POSITION_LAYOUT` / `MODIFIER_LAYOUT` in the slicing script and re-run.

### Key architectural choices to preserve

- **9-slice ONLY on `scoreboard_frame` and the two buttons** (`button_concede`, `button_snap`). Everything else (badges, orb, rings, power circles, pills, ability star, portraits, card frames) is baked at fixed size. This is the locked design decision; don't 9-slice anything else without explicit approval.
- **Card frames use runtime `gui.play_flipbook`.** Hand `hand_N_root` and lane `lane_X_*_slot_Y` boxes have no texture set in the `.gui` file. At render time, `render_hand_slot` / `render_slot` / `flip_slot` call `gui.set_texture(node, "cards")` + `gui.play_flipbook(node, hash(get_card_frame_sprite(card)))`. **There is no clean way to UNSET a texture at runtime in this Defold version** — `gui.set_texture(node, "")` raises `Texture '' is not specified in scene`. For face-down lane slots and empty hand slots, the script just dims the box color and leaves whatever frame texture was previously bound. This produces a faint card-frame outline under the dim tint; the trade-off was taken for Phase 5 because the alternative (a child sprite node per slot, hidden/shown for face-down/up) was too much node churn. Phase 5.5 polish should either add a "blank" sprite to `cards.atlas` to swap to, or introduce the child sprite pattern.
- **Solid-color portraits per position for non-QB cards** were specified, but Defold's no-clear-texture limitation means the non-QB fallback in `render_hand_slot` currently HIDES the portrait node instead. `POSITION_COLOR` table is defined for the (eventual) cleaner fallback once a blank sprite is added to `portraits.atlas` or `cards.atlas`. Non-QB cards today show frame + position icon + name/stat + ability star, with no portrait fill — a slight visual regression from the prompt's intent.
- **The 3-piece pill row** (`pill_left` + `pill_middle` + `pill_right` from `ui_chrome.atlas`) is **NOT yet rendered in the HUD** — see deviations below. The sprites exist in the atlas for when the lane-modifier display ships in Phase 6.
- **Coin flip uses two sprite nodes** (`conversion_coin` = heads, `conversion_coin_tails` = tails) with synchronized `rotation.y` animation. Heads sits at 0° at rest; tails sits at 180° (back-facing). On flip, both animate by the same delta. `coin_result == "heads"` → final rotation 720° (heads facing). `coin_result == "tails"` → final rotation 900° (heads has spun 2.5 turns, tails ends front-facing). The mid-flip text swap from Phase 3 is gone — the 3D rotation handles the face transition automatically via GL backface culling.
- **`hud.gui_script` not split.** The prompt explicitly deferred this to Phase 5.5. The script is ~1100 lines now.
- **Default Defold font everywhere.** Real fonts (Bebas Neue, Oswald, JetBrains Mono) are Phase 5.5.
- **Texture bindings live in `hud.gui` and `menu.gui` text-headers.** Names: `field`, `ui_chrome`, `cards`, `icons`, `portraits`. Any new sprite reference uses one of these binding names + the sprite id.

### Intentionally still stubbed

- **Real fonts** (Phase 5.5).
- **`hud.gui_script` refactor** (Phase 5.5).
- **More portrait PNGs.** Only QB has a real portrait today. RB / WR / TE / OL / K / CB / S / LB / DE / DT / ST all show the POSITION_COLOR box.
- **Lane modifiers used in gameplay.** `mod_*` sprites are in `icons.atlas` but no game system reads them. Phase 6.
- **Audio.** No SFX added.
- **Game-over splash.** Match summary panel still uses the Phase 3/4 layout.

### Phase 5.5 / 6 follow-ups

- Real fonts: Bebas Neue (display), Oswald (subhead), JetBrains Mono (numbers). Bind in `.gui` headers; replace `font: "default"` references; verify text-node `size` fields still fit the new metrics.
- Split `hud.gui_script` into `hud_match` / `hud_conversion` / `hud_meta`.
- Portrait generation pipeline (procedural or commissioned) for the other 11 positions.
- Phase 6: lane modifiers. The medallion display will be the 3-piece pill row in the middle band of each lane; modifier icons come from `icons.atlas/mod_*`.
- Game-over splash (probably alongside the leveling/summary screen).

### Deviations from the prompt

- **Pill medallion row (3-piece) not added to `hud.gui`.** The atlas sprites exist (`pill_left`, `pill_middle`, `pill_right`). When the lane-modifier display ships in Phase 6, the medallion goes in the lane's central band between the AI and player UI. Phase 5 didn't add it because it'd be empty chrome with no content to host.
- **Played card slots show only the card frame**, not position icons / portraits / ability stars. The compact slot text (`"QB c3 OFF 20"`) already conveys the position info, and adding three sprite sub-nodes per slot × 30 slots = 90 nodes that would crowd the 320×60 slot dimensions. The card frame is the visible upgrade for played slots in Phase 5; per-card detail nodes can land alongside larger card visuals when the lane layout is reworked for modifiers in Phase 6.
- **Position text on hand cards is blanked at runtime**, not removed from `hud.gui`. The `hand_N_pos` text nodes still exist as a positional scaffold; `render_hand_slot` sets their text to `""` because the new `hand_N_pos_icon` sprite shows the position visually. If you'd rather see both the icon and the abbreviation, remove the `gui.set_text(nodes.pos, "")` line in `render_hand_slot`.
- **`hand_N_portrait` default texture in `.gui` is `portraits/qb_black_navy`.** Each card slot's portrait node has the QB sprite as a default; runtime renders override per card. If you open `hud.gui` and see five QB portraits stacked, that's the default state before the script runs — it'll resolve once `init` + the first `HUD_HAND_CHANGED` fires.
- **`Gemini_Generated_Image_vvzouwvvzouwvvzo (1).png`** (the awkward-named AI-generated PNG from the original asset migration) is NOT in any atlas. It's leftover content; can be deleted or repurposed later.

### Atlas / file mapping cheat sheet

| Source PNG | Atlas | Sprite id |
|---|---|---|
| 01_scoreboard_frame.png | ui_chrome | scoreboard_frame |
| 02_endzone_red.png | field | endzone_red |
| 03_endzone_green.png | field | endzone_green |
| 04_stadium_bg.png | field | stadium_bg |
| 05_pill_left.png / middle / right | ui_chrome | pill_left, pill_middle, pill_right |
| 07_button_concede.png / button_snap.png | ui_chrome | button_concede, button_snap |
| 09_energy_orb_frame.png | ui_chrome | energy_orb_frame |
| 10_football_icon.png | icons | football_icon |
| 11_football_scoreboard.png | icons | football_scoreboard |
| 12_ring_you.png / 13_ring_cpu.png | ui_chrome | ring_you, ring_cpu |
| 14_power_circle_red.png / 15_power_circle_green.png | ui_chrome | power_circle_red, power_circle_green |
| 16_badge_deck.png / 17_badge_discard.png | ui_chrome | badge_deck, badge_discard |
| 18-25 card frames | cards | frame_{rarity}_{side} |
| 26_portraits/qb_black_navy.png | portraits | qb_black_navy |
| 27_star_ability.png | ui_chrome | star_ability |
| 28_position_icons_grid.png (sliced) | icons | pos_qb / pos_rb / ... / pos_st |
| 29_modifier_icons_grid.png (sliced) | icons | mod_homeTurf / ... / mod_playOfGame |
| 30_coin_heads.png / 31_coin_tails.png | icons | coin_heads, coin_tails |
| football-field-bg.png | field | football_field_bg |
| logo.png / subtitle-logo.png | (not yet wired) | — |
| 05_medallion_pill.png / 06_yardage_strip.png | (not used) | — |
