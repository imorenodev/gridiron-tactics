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
