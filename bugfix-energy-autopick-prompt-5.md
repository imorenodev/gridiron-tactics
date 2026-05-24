# Bug Fixes — Energy Gain, Auto-Pick Button State, Fast-Forward Speed

## Context

Three playtest bugs to fix in `index.html`. Re-read CLAUDE.md if it's been a while.

These are surgical fixes — do not refactor surrounding code. Bug #1 is a design bug (wrong math); bugs #2 and #3 are smaller polish issues.

---

## Bug 1: Energy gain doesn't scale by drive number

### What's happening (the bug)

The energy carryover system added in the previous phase grants a flat **+1 energy per drive**, regardless of drive number. So drive 1 grants 1 energy, drive 2 grants 1 more, drive 8 grants 1 more. This makes the late game feel underpowered.

The original game (before carryover) used **escalating energy**: drive N granted N energy total (drive 1 = 1, drive 2 = 2, drive 8 = 8). My carryover refactor silently broke this curve.

### The fix

Restore **escalating per-drive gain** while keeping the carryover and the cap.

- Drive 1: gain **+1** energy
- Drive 2: gain **+2** energy
- Drive 3: gain **+3** energy
- ...
- Drive N: gain **+N** energy

Unspent energy still carries over. The total cap is still `MAX_ENERGY_BANK = 10`.

### Worked example (what the player expects to see)

| Drive | Spent prev drive | Energy at drive start |
|---|---|---|
| 1 | — | 0 + 1 = **1** |
| 2 | 0 | 1 carried + 2 new = **3** |
| 3 | 0 | 3 carried + 3 new = 6 capped at... wait, **6** (under cap) |
| 4 | 0 | 6 + 4 = **10** (hit cap, 0 wasted) |
| 5 | 0 | 10 + 5 = **10** (5 wasted to cap) |
| 5 (alt) | 3 in drive 4 | 7 + 5 = **10** (2 wasted) |

The cap stays at 10 (which is intentionally low enough that hoarding all 8 drives is impossible — you must spend along the way).

### Implementation

Find where the previous fix wrote:

```javascript
state.youEnergy = Math.min(MAX_ENERGY_BANK, state.youEnergy + 1);
state.aiEnergy = Math.min(MAX_ENERGY_BANK, state.aiEnergy + 1);
```

Change the `+ 1` to the current drive number. After `state.turn` has been incremented for the new drive (verify the order — the increment must happen BEFORE energy is granted, OR you use `state.turn + 1`, depending on where in the flow this sits):

```javascript
const gain = state.turn;  // drive 1 grants 1, drive 2 grants 2, etc.
state.youEnergy = Math.min(MAX_ENERGY_BANK, state.youEnergy + gain);
state.aiEnergy = Math.min(MAX_ENERGY_BANK, state.aiEnergy + gain);
```

