# Claude Code Prompt — Phase 1: Architecture Slice

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** Every file you create or modify must conform to its conventions. If this prompt conflicts with `CLAUDE.md`, surface the conflict in your response and stop. Do not silently resolve.

Specifically re-read:

- The "Hard rules" section (especially the new rule #11 about custom render scripts — do not write a custom render script in Phase 1)
- The "Code conventions" section (snake_case, module structure, hashes, messages)
- The "Things I would NOT do" section (no god modules, no game logic in `.gui_script` files, no hand-authoring complex collections, no `msg.post` from `init()` in ways that race)
- The Phase 0 notes at the bottom (file layout, established conventions like socket-name-equals-screen-name)

## Context

Phase 0 shipped a vertical slice: menu → match screen with one tappable test button that increments a yards counter → back to menu, with save persistence. That proved the engine, input, GUI, asset pipeline, render config, and build all work.

**Phase 1's goal:** Port the architectural pattern for cards, lanes, and a match drive — without porting any actual game logic depth. After Phase 1, the player can tap PLAY, see three lanes side by side, drag cards from their hand into lanes, watch net-yards pills update, tap END DRIVE to resolve all lanes (advance the ball positions), see a summary, and return to menu. One drive per match. No AI plays cards. No scoring. No modifiers. No synergies. No perks. No deck cycle (the hand is hardcoded).

This phase proves the pattern works. Every later phase (AI, scoring, multiple drives, modifiers, synergies, deck/draw, asset integration) adds onto this foundation without restructuring it. So the architecture choices matter more than the visual polish.

## Hard rules for this phase

Beyond `CLAUDE.md`'s rules, these are specific to Phase 1:

1. **Drag-to-play only, no tap fallback.** The player drags a card from hand onto a lane. Tapping a card does nothing. This is the Marvel Snap pattern and we commit to it.
2. **Three lanes from the start.** Even though only one would technically suffice to prove the slice. We need the layout to work across all three on iPhone-width screens.
3. **Hardcoded 5-card hand.** No deck, no discard, no draw, no reshuffle. Hand contents are fixed at match start and never refilled. The card data module exists, but only as a static pool from which the 5 hand cards are picked.
4. **12 starting energy, flat.** Phase 1 override; the HTML game uses drive-scaled energy. Document this as a Phase 1 hack in code comments.
5. **No AI cards played.** AI plays nothing. Each lane's `theirLaneDEF = 0` so net yards = `floor(yourLaneOFF / 2.5)`. This means even Phase 1 can use the real lane math formula.
6. **No scoring.** Touchdowns, safeties, PATs, conversions, pick-sixes, field goals — none of it. Ball position can exceed 100 yards; we don't react.
7. **No real assets.** Played cards render as box+text on game objects (programmer art). Hand cards render as box+text GUI nodes. No atlases beyond what Phase 0 has. No new fonts.
8. **Match state machine is required.** Match has phases: `"play"`, `"resolving"`, `"ended"`. `match.script` enforces phase transitions. Skipping this isn't an option.
9. **Cards-as-game-objects.** When played, a card spawns as a game object via factory, NOT as a GUI node. Hand cards remain GUI nodes. This means card visuals exist in two systems with two visual implementations — that's the price for now.
10. **Save schema stays version 1.** Add `total_drives_played` field. Missing field defaults to 0 on load. No migration function needed.
11. **No third-party Lua libraries.** Defold stdlib only.
12. **Pre-compute all hashes at the top of each script.** Per CLAUDE.md.
13. **GUI scripts contain no game logic.** GUI scripts translate input to messages and render in response to incoming messages. Game logic lives in `.script` files and `state/*.lua` modules.
14. **Do not start Phase 2.** Stop after Phase 1's final acceptance.

## Sub-phases

This is a **four-sub-phase prompt**. Each ends with a `// === STOP for developer review ===` marker. **Stop after each sub-phase, wait for the developer to confirm before proceeding to the next.** This lets them open the project between phases and catch issues before they compound.

Each sub-phase has explicit acceptance criteria. If you can't meet them, surface why before moving on.

---

### Sub-phase 1.1 — Data and state foundation

Build the data and state layer. No new UI behavior. The project still runs Phase 0's flow at the end of this sub-phase; the new modules just exist and are `require`-able.

**Files to create:**

#### `main/data/cards.lua`

A static card pool. Returns a table with at least 15 cards covering both sides and a range of positions/costs. Each card has:

```lua
{
    id = "stable_string_id",     -- e.g. "qb_01", stays the same across runs
    name = "Display Name",
    pos = "QB",                   -- one of: QB, RB, WR, TE, OL, K (offense)
                                  -- or:    CB, S, LB, DE, DT, ST (defense)
    cost = 3,                     -- 1-6
    off = 20,                     -- offense power (0 if defensive card)
    def = 0,                      -- defense power (0 if offensive card)
    side = "off",                 -- "off" or "def"
    rarity = "common",            -- "common", "uncommon", "rare", "legendary"
}
```

Skip `ability`, `desc`, `team` for Phase 1 — abilities and team flavor come in later phases.

Module structure:

```lua
local M = {}

M.POOL = {
    { id = "qb_01", name = "...", pos = "QB", cost = 3, off = 20, def = 0, side = "off", rarity = "common" },
    -- ... 14 more cards, mix of off/def, mix of costs 1-5 (skip 6 for now)
}

function M.get_by_id(id)
    for _, c in ipairs(M.POOL) do
        if c.id == id then return c end
    end
    return nil
end

function M.random_hand(size)
    -- Returns `size` shuffled card records (cloned, not references)
    -- so callers can mutate without affecting the pool.
    -- ...
end

return M
```

Cards should be deterministic IDs (so save/load works later) but `random_hand` shuffles which 5 you get each match. Hand size in Phase 1 is always 5.

#### `main/state/match_state.lua`

Holds the in-match state. Module-local Lua tables, no bare globals. Exports getters/setters/mutators.

State shape:

```lua
{
    drive = 1,                       -- always 1 in Phase 1
    phase = "play",                  -- "play" | "resolving" | "ended"
    energy = 12,                     -- 12 at match start (Phase 1 override)
    hand = { card_records... },      -- array of 5 card records (live, mutated as played)
    played_uids = { [uid] = true },  -- set of card uids currently played, for double-spend prevention
    lanes = {
        { idx = 0, you_pos = 25, you_cards = {}, you_off_sum = 0, you_net_yards = 0 },
        { idx = 1, you_pos = 25, you_cards = {}, you_off_sum = 0, you_net_yards = 0 },
        { idx = 2, you_pos = 25, you_cards = {}, you_off_sum = 0, you_net_yards = 0 },
    },
    drive_summary = nil,             -- populated at drive resolution, used by match-end summary
}
```

Each hand card record needs a unique `uid` attached when the hand is built (so we can track which one was dragged). `uid` is generated by a local function (similar to the HTML's `uid()` — `math.random` based, returned as a string).

Required exports (minimum):

- `M.new_match()` — initialize state for a new match. Picks 5 random cards from `cards.lua`, assigns uids, sets `you_pos = 25` (a reasonable kickoff start) on each lane.
- `M.get_drive()`, `M.get_phase()`, `M.set_phase(p)`
- `M.get_energy()`, `M.spend_energy(amount)` — returns true if successful, false if not enough
- `M.get_hand()` — returns the array (don't expose internal table; return a shallow copy)
- `M.get_lane(idx)` — returns the lane record by index (0, 1, or 2)
- `M.play_card(card_uid, lane_idx)` — moves card from hand to the lane's `you_cards`, recomputes `you_off_sum` and `you_net_yards` for that lane, deducts energy. Returns `{ success = true, card = ..., new_energy = ..., new_off_sum = ..., new_net_yards = ... }` or `{ success = false, reason = "insufficient_energy" | "card_not_in_hand" | "lane_full" }`. A lane is "full" at 8 cards.
- `M.resolve_drive()` — advances `you_pos` on each lane by `you_net_yards`, clamps 0-100, sets `phase = "ended"`, returns a summary table `{ lanes = { { idx, yards_gained, new_pos }, ... } }`.
- `M.reset()` — clears state. Called when leaving match.

The net yards formula in Phase 1 is `math.floor(you_off_sum / 2.5)`. Since `theirLaneDEF = 0`, we just divide.

#### `main/state/messages.lua` (modify existing)

Add the new message hashes. Pre-computed at module load. Existing messages stay.

```lua
-- Phase 1 additions
M.MATCH_PLAY_CARD       = hash("match.play_card")
M.MATCH_END_DRIVE       = hash("match.end_drive")
M.MATCH_DRIVE_RESOLVED  = hash("match.drive_resolved")
M.MATCH_ENDED           = hash("match.ended")
M.MATCH_RETURN_TO_MENU  = hash("match.return_to_menu")

M.LANE_RESOLVE          = hash("lane.resolve")

M.CARD_SPAWN            = hash("card.spawn")

M.HUD_HAND_CHANGED      = hash("hud.hand_changed")
M.HUD_ENERGY_CHANGED    = hash("hud.energy_changed")
M.HUD_LANE_UPDATED      = hash("hud.lane_updated")
M.HUD_LANE_RESOLVED     = hash("hud.lane_resolved")
M.HUD_MATCH_ENDED       = hash("hud.match_ended")
```

The Phase 0 `MATCH_PLAY_TEST_CARD` message stays for now — we'll remove it in 1.4 when the test card goes away.

#### `main/state/save.lua` (modify existing)

Update the default save table to include `total_drives_played = 0`. Update `M.load()` so that a save loaded without this field gets `total_drives_played = 0` on the in-memory copy (the existing pattern of merging over defaults).

**Acceptance criteria for 1.1:**

- [ ] Project still builds and runs Phase 0's flow (PLAY → tap test card → MENU still works)
- [ ] `require("main.data.cards")` from a script returns a module exposing `POOL` and `random_hand`
- [ ] `require("main.state.match_state")` returns a module; calling `M.new_match()` populates state, calling `M.get_hand()` returns 5 cards
- [ ] All new message hashes are present in `messages.lua`
- [ ] Save still loads without errors; if existing saves on disk lack `total_drives_played`, it defaults to 0
- [ ] No console warnings or errors
- [ ] Less than 350 lines added total across all three new/modified files

`// === STOP for developer review ===`

---

### Sub-phase 1.2 — Three-lane layout (visual only)

Replace Phase 0's match screen with the Phase 1 three-lane layout. No drag-and-drop yet. No game logic wired up. Just the visual scaffold — three lane regions, a hand area showing 5 static cards, energy display, END DRIVE button, MENU button. Tapping the cards or the END DRIVE button does nothing yet (or prints a placeholder).

**Files to create or modify:**

#### `main/match/match.collection` (modify)

Replace the Phase 0 single-lane setup with three lane game objects + factory + HUD:

```
match.collection (socket: match)
├── match.go              # New: holds match.script
│   └── match.script
├── lane_left.go          # idx=0, position (293, 1400) in design space
│   └── lane.script (with idx=0 property)
├── lane_middle.go        # idx=1, position (585, 1400)
│   └── lane.script (with idx=1 property)
├── lane_right.go         # idx=2, position (877, 1400)
│   └── lane.script (with idx=2 property)
├── card_factory.go       # Factory game object
│   └── card.factory (prototype = card.go)
└── hud.go                # HUD game object (same as Phase 0 but expanded GUI)
    └── hud.gui + hud.gui_script
```

Position values are design-space coordinates. The three lane GOs are positioned for visual reference but the actual visible "lane region" is rendered in the HUD GUI; lane GOs primarily exist as containers for `lane.script` and as parents for spawned card game objects.

#### `main/match/lane.script` (new/modify)

Each lane script:

- Has a script property `idx` (0, 1, or 2)
- `init`: reads `match_state.get_lane(self.idx)`, stores `self.idx`. No DOM/visual work — that's the HUD's job.
- `on_message`:
    - On `LANE_RESOLVE`: calls a state mutation that's part of `match.resolve_drive` (TBD how this works — probably `lane.script` doesn't need to handle this directly since `match.script` orchestrates resolution via `match_state.resolve_drive()`. Simplification: `lane.script` may not need any message handlers in Phase 1 at all. If it ends up empty, leave the file as a stub with TODO comments noting Phase 2 will add modifier/synergy hooks here.)

**Important:** if `lane.script` ends up nearly empty after this analysis, that's fine. The architectural point is that the script *exists* on the game object and has a place to grow into. Don't fabricate work for it.

#### `main/match/card.go` (new)

A game object prefab. Contains:

- One sprite component for the card frame (just use a box-colored sprite via... actually, sprites need atlas references. For Phase 1, the card visual is just a positioned game object with no visual components — invisible, exists only as a logical container.)

Hmm, this is the same issue Phase 0 hit. Sprites need atlases. For Phase 1, **`card.go` should have no visual components**. It's a positional anchor with `card.script` attached. Whatever visual representation of "this card is on the field" exists in Phase 1 lives in the HUD as a GUI node, NOT on the game object.

Wait — that contradicts the "cards-as-game-objects" rule.

Let me think this through. The rule was: cards-as-game-objects, not GUI-everything, because we want to validate the architectural pattern. But validating the pattern doesn't require the game object to have a sprite. The pattern is: when a card is played, a game object is spawned via factory at the right position, and that game object has a script and the *option* to add visual components later when assets are integrated. Phase 1 just doesn't have the visual components yet.

**Resolution:** `card.go` has a `card.script` component and nothing else. When a card is played, the factory spawns it. The HUD shows "card N played in lane X" via a GUI node it manages. The game object exists, the HUD's GUI node exists, they're parallel until asset integration replaces the GUI node with a real sprite on the game object.

So Sub-phase 1.2 does NOT need `card.go` or the factory yet. They come in 1.3 when we wire up card spawning. Let me restructure.

**Revised Sub-phase 1.2 file list:**

- Modify `main/match/match.collection`: replace single-lane with three lane game objects + match.go + hud.go. No factory yet.
- Modify `main/match/lane.script`: stub for now, holds `idx` property.
- New `main/match/match.script`: match-level state machine, mostly empty in 1.2.
- Modify `main/ui/hud.gui`: expand to show three lane visual regions, 5 hand card GUI nodes, energy display, END DRIVE button, MENU button.
- Modify `main/ui/hud.gui_script`: react to `HUD_HAND_CHANGED`, `HUD_ENERGY_CHANGED`, `HUD_LANE_UPDATED` messages to render state, but no input handling for drag yet — just tap MENU to return.

#### `main/ui/hud.gui` (modify) — visual layout

Design-resolution coordinates (1170 × 2532, bottom-left origin).

Layout from top to bottom:

1. **Top bar** (y ≈ 2400) — 1170 wide × 200 tall. Background box (dark green). Inside:
    - Left: "YOU 0" text (large)
    - Center: "DRIVE 1" text (medium, yellow)
    - Right: "0 CPU" text (large)
    - Top-right corner: "MENU" button (small box with text)
2. **Lane area** (y from 800 to 2200) — three columns. Each column is ~370 wide:
    - Lane 1: x = 100, width 360 (centered at x ≈ 280)
    - Lane 2: x = 480, width 360 (centered at x ≈ 660)
    - Lane 3: x = 860, width 360 (wait — too far right; revise)

Let me redo this math. Design width is 1170. Three lanes side by side with small gaps. Each lane gets ~370 wide. So:

- Lane 1: x_center = 195, x_range = 10-380
- Lane 2: x_center = 585, x_range = 400-770
- Lane 3: x_center = 975, x_range = 790-1160

Each lane column contains, from top to bottom within the lane region:

- A "yardage bar" box (full-width, 80 tall). Background gray; a green inner fill anchored left, width = `you_pos / 100 * full_width`. Show `you_pos` as text inside.
- A small medallion area (empty/placeholder in Phase 1, just a darker rounded box ~120 tall with no text)
- A "net yards" pill (gold rounded box, 80×60, centered, shows "+0")
- A "played cards stack" region (400 tall, where played card GUI representations get added)

3. **Hand area** (y from 400 to 700) — 1170 wide. Background dark. Contains 5 card slots arranged horizontally:
    - Card 1: x_center = 165
    - Card 2: x_center = 360
    - Card 3: x_center = 555
    - Card 4: x_center = 750
    - Card 5: x_center = 945
    - (and gap on the right)

Each hand card slot is 180 wide × 280 tall. Card slot contains:
    - Top-left: cost badge (gold circle, 50×50, shows cost number)
    - Top-right: position badge (small box, shows "QB" / "RB" etc.)
    - Center: name text (white, two lines if needed)
    - Bottom: stat number (large, orange for off / blue for def)

4. **Action bar** (y from 200 to 380) — 1170 wide. Inside:
    - Left: "CONCEDE" button (returns to menu, same as MENU)
    - Center: Energy orb (yellow circle, shows "12")
    - Right: "END DRIVE" button (red, large)

5. **Bottom edge** (y from 0 to 180) — empty/letterbox area

#### `main/ui/hud.gui_script` (modify) — behavior in 1.2

For 1.2, this script:

- `init`: acquire input focus, cache node references for all the things, ask `match.script` for initial state (post `MATCH_RETURN_TO_MENU` if no state, etc.). Render initial state.
- `on_message`:
    - `HUD_HAND_CHANGED { hand }` → re-render the 5 hand card slots from the hand array
    - `HUD_ENERGY_CHANGED { energy }` → update energy orb text
    - `HUD_LANE_UPDATED { lane_idx, ... }` → update that lane's net yards pill, yardage bar fill, etc.
- `on_input`:
    - Tap MENU or CONCEDE → post `match.return_to_menu` to match.script

In 1.2, the hand is populated by `match.script` calling `match_state.new_match()` and then telling the HUD via `HUD_HAND_CHANGED`. Cards in hand are rendered as static visuals — they're tappable visually but tapping does nothing yet.

#### `main/match/match.script` (new) — behavior in 1.2

Minimal for 1.2:

- `init`: call `match_state.new_match()`. Post `HUD_HAND_CHANGED { hand = match_state.get_hand() }` to hud. Post `HUD_ENERGY_CHANGED { energy = match_state.get_energy() }` to hud. Post `HUD_LANE_UPDATED { lane_idx, you_pos, you_net_yards }` to hud for each of the 3 lanes.
- `on_message`:
    - `match.return_to_menu` → call `match_state.reset()`, post `show_menu` to loader.

That's it for 1.2. No play_card handling yet.

**Acceptance criteria for 1.2:**

- [ ] Tapping PLAY from menu shows the match screen with 3-lane layout
- [ ] Top bar shows "YOU 0", "DRIVE 1", "0 CPU"
- [ ] All three lanes are visible, side by side, with their yardage bars showing position 25 (or wherever new_match starts them)
- [ ] Hand area shows 5 cards with their names, costs, positions, and stat numbers
- [ ] Energy orb shows "12"
- [ ] END DRIVE button is visible but tapping it does nothing (or logs a placeholder)
- [ ] Tapping MENU or CONCEDE returns to the main menu
- [ ] No console errors
- [ ] Visual layout looks clean in editor preview at typical mobile aspect ratio

`// === STOP for developer review ===`

---

### Sub-phase 1.3 — Drag-and-drop + card spawning

The big sub-phase. Implement drag-and-drop in the HUD, wire up the play_card message flow, spawn card game objects in lanes when cards are played.

**Files to create or modify:**

#### `main/match/card.go` (new)

Game object prefab with `card.script` component, no visual components. (Per the analysis above — visuals come in asset integration phase. For 1.3, played cards are "invisible game objects" backed by GUI nodes in the HUD.)

#### `main/match/card.factory` (new)

Factory component pointing to `card.go`. Lives on `card_factory.go`.

#### `main/match/match.collection` (modify)

Add `card_factory.go` with a factory component back. We took it out in 1.2; it returns in 1.3.

#### `main/match/card.script` (new)

Minimal:

- `init`: store `self.card_uid`, `self.lane_idx`, `self.slot_idx` (passed via `factory.create`'s properties argument)
- `on_message`: nothing in Phase 1. Stub with TODO comments noting Phase 2 will add SNAP ability triggers here.

This script's main purpose is to be the architectural placeholder for per-card behavior in later phases.

#### `main/match/match.script` (modify)

Add play_card handling:

- `on_message`:
    - `match.play_card { card_uid, lane_idx }` →
        - Call `match_state.play_card(card_uid, lane_idx)`
        - If failed: post a toast or just ignore (Phase 1 can ignore silently — the HUD should prevent invalid plays)
        - If succeeded:
            - Post `card.spawn { card_uid, lane_idx, slot_idx, card_data }` to `card_factory.go` (which spawns the game object)
            - Post `HUD_HAND_CHANGED { hand }` to hud
            - Post `HUD_ENERGY_CHANGED { energy }` to hud
            - Post `HUD_LANE_UPDATED { lane_idx, you_pos, you_net_yards, you_cards_count }` to hud

The card spawning works by `card_factory.go`'s script receiving `card.spawn` and calling `factory.create` with the appropriate position. Position is computed from `lane_idx` and `slot_idx`: lanes are at design-space x = 195, 585, 975. Played cards stack vertically within the lane; slot 0 is at y ≈ 1200, slot 1 at 1280, etc. (just a simple stack for Phase 1).

Wait — `card_factory.go` doesn't have a script in this design. The factory component receives messages. Let me revise: `card_factory.go` has:
- `card.factory` component (the factory)
- `card_factory.script` component (handles the `card.spawn` message and calls `factory.create`)

Add `main/match/card_factory.script`:

- `init`: no-op
- `on_message`:
    - `card.spawn { card_uid, lane_idx, slot_idx, card_data }` →
        - Compute position based on lane_idx and slot_idx
        - Call `factory.create("#factory", position, nil, { card_uid = hash(card_uid), lane_idx = lane_idx, slot_idx = slot_idx })`
        - (Note: `factory.create` properties have to be primitives. card_uid as hashed string is fine.)

#### `main/ui/hud.gui_script` (modify) — drag-and-drop implementation

This is the biggest chunk of new code in Phase 1.

Add to `init`:
- `self.dragging = nil` (will hold drag state when active)
- Cache references to each hand card node group and each lane region node
- Create a "drag ghost" node (hidden by default — a single GUI node that gets shown and positioned during drag)

Add to `on_input`:

```lua
function on_input(self, action_id, action)
    if action_id ~= msgs.TOUCH then return end
    
    if action.pressed then
        -- Touch start: check if it's on a hand card
        for i, card_node in ipairs(self.hand_card_nodes) do
            if gui.pick_node(card_node, action.x, action.y) then
                local card = self.current_hand[i]
                if card and match_state_can_afford(card) then
                    self.dragging = {
                        card_uid = card.uid,
                        source_index = i,
                        offset_x = ...,
                        offset_y = ...,
                    }
                    -- Show drag ghost at touch position
                    show_drag_ghost(self, card, action.x, action.y)
                    -- Hide source hand card
                    gui.set_color(card_node, vmath.vector4(0.3, 0.3, 0.3, 0.5))
                end
                return
            end
        end
    end
    
    if self.dragging and action.x and action.y then
        -- Drag in progress: move ghost
        gui.set_position(self.drag_ghost, vmath.vector3(action.x, action.y, 0))
        
        -- Highlight lane under cursor (if any)
        local hovered_lane = pick_lane_at(self, action.x, action.y)
        update_lane_highlights(self, hovered_lane)
    end
    
    if action.released and self.dragging then
        local target_lane = pick_lane_at(self, action.x, action.y)
        if target_lane ~= nil then
            -- Valid drop: post play_card to match
            msg.post("/match", msgs.MATCH_PLAY_CARD, {
                card_uid = self.dragging.card_uid,
                lane_idx = target_lane,
            })
        else
            -- Invalid drop: animate ghost back to source
            animate_ghost_back(self)
        end
        
        -- Hide ghost, restore source card opacity
        gui.set_enabled(self.drag_ghost, false)
        gui.set_color(self.hand_card_nodes[self.dragging.source_index], vmath.vector4(1, 1, 1, 1))
        self.dragging = nil
        clear_lane_highlights(self)
    end
end
```

(Pseudo-code; you'll need to write the helper functions like `pick_lane_at`, `update_lane_highlights`, `show_drag_ghost`, `animate_ghost_back`. Keep them inside the gui_script file.)

The drag ghost is a single GUI node (box with text) that gets positioned at the touch coordinates. When a drag starts, populate its text/color to match the source card. When it ends, hide it. For "snap back" animation, use `gui.animate` to move it to the source card position over 0.2 seconds, then hide.

**Affordability check** in the drag-start: `card.cost <= match_state.get_energy()`. If a card can't be afforded, dragging just doesn't initiate.

**Lane picking** uses `gui.pick_node` against three large invisible box nodes that each cover a lane's "drop zone" area. These are added to `hud.gui` in 1.2 as transparent overlay nodes.

Update `HUD_HAND_CHANGED` handler:
- Re-render the 5 hand card slots with the current hand
- If a card has been removed (played), that slot becomes empty (gray placeholder)

Update `HUD_LANE_UPDATED` handler:
- Update lane's net yards pill: text is "+N" if N>0 else "0"
- Update lane's yardage bar fill width (in 1.3, ball position doesn't move yet — that happens at drive resolution in 1.4)

**Acceptance criteria for 1.3:**

- [ ] Project builds and runs
- [ ] Dragging an affordable card from hand toward a lane creates a "drag ghost" that follows the finger/cursor
- [ ] Dropping on a lane: card disappears from hand, energy decreases by card cost, lane's net yards pill updates to reflect new total
- [ ] Dropping off-lane (e.g., on the top bar or in dead space): drag ghost snaps back to source, no state change
- [ ] Trying to drag a card that costs more than current energy: nothing happens (drag doesn't initiate)
- [ ] Can play multiple cards into multiple lanes during the drive (up to 8 per lane, then "lane full" prevents more)
- [ ] After 4-5 cards played, the visual state matches: hand has fewer cards (gray slots for played ones), energy is reduced, lanes show their accumulated net yards
- [ ] A game object is spawned per played card (visible in Defold's debug runtime view, even though it has no visual components)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 1.4 — Drive resolution + persistence

Wire up END DRIVE, ball animation, match-end summary, save persistence.

**Files to modify:**

#### `main/match/match.script`

Add END DRIVE flow:

- `on_message`:
    - `match.end_drive` →
        - If `match_state.get_phase() ~= "play"`, ignore (prevents double-tap)
        - Call `match_state.set_phase("resolving")`
        - Call `match_state.resolve_drive()` to get the summary
        - For each lane in the summary, post `HUD_LANE_RESOLVED { lane_idx, new_pos, yards_gained }` to hud
        - Wait ~1.0 seconds (use `timer.delay`) for the ball animations to complete
        - Then post `HUD_MATCH_ENDED { summary }` to hud
        - Then `match_state.set_phase("ended")`
        - Save: increment `total_drives_played` in save_data via loader. Loader handles the actual file write.
    - `match.return_to_menu` →
        - Existing handler; now also called when player taps through the match-end summary.

Posting to the loader to increment the saved drive count: post a new message `match.drive_completed` to loader, which the loader catches and increments + saves. This keeps the save logic in the loader.

#### `main/loader.script`

Add handling for the new message:

- `on_message`:
    - `match.drive_completed` →
        - Increment `self.save_data.total_drives_played` by 1
        - Call `save.save(self.save_data)`

Also: update the existing menu-load flow so that `total_drives_played` is sent to the menu instead of `total_taps`. The menu GUI script needs to be updated to render "DRIVES PLAYED: N" instead of "TOTAL TAPS: N".

#### `main/ui/menu.gui` + `main/ui/menu.gui_script`

Update the displayed text. Replace `total_taps_text` references with `drives_played_text` (or rename the existing node). Menu shows "DRIVES PLAYED: 0" on first launch, increments by 1 each completed drive.

#### `main/ui/hud.gui_script`

Add handling for new messages:

- `on_message`:
    - `HUD_LANE_RESOLVED { lane_idx, new_pos, yards_gained }` →
        - Use `gui.animate` to animate the ball position (the green fill on the yardage bar) from current position to `new_pos / 100` over ~0.6 seconds
        - Update the lane's display text to show new position
    - `HUD_MATCH_ENDED { summary }` →
        - Show a centered panel with text summarizing each lane's gain ("LANE 1: +X · LANE 2: +Y · LANE 3: +Z")
        - The panel has a "RETURN TO MENU" button
- `on_input`:
    - Tap on the match-end summary's return button → post `match.return_to_menu` to match.script

#### `main/ui/hud.gui` (modify)

Add a "match-end summary" panel node group. Hidden by default. Contains:
- Background overlay (semi-transparent dark, full screen)
- Centered text node showing the summary
- Centered "RETURN TO MENU" button

**Acceptance criteria for 1.4:**

- [ ] After playing cards, tapping END DRIVE causes:
    - Each lane's ball position animates forward by `floor(you_off_sum / 2.5)` yards over ~0.6 seconds
    - After animations complete, a summary panel appears showing the gains per lane
    - Tapping RETURN TO MENU returns to the main menu
- [ ] Total drives played counter on the menu increments by 1 each completed drive
- [ ] Quit and relaunch: drives counter persists
- [ ] Tapping END DRIVE before playing any cards: still works (just resolves with 0 yards on all lanes)
- [ ] Cannot double-tap END DRIVE to break things (phase check prevents)
- [ ] No console errors

`// === STOP for developer review ===`

---

## Final acceptance for Phase 1

All of these must be true:

- [ ] Project opens in Defold editor with no errors
- [ ] Builds and runs on macOS
- [ ] Menu → tap PLAY → match screen
- [ ] Match screen shows: 3 lane columns, 5 hand cards at bottom, energy=12, END DRIVE button, MENU button, top bar with score and drive number
- [ ] Drag any card from hand onto any of 3 lanes works
- [ ] Energy deducts correctly when cards are played
- [ ] Lane net-yards pills update as cards are stacked
- [ ] Invalid drops (off-lane, unaffordable) handled gracefully
- [ ] Tap END DRIVE → ball positions animate forward → summary appears → tap returns to menu
- [ ] Menu shows updated "DRIVES PLAYED: N"
- [ ] Save persists across app launches
- [ ] All hard rules respected: drag-only (no tap), 3 lanes, hardcoded hand, 12 energy, no AI, no scoring, no assets beyond Phase 0
- [ ] `CLAUDE.md` updated with Phase 1 notes
- [ ] No third-party Lua libraries added
- [ ] No console errors or warnings

## CLAUDE.md updates

Add to CLAUDE.md:

- A new "Phase 1: complete (architecture slice)" entry in the Phase log
- A "## Phase 1 — Architecture slice notes" section at the bottom documenting:
    - What's in (the architecture pattern: cards, lanes, match state machine, drive resolution)
    - What's deliberately stubbed (AI plays nothing, no scoring, no modifiers, no synergies, no perks, no deck cycle, no real assets)
    - Key architectural choices to preserve:
        - Hand cards are GUI nodes, played cards are game objects (will be revisited at asset integration)
        - Match state machine has phases "play" / "resolving" / "ended"
        - The message vocabulary established
    - Known follow-ups for Phase 2:
        - AI plays cards (mirror the player flow for AI side)
        - Multi-drive (loop the match for 8 drives)
        - Deck/draw/discard cycle (hand size becomes dynamic)
        - Scoring system (TD, safety, etc.)

## When you're done

Reply with:

1. Summary of what was built per sub-phase
2. Any deviations from the prompt and why
3. Any conventions you established that should be in CLAUDE.md
4. Open items or things you couldn't finish

Do not start Phase 2.
