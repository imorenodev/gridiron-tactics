# Draw Pile + Discard Pile Mechanics

## Context

Adding proper card-cycling mechanics to `gridiron-tactics.html`. Currently the player's hand persists indefinitely across drives — cards drawn into hand stay there until played. We're replacing this with a Slay-the-Spire-style draw/discard cycle:

- Fixed hand size: **5 cards** drawn at the start of each drive
- Unplayed cards from previous drive are **discarded** at end of drive
- When draw pile empties, the **discard pile shuffles back in**
- Both player and AI follow these rules

**Re-read CLAUDE.md and inspect the current card-state handling in `gridiron-tactics.html` before editing.** Search for `youHand`, `aiHand`, `youDeck`, `aiDeck` to find the relevant code paths.

This is a significant gameplay change — strategic feel will shift from "hoard your good cards" to "play what you draw, plan around the cycle." Make sure the existing in-match flow still works end-to-end after the change.

---

## Part A: Data model changes

### Add discard piles to state

`newState()` currently creates `youDeck`, `youHand`, `aiDeck`, `aiHand`. Add:

```javascript
state.youDiscard = [];
state.aiDiscard = [];
```

These are arrays of card objects, same shape as deck/hand. Cards move between deck → hand → (played to field OR discarded) → reshuffled to deck.

### Constants

Add a constant near the top of the JS section (near `MAX_ENERGY_BANK`):

```javascript
// Hand size drawn at the start of each drive. Future perks may increase this.
const HAND_SIZE = 5;
```

Do NOT hardcode 5 elsewhere — use the constant everywhere a hand size is referenced. Future perks will read or override this constant.

### Card object identity

Cards must maintain their identity through the cycle. When a card goes deck → hand → discard → deck, it's the **same JavaScript object** (same `uid`). Do not create copies. This matters because:

- The player visually recognizes "oh, my Mahomes legendary came back around"
- Card-specific state (curOff, curDef, abilities) resets correctly because it's the same reference

When a card is **played to the field**, it leaves the cycle entirely (it lives in `lane.youCards` or `lane.aiCards`). It does NOT return to the discard pile after the drive — played cards stay on the field until lane reset, at which point they're removed from the game.

---

## Part B: Core game flow changes

### Initial hand at match start

In `newState()` or the equivalent match-init function, after the deck is set up, **immediately draw the starting hand** for drive 1:

- `drawCardsToHand('you', HAND_SIZE)`
- `drawCardsToHand('ai', HAND_SIZE)`

This means drive 1 begins with the player holding 5 cards (assuming deck has at least 5).

### End-of-drive cycle

The existing end-of-drive flow is roughly:
1. Player taps END TURN
2. AI plays cards
3. Reveal phase (all face-down cards flip)
4. Yardage and scoring phase
5. Next drive: increment `state.turn`, grant energy, draw cards

The new flow must insert a **discard + redraw** step between scoring and the next drive's start:

1. Player taps END TURN
2. AI plays cards
3. Reveal phase
4. Yardage and scoring phase
5. **NEW: Discard phase** — move all cards remaining in `state.youHand` to `state.youDiscard`. Same for AI. Animate (see Part D).
6. **NEW: Draw phase** — draw `HAND_SIZE` cards to each player's hand from their deck. Animate.
7. Next drive: increment `state.turn`, grant energy (now using the existing escalating-carryover logic from previous phase).

The discard phase happens AFTER scoring so the player sees the result of the drive before their hand cycles. The draw phase happens BEFORE the new drive number is shown so the player enters drive N+1 already holding their new hand.

### Helper functions to add

Add these helpers in a logical spot near existing card-handling code:

```javascript
// Draw cards from deck to hand, reshuffling discard back into deck if needed.
// Returns the cards drawn (in order).
function drawCardsToHand(side, count) {
  const deck = (side === 'you') ? state.youDeck : state.aiDeck;
  const hand = (side === 'you') ? state.youHand : state.aiHand;
  const discard = (side === 'you') ? state.youDiscard : state.aiDiscard;
  const drawn = [];
  for (let i = 0; i < count; i++) {
    if (deck.length === 0) {
      // Reshuffle: discard pile becomes new deck (shuffled)
      if (discard.length === 0) break;  // truly out of cards
      reshuffleDiscardIntoDeck(side);
      // Now retry the draw
    }
    if (deck.length === 0) break;  // still empty after reshuffle (impossible if discard had cards)
    const card = deck.shift();
    hand.push(card);
    drawn.push(card);
  }
  return drawn;
}

function reshuffleDiscardIntoDeck(side) {
  const deck = (side === 'you') ? state.youDeck : state.aiDeck;
  const discard = (side === 'you') ? state.youDiscard : state.aiDiscard;
  // Move all cards from discard into deck and shuffle
  while (discard.length > 0) deck.push(discard.shift());
  shuffle(deck);  // use the existing shuffle helper
  if (side === 'you') showReshuffleAnimation();  // visual moment for the player only
}

function discardHand(side) {
  const hand = (side === 'you') ? state.youHand : state.aiHand;
  const discard = (side === 'you') ? state.youDiscard : state.aiDiscard;
  while (hand.length > 0) discard.push(hand.shift());
}
```

