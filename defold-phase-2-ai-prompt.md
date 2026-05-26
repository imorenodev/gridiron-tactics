# Claude Code Prompt — Phase 2: AI Side (Reveal Mechanic)

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** Every file you create or modify must conform to its conventions. If this prompt conflicts with `CLAUDE.md`, surface the conflict and stop.

Re-read specifically:

- "Hard rules" section, including rule #11 about render scripts (default render only, do not customize)
- "Code conventions" section (snake_case, module-local state with getters, pre-computed hashes, message naming)
- "Things I would NOT do" section (no god modules, no game logic in `.gui_script` files, no third-party libs)
- Phase 0 and Phase 1 notes at the bottom — the existing patterns we're extending

Also review the existing files this prompt will modify:

- `main/state/match_state.lua`
- `main/state/messages.lua`
- `main/match/match.script`
- `main/match/card.script`
- `main/match/card_factory.script`
- `main/match/match.collection`
- `main/ui/hud.gui`
- `main/ui/hud.gui_script`

If anything in those files surprises you (e.g. a convention not documented in CLAUDE.md), note it in your response.

## Context

Phase 1 shipped the architecture slice: one playable drive, 3 lanes, drag-to-play, hardcoded 5-card hand, drive resolution updating ball positions. The player side works end-to-end.

**Phase 2 goal:** Mirror the player flow for the AI. After Phase 2:

- AI has its own hand (5 cards), energy (12), and lane state (`ai_cards`, `ai_pos`)
- AI plays cards at END DRIVE using a greedy heuristic ported from the HTML
- AI cards play face-down (`revealed = false`); player cards also become face-down on play
- END DRIVE triggers a reveal sequence: AI plays its cards, then a `revealing` phase flips all cards face-up with animation, then `resolving` phase animates ball positions
- Net yards formula now uses both sides: `floor(off_sum / 2.5) − floor(opp_def_sum / 2.5)`
- Lane stats (`*_off_sum`, `*_def_sum`, `*_net_yards`) only count *revealed* cards

What stays out (deferred):

