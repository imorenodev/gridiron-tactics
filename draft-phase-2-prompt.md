# Draft Overhaul — Phase 2 (with Phase 1 tweaks first)

## Context

Phase 1 of the pack-rip draft is complete and playtested. Before building the escalating rarity system, the user has three UX refinements from playtesting that must ship first. These are tweaks to Phase 1 code, then we proceed with the planned Phase 2 work.

**Re-read CLAUDE.md and the existing Phase 1 implementation in `gridiron-tactics.html` before editing.** The Phase 1 marker comment is your starting point — look for `// === PHASE 1 COMPLETE ===` and read the surrounding draft code.

---

## Part A: Phase 1 tweaks (do these first)

### Tweak 1: Pack composition is now exactly 3 OFF + 3 DEF (6 cards)

Current: 5 cards with a min-1-of-each-side guarantee, sometimes 4 DEF + 1 OFF.
New: **Exactly 3 offense cards and exactly 3 defense cards per pack. Always.**

**Implementation:**
- Modify `generateDraftPack(packNum)` (or whatever it's called in Phase 1) so it generates 3 OFF cards and 3 DEF cards independently, then concatenates them. No more "re-roll if all same side" — the composition is enforced by construction.
- Rarity rolls still happen per card, independent. (Phase 2 escalating rarity, below, applies the same way to each.)
- Update any places that assume `pack.length === 5`. Use a constant `CARDS_PER_PACK = 6` if it isn't one already.
- The deck-size invariant still holds: 30 starter + 10 packs × 2 picks (still 1 OFF + 1 DEF per pack) = 50 cards.

### Tweak 2: Spread the cards out after the flip sequence

Current: Cards stay in their fanned position after flipping. Overlapping, harder to read.
New: After all 6 cards finish flipping face-up, they animate into a **clean spread-out layout** so the player can clearly see all options before picking.

**Implementation:**
- After the last card's flip animation completes (use a `Promise.all` or sequential `setTimeout`), trigger a "spread" transition.
- Layout: **two rows of 3 cards each**, OFFENSE row on top (orange-tinted background label "🟧 OFFENSE — pick one"), DEFENSE row on bottom (blue-tinted background label "🟦 DEFENSE — pick one"). The rows visually group the choices.
- The transition from fan → spread should be a single CSS transform animation, ~400ms ease-out. Cards translate to their new grid positions simultaneously.
- On viewports ≤480px (mobile), card size shrinks proportionally to fit 3 across with gaps. Aspect ratio stays 3:4. Use `grid-template-columns: repeat(3, 1fr); gap: 8px;` or similar.
- The picked slots at the bottom of the screen (OFFENSE slot, DEFENSE slot) are removed in the next tweak, so plan the layout without them.

### Tweak 3: No confirm button — pick-by-tap with fade feedback

Current: Tap to fill OFFENSE/DEFENSE slot, then tap CONFIRM button.
New: **Tap a card to pick it. Same-side alternatives immediately fade. Both sides picked → pack auto-advances after a 600ms grace period.**

**Implementation:**

- Remove the CONFIRM button entirely from the DOM and CSS.
- Remove the picked-slots area at the bottom (the dedicated OFFENSE/DEFENSE slot rectangles). The picked card stays in its pack-spread position, just visually marked as picked.
- New per-card states after the spread completes:
  - **AVAILABLE**: full color, slight hover/tap scale on touch
  - **PICKED**: full color + glowing gold border + subtle scale-up (~1.05) + "✓ PICKED" badge top-right + soft gold halo around the card
  - **FADED**: same-side alternative cards once a pick is made → 35% opacity + grayscale 60% + non-interactive cursor (but see swap behavior below)
- Pick interaction:
  - Tap a card → it becomes PICKED. The other 2 cards on its side immediately animate to FADED (300ms transition). Play `playSfx('pick')`.
  - **Swap behavior**: tapping any of the FADED same-side cards swaps the pick — the new card becomes PICKED, the previously-picked card returns to FADED. This gives the player a take-back without an explicit confirm step.
  - Tapping a card on the OTHER side that has its own picks works independently.
- Auto-advance:
  - When BOTH sides have a picked card, start a **600ms grace period** during which the player can still swap.
  - During the grace period, show a subtle "LOCKING IN..." text fade-in beneath the cards. If the player swaps during this window, cancel the timer and restart it on next pick.
  - When the 600ms elapses with no further interaction, run the existing confirm flow (animate picked cards toward deck, fade unpicked cards downward, advance to next pack). Play `playSfx('confirm')`.
- The 12-second pick timer still runs. If it expires before both sides are picked, auto-pick remaining sides as before. If both sides are picked but the player keeps swapping past the 12s mark, accept the current state immediately and advance (don't penalize them for indecision after they've made valid picks).

**Edge cases:**
- If the user picks the OFFENSE side first, then the timer expires before they pick DEFENSE → auto-pick the highest-stat DEFENSE card from the available 3.
- If they swap during the grace period: cancel the auto-advance timer and visual indicator. They get a fresh 600ms after their next change.
- Picked cards from the *same side* swap cleanly — no flicker, no double-pick state.

**At end of Part A:**
- Run the syntax check from CLAUDE.md (`node -e "..."`)
- Add a comment block above the modified Phase 1 section: `// === PHASE 1 TWEAKS APPLIED ===`
- **DO NOT STOP.** Continue directly to Part B (the original Phase 2 work).

---

## Part B: Phase 2 — Escalating rarity by pack number

This is the originally-planned Phase 2 from the draft-overhaul prompt, unchanged in design.

### Rarity distribution table

Each card slot rolls against this table, indexed by pack number. (Reminder: each pack is now 3 OFF + 3 DEF, but rarity rolls happen per card independent of side.)

| Pack | Common | Uncommon | Rare | Legendary |
|---|---|---|---|---|
| 1   | 80% | 18% | 2%  | 0%  |
| 2   | 75% | 22% | 3%  | 0%  |
| 3   | 70% | 25% | 5%  | 0%  |
| 4   | 60% | 30% | 9%  | 1%  |
| 5   | 50% | 35% | 13% | 2%  |
| 6   | 40% | 38% | 18% | 4%  |
| 7   | 30% | 40% | 24% | 6%  |
| 8   | 20% | 40% | 30% | 10% |
| 9   | 10% | 38% | 38% | 14% |
| 10  | 0%  | 30% | 50% | 20% |

### Implementation

- Add a constant `PACK_RARITY_TABLE` at the top of the draft section. Use an array indexed by pack number (1-based, so `PACK_RARITY_TABLE[1]` is pack 1's distribution; index 0 is unused or mirrors index 1).
- Each entry is an object: `{ common, uncommon, rare, legendary }` with values summing to 100.
- Create a `rollRarity(distribution)` helper: rolls a 0-99 random integer and returns the rarity name based on cumulative thresholds.
- Modify `generateDraftPack(packNum)` to use `rollRarity(PACK_RARITY_TABLE[packNum])` when generating each of the 6 cards. The existing card-generation pipeline (which already knows how to roll position, stats, abilities by rarity) should accept the pre-determined rarity. If the current `generateCard` rolls rarity internally, refactor it to accept an optional `forcedRarity` parameter so the draft can override the roll.
- The PACK_RARITY_TABLE applies *only* to draft packs. The starter deck stays all-Common. Quick play decks and AI opponent decks keep whatever rarity logic they had pre-Phase-2.

### Final pack (Pack 10) special treatment

When `packNum === 10`:
- Header text changes from "PACK 10 OF 10" to a larger "**FINAL PICK**" in gold, all caps, with subtle pulsing glow.
- Before the cards reveal, a 1-second intro plays:
  - A "FINAL PACK" banner sweeps across the screen (translateX from off-left to off-right, 1s ease-in-out)
  - A deeper synthesized chord plays via `playSfx` — extend the helper to support a `'finalIntro'` type (3-note descending minor arpeggio, slightly longer envelope than the existing `legendaryHit`).
  - Optional: very subtle background dim during the intro to focus attention.
- Pick timer is **15 seconds** instead of 12.
- Card backs glow more intensely during the fan-in (boost the rarity glow effect by ~30%).
- After the cards spread, an extra subtle gold haze surrounds the OFFENSE and DEFENSE rows.

### Edge cases (Phase 2 specific)

- Pack 10 rarity table has 0% Common. This is intentional — the final pack is always at least an Uncommon. If for some reason a Common slips through (rounding bug, etc.), allow it; just ensure the rarity roll math is correct.
- `prefers-reduced-motion`: skip the FINAL PACK banner sweep, just show a static "FINAL PICK" label. Sounds still play.

### Acceptance checks for Phase 2

- [ ] Pack 1 produces mostly commons; rare cards almost never appear
- [ ] Pack 10 produces no commons; ~20% of pack 10 cards are legendary across multiple test runs
- [ ] FINAL PICK intro plays correctly and feels distinct from earlier packs
- [ ] Each pack still has exactly 3 OFF + 3 DEF cards
- [ ] Deck-size invariant still holds: 50 cards at end of draft

---

## At end of all Part B work

- Run syntax check
- Add marker: `// === PHASE 2 COMPLETE — playtest before continuing to Phase 3 ===`
- Stop. Report to the user with:
  - Summary of tweaks applied (Part A)
  - Summary of escalating rarity work (Part B)
  - List of things to playtest specifically:
    1. Every pack has exactly 3 OFF + 3 DEF — confirm by playing through 10 packs and observing
    2. Cards spread cleanly into 2 rows of 3 after reveal
    3. Picking a card fades the same-side alternatives; swap-by-tapping works
    4. 600ms grace period before auto-advance feels natural
    5. Pack 1 is mostly commons; pack 10 has visible legendaries appearing
    6. FINAL PICK intro on pack 10 is dramatic but not annoying
    7. No CONFIRM button anywhere
    8. Reduced-motion mode dampens animations correctly

Do not proceed to Phase 3 (streaks & rarity bias) without explicit confirmation.
