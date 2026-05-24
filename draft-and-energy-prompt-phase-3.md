# Draft & Energy Improvements — Auto-Pick + Banked Energy

## Context

Phase 2 (escalating rarity, 3+3 pack composition, no-confirm picking, FINAL PICK moment) is complete and playtested. This phase adds two unrelated improvements based on playtester feedback:

1. **Auto-Pick Remaining** button in the draft — for users who want to skip the remaining packs and start playing
2. **Energy carryover** — unspent energy at the end of a drive carries forward to the next drive, capped at 10

**Re-read CLAUDE.md and inspect the current state of `gridiron-tactics.html` before editing.** Look for the `// === PHASE 2 COMPLETE ===` marker and the energy-related code in the game-turn flow.

Both changes are independent. Build them in the order below.

---

## Part A: Auto-Pick Remaining button

### Placement & visual

- Located at the **top of the draft screen**, right side, in the header row alongside the pack number ("PACK 3 OF 10") and the timer
- Visible during every pack of the draft (packs 1 through 10)
- **Style**: small button, secondary visual weight — NOT competing with the cards. Outline style with subtle background, ~60% visual prominence of the primary game buttons
- Label: `AUTO-PICK REMAINING` (full caps, Bebas Neue)
- Small ⏩ icon prefix
- Position: anti-misclick — placed at the top corner where the user's thumb is least likely to land while interacting with cards. Test against the existing 375px viewport.
- Hide the button entirely on **Pack 10** — by definition there's nothing to skip if you're on the last pack. Show the timer and FINAL PICK header without it.

### Confirmation flow (REQUIRED — no instant execution)

Tapping the button opens a confirmation modal:

- Modal title: `SKIP REMAINING PACKS?`
- Body: `Auto-pick the rest of your draft? You'll see your remaining cards flash by in fast-forward, then jump straight to the season hub.<br><br>Highest-rarity card wins each side; ties broken by stat. <em>This cannot be undone.</em>`
- Two buttons: `CANCEL` (left, neutral) and `SKIP IT` (right, gold/primary, the destructive-but-OK action)
- Tapping CANCEL or outside the modal dismisses it without action
- Tapping SKIP IT begins the fast-forward sequence (below)

Use the existing modal system if there is one (check for `.modal` class patterns in CSS); otherwise build a minimal one matching the visual language of the existing how-to-play modal.

### Auto-pick algorithm

For each remaining pack from the current pack number to pack 10:

1. Generate the pack as normal (uses escalating rarity from Phase 2)
2. Among the 3 OFF cards, pick the one with the **highest rarity tier**; ties broken by **highest off stat**. Rarity order: Legendary > Rare > Uncommon > Common.
3. Same logic for the 3 DEF cards (using def stat for tiebreaker).
4. Add both picks to the player's deck.

After all remaining packs are processed, the player's deck should still total exactly 50 cards (or whatever the invariant is at this stage of the codebase — 30 starter + 2 per pack × 10 packs).

### Fast-forward animation (the dopamine preservation)

The skip should *feel like* the player is watching their draft happen at speed, not like they're being yanked to the next screen. Here's the rhythm:

- For each remaining pack, run a **compressed pack-rip sequence at 4x speed**:
  - Fan-in animation: ~80ms (vs ~320ms normal)
  - Flip stagger: ~90ms per card (vs 350ms normal)
  - Spread animation: ~100ms (vs 400ms normal)
  - Pick visual (gold-glow appears on the two auto-picked cards): ~150ms
  - Same-side fade of the un-picked cards: ~100ms
  - Confirm transition (cards fly off to deck, faded cards drift down): ~150ms
  - Total per pack: ~700ms
- Sounds: keep `playSfx('flip')` per card but at reduced volume (multiply gain envelope by 0.4). Keep `rareFlash` and `legendaryHit` at full volume — these are the moments worth preserving.
- The FINAL PICK intro for pack 10: if pack 10 is among the remaining packs, still play its dramatic intro but compressed to ~400ms (vs ~1000ms normal). Sound stays full volume — it's a once-per-run moment.
- During fast-forward, the "AUTO-PICK REMAINING" button is hidden and pack interaction is disabled.
- After the last pack completes, brief 400ms pause, then advance to the season hub.

### Edge cases (Part A)