**Critical**: verify whether `state.turn` represents "the drive that just ended" or "the drive about to start" at this point in the flow. Trace through `endTurn()` and find the moment energy is granted. The gain should match the drive that is **about to be played**, not the one that just finished. If `state.turn` is the just-finished drive, use `state.turn + 1` (and don't exceed 8, even defensively).

### Update the "+N CARRIED" floating text logic

The previous phase added a "+N CARRIED" indicator when energy carried over. That logic still works — it just needs to display the actual carried amount, not assume +1. Check the implementation:

```javascript
// Before the new gain is applied:
const carried = state.youEnergy;  // whatever the player ended last drive with
if (carried > 0) {
  showFloatingText('+' + carried + ' CARRIED');  // or however it's named
}
```

If the existing implementation hardcodes "+1 CARRIED", change it to the actual carried value.

### Update the tooltip text

The `TOOLTIPS.energyOrb` body was updated to mention "+1 each drive" — this is now wrong. Change it to reflect the new scaling:

```javascript
TOOLTIPS.energyOrb = {
  title: 'ENERGY',
  body: 'Energy available to spend on cards.<br><br>Each drive grants <strong>energy equal to the drive number</strong> — drive 1 gives +1, drive 2 gives +2, all the way up to +8 on drive 8.<br><br><em>Unspent energy carries over</em> up to a max of ' + MAX_ENERGY_BANK + '. Spend wisely or hoard for big plays.'
};
```

### Acceptance for Bug 1

- [ ] Spend 0 in drive 1, drive 2 begins with **3 energy** (1 carried + 2 new)
- [ ] Spend 0 in drives 1-3, drive 4 begins with **10 energy** (1+2+3+4 = 10, hits cap)
- [ ] Spend 0 in drives 1-4, drive 5 begins with **10 energy** (cap held, 4 wasted)
- [ ] "+N CARRIED" shows the actual carried amount (e.g., "+5 CARRIED" if you ended last drive with 5 unspent)
- [ ] Energy orb pulses at cap (this already works from previous phase)
- [ ] AI also receives escalating gain symmetrically — verify by watching late-game AI plays drop multiple expensive cards

---

## Bug 2: Auto-Pick button incorrectly disabled

### What's happening (the bug)

The "AUTO-PICK REMAINING" button at the top of the draft screen is only active when a card is selected. It should be active **any time the draft is in progress and packs remain**, regardless of whether the player has picked anything in the current pack.

### The fix

Find the auto-pick button's enabled/disabled logic. It's probably gated on a condition like `draftState.pickedOff && draftState.pickedDef` or `selectedCard !== null`. Remove that gating.

The button should be **enabled** whenever ALL of the following are true:

- The draft screen is active
- The current pack number is less than 10 (the button is already hidden on pack 10 per previous spec)
- The draft is not currently in the middle of fast-forwarding (i.e., the user hasn't already initiated auto-pick)
- The pack's card reveal animation is complete (the existing "disable during reveal" behavior — keep this)

That's it. No requirement for any card to be selected.

### Practical change

The button should look identical visually but become tappable from the moment the pack's reveal completes. Check the CSS — if there's a `disabled` class or `aria-disabled` attribute applied based on selection state, remove that coupling.

### Acceptance for Bug 2

- [ ] Pack reveal completes → button is immediately tappable (no card selection needed)
- [ ] Tapping with zero picks → confirmation modal opens, SKIP IT works correctly (auto-picks all remaining packs from current onward)
- [ ] Tapping with one side picked → confirmation modal opens, SKIP IT honors that pick for current pack and auto-picks the rest (per the existing edge case #2 from previous prompt)
- [ ] Tapping with both sides picked → still works (the 600ms grace period might be active; either cancel it cleanly or just override and run auto-pick on remaining packs)
- [ ] Button is correctly disabled only during the fan-in/flip reveal sequence and during fast-forward itself

---

## Bug 3: Auto-Pick fast-forward is too fast

### What's happening (the bug)

The 4x-speed fast-forward animation goes by so quickly the player can't see the rare/legendary moments register. Reduce the speed by 50% — make it 2x speed instead of 4x.

### The fix

Find the fast-forward timing constants from the previous prompt. They were specified as:

- Fan-in animation: ~80ms (vs ~320ms normal)
- Flip stagger: ~90ms per card (vs 350ms normal)
- Spread animation: ~100ms (vs 400ms normal)
- Pick visual: ~150ms
- Same-side fade: ~100ms
- Confirm transition: ~150ms
- Total per pack: ~700ms

**Multiply each of these by 1.5** to slow down by 50%:

- Fan-in animation: **~120ms**
- Flip stagger: **~135ms per card**
- Spread animation: **~150ms**
- Pick visual: **~225ms**
- Same-side fade: **~150ms**
- Confirm transition: **~225ms**
- **Total per pack: ~1050ms**

For a 10-pack full auto-skip, total time goes from ~7 seconds to ~10.5 seconds. Still snappy, but enough breathing room to see what's happening.

The FINAL PICK intro (compressed to ~400ms in the previous spec) should also be slowed proportionally to ~600ms.

### Sound balance reminder

The previous spec said sounds during fast-forward play `flip` at 40% volume but `rareFlash` and `legendaryHit` at full. **Keep that.** The slower pacing now gives those moments enough room to actually be heard.

### Acceptance for Bug 3

- [ ] Full auto-skip from pack 1 takes ~10-11 seconds (verify with stopwatch or `console.time`)
- [ ] When a Legendary appears during fast-forward, you can see and hear it clearly
- [ ] When a Rare appears, the gold flash is visible long enough to register
- [ ] FINAL PICK intro (if pack 10 is in the skip) plays with audible drama, ~600ms long

---

## At end of work

- Run the syntax check from CLAUDE.md
- Add or update marker: `// === ENERGY GAIN: ESCALATING + CARRYOVER ===` near the energy logic
- **Update CLAUDE.md** if energy mechanics are described anywhere — specifically the "Subsystems and where they live" entry for energy, and the "Common tasks" entry for changing scoring rules. The new behavior is "drive N grants N energy, carryover up to MAX_ENERGY_BANK".
- Report to the user with:
  - Summary of each bug fix
  - Confirmation that the energy curve now scales (drive 1 = 1, drive 2 = 2, etc.)
  - List of things to playtest:
    1. Spend nothing in drive 1 → drive 2 starts with 3 energy
    2. Spend nothing in drives 1-3 → drive 4 starts at the cap (10)
    3. Auto-pick button is tappable as soon as cards finish revealing (no need to select first)
    4. Auto-pick fast-forward is noticeably slower and you can see rare moments
    5. AI plays bigger cards in late drives (drives 6-8) thanks to its own energy curve

Do not proceed with any further changes without explicit confirmation.
