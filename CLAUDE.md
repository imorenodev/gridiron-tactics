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
- **No real assets.** Everything is solid-color GUI box nodes + Defold's built-in default font. The PNGs in `src/assets/` (left over from the HTML prototype) are **not yet wired up** — they need to be migrated into `assets/images/` and packed into the atlases listed in this doc's file layout. Treat that as a Phase 1 task.
- **No reduced-motion flag** yet. CLAUDE.md mandates it ships in v1; Phase 0 has no animations, so the flag has nothing to gate. Add `meta_state.reduced_motion` when the first animation lands.
- **No save migration logic.** `save.lua` checks `version == 1` but has no migration table because there's only one schema. Add migrations the first time the schema changes.

### Known repo-state quirk

The repo still contains `src/assets/` with PNGs from the HTML prototype. CLAUDE.md's file layout places `assets/` at the project root and we created that empty structure in Phase 0. The `src/assets/` PNGs need to be migrated (and the `src/` folder removed) in a Phase 1 asset-pipeline task — Phase 0 left them in place to avoid touching tracked files without authorization.

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
- Asset integration. Pack `src/assets/` into Defold atlases under `assets/`, swap colored boxes for sprites, move per-card visuals onto the GO and remove the parallel HUD representation.

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
