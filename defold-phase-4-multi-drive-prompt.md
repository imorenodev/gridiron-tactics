# Claude Code Prompt — Phase 4: Multi-Drive + Deck Cycle

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** Every file you create or modify must conform to its conventions. If this prompt conflicts with `CLAUDE.md`, surface the conflict and stop.

Re-read specifically:
- Hard rules (especially #11 about render scripts — default render only)
- Code conventions (snake_case, module-local state with getters, pre-computed hashes, message naming `category.event`)
- Things I would NOT do (no god modules, no game logic in `.gui_script` files, no third-party libs)
- Phase 0 / 1 / 2 / 2.5 / 3 notes at the bottom

Also review the existing files this prompt will modify:
- `main/state/match_state.lua`
- `main/state/messages.lua`
- `main/state/save.lua`
- `main/match/match.script`
- `main/data/cards.lua`
- `main/ai/cpu.lua`
- `main/ui/hud.gui`
- `main/ui/hud.gui_script`
- `main/animation/animate_helper.lua`
- `main/loader.script`

## Context

Phase 3 shipped scoring. The single-drive match has: drag-to-play, AI reveal, score events (TD/safety/PAT/2pt/pick-6/FG), lane reset with kickoff returns, full match summary with real scores.

**What's missing:** The match still ends after one drive. There's no deck cycle — hands are hardcoded 5-card draws from the pool, no discard, no reshuffle, no escalating energy across drives.

**Phase 4 goal:** Port the full drive-cycle architecture. After Phase 4 the core gameplay loop is complete — 8 drives per match, full deck cycle, escalating energy with carryover, full HTML-parity animations.

## What ships

- 8 drives per match, scoreboard shows "DRIVE N OF 8"
- 30-card deck per side (built at match start from the card pool with replacement)
- Discard pile per side (filled as drives end with unplayed hand cards)
- Reshuffle when deck empties (discard merges back into deck, gets shuffled)
- Energy escalation: drive N grants +N energy
- Energy carryover capped at `MAX_ENERGY_BANK = 10`
- "+N CARRIED" toast animation when carryover happens
- Energy orb pulses when at max bank
- Discard count badge + bump animation on change
- Deck count badge + bump animation on change
- Discard arc animation (cards from hand → discard badge, 600ms, 40ms stagger)
- Draw arc animation (cards from deck badge → hand slot, 400ms, 80ms stagger)
- Reshuffle visual ("RESHUFFLING DECK" text + badge bump, ~1s)
- Tap discard badge → simple text-list modal: "You discarded X cards across N drives" with per-drive counts. Tap to dismiss.
- Match ends after drive 8 with real cumulative score, returns to menu

## What stays out (deferred)

- Lane modifiers, synergies, perks
- Card abilities beyond Clutch Kicker (dispatcher stays the same)
- Audio (no SFX for discard/draw/reshuffle/carryover)
- Discard pile grid modal (HTML has a full grid view; we ship text summary only)
- Halftime comeback tracking (Phase A leveling will add this; we deliberately skip the data hook for now per design doc decision)
- Season mode / draft mode / locker room
- Real card visuals (still box-and-text)
- Game-over splash (match summary unchanged from Phase 3)

## Hard rules

1. **8 sub-phases with STOP markers.** Do not collapse sub-phases. The phasing exists to let the developer playtest between each step.
2. **All new animations use `animate_helper`** (from Phase 2.5). No raw `gui.animate` or `go.animate` calls.
3. **Deck cycle is hand+discard only.** Cards played to the field (and revealed) are consumed — they do NOT return to discard or deck. Lane reset deletes them via the existing `go.delete` path. This matches HTML behavior.
4. **AI deck cycle is silent.** AI draws/discards/reshuffles with no animations — the player can't see the AI's hand, so animating it would be wasted work.
5. **Phase machine vocabulary unchanged.** No new phases. Drive transitions happen entirely within `"resolving"`; the phase only flips back to `"play"` after the new hand is drawn and energy is granted.
6. **Save schema stays at version 1.** Phase 4 doesn't add new persistent fields. `total_drives_played` already exists; it now increments by `max_drives` per completed match (or by drives actually played if you concede mid-match — we'll decide below).
7. **Pre-compute all new hashes** in `main/state/messages.lua`.
8. **No new top-level folders** or third-party libraries.
9. **Do not modify CLAUDE.md mid-prompt.** Update once at the end (Sub-phase 4.8).
10. **Do not start Phase 5.**