- No scoring (no TD, safety, PAT, pick-6, FG)
- No multiple drives (match still ends after one drive)
- No modifiers, no synergies, no perks (all `revealed`-card filtering exists in the new code, but the modifier/synergy hooks stay empty)
- No SNAP/FIELD card abilities (the reveal loop has an explicit ability hook that's a no-op for Phase 2)
- No real card visuals (player cards still box+text in GUI; AI cards on field are face-down box+icon game objects, then flip to box+text on reveal)
- No deck cycle (hand stays hardcoded; reshuffle, draw, discard all deferred)
- No real audio (Web Audio synths in HTML don't port; silent for now)

## Critical architectural change from Phase 1

**Player cards now play face-down too.** This is a behavioral change to Phase 1's `play_card` flow, not just an addition.

In Phase 1, when the player dragged a card to a lane:
- The card moved to `lane.you_cards`
- `you_off_sum` and `you_net_yards` were immediately updated
- The lane's net-yards pill in the HUD updated live
- Energy deducted
- Card removed from hand

In Phase 2, when the player drags a card to a lane:
- The card moves to `lane.you_cards` with `revealed = false`
- The card is also added to `state.pending_plays` (a top-level array)
- `you_off_sum`, `you_def_sum`, `you_net_yards` stay at 0 (since no revealed cards yet contribute)
- The lane's net-yards pill stays at "+0" until reveal at END DRIVE
- Energy deducts (same as Phase 1)
- Card removed from hand (same as Phase 1)
- Card visually appears in lane as a face-down game object (different from Phase 1 — was face-up box+text)

This matches the HTML behavior: even your own pill shows 0 until reveal, preserving the bluff/anticipation that makes Snap-style games tense. **This is intentional and per design — do not "fix" it to show progressive net yards during the play phase.**

The asymmetry — player can see *which* cards they played (they're in their own lane slots, face-down) while AI cards don't appear until END DRIVE — is also intentional and matches the HTML.

## Hard rules for this phase

1. **No scoring.** Even though ball positions advance, do not implement TD/safety/PAT/conversion/pick-6/FG. Ball can exceed 100 or go below 0; we don't react.
2. **No SNAP/FIELD abilities.** The reveal loop has a `try_apply_snap_ability(play)` hook in `card_factory.script` or `match.script` — leave it as an empty function stub with a TODO comment. Card abilities ship in a later phase.
3. **No real card visuals.** Played cards (both sides, revealed) use the same box+text rendering as Phase 1 player cards. Face-down cards use a different visual (box with football icon "🏈" or similar simple distinguisher).
4. **AI heuristic is ported from the HTML, not redesigned.** Use the algorithm shown in the HTML's `aiMakePlays()` (see "AI heuristic" section below). Do not invent a new heuristic for Phase 2.
5. **The reveal order is "winner reveals first."** Since Phase 2 has no scoring (both scores stay 0), the tiebreaker defaults to player-reveals-first. Implement the comparison logic correctly so it works when scoring is added later.
6. **All hashes pre-computed.** All new message hashes go into `main/state/messages.lua`.
7. **GUI scripts contain no game logic.** Reveal animations are driven by messages from `match.script`; the GUI just animates in response.
8. **No third-party libraries.** Defold stdlib only.
9. **Do not modify CLAUDE.md mid-prompt.** Update it once at the end (Sub-phase 2.4).
10. **Do not start Phase 3.**

## AI heuristic (port verbatim from HTML)

The HTML's `aiMakePlays()` is the Phase 2 heuristic. Port it to Lua as `main/ai/cpu.lua`:

```lua
local M = {}

-- choose_plays(ai_hand, ai_energy, lanes) → array of {card, lane_idx}
-- Iterates ai_hand sorted by (off + def) descending, scores each card across
-- the 3 lanes, picks the highest score, plays if affordable + lane not full.
-- Mutates a working copy; caller applies the resulting plays to real state.
function M.choose_plays(ai_hand, ai_energy, lanes)
    -- Sort hand by power descending
    local playable = {}
    for _, c in ipairs(ai_hand) do table.insert(playable, c) end
    table.sort(playable, function(a, b)
        return (a.off + a.def) > (b.off + b.def)
    end)

    local energy_left = ai_energy
    local plays = {}
    -- Track lane fill counts in a working copy so we don't double-fill
    local lane_fill = {}
    for i, lane in ipairs(lanes) do
        lane_fill[i] = #lane.ai_cards
    end

    for _, card in ipairs(playable) do
        if card.cost <= energy_left then
            local best_lane = -1
            local best_score = -math.huge
            for i = 1, 3 do
                local lane = lanes[i]
                if lane_fill[i] < 8 then  -- MAX_SLOTS = 8
                    local score = 0
                    if card.side == "off" then
                        score = card.off
                        -- Bonus if AI is close to scoring on this lane
                        if lane.ai_pos >= 70 then score = score + 18
                        elseif lane.ai_pos >= 50 then score = score + 8 end
                        -- Bonus if player's defense is weak on this lane
                        if lane.you_def_sum < card.off / 2 then score = score + 6 end
                        -- Kicker positioning bonus
                        if card.pos == "K" and lane.ai_pos >= 50 then
                            score = score + 14
                        end
                    else
                        -- Defensive card
                        score = card.def
                        -- Urgent if player is threatening
                        if lane.you_pos >= 70 then score = score + 22
                        elseif lane.you_pos >= 50 then score = score + 10 end
                        -- If AI is near own endzone, defense helps avoid safety
                        if lane.ai_pos <= 30 then score = score + 6 end
                        -- DB stacking for pick-6 (player ball near AI endzone)
                        if (card.pos == "CB" or card.pos == "S") and lane.ai_pos <= 50 then
                            local dbs_here = 0
                            for _, c2 in ipairs(lane.ai_cards) do
                                if c2.pos == "CB" or c2.pos == "S" then
                                    dbs_here = dbs_here + 1
                                end
                            end
                            score = score + dbs_here * 5
                        end
                    end
                    -- Tiny random tiebreaker
                    score = score + math.random() * 3

                    if score > best_score then
                        best_score = score
                        best_lane = i
                    end
                end
            end

            if best_lane >= 1 then
                table.insert(plays, { card = card, lane_idx = best_lane })
                lane_fill[best_lane] = lane_fill[best_lane] + 1
                energy_left = energy_left - card.cost
            end
        end
    end

    return plays
end

return M
```

The HTML scores defense cards based on player position (`lane.youPos`) — the AI wants to defend lanes where the player is winning. Phase 2 has no scoring, but the player can still drive forward via card placements, so this scoring logic still works.

The card pool from Phase 1 (`main/data/cards.lua`) is the same for both sides — AI gets a random hand from the same pool.

## Sub-phases

Four sub-phases with `// === STOP for developer review ===` markers between each.

---

### Sub-phase 2.1 — State foundation + AI heuristic module

Build the data plumbing and the AI module. No new visible behavior yet.

**Files to create:**

- `main/ai/cpu.lua` — the heuristic, per the section above

**Files to modify:**

- `main/state/match_state.lua`:
    - Extend the `lanes` shape with AI fields:
        - `ai_pos` (int, starts 25)
        - `ai_cards` (array, empty)
        - `ai_off_sum` (int, 0)
        - `ai_def_sum` (int, 0)
        - `ai_net_yards` (int, 0)
        - Rename existing `you_off_sum` → keep, but add `you_def_sum` for symmetry (some player cards have `def`, even if rare; the math needs both sides)
    - Extend top-level state:
        - `ai_hand` (array of 5 cards, parallel to `hand`)
        - `ai_energy` (int, 12)
        - `ai_played_uids` (table set, for double-spend prevention)
        - `pending_plays` (array of `{ card_uid, lane_idx, side ("you" or "ai") }`)
    - **Modify `M.new_match()`**:
        - Build the player hand as before
        - Build an AI hand the same way (5 random cards from `cards.lua`'s pool)
        - Initialize `ai_energy = 12`
        - Initialize all lane AI fields
        - Initialize `pending_plays = {}`
    - **Modify `M.play_card(card_uid, lane_idx)`** — this is the breaking change from Phase 1:
        - Instead of immediately moving the card to `you_cards` and updating sums:
            - Find the card in `hand`, remove it from hand
            - Add to `lane.you_cards` with `revealed = false`
            - Add to `pending_plays` as `{ card_uid, lane_idx, side = "you" }`
            - Deduct energy
            - **Do NOT update `you_off_sum`, `you_def_sum`, or `you_net_yards`** — these stay at 0 until reveal
        - Return shape stays the same: `{ success = true, card = ..., new_energy = ..., new_off_sum = 0, new_net_yards = 0 }` (the sums are now always 0 from this function's perspective since cards are face-down)
    - **Add `M.ai_play_card(card, lane_idx)`** — mirror of `play_card` for the AI:
        - Add to `lane.ai_cards` with `revealed = false`
        - Add to `pending_plays` as `{ card_uid = card.uid, lane_idx, side = "ai" }`
        - Deduct `ai_energy`
        - Return shape similar to `play_card`
    - **Add `M.reveal_pending_plays()`**:
        - Determines reveal order: player-side first if `you_score >= ai_score`, else AI first
        - For each pending play, in order:
            - Find the card object in the relevant lane
            - Set `card.revealed = true`
            - Set `card._base_off = card.off`, `card._base_def = card.def` (for future ability work)
            - Set `card.cur_off = card.off`, `card.cur_def = card.def` (Phase 2: no modifiers, so cur = base)
            - **Call `try_apply_snap_ability(card)` — a no-op stub function** with a TODO comment that says "Phase TBD: implement card snap abilities here"
            - Recompute lane sums (see helper below)
        - Clear `pending_plays`
        - Return a summary table of revealed plays (for the HUD to animate): `{ { lane_idx, side, card_uid, slot_idx } }` in reveal order
    - **Add `M.recompute_lane_sums(lane_idx)`** — helper called after each reveal:
        - For the given lane, sum `cur_off` and `cur_def` across revealed cards on each side
        - Update `you_off_sum`, `you_def_sum`, `ai_off_sum`, `ai_def_sum`
        - Compute new net yards:
            - `you_net_yards = floor(you_off_sum / 2.5) - floor(ai_def_sum / 2.5)`
            - `ai_net_yards = floor(ai_off_sum / 2.5) - floor(you_def_sum / 2.5)`
    - **Modify `M.resolve_drive()`**:
        - No longer uses the simple Phase 1 formula
        - Reads `you_net_yards` and `ai_net_yards` from the lane (already computed during reveal)
        - Advances `you_pos` and `ai_pos` on each lane, clamping 0-100
        - Sets `phase = "ended"`
        - Returns summary: `{ lanes = { { idx, you_yards_gained, ai_yards_gained, new_you_pos, new_ai_pos } } }`

- `main/state/messages.lua` — add new hashes:
    - `M.MATCH_PLAY_AI_CARDS = hash("match.play_ai_cards")` — internal post to self
    - `M.MATCH_REVEAL = hash("match.reveal")` — internal
    - `M.HUD_AI_CARDS_SPAWNED = hash("hud.ai_cards_spawned")` — match → hud, after AI plays its hand
    - `M.HUD_REVEAL_CARD = hash("hud.reveal_card")` — match → hud, one per card during reveal sequence
    - `M.HUD_LANE_SUMS_UPDATED = hash("hud.lane_sums_updated")` — match → hud, after each reveal recomputes lane sums

- `main/ai/cpu.lua` is the new file (already specced above)

**Acceptance criteria for 2.1:**

- [ ] Project builds with no errors
- [ ] `require("main.ai.cpu")` returns a module exposing `choose_plays`
- [ ] `match_state.new_match()` initializes AI hand, AI energy, AI lane fields, and `pending_plays`
- [ ] Calling `match_state.play_card(uid, idx)` from a script puts the card in `lane.you_cards` with `revealed = false` and adds to `pending_plays`; lane sums stay 0
- [ ] Visible behavior in-game: tapping PLAY shows the match screen, drag-to-play works, but the lane net-yards pill stays at "+0" no matter how many cards you play (this is expected — reveal isn't implemented yet)
- [ ] END DRIVE button still works but the drive resolves with 0 net yards on all lanes (since nothing is revealed yet)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 2.2 — AI plays at END DRIVE (no reveal animation yet)

Wire the AI plays into the END DRIVE flow. AI cards spawn face-down. Cards immediately reveal *without animation* — they just flip face-up instantly, sums update, and drive resolution proceeds with the real net yards. This is an intermediate state that lets us verify AI plays and drive resolution work correctly before adding the animation layer.

**Files to modify:**

- `main/match/match.script`:
    - **Modify `match.end_drive` handler**:
        - Set `phase = "revealing"`
        - Call `cpu.choose_plays(ai_hand, ai_energy, lanes)` to get AI's intended plays
        - For each AI play, call `match_state.ai_play_card(card, lane_idx)`. This adds to lane with `revealed = false` and to `pending_plays`.
        - For each AI play, post `card.spawn` to `card_factory.go` (existing factory) — but now with a new property `side = "ai"` so the factory knows which lane region to spawn into
        - Post `hud.ai_cards_spawned { plays = { { lane_idx, slot_idx, card_data } } }` to HUD so it can render face-down AI cards
        - **In 2.2 only**: immediately after spawning AI cards, call `match_state.reveal_pending_plays()` to flip everything face-up *instantly* (no animation). This gives us the right end-state for verifying AI plays correctly.
        - After reveal, post `hud.lane_sums_updated { lanes = {...} }` so HUD shows the new net yards on each lane
        - Call `match_state.resolve_drive()` and post `hud.lane_resolved` per lane (existing behavior)
        - After resolve animations complete (~1 second), post `hud.match_ended` (existing)
        - Set `phase = "ended"`

- `main/match/card_factory.script`:
    - Extend the `card.spawn` message handler to accept a `side` property
    - Compute position based on `lane_idx`, `slot_idx`, **and `side`**:
        - Player cards (side = "you") stack at the bottom of the lane, at `y = 1200 + slot_idx * 80` (existing)
        - AI cards (side = "ai") stack at the top of the lane, at `y = 2100 - slot_idx * 80` (new)
        - Lane x positions stay the same (195/585/975)

- `main/match/card.script`:
    - Add a script property `side` (string, default "you")
    - On init, store `self.side`, `self.lane_idx`, `self.slot_idx`, `self.card_uid` as before

- `main/ui/hud.gui`:
    - For each lane, add a top region (above the existing player-side region) that will hold AI face-down/revealed card visuals
    - Each lane gets 8 "ai card slot" GUI nodes (parallel to the 8 player slots from Phase 1)
    - AI slot positions in the GUI scene: `y` near top of the lane area, stacking downward
    - **Visually distinguish face-down vs face-up:**
        - Face-down: dark gray box with white "🏈" text in center, no stats visible
        - Face-up: same box+text format as player cards (cost, position, stat, name), but with a red tint instead of green
    - Add a second net-yards pill per lane for the AI's net yards (small, top of lane), distinct from player's (which stays at bottom of lane area)

- `main/ui/hud.gui_script`:
    - Add handler for `HUD_AI_CARDS_SPAWNED`:
        - For each spawned card, render it in the appropriate lane's AI slot at the right `slot_idx`
        - Render as face-down initially
    - Add handler for `HUD_LANE_SUMS_UPDATED`:
        - For each lane in the message, update:
            - The player net-yards pill (existing)
            - The AI net-yards pill (new)
        - When a sum changes from 0, the lane is "live" — visual could update via tween
    - **In 2.2**: After `HUD_AI_CARDS_SPAWNED` is received and processed, the next message will be `HUD_LANE_SUMS_UPDATED` and the AI cards will become face-up at the same time the sums update. There's no separate reveal animation yet — the face-up rendering happens implicitly when `revealed = true` lookups change.
    - **Important**: when `HUD_LANE_SUMS_UPDATED` arrives, the AI cards (and player cards) in the lane should re-render as face-up. The rendering function for a played card should check the card's `revealed` flag from state.

**Acceptance criteria for 2.2:**

- [ ] Project builds and runs
- [ ] Player drags cards face-down into lanes. Lane net-yards pill stays at +0.
- [ ] Tapping END DRIVE:
    - AI cards appear face-down in each lane (visible in the lane's top region)
    - Immediately (no animation), all cards flip face-up
    - Both lane net-yards pills update to show real values (one for player, one for AI)
    - Ball positions animate based on actual `you_net_yards` and `ai_net_yards`
    - Match summary appears with both sides' gains per lane
- [ ] AI plays a reasonable number of cards based on its 12 energy and the heuristic (typically 3-5 cards across the 3 lanes)
- [ ] AI never plays into a lane that's already full (8 cards)
- [ ] Save persistence still works (drives count still increments on return to menu)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 2.3 — Reveal animation

Add the `revealing` phase as a real, animated sequence. AI cards spawn face-down, then each card (both AI and player) flips face-up one by one with animation, with lane sums updating as each card reveals.

**Files to modify:**

- `main/match/match.script`:
    - **Modify `match.end_drive` handler** to drive the reveal animation:
        - Set `phase = "revealing"`
        - Call `cpu.choose_plays(...)` → spawn AI cards face-down via factory + post `hud.ai_cards_spawned`
        - Wait ~0.4 seconds (use `timer.delay`) for AI cards to "settle" face-down (HUD animates them in with a brief scale-up)
        - Call `match_state.reveal_pending_plays()` to get the ordered reveal list (this also flips revealed flags and recomputes sums in state)
        - **But don't post sum updates yet.** Instead, walk through the reveal list one card at a time:
            - For each entry in order, post `hud.reveal_card { lane_idx, side, card_uid, slot_idx, card_data }` to HUD
            - Post `hud.lane_sums_updated` with the new sums for that one lane (so the pill animates progressively as cards reveal)
            - Wait ~0.28 seconds (matching HTML's 280ms stagger)
        - After all cards are revealed (~1.5-2 seconds total for typical 6-8 cards), proceed to drive resolution:
            - Call `match_state.resolve_drive()` and post `hud.lane_resolved` per lane (existing)
            - After resolve animations complete (~1 second), post `hud.match_ended` (existing)
            - Set `phase = "ended"`

- `main/ui/hud.gui_script`:
    - Add handler for `HUD_REVEAL_CARD { lane_idx, side, card_uid, slot_idx }`:
        - Find the GUI node for that card slot
        - Run a flip animation:
            - Scale-X 1 → 0 over 0.14 seconds (`go.EASING_INQUAD`)
            - At midpoint, swap the visual from face-down to face-up
            - Scale-X 0 → 1 over 0.14 seconds (`go.EASING_OUTQUAD`)
        - The total flip animation is ~0.28 seconds — matches the stagger interval
    - `HUD_LANE_SUMS_UPDATED` handler: tween the affected net-yards pill from old value to new (~0.3 seconds via `gui.animate` on the text node, or use a simple `gui.set_text` followed by a brief scale pulse for visual punch)
    - For face-down → face-up swap: the GUI scene has the card slot already in place. The face-down state shows the football icon. The face-up state replaces it with the full card readout (cost, pos, stat, name).
    - **Important detail**: between the time `HUD_AI_CARDS_SPAWNED` is received and the first `HUD_REVEAL_CARD`, AI cards should be visible as face-down. This is the "anticipation" moment — about 0.4 seconds where the player sees AI played some number of cards but can't tell what they are.

- `main/state/match_state.lua`:
    - **Refactor `M.reveal_pending_plays()`**:
        - Instead of fully revealing in one call, return an ordered list of plays to reveal (per the spec in 2.1)
        - Caller (`match.script`) walks this list and calls `M.reveal_single_play(play)` per card
    - **Add `M.reveal_single_play(play)`**:
        - Set the card's `revealed = true`, store base stats, set cur stats
        - Call `try_apply_snap_ability(card)` no-op stub
        - Call `recompute_lane_sums(play.lane_idx)`
        - Return updated lane sums for the affected lane

**Acceptance criteria for 2.3:**

- [ ] Project builds and runs
- [ ] Player plays cards face-down (visible in their lane), lane pill stays at +0
- [ ] Tap END DRIVE:
    - AI cards appear face-down in lanes (brief settle animation ~0.4s)
    - Each card flips face-up with a flip animation, in winner-first order
    - As each card reveals, that lane's net-yards pill animates to its new value
    - All flips complete in ~1.5-2 seconds total
    - Then ball positions animate to new positions (~1 second)
    - Then match summary appears
- [ ] Reveal animation is smooth and the staggering feels deliberate (matches Marvel Snap pacing)
- [ ] Tapping anywhere during the reveal animation does NOT skip or break it (the phase machine should ignore touch during `revealing`)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 2.4 — CLAUDE.md update

Update `CLAUDE.md` with Phase 2 notes:

- Add `Phase 2: complete (AI side + reveal mechanic)` to the Phase log
- Add a new section `## Phase 2 — AI side notes` at the bottom documenting:
    - What was built: AI hand/energy/lane state, `cpu.lua` heuristic ported from HTML, face-down play model for both sides, reveal phase with animation, real net yards formula
    - Key architectural choices:
        - `pending_plays` is the source of truth between play phase and reveal phase
        - Cards always play face-down (both player and AI); reveal happens only at END DRIVE
        - Lane sums (`*_off_sum`, `*_def_sum`, `*_net_yards`) only count revealed cards
        - The "winner reveals first" tiebreaker is implemented even though Phase 2 has no scoring (tied at 0, defaults to player-first)
        - Card abilities have an explicit no-op hook (`try_apply_snap_ability`) in `reveal_single_play` for future implementation
        - The reveal animation is staggered at ~280ms per card to match HTML pacing
    - Intentional stubs: card abilities, scoring, modifiers, synergies, multi-drive cycle, deck/draw/discard, audio
    - Phase 3 follow-ups (likely): scoring (TD/safety/PAT/conversion/pick-6/FG), multi-drive cycle with energy scaling, deck/draw/discard

`// === STOP for developer review ===`

---

## Final acceptance for Phase 2

All of the following must be true:

- [ ] Project opens in Defold editor with no errors
- [ ] Builds and runs on macOS
- [ ] Player can drag cards into lanes face-down; lane pills stay at +0
- [ ] Tapping END DRIVE triggers the full reveal sequence:
    - AI cards appear face-down (~0.4s)
    - Each card flips face-up with animation (~280ms stagger, ~1.5-2s total)
    - Lane sums update progressively as cards reveal
    - Ball positions animate to final positions
    - Match summary appears with both sides' yard gains per lane
- [ ] AI heuristic plays sensibly: more cards in lanes where the player is winning, defense in lanes the player is pushing, kickers near midfield
- [ ] Save persistence still works (drives counter increments and persists)
- [ ] All hard rules respected: drag-only player input, 3 lanes, hardcoded 5-card hands for both sides, 12 energy for both sides, no scoring, no abilities, no modifiers/synergies, no real assets
- [ ] CLAUDE.md updated with Phase 2 notes
- [ ] No third-party Lua libraries added
- [ ] No console errors at any point

## When you're done

Reply with:

1. Summary of what was built per sub-phase
2. Any deviations from the prompt and why
3. Any conventions you established that should be in CLAUDE.md
4. Open items or things you couldn't finish
5. Specific things you'd like the developer to verify on their Mac (since you can't run Defold)

Do not start Phase 3.
