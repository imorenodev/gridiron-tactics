# Draft Overhaul: Pack-Rip Dopamine Edition

## Context

You're working in the Gridiron Tactics codebase (single-file HTML/CSS/JS game — read CLAUDE.md first if you haven't). The current draft is functional but feels flat: 25 rounds of picking 1-of-3 OFF and 1-of-3 DEF cards, no animation, no timer, no escalation. Players bounce off it.

We're replacing it with a "Pack Rip" draft modeled on Hearthstone Arena × FIFA Ultimate Team pack-opening, with one twist: **streaks and moments don't grant direct rewards — they shift the rarity probability distribution of subsequent packs.** The game rewards good play with better luck. Hot streaks feel hot.

## Hard rules before you start

1. **Read CLAUDE.md first.** Match the codebase's conventions (single file, no framework, no modules, `function name()` declarations, render-on-mutate pattern, mobile-first).
2. **Build in the phase order below. Do not skip phases or combine them.** After each phase, run the syntax check from CLAUDE.md and stop for the user to playtest before continuing.
3. **Don't rewrite the existing draft system; replace it.** The current `draftState`, `drawDraftOptions`, `selectDraftCard`, `confirmDraftPicks`, and the `#draft` screen HTML are all getting reworked. Keep function names where reasonable so other parts of the code still call them, but their internals change.
4. **The deck-size invariant must hold.** Players must finish the draft with exactly 25 offense + 25 defense = 50 cards. The current draft achieves this via 25 rounds × 2 picks. We're changing to 10 packs × 2 picks (= 20 picks) plus a 30-card starter deck of commons (15 OFF + 15 DEF) granted up front. **Update `buildQuickPlayDeck` / `startSeasonDraft` / wherever decks are assembled to account for this.**
5. **Don't add a backend, modules, or build tooling.** Still a single HTML file.
6. **Don't add dependencies.** No external image/sound URLs that could 404. If you need sounds, use the Web Audio API to synthesize them inline (oscillator + envelope is fine — short blips, not music). If you need particle effects, do them in CSS/DOM.
7. **Don't touch the in-match game logic.** Lanes, scoring, synergies, modifiers, the turn loop — all out of scope. Only the draft.

---

## The new draft design (all phases)

### Structure
- **10 packs total** (down from 25 rounds)
- Each pack = **5 cards revealed**, player picks **2** (one OFF, one DEF) — the other 3 fade away forever
- Player starts the draft with a **30-card starter deck** auto-granted (15 OFF + 15 DEF, all Common, balanced across positions). This guarantees a playable deck even if the player only takes Legendaries during draft.
- After 10 packs × 2 picks, the player has 30 + 20 = **50 cards. Deck complete.**

### Pack composition (escalating rarity by round)
Each card slot in each pack rolls against a rarity distribution. Base distribution by pack number:

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

The final pack (FINAL PICK) is the climax. Bias is real but never guaranteed. Even pack 10 doesn't promise a Legendary — feels earned when it appears, not entitled.

### Streaks & Moments (the rarity-bias system)
This is the core innovation. After each pack is resolved, evaluate streak conditions on the player's picks history. Active streaks modify the *next* pack's rarity distribution only — they expire after one pack unless re-earned.

Streaks add **percentage points** to the next pack's rarity rolls (re-normalize so total = 100%):

| Streak | Trigger | Next pack effect |
|---|---|---|
| **BACK-TO-BACK RARES** | Picked a Rare+ in 2 consecutive packs | +10% Rare, +3% Legendary (taken from Common) |
| **HOT HAND** | Picked Rare+ in 3+ consecutive packs | +20% Rare, +5% Legendary (taken from Common) |
| **DIVERSITY** | Last 3 picks were 3 different teams | +8% Uncommon, +2% Rare (taken from Common) |
| **POSITION STACK** | Last 3 picks include 2+ of the same position | +5% Rare (taken from Common) |
| **HIGH ROLLER** | Drafted a Legendary at any point in the run | Every subsequent pack: +3% Legendary chance, permanent |
| **TRENCH WAR** | Picked 2+ OL or 2+ DL across the run | +10% chance both linemen-positions appear in next pack |
| **EMPTY PACK PITY** | Last pack contained zero Uncommon+ cards | Next pack: +15% Uncommon, +5% Rare (taken from Common). Quiet consolation, no big UI moment. |

Display all active streaks as small badges above the next pack-rip screen. Tapping a badge shows its effect in a tooltip (use the existing tooltip system — `data-tooltip-title` and `data-tooltip-body`).

### Pick timer
- **12 seconds per pack** (starts after all 5 cards have finished revealing).
- 0-7s: calm. 8-10s: timer turns yellow and audibly ticks each second. 11-12s: timer flashes red, urgent tick.
- If timer expires with picks incomplete: auto-pick the highest-stat OFF and highest-stat DEF among remaining cards. Show "AUTO-PICKED" briefly.
- Player can finish early by tapping CONFIRM once both slots are filled, OR by tapping 2 cards if you make the confirm implicit (your call — explicit confirm is probably safer to prevent misclicks; go with that).