## Sub-phases

Eight sub-phases. STOP after each, wait for developer review.

---

### Sub-phase 4.1 — Deck state + draw/discard/reshuffle logic (no UI)

Build the data layer for the deck cycle. No visible behavior change yet — match still ends after drive 1, but the state plumbing for multi-drive is in place.

**Files to modify:**

#### `main/state/match_state.lua`

- Extend top-level state:
    ```lua
    {
        -- existing...
        max_drives = 8,                -- NEW
        you_deck = {},                 -- NEW: array of card records
        you_discard = {},              -- NEW
        ai_deck = {},                  -- NEW
        ai_discard = {},               -- NEW
        you_energy_carried = 0,        -- NEW: amount carried from prev drive (for toast)
        ai_energy_carried = 0,         -- NEW: tracked for parity, not displayed
    }
    ```
- Card record extension (set when a card is moved to discard):
    ```lua
    card.discarded_on_drive = <drive number>
    ```

- **Modify `M.new_match()`**:
    - For each side, build a 30-card deck by sampling from `cards.lua` pool **with replacement** to fill 30 slots
    - Shuffle each deck using Fisher-Yates on a local copy
    - Empty `you_discard`, `ai_discard`
    - Draw 5 cards from each deck into starting hand using `draw_cards_to_hand` (defined below)
    - Set `drive = 1`, `you_energy = 1`, `ai_energy = 1` (matching HTML — drive 1 grants 1)
    - Initialize `you_energy_carried = 0`, `ai_energy_carried = 0`

- **New: `M.draw_cards_to_hand(side, count)`**:
    - Pulls `count` cards from the side's deck into hand
    - If deck empty before count is satisfied: reshuffle that side's discard into deck first
    - If deck AND discard are both empty: stop early, return whatever was drawn
    - Returns `{ drawn = { card_records... }, reshuffled = true|false }`
    - Reshuffled flag is used by `match.script` to trigger the reshuffle visual

- **New: `M.reshuffle_discard_into_deck(side)`**:
    - Moves all cards from the side's discard back into deck
    - Clears `discarded_on_drive` on each card
    - Shuffles the deck

- **New: `M.discard_hand(side)`**:
    - Moves all of the side's remaining hand cards into discard
    - Tags each card with `discarded_on_drive = state.drive`
    - Clears the hand array