1. **User taps the button during reveal animation**: don't open the modal until the current pack's reveal is complete. Either queue the action or disable the button during reveal (preferred: disable + slight opacity drop).
2. **User taps button after picking one side but not the other**: their existing pick should be honored for the current pack. The auto-algorithm runs for the un-picked side of the current pack, then proceeds with full auto for packs N+1 through 10.
3. **Pack 1 with no picks yet**: full auto from pack 1 forward. Works the same.
4. **Reduced-motion preference**: skip all the fast-forward animation entirely. Just flash a brief "Auto-picking 7 packs..." toast and jump to the season hub. Audio still plays for rare/legendary picks since those have minimal motion.
5. **Quit during fast-forward**: pressing EXIT or back button cancels the auto-pick and returns to the menu cleanly. No half-state persisted.

### Acceptance checks for Part A

- [ ] Button visible packs 1-9, hidden pack 10
- [ ] Tap → modal opens; CANCEL dismisses; SKIP IT executes
- [ ] Fast-forward animation completes in ~5-7 seconds for a full 7-pack skip
- [ ] Rare and Legendary flashes still visible and audible during fast-forward
- [ ] Final 50-card deck matches what a manual draft would produce (algorithmically — same picks regardless of speed)
- [ ] reduced-motion mode skips animation cleanly
- [ ] Cannot trigger during in-progress reveal

---

## Part B: Energy carryover with flat cap

### Current behavior (to change)

At the start of each drive, `state.youEnergy = state.youEnergyMax` (and same for AI). Unspent energy is overwritten/lost. `state.youEnergyMax` increments by 1 per drive, capping naturally at 8 by drive 8.

### New behavior

- At the start of each drive, **add** the per-drive energy increment to the player's existing energy bank (instead of resetting).
- Cap the resulting energy at a constant `MAX_ENERGY_BANK = 10`.
- This applies symmetrically to both the player and the AI.
- The per-drive increment stays at +1 (drive 1 grants 1, drive 2 grants 1 more, etc.).

### Implementation

**Add a constant at the top of the JS section:**

```javascript
// Maximum banked energy. Future leveling/perk rewards will increase this.
// IMPORTANT: this constant is the single source of truth — do not hardcode 10
// elsewhere. To add a "+1 Energy Capacity" perk later, modify only this value
// (or expose it as a per-match override).
const MAX_ENERGY_BANK = 10;
```

**Refactor the drive-start energy logic:**

Find wherever drive transitions happen (search for `state.youEnergy` assignments, `state.turn++`, and the "new drive" logic). The current pattern is likely something like:

```javascript
state.youEnergyMax++;
state.youEnergy = state.youEnergyMax;
state.aiEnergyMax++;
state.aiEnergy = state.aiEnergyMax;
```

Change it to:

```javascript
state.youEnergy = Math.min(MAX_ENERGY_BANK, state.youEnergy + 1);
state.aiEnergy = Math.min(MAX_ENERGY_BANK, state.aiEnergy + 1);
```