### Edge cases (Part B)

1. **Deck has fewer than HAND_SIZE cards remaining + discard has none**: draw as many as available, leave hand smaller than HAND_SIZE. Don't crash. This will rarely happen — only if a player builds a tiny deck or near end of an unusually long match.
2. **Deck empty exactly when reshuffle triggers mid-draw**: handled in the helper above — reshuffle and continue.
3. **Card played from hand directly to field**: removed from hand, added to lane's card array. Does NOT enter discard. This is the existing behavior — verify it still works.
4. **Match ends mid-cycle**: discard piles are discarded with the match (not persisted). `newState()` always creates empty discard piles.

---

## Part C: UI — piles, badges, hand display

### Deck and discard pile UI

The existing "DECK REMAINING: 47" text needs to become a more interactive display with two visible piles. Replace the existing `.deck-info-row` (or whatever it's named) with a new layout:

```
[🂠 DECK 32] ........... HAND ........... [🗑️ DISCARD 13]
```

- **Deck badge** on the left: small icon (face-down card or 🂠 symbol), label "DECK", count
- **Discard badge** on the right: small icon (a discard pile, possibly with a small folded-card visual or 🗑️), label "DISCARD", count
- The hand cards display between them as currently
- Both badges should have a subtle gold/white border, mobile-tap-friendly size (~44x44px minimum tap target)

When a count changes, briefly pulse/scale the badge for visual feedback (200ms scale-bounce animation).

### Tap discard badge → open discard pile modal

Tapping the discard badge opens a modal showing all currently discarded cards:

- Modal title: `DISCARD PILE` with the count: `DISCARD PILE (13 cards)`
- Cards grouped by **drive number** (e.g., section header "After Drive 2", "After Drive 4")
  - Track this via a `discardedOnDrive` field added to cards when they're discarded, OR maintain a parallel `discardLog: [{drive, cards}]` structure. Pick whichever is cleaner.
- Cards displayed at small/medium size in a scrollable grid
- Sticky close button or tap-outside-to-dismiss
- The deck badge should NOT be tappable (deck contents are hidden by design — that's the point of a deck)

### Tooltip for the new piles

Add to TOOLTIPS:

```javascript
TOOLTIPS.deckPile = {
  title: 'DRAW PILE',
  body: 'Cards remaining in your deck. At the start of each drive, you draw up to <strong>' + HAND_SIZE + '</strong> cards into your hand.<br><br>When this pile empties, your <em>discard pile</em> reshuffles into a new draw pile.'
};
TOOLTIPS.discardPile = {
  title: 'DISCARD PILE',
  body: 'Cards you held but didn\'t play. At the end of each drive, your unplayed hand goes here.<br><br>Tap to see what\'s been discarded. When the draw pile is empty, these cards shuffle back in.'
};
```

Add `data-tooltip="deckPile"` and `data-tooltip="discardPile"` to the respective badges.

**Important**: the tap-to-open-modal behavior for the discard badge needs to coexist with the tap-to-tooltip behavior. Use the existing tap-vs-long-press heuristic from the tooltip system, OR make the modal the primary action and remove the tooltip for discard (since the modal IS the explanation). My recommendation: **keep the tooltip on tap, open the modal on a separate "view" button or a long-press**. Or simpler: tap = modal, no tooltip (the icon and label are self-explanatory). Pick the simpler path.

### Update the existing card counts elsewhere

Anywhere the old "DECK: 47" was shown (e.g., the deckCount span in the hand section), update to read from `state.youDeck.length` for deck, and add `state.youDiscard.length` for discard.

---

## Part D: Animations

### End-of-drive discard animation

After scoring resolves and before the new drive starts, animate each card in the hand flying to the discard pile:

- All hand cards simultaneously begin a 600ms arc animation
- Path: from their current hand position → curving up-and-right (or wherever the discard badge sits) → ending at the discard badge position
- During flight: card rotates ~30 degrees, scales down to ~40%, fades to 70% opacity
- Cards stagger their start by 40ms so they don't all move identically (sequential dispatch)
- On completion: card removed from DOM (it now exists logically in `state.youDiscard`)
- Sound: a soft "swoosh" per card via `playSfx('discard')` — use the existing helper or extend it
- Total time for the discard phase: ~800-900ms regardless of hand size (stagger compresses naturally)

### Draw animation for new hand

Immediately after the discard completes:

- For each of the 5 cards drawn, create the new hand card DOM element OFF-SCREEN at the deck badge position
- Stagger their arrival by 80ms each (total ~400ms for 5 cards)
- Each card flies from deck → its slot in the hand area with a smooth arc, scaling from 40% to 100%
- Card lands face-up — no flip animation needed since the player sees their own cards
- Sound: a soft "draw" per card via `playSfx('draw')` — synthesize a brief sine-tone blip
- After all 5 land: brief subtle highlight on the hand area (200ms gold glow fade)

### Reshuffle animation

When `reshuffleDiscardIntoDeck('you')` is called:

- The discard badge pulses dramatically (scale 1.0 → 1.3 → 1.0 over 400ms)
- A "RESHUFFLING DECK" floating text appears centered between the piles for ~1s
- Discard count animates down to 0; deck count animates up to the new total
- Sound: a `playSfx('reshuffle')` — synthesize a quick descending whoosh or shuffled-card swish (maybe a noise burst with rapid frequency drop)
- After the reshuffle, the draw animation proceeds normally

### AI animations

AI's hand isn't visible, so AI's discard/draw is **silent and instant** — no animation, just state update. Only the AI's deck and discard counts update if displayed (they probably aren't — AI piles are usually hidden).

### Reduced-motion behavior

If `prefers-reduced-motion` is set:
- Skip the arc animations entirely; cards just disappear from hand and counts update
- Reshuffle: skip the dramatic pulse, but DO still show the floating "RESHUFFLING DECK" text (informational, not motion)
- All sounds still play (sound isn't motion)

---

## Part E: Integration checks

### Energy carryover still works

The energy carryover mechanic from the previous phase must still function. Verify by manually tracing:

1. Drive 1: gain 1 energy, spend 0, end drive
2. Discard phase runs (hand → discard, new hand drawn)
3. Drive 2 starts: gain 2 energy, total = 1 carried + 2 new = 3

The discard/draw cycle must happen BEFORE energy is granted for the new drive (since the player needs to see their new hand to plan how to spend energy).

### Synergies still work

Synergies trigger when cards are played to the same lane. With the new cycle, players can't hold cards across drives anymore — so synergies are harder to set up (you need both QB and RB in the *same hand*). This is intentional; don't try to fix it. The synergy detection code itself doesn't need changes.

### Snap/field abilities unchanged

Card abilities (`snapDraw`, `fieldBuffOffLane`, etc.) operate on cards already in play. They don't interact with the deck/discard system. No changes needed there.

**Exception**: if any ability has a `snapDraw` effect (drawing a card from the deck), that needs to keep working. With the new system, `snapDraw` should pull from the deck (reshuffling discard if empty). The existing helper `drawCardsToHand` handles this — just call it with `count=1` from the snap ability handler.

### Auto-pick draft fast-forward

The previous fast-forward auto-pick draft has nothing to do with this system. No changes there.

---

## Acceptance checks

- [ ] Match begins with player holding exactly 5 cards (assuming deck has ≥5)
- [ ] At end of every drive, unplayed hand cards visibly fly to the discard pile
- [ ] At start of every drive, 5 new cards visibly fly from the deck into the hand
- [ ] DECK badge and DISCARD badge are both visible and updating correctly
- [ ] Tapping DISCARD badge opens a modal showing all discarded cards grouped by drive
- [ ] When deck reaches 0 cards, discard reshuffles back in with a clear "RESHUFFLING DECK" moment
- [ ] AI follows the same cycle (verify by playing 5+ drives and checking that AI's deck count is decreasing similarly)
- [ ] Energy carryover continues to work correctly across the new cycle
- [ ] Snap abilities that draw cards still function (test with a card that has `snapDraw`)
- [ ] `prefers-reduced-motion` skips arc animations but keeps the reshuffle text and all sounds
- [ ] No JS errors in console during a full match
- [ ] Match end state is clean (deck/hand/discard all cleared on `newState()`)

---

## At end of work

- Run the syntax check from CLAUDE.md
- Add marker: `// === DRAW/DISCARD CYCLE ENABLED ===` near the deck/discard handling code
- **Update CLAUDE.md**:
  - Add `state.youDiscard` and `state.aiDiscard` to the state shape documentation
  - Add a row to the "Subsystems and where they live" table: `Draw/discard cycle — drawCardsToHand, discardHand, reshuffleDiscardIntoDeck`
  - Add to "Common tasks": `"Change hand size" → modify HAND_SIZE constant. To make hand size depend on perks later, wrap it in a function getter.`
  - Add to "Things I would NOT do": `Don't add a "save card from discard" mechanic. The discard cycle is the core tension — circumventing it defeats the purpose.`
- Report to the user with:
  - Summary of the changes
  - List of things to playtest:
    1. Drive 1 starts with 5 cards in hand
    2. Play 2 cards in drive 1 → end drive → see 3 cards fly to discard, 5 new cards fly in
    3. Tap the discard badge → modal opens showing the 3 discarded cards labeled "After Drive 1"
    4. Continue playing until you've seen ~30 cards drawn (about 6 drives) → discard pile should be substantial
    5. Eventually trigger a reshuffle by depleting the deck → confirm the "RESHUFFLING DECK" moment appears
    6. Energy carryover still works correctly (don't spend in drive 1, see 3 energy in drive 2)
    7. AI plays its cards normally; verify AI's behavior hasn't broken

Do not proceed with any further changes without explicit confirmation.