- **New: `M.advance_drive()`**:
    - Increments `state.drive`
    - For each side: calculates `gain = state.drive` (escalating per HTML), then `carried = state.<side>_energy` (whatever's left unspent), then `new_energy = math.min(MAX_ENERGY_BANK, state.<side>_energy + gain)` where `MAX_ENERGY_BANK = 10`
    - Stores `you_energy_carried = carried` (for the carryover toast trigger; only matters when carried > 0)
    - Returns: `{ new_drive, you_gain, you_carried, you_new_energy, ai_gain, ai_carried, ai_new_energy }`

- **New: `M.is_match_over()`** — returns true if `state.drive > state.max_drives`

- **New: `M.get_discard_summary(side)`** — returns `{ total = N, per_drive = { [drive_num] = count, ... } }` for the text modal

- **Modify `M.play_card`** — no change needed; card already leaves hand. Just verify it doesn't accidentally add to discard.

- **Modify `M.reset_lane_after_score`** — no change needed; lane reset clears the lane's `you_cards`/`ai_cards` arrays. The cards on the field are consumed.

- **Add constant at top of module:**
    ```lua
    local MAX_ENERGY_BANK = 10
    local DECK_SIZE = 30
    local HAND_SIZE = 5
    ```

#### `main/state/messages.lua`

Add (most will be used in later sub-phases):
```lua
M.HUD_DECK_COUNT_CHANGED    = hash("hud.deck_count_changed")
M.HUD_DISCARD_COUNT_CHANGED = hash("hud.discard_count_changed")
M.HUD_START_DISCARD_ANIM    = hash("hud.start_discard_anim")
M.HUD_START_DRAW_ANIM       = hash("hud.start_draw_anim")
M.HUD_RESHUFFLE             = hash("hud.reshuffle")
M.HUD_CARRIED_TOAST         = hash("hud.carried_toast")
M.HUD_DRIVE_CHANGED         = hash("hud.drive_changed")
M.HUD_ENERGY_AT_CAP         = hash("hud.energy_at_cap")
M.HUD_OPEN_DISCARD_MODAL    = hash("hud.open_discard_modal")
```

**Acceptance criteria for 4.1:**

- [ ] Project builds, no console errors
- [ ] Phase 3 behavior preserved (single drive, scoring works, summary appears)
- [ ] `match_state.new_match()` populates 30-card decks for both sides
- [ ] Starting hand has 5 cards drawn from the deck (deck reduces from 30 to 25)
- [ ] Calling `draw_cards_to_hand("you", 5)` returns 5 cards and reduces deck
- [ ] Calling `discard_hand("you")` moves unplayed hand into discard
- [ ] After discarding then drawing past empty deck: `reshuffled = true` returned
- [ ] No visible UI change (badge counts not added yet)

`// === STOP for developer review ===`

---

### Sub-phase 4.2 — Multi-drive cycle + scoreboard drive number

Match doesn't end after drive 1. Drive transition runs the discard/draw/energy-escalation sequence. No animations yet — just functional state mutation. Scoreboard top bar shows "DRIVE N OF 8" updating each drive.

**Files to modify:**

#### `main/match/match.script`

Refactor the end-of-drive flow:

After scoring events resolve (Phase 3's `start_scoring_pipeline` chain completes), instead of going straight to `finish_drive` (match end):

1. Check `match_state.is_match_over()`:
    - **If yes**: existing flow — show match summary, post `MATCH_DRIVE_COMPLETED`, return to menu
    - **If no**: drive transition

2. Drive transition sequence (still all within `phase = "resolving"`):
    a. Call `match_state.discard_hand("you")`
    b. Call `match_state.discard_hand("ai")`
    c. Call `match_state.draw_cards_to_hand("ai", 5)` — silent for AI
    d. Call `match_state.draw_cards_to_hand("you", 5)` — capture the `reshuffled` flag for later (4.4 will use it for the reshuffle visual)
    e. Call `match_state.advance_drive()` — capture the return values for energy info
    f. Post `HUD_DRIVE_CHANGED { drive = state.drive, max_drives = 8 }` to HUD
    g. Post `HUD_ENERGY_CHANGED { you_energy, ai_energy }` to HUD (existing message)
    h. Post `HUD_HAND_CHANGED { hand = match_state.get_hand() }` to HUD (existing message)
    i. Set `phase = "play"` (re-enables input via existing 2.5 phase gate)

#### `main/ui/hud.gui`

- Add or confirm the scoreboard "DRIVE N OF 8" text node exists. Phase 1/2 had a static "DRIVE 1" — extend to update dynamically.
    - Position: scoreboard center area (between YOU score and CPU score)
    - Text: "DRIVE 1 OF 8" initially
    - Font: medium, gold-colored if possible (uses default font for now)

#### `main/ui/hud.gui_script`

- Add handler for `HUD_DRIVE_CHANGED { drive, max_drives }`:
    - Update the drive text node: "DRIVE N OF M"
    - Brief pulse animation via `animate_helper.animate_gui` (scale 1 → 1.15 → 1 over 250ms) — same pulse as Phase 3's score top bar

**Acceptance criteria for 4.2:**

- [ ] Project builds, no console errors
- [ ] Play through a full match: drive 1 ends → drive 2 begins automatically
- [ ] Scoreboard updates "DRIVE 1 OF 8" → "DRIVE 2 OF 8" → ... → "DRIVE 8 OF 8" with brief pulse on each change
- [ ] After drive 8, match summary appears (existing Phase 3 behavior)
- [ ] During drive transition, hand visibly changes — old hand replaced by new hand (no animation, just instant swap for now)
- [ ] No console errors during any drive transition
- [ ] Match summary at end shows real cumulative scores (TDs across multiple drives accumulate)

`// === STOP for developer review ===`

---

### Sub-phase 4.3 — Energy escalation + carryover toast + cap pulse

Energy escalates per drive. Carryover toast appears above the orb when unspent energy carries to next drive. Orb pulses when at MAX_ENERGY_BANK.

**Files to modify:**

#### `main/ui/hud.gui`

- Add `carried_toast` text node:
    - Initially: `enabled = false`, alpha = 0
    - Position: just above the energy orb in design space
    - Text: "+N CARRIED" (placeholder; updates dynamically)
    - Font: medium-large, gold color
- The energy orb already exists from Phase 1. No structural change needed, just add an `at_cap` visual treatment (described below).

#### `main/ui/hud.gui_script`

- Add handler for `HUD_CARRIED_TOAST { amount }`:
    - Set the toast text: `"+" .. amount .. " CARRIED"`
    - Enable the node, animate via `animate_helper`:
        - Alpha 0 → 1 over 200ms, simultaneous with Y position rising by 12 design pixels (slight float up)
        - Hold 850ms at full opacity
        - Alpha 1 → 0 over 250ms, simultaneous with Y rising another 10 pixels
    - Total ~1.3s
    - After animation: reset position, alpha = 0, `enabled = false`
- Add handler for `HUD_ENERGY_AT_CAP { at_cap }`:
    - If `at_cap = true`, start a pulsing animation on the energy orb (scale 1 → 1.08 → 1 in a loop)
    - If `at_cap = false`, stop the pulse and reset scale to 1
    - Use `animate_helper` with PLAYBACK_LOOP_PINGPONG or similar; can be a manual repeating timer if PINGPONG doesn't work cleanly
- Modify existing `HUD_ENERGY_CHANGED` handler:
    - After updating the energy text, check if `you_energy == MAX_ENERGY_BANK` (10) and post-process accordingly. The match script will also post `HUD_ENERGY_AT_CAP` explicitly.

#### `main/match/match.script`

- After drive transition (step `2g` from 4.2), if `you_energy_carried > 0`:
    - Post `HUD_CARRIED_TOAST { amount = you_energy_carried }` to HUD
- Also after step `2g`: if `you_energy >= 10`:
    - Post `HUD_ENERGY_AT_CAP { at_cap = true }`
    - Otherwise post `at_cap = false` to stop any existing pulse
- When the player plays a card (`MATCH_PLAY_CARD` handler), after deducting energy:
    - If energy drops below cap, post `HUD_ENERGY_AT_CAP { at_cap = false }`

**Acceptance criteria for 4.3:**

- [ ] Play drive 1, end drive without spending all 1 energy → drive 2 starts → "+1 CARRIED" toast appears above orb
- [ ] Energy values match HTML: drive 1 = 1, drive 2 = up to 3 (1 carry + 2 grant), drive 3 = up to 6, etc.
- [ ] Energy caps at 10 even if drive_number + carryover would exceed it
- [ ] When energy is at 10, orb pulses visibly
- [ ] When you spend energy, pulse stops
- [ ] Reduced motion ON: toast and pulse short-circuit (toast appears statically, pulse doesn't loop) — verify by pressing R
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 4.4 — Deck/discard badge counts + bump animation + reshuffle visual

Add count badges to the HUD. Reshuffle visual triggers when the deck empties.

**Files to modify:**

#### `main/ui/hud.gui`

- Add `deck_badge` group:
    - Box node ("DECK" label) + text node showing remaining card count
    - Position: lower-left area near the hand
    - Initial count: "30"
    - Background color: dark
- Add `discard_badge` group:
    - Box node ("DISCARD" label) + text node showing count
    - Position: lower-right area near the hand
    - Initial count: "0"
    - Background color: dark
    - **Tappable** (input goes through Phase 2.5's input gate, which is fine because in `phase = "play"` taps still register; the modal it opens is separate)
- Add `reshuffle_text` node:
    - Position: between deck and discard badges (or above the hand area)
    - Text: "RESHUFFLING DECK"
    - Color: gold
    - Initially: `enabled = false`, alpha = 0

#### `main/ui/hud.gui_script`

- Add handlers:
    - `HUD_DECK_COUNT_CHANGED { count }`:
        - Update text on deck badge
        - Bump animation: scale 1 → 1.18 → 1 over 220ms via `animate_helper`
    - `HUD_DISCARD_COUNT_CHANGED { count }`:
        - Same pattern for discard badge
    - `HUD_RESHUFFLE`:
        - Show "RESHUFFLING DECK" text via fade-in/fade-out (alpha 0 → 1 → 0 over 1000ms total)
        - Trigger an extra bump on the discard badge (it's the badge "emptying" symbolically)
- Add input handling for tapping the discard badge:
    - In `on_input`, after the existing drag-start check, check if tap landed on `discard_badge`
    - If yes, post `HUD_OPEN_DISCARD_MODAL` to self (which 4.7 will handle by showing the modal)
    - In 4.4: print a placeholder log "open discard modal" — actual modal ships in 4.7

#### `main/match/match.script`

- After every state mutation that changes deck/discard counts, post the corresponding count-changed messages to HUD:
    - After `new_match` init: post both counts (30 deck, 0 discard for each side)
    - After `discard_hand("you")`: post discard count
    - After `draw_cards_to_hand("you", 5)`: post deck count (decreases) and discard count (may have decreased if reshuffle happened)
    - If `draw_cards_to_hand` returned `reshuffled = true`: post `HUD_RESHUFFLE` BEFORE posting the count changes (so the visual "RESHUFFLING" message appears, then the discard goes to 0 and deck pops back up)
- The actual order in the transition is:
    1. discard_hand: post discard count up
    2. (potentially) reshuffle visual
    3. draw_cards_to_hand: post deck count down, post discard count down (if reshuffled)

**Acceptance criteria for 4.4:**

- [ ] After match start, badges show "DECK 25" / "DISCARD 0" (since 5 cards were drawn from the 30-deck)
- [ ] After drive 1 ends with unplayed cards: discard count bumps up, deck count holds
- [ ] After drive 2 starts: deck count bumps down by 5 (new hand drawn)
- [ ] Around drive 5-6, deck count reaches 0 → on next draw, "RESHUFFLING DECK" text appears, discard count drops to 0, deck count pops up to whatever the discard had
- [ ] Tap the discard badge: console log "open discard modal" (placeholder; modal ships in 4.7)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 4.5 — Discard arc animation

Hand cards animate to the discard badge with rotation and scale, staggered.

**Files to modify:**

#### `main/ui/hud.gui_script`

- Add handler for `HUD_START_DISCARD_ANIM { card_uids }`:
    - For each card_uid (in order), find the GUI node currently representing that hand card
    - Get the discard badge's position
    - For each card, schedule an animation via `animate_helper`:
        - Move from current position to discard badge position (use `gui.set_position` initial state + `animate_gui` on position)
        - Add rotation: 0 → 30° via animate on `rotation.z`
        - Add scale: 1 → 0.4 via animate on `scale`
        - Add alpha: 1 → 0 via animate on `color.w`
        - Duration: 600ms with `EASING_INQUAD` or `EASING_INCUBIC`
    - Stagger between cards: 40ms (i.e., card N's animation starts at time `i * 40ms`)
    - After the full animation completes (~600ms + 40ms * (cards-1) + 40ms buffer), post `match.discard_animation_complete` to match.script

#### `main/match/match.script`

- Modify the drive transition sequence:
    - Replace the immediate `discard_hand("you")` call with:
        1. Capture the current hand card UIDs: `local card_uids = ...` (read from `match_state.get_hand()`)
        2. Post `HUD_START_DISCARD_ANIM { card_uids }` to HUD
        3. Wait via `timer.delay` for the animation duration (~700ms total)
        4. Then call `match_state.discard_hand("you")` (after animation, mutate state — so the cards have already visually arrived at the discard pile before state reflects)
        5. Continue with the rest of the transition

Alternative simpler sequencing: mutate state first, animate based on the captured UIDs after. Either works; pick whichever is cleaner. The visual outcome is the same — cards arc to discard badge.

#### `main/ai/cpu.lua` (no changes)

AI discard is silent. Just call `match_state.discard_hand("ai")` with no animation.

**Acceptance criteria for 4.5:**

- [ ] End drive 1 with cards in hand: cards visibly arc to discard badge (rotating, shrinking, fading)
- [ ] 40ms stagger between cards (visible — they don't all leave at once)
- [ ] Discard badge bump fires after the cards arrive (Phase 4.4's existing bump on count change)
- [ ] AI discards silently (no visible cards from AI's hand because we don't render AI's hand)
- [ ] Reduced motion ON: cards disappear instantly (no arc)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 4.6 — Draw arc animation

New hand cards spawn at the deck badge and animate to their hand slot positions.

**Files to modify:**

#### `main/ui/hud.gui_script`

- Add handler for `HUD_START_DRAW_ANIM { drawn_cards }`:
    - `drawn_cards` is an array of card records that were just drawn
    - For each drawn card (in order):
        - Render the card in its target hand slot but at a "spawn" state: position = deck badge position, scale = 0.4, alpha = 0.35
        - Animate via `animate_helper`:
            - Position to natural slot position
            - Scale 0.4 → 1
            - Alpha 0.35 → 1
            - Duration: 400ms with `EASING_OUTQUAD` or `EASING_OUTCUBIC`
        - Stagger between cards: 80ms

#### `main/match/match.script`

- Modify the drive transition further:
    - After discard animation completes and `match_state.discard_hand("you")` has mutated state
    - Call `match_state.draw_cards_to_hand("you", 5)` and capture both `drawn` and `reshuffled` from the return value
    - If `reshuffled = true`: post `HUD_RESHUFFLE` first, wait ~500ms for the reshuffle visual to play
    - Then post `HUD_START_DRAW_ANIM { drawn_cards = drawn }` to HUD
    - Wait via `timer.delay` for the draw animation (~600ms total)
    - Then proceed with the rest of the transition (advance_drive, energy/drive HUD updates)

#### Important: the `HUD_HAND_CHANGED` message from 4.2

In 4.2 we posted `HUD_HAND_CHANGED` to render the new hand instantly. With 4.6, the draw animation handles the rendering — we should NOT post `HUD_HAND_CHANGED` for the new hand, because the draw animation puts the cards in place.

**However**, after the draw animation completes, post `HUD_HAND_CHANGED` to ensure the HUD's internal state is in sync with the visual state. This avoids drift between Lua state and rendered nodes.

**Acceptance criteria for 4.6:**

- [ ] After drive transition, new hand visibly draws in: cards arc from deck badge to their slots
- [ ] 80ms stagger between cards
- [ ] Deck count bumps down as cards leave
- [ ] If reshuffle happens during draw: "RESHUFFLING DECK" appears first, then deck count pops up, then draw animation starts
- [ ] Reduced motion ON: cards appear instantly in hand slots (no arc)
- [ ] No console errors
- [ ] Cards in hand are immediately draggable once the draw animation completes (no input lockout extending past phase change)

`// === STOP for developer review ===`

---

### Sub-phase 4.7 — Discard text modal

Tap the discard badge → show a small modal with text summary. Tap anywhere to dismiss.

**Files to modify:**

#### `main/ui/hud.gui`

- Add `discard_modal_root` group:
    - Full-screen semi-transparent dim overlay
    - Centered modal box (~500×400 design pixels):
        - Title: "DISCARD PILE" (large)
        - Body text node (filled dynamically):
            - "You discarded X cards across N drives:"
            - "Drive 1: 3 cards"
            - "Drive 2: 4 cards"
            - etc.
        - "Tap to dismiss" hint at bottom
    - Initially: `enabled = false`

#### `main/ui/hud.gui_script`

- Add handler for `HUD_OPEN_DISCARD_MODAL`:
    - Call `match_state.get_discard_summary("you")` to get `{ total, per_drive }`
    - Format body text:
        - `"You discarded " .. total .. " card" .. (total == 1 and "" or "s") .. " across " .. count_drives_with_discards .. " drive" .. ...`
        - Then for each drive in `per_drive`, sorted ascending, add a line: `"Drive " .. drive_num .. ": " .. count .. " card" .. (count == 1 and "" or "s")`
    - Set the body text node
    - Enable the modal root
    - Use `animate_helper` for a brief scale-in: 0.9 → 1.0 over 150ms
- Add input handler for the modal:
    - On touch when modal is visible: dismiss the modal (animate out: scale 1 → 0.9, alpha 1 → 0, then disable)
    - Touch on the modal blocks all other input while it's open

**Important**: the modal is *not* phase-aware. It can open during any phase — even during the reveal animation, tapping the discard badge should open the modal. This is intentional and matches the HTML's behavior.

**Acceptance criteria for 4.7:**

- [ ] During a match (any phase), tap the discard badge
- [ ] Modal appears with title and per-drive breakdown
- [ ] Counts match the actual discard state (verify by playing 2 drives, discarding different numbers of cards, checking the modal numbers)
- [ ] Tap anywhere → modal dismisses with brief animation
- [ ] After dismissing, gameplay continues normally
- [ ] Empty discard pile: modal shows "Nothing discarded yet."
- [ ] Reduced motion ON: modal opens/closes instantly
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 4.8 — CLAUDE.md update

Update `CLAUDE.md`:

- Phase log: add `Phase 4: complete (multi-drive cycle + deck cycle)`
- Add a new `## Phase 4 — Multi-drive notes` section at the bottom documenting:
    - What was built per sub-phase
    - Key architectural choices to preserve:
        - 30-card deck per side (smaller than HTML's 50 for reshuffle visibility in playtest; expand when balance work happens)
        - Cards played to the field are consumed — they do NOT return to deck or discard. Lane reset deletes them.
        - AI deck cycle runs silently; no animations, no messages to HUD for AI hand changes
        - Drive transition happens entirely within `phase = "resolving"`; the phase only flips back to `"play"` after the new hand draw animation completes
        - Energy carryover toast is the only "+N CARRIED" feedback; reshuffle uses text + badge bump only
        - Discard modal is text-only by design (full grid modal deferred)
        - Halftime tracking deliberately omitted — will be added when leveling/summary phase ships
        - `HUD_HAND_CHANGED` is posted AFTER draw animation completes to keep state and visuals in sync, even though the draw animation itself handles rendering
    - Intentional stubs: card abilities beyond Clutch Kicker, modifiers, synergies, perks, audio, halftime tracking, discard grid modal, game-over splash
    - Phase 5 / 6+ follow-ups: card abilities dispatcher expansion (more SNAP/FIELD abilities), lane modifiers, card synergies, perks, season mode, draft mode, leveling/summary screen

`// === STOP for developer review ===`

---

## Final acceptance for Phase 4

All of these must be true before marking Phase 4 complete:

- [ ] Project opens in Defold editor with no red error markers
- [ ] Builds and runs on macOS
- [ ] Full match plays out across 8 drives, ending naturally after drive 8
- [ ] Drive transitions visibly happen:
    - Old hand cards arc to discard badge with rotation and scale
    - "RESHUFFLING DECK" visual fires when deck empties (typically around drive 6-7)
    - New hand cards arc from deck badge to their hand slots
    - Energy escalates per drive (1, 2, 3, ...) capped at 10
    - "+N CARRIED" toast appears when carryover happens
    - Energy orb pulses when at 10
    - Scoreboard shows "DRIVE N OF 8" with brief pulse on change
- [ ] Cards played to the field are consumed (do NOT return to deck/discard)
- [ ] AI hand draws/discards silently across drives
- [ ] Discard badge tap opens text modal with correct per-drive counts; tap to dismiss
- [ ] Scoring still works correctly across multiple drives (TDs from drive 3 and drive 7 both add to score)
- [ ] Lane reset after score still works mid-match (kickoff returns happen, both balls reset to 15-35)
- [ ] FG via Clutch Kicker becomes more achievable in multi-drive matches (lanes can advance past 50 before reveal in later drives)
- [ ] Save persistence still works
- [ ] Reduced motion ON shorts-circuits all new animations but preserves sequencing pacing
- [ ] All hard rules respected
- [ ] CLAUDE.md updated with Phase 4 notes
- [ ] No third-party libraries added
- [ ] No console errors at any point

## When you're done

Reply with:

1. Summary of what was built per sub-phase
2. Any deviations from the prompt and why
3. Conventions established that should be in CLAUDE.md
4. Things to verify on Mac (since you can't run Defold)
5. Open items

Do not start Phase 5.