### Loss-aversion treatment for unpicked cards
When the player confirms, the 3 unpicked cards **slide downward off-screen with a grayscale fade and 50% opacity drop**. Brief "discarded" text appears beneath them, no harsh sound. Felt but not aggressive.

---

## Phase plan — build in this order

### Phase 1: Pack-rip mechanics + pick timer (the core dopamine)

Build only this in phase 1. No streaks yet, no escalating rarity, no missions. Just transform the draft *feel*.

**What to build:**
- New draft state shape: `draftState = { packNum, totalPacks, currentPack: [5 cards], picks: [], pickedOff: null, pickedDef: null, history: [...], timeLeft, timerInterval }`
- New `#draft` screen layout:
  - **Header**: "PACK 3 OF 10" centered, plus a 12-second timer ring/countdown beneath
  - **5 face-down card backs** fanned across the middle of the screen, rarity-tinted glow on each back (subtly hinting at the rarity inside — gold glow = Legendary, etc., but only AFTER they're being revealed)
  - **Picked slots** at the bottom: two empty card-shaped slots labeled "OFFENSE" and "DEFENSE". Cards animate to these slots when picked.
  - **CONFIRM** button (disabled until both slots filled, then pulsing gold)
- Pack reveal flow on entering a new pack:
  1. Cards spawn face-down, fanned out, with a brief stagger (each card flies in from off-screen)
  2. After 500ms delay, cards begin flipping one-by-one with a 350ms gap between flips
  3. Each flip plays a synthesized "card flip" sound (Web Audio: short noise burst + pitched sine drop)
  4. Rare cards: brief gold flash during flip + slightly stronger sound
  5. Legendary cards: screen shake (subtle, body element transform jitter 200ms) + rainbow shimmer + a "JACKPOT" sound (synthesized chord arpeggio)
  6. Once all 5 are revealed, start the 12s timer.
- Picking flow:
  - Tap a card → it animates into the OFFENSE or DEFENSE slot (auto-routed by `card.side`)
  - Already-picked side: tapping a new card swaps it; the old one returns to the pack
  - Picked cards get a green glow border in the pack lineup
- Timer expiration: auto-pick highest-stat OFF and DEF from remaining cards, show "AUTO-PICKED" toast for 1s, then proceed to next pack
- CONFIRM tap: 
  - The 3 unpicked cards slide down off-screen with grayscale fade
  - The 2 picked cards fly out toward an off-screen "deck" position
  - Brief "+2 to your deck" feedback
  - 600ms delay, then next pack begins

**Synth sound helpers to add (Web Audio API):**
```javascript
function playSfx(type) {
  // types: 'flip', 'rareFlash', 'legendaryHit', 'tick', 'confirm', 'discard'
  // Use AudioContext + OscillatorNode + GainNode for envelope
  // Keep each effect <300ms; total memory cost ~zero
}
```

Build small, focused, no music. Each sound 50-300ms.

**At end of Phase 1:**
- Run the syntax check from CLAUDE.md
- Stop. Add a comment block: `// === PHASE 1 COMPLETE — playtest before continuing to Phase 2 ===`
- Tell the user to playtest and confirm before you continue

---

### Phase 2: Escalating rarity by pack number

**What to build:**
- Implement the rarity distribution table above as `PACK_RARITY_TABLE[packNum]`
- Refactor the card-generation path so the draft uses `generateDraftPack(packNum, streakBonuses)` instead of pulling from a flat pool
- `generateDraftPack(packNum)` returns 5 cards, each rolled independently against `PACK_RARITY_TABLE[packNum]` (no streak bonuses yet — that's Phase 3)
- Position distribution: ensure each pack has at least one OFF and one DEF card (otherwise the player can't fill both slots). If a random roll produces 5 OFF or 5 DEF, re-roll the last card with the opposite side forced.
- The final pack (Pack 10) gets a different screen treatment:
  - Header changes to "**FINAL PICK**" in larger gold text
  - Timer is 15s instead of 12s
  - Brief dramatic intro before card reveal: "FINAL PACK" banner pulses across screen for 1s with a deeper synthesized chord
  - The card backs glow more intensely

**At end of Phase 2:**
- Run syntax check
- `// === PHASE 2 COMPLETE — playtest before continuing to Phase 3 ===`
- Stop for playtest

---

### Phase 3: Streaks & moments (the rarity-bias engine)

**What to build:**
- `state.draftStreaks = { backToBackRares: 0, hotHand: 0, diversity: false, positionStack: false, highRoller: false, trenchWar: false, emptyPackPity: false }`
- After each pack confirm, evaluate streak conditions against `draftState.history` (an array of `{packNum, picks: [card, card]}`)
- Maintain a `getNextPackRarityDistribution(packNum, activeStreaks)` function that:
  1. Starts with base `PACK_RARITY_TABLE[packNum]`
  2. Applies each active streak's percentage shifts
  3. Re-normalizes to sum = 100%
  4. Returns the adjusted distribution
- Use this adjusted distribution in `generateDraftPack`
- Streak UI:
  - Above the pack header, show a horizontal row of streak badges that are currently active for THIS pack
  - Each badge: small icon + name, tappable, uses the existing tooltip system to show the bonus effect
  - Streaks that just activated get a brief "STREAK ACTIVATED" highlight on the previous pack's confirm screen (between packs)
  - HIGH ROLLER once active stays visible for the rest of the draft (permanent bonus indicator)
- Streak persistence:
  - All streaks except HIGH ROLLER expire after the next pack regardless of re-evaluation
  - HIGH ROLLER persists for the rest of the draft
  - Re-earned streaks (BACK-TO-BACK RARES → HOT HAND) just refresh their state
- HOT HAND vs BACK-TO-BACK RARES: only one of these is active at a time. HOT HAND supersedes BACK-TO-BACK RARES.

**Add these tooltip entries:**
```javascript
TOOLTIPS.streakBackToBackRares = { title: '🔥 BACK-TO-BACK RARES', body: 'Two rare-or-better picks in a row earned you a hotter next pack.<br><br>Next pack: <em>+10% Rare chance, +3% Legendary chance</em>.' };
TOOLTIPS.streakHotHand = { title: '🔥🔥 HOT HAND', body: 'Three rare-or-better picks in a row. You\'re on fire.<br><br>Next pack: <em>+20% Rare chance, +5% Legendary chance</em>.' };
// ... etc for all 7 streaks
```

**At end of Phase 3:**
- Run syntax check
- `// === PHASE 3 COMPLETE — playtest before continuing to Phase 4 ===`
- Stop for playtest

---

### Phase 4: Polish

**What to build:**
- **Particle effects** on Legendary reveal: 12-15 small div elements that animate outward from the card position with rotation + fade. Pure DOM, no canvas needed.
- **Streak badge pop animation** when a new streak activates: 400ms scale-bounce
- **Better confirm-screen feedback**: brief summary of the 2 picks ("✨ TOOK ROY MCGRAW (RB) AND HEX VANCE (CB)") before next pack starts
- **Pack progress indicator**: a row of 10 small dots at the very top of the screen, filled = completed, hollow = upcoming, gold pulse on current. Replaces or supplements "PACK 3 OF 10" header.
- **Sound polish pass**: review all the synth sounds and tune their envelopes for better feel. Card flip should be crisp, not muddy. Legendary jackpot should feel like a slot machine win (3-4 note arpeggio).
- **Empty-pack consolation**: if a pack rolls zero Uncommon+ cards (which is possible in early packs), still show full pack-rip, BUT after confirm display a small "BAD LUCK BONUS" toast indicating the EMPTY PACK PITY streak just activated.
- **Reduce motion option respect**: if `prefers-reduced-motion` media query is set, skip screen shake and dampen all animations. Sounds stay.

**At end of Phase 4:**
- Run full syntax check
- Verify the whole flow start-to-finish: enter draft → 10 packs → confirm exits to roster screen with 50 cards
- `// === PHASE 4 COMPLETE — draft overhaul shipped ===`

---

## Edge cases to handle explicitly

These have bitten me before — handle them defensively:

1. **Quit-mid-draft**: if the user backs out of a draft, draftState resets cleanly. No half-state persisted to localStorage. Season draft has a separate flow — check `seasonState` if it's a season draft and behave accordingly (the season run is what gets persisted, not the in-progress draft).
2. **All 5 cards same side**: re-roll one card as enforced above to guarantee both slots can be filled.
3. **Pack 1 with all Commons**: this is fine and intentional. Early packs SHOULD feel "meh" — that's what makes Pack 10 hit.
4. **HOT HAND + HIGH ROLLER stacking**: both can apply simultaneously and DO stack (re-normalize correctly).
5. **Timer running while user is in a tooltip**: pause the timer when the tooltip overlay is showing. Resume on dismiss.
6. **Auto-pick fallback when only one side has cards left**: skip that side (leave slot empty), proceed. Shouldn't happen given edge case #2, but defensive.
7. **Mobile orientation change mid-draft**: just trust the existing CSS responsive layout. Don't add orientation handling.

---

## Acceptance criteria

Before declaring done:
- [ ] Draft completes in ~5 minutes (10 packs × ~30s each)
- [ ] Player finishes with exactly 50 cards (25 OFF + 25 DEF), verified in roster
- [ ] At least one streak triggers in a typical 10-pack run (test with several runs)
- [ ] No JS errors on iOS Safari at viewport widths 375-430px
- [ ] All draft tooltips work — tap streak badges, tap face-up cards
- [ ] Reduced-motion respects the OS preference
- [ ] Quitting and returning to menu mid-draft doesn't corrupt state

When all phases are complete, update CLAUDE.md's "Roadmap" section to mark the draft overhaul as done and note any architectural decisions worth remembering (especially the streaks system since it'll be referenced when adding new ones later).

Now read CLAUDE.md, scan the existing draft code, and begin Phase 1.