The concept of `energyMax` may still be used elsewhere (for display, for AI's perceived budget). Decide whether to:
- (a) Keep `energyMax` as a separate "this drive's allocation" concept (it still increments by 1 each drive, but `energy` no longer resets to it), or
- (b) Delete `energyMax` entirely if it's only used for the reset logic.

Check usage and pick whichever is cleaner. **My recommendation**: if `energyMax` is only used internally, delete it. If it's displayed anywhere in the UI (e.g., "3/5" style), repurpose its meaning to show "available / cap" — i.e., always display against `MAX_ENERGY_BANK` (so "3/10" early game, "8/10" later, etc.).

### UI updates required

1. **Energy orb display** (`#energyOrb` in the top bar): now shows just the current available energy (the number). The existing implementation likely already does this — verify.
2. **Energy display elsewhere**: if there's a "1/1", "2/2" style display, update it to show "current / MAX_ENERGY_BANK" instead (e.g., "5/10").
3. **Visual signal when at cap**: if the player is sitting at `MAX_ENERGY_BANK`, the energy orb pulses with a subtle gold glow to telegraph "you're at the cap — spend some or you'll waste the next gain". Reuse the existing pulse animation if possible (the "ready" pulse pattern used elsewhere).
4. **Visual signal when energy carried over**: at drive transition, if the player ended the previous drive with unspent energy, briefly show a "+N CARRIED" floating text near the orb (200ms appear, hold 1s, fade out). This makes the new mechanic discoverable.
5. **Tooltip update**: update the `energyOrb` tooltip in the `TOOLTIPS` object to reflect the new behavior:

```javascript
TOOLTIPS.energyOrb = {
  title: 'ENERGY',
  body: 'Energy available to spend on cards.<br><br>You gain <strong>+1 energy</strong> each drive. <em>Unspent energy carries over</em> up to a max of ' + MAX_ENERGY_BANK + '.<br><br>Save up for big plays or spend each drive — your call.'
};
```

(Use string concatenation so it stays in sync with the constant.)

### AI behavior update

The AI's decision-making (`aiMakePlays()` or similar) needs to be aware that it now has carryover. The simplest change: AI continues to play cards greedily up to its current `state.aiEnergy`. With carryover, on big drives it may have 6-8 energy banked and play multiple high-cost cards in one turn. **This is intentional — it adds variety to AI play patterns.** Don't add complex save-up logic; let the existing greedy heuristic benefit from larger pools naturally.

### Edge cases (Part B)

1. **Energy at exactly `MAX_ENERGY_BANK` at end of drive**: the +1 gain is wasted (capped). The orb pulse should make this visible so the player learns to spend before the cap.
2. **AI hits the cap**: same wasted gain. AI's greedy play should usually prevent this, but it's possible in rare configurations.
3. **Card cost reduction from lane modifiers (HURRY-UP, PREVENT D)**: still uses the existing `effectiveCost(card, laneIdx)` logic. Carryover doesn't interact with cost discounts — they're independent.
4. **First drive**: player still starts drive 1 with 1 energy (the +1 increment from 0). Same as before.
5. **Concede / new game**: energy fully resets to 0 on `newState()`. Verify the new state creation explicitly sets `state.youEnergy = 0` and `state.aiEnergy = 0` so the very first drive's increment lands at 1, not 1-plus-leftover-from-a-prior-game.

### Acceptance checks for Part B

- [ ] `MAX_ENERGY_BANK = 10` is the only place the cap value lives in the code
- [ ] Unspent energy visibly carries over between drives (test: play nothing in drive 1, drive 2 starts with 2 energy)
- [ ] Cap correctly enforces 10 (test: play nothing for many drives, never exceed 10)
- [ ] Cap-pulse visual triggers when player is at 10
- [ ] "+N CARRIED" floating text appears when energy carries over
- [ ] AI also benefits from carryover (test: observe AI plays in mid-late game — it should occasionally drop multiple expensive cards in one drive)
- [ ] Tooltip text reflects new mechanic
- [ ] No hardcoded `10` for energy max anywhere outside the constant declaration

---

## At end of all work

- Run the syntax check from CLAUDE.md
- Add marker comments:
  - `// === AUTO-PICK REMAINING ADDED ===` near the new draft button
  - `// === ENERGY CARRYOVER (MAX_ENERGY_BANK) ENABLED ===` near the constant declaration
- **Update CLAUDE.md**:
  - In the "Subsystems and where they live" table, add a row for `Energy carryover (MAX_ENERGY_BANK constant)`
  - In the "Things I would NOT do" or "Common tasks" section, add a note: `Energy cap is a single constant (MAX_ENERGY_BANK). When adding perks/leveling, modify this value (or wrap it in a getter that checks active perks). Do not introduce a parallel cap variable.`
- Report to the user with:
  - Summary of Part A (auto-pick button) and Part B (energy carryover) work
  - List of things to playtest:
    1. Auto-Pick button visible packs 1-9, modal opens cleanly, SKIP IT triggers fast-forward
    2. Fast-forward feels snappy (~5-7 sec for full skip) and you can still see rare flashes
    3. CANCEL on modal works and returns to draft cleanly
    4. Energy carries over (don't spend in drive 1, see 2 energy in drive 2)
    5. Energy caps at 10 visually with pulse
    6. "+N CARRIED" floating text appears on carryover drives
    7. AI plays more aggressively in mid-game thanks to its own carryover
    8. Quitting mid-fast-forward returns to menu cleanly

Do not proceed with any further changes without explicit confirmation.
