# Scrollable Hand + Coin Flip 2-Point Conversion

## Context

Two unrelated changes in `gridiron-tactics.html`. Re-read CLAUDE.md before editing.

These are independent — build them in the order below.

---

## Part A: Horizontally scrollable hand

### Why this matters

Currently the hand container uses `overflow-x: auto` with `justify-content: center`, which works fine for 5 cards but breaks down with larger hands. With perks like Big Hand (+1) and future perks possibly pushing hand size to 6, 7, or more, the cards either shrink uncomfortably or overflow awkwardly. We need clean horizontal swipe-scrolling that keeps card size constant.

### The challenge

The hand area already has horizontal overflow scrolling capability, but there's a **gesture conflict**: the drag-to-play system uses `pointerdown` on each card with no movement threshold, so any horizontal swipe on a card immediately becomes a drag attempt. We need to discriminate: small initial horizontal movement = scroll, otherwise = drag.

### Implementation

#### 1. Update hand container CSS

Find the `.hand` rule (currently around line 720):

```css
.hand {
  display: flex; gap: 5px; overflow-x: auto; padding: 2px;
  scrollbar-width: none;
  justify-content: center;
}
```

Replace with:

```css
.hand {
  display: flex;
  gap: 5px;
  overflow-x: auto;
  overflow-y: hidden;
  padding: 2px 12px;  /* extra horizontal padding so edge cards aren't flush */
  scrollbar-width: none;
  -webkit-overflow-scrolling: touch;
  scroll-behavior: smooth;
  scroll-snap-type: x proximity;  /* gentle snap, not aggressive */
}
.hand-card {
  scroll-snap-align: start;
  flex-shrink: 0;  /* prevent shrinking when many cards */
}
/* Edge fade affordances: subtle gradients hinting at off-screen content */
.hand-wrapper {
  position: relative;
}
.hand-wrapper::before,
.hand-wrapper::after {
  content: '';
  position: absolute;
  top: 0; bottom: 0;
  width: 16px;
  pointer-events: none;
  z-index: 2;
  transition: opacity 0.2s;
}
.hand-wrapper::before {
  left: 0;
  background: linear-gradient(90deg, rgba(0,0,0,0.7) 0%, transparent 100%);
  opacity: 0;
}
.hand-wrapper::after {
  right: 0;
  background: linear-gradient(270deg, rgba(0,0,0,0.7) 0%, transparent 100%);
  opacity: 0;
}
.hand-wrapper.scroll-left::before { opacity: 1; }
.hand-wrapper.scroll-right::after { opacity: 1; }
```

The `justify-content: center` is removed. Cards now start from the left edge. For 5 or fewer cards, this means they appear left-aligned — that's fine because the leveling system will push hand sizes higher, and consistent layout beats centered-or-not-depending-on-count.

If you'd prefer the cards centered when they fit and scroll when they don't, use `justify-content: safe center` instead of removing it — this is a modern CSS feature where center-alignment is abandoned when overflow occurs.

#### 2. Wrap the `<div class="hand" id="hand">` element

Wrap it with `<div class="hand-wrapper">` so the edge-fade pseudo-elements have a positioning context:

```html
<div class="hand-wrapper" id="handWrapper">
  <div class="hand" id="hand"></div>
</div>
```

#### 3. Add scroll-shadow JS to toggle the fade classes

After the existing render code, add a scroll listener that toggles the edge-fade visibility based on scroll position:

```javascript
function updateHandScrollShadows() {
  const wrapper = document.getElementById('handWrapper');
  const hand = document.getElementById('hand');
  if (!wrapper || !hand) return;
  const scrollLeft = hand.scrollLeft;
  const maxScroll = hand.scrollWidth - hand.clientWidth;
  wrapper.classList.toggle('scroll-left', scrollLeft > 4);
  wrapper.classList.toggle('scroll-right', scrollLeft < maxScroll - 4);
}

// Wire up on mount (once) and after every renderHand call:
document.addEventListener('DOMContentLoaded', () => {
  const hand = document.getElementById('hand');
  if (hand) hand.addEventListener('scroll', updateHandScrollShadows);
});
```

Call `updateHandScrollShadows()` at the end of `renderHand()` so the shadows update when cards are added/removed.

#### 4. Gesture discrimination: scroll vs drag

This is the trickiest part. The current `startDrag(e, card, sourceEl)` is called from `pointerdown` and immediately commits to a drag. We need to introduce a **movement threshold** — only commit to drag after the pointer moves more than a threshold AND the movement is mostly vertical or diagonal-up (not purely horizontal).

Modify the card's pointer handling in `renderHand()`. Find where `el.addEventListener('pointerdown', e => startDrag(e, card, el))` is set.

Replace with a deferred-start system:

```javascript
// In renderHand, when wiring up a card's drag:
el.addEventListener('pointerdown', e => prepareDrag(e, card, el));
```

Add this new prepareDrag function near startDrag:

```javascript
// Tracks a pending drag — pointer is down but we haven't committed yet
let pendingDrag = null;
const DRAG_THRESHOLD_PX = 8;
// Drag commits when movement exceeds threshold AND is more vertical than horizontal
// (or moves up — moving up = toward the field, clearly a drag intent)

function prepareDrag(e, card, sourceEl) {
  if (state.busy) return;
  // Don't preventDefault here — let the browser potentially start a scroll
  pendingDrag = {
    card, sourceEl, pointerId: e.pointerId,
    startX: e.clientX, startY: e.clientY,
    moved: false
  };
  sourceEl.addEventListener('pointermove', onPrepareDragMove);
  sourceEl.addEventListener('pointerup', onPrepareDragEnd);
  sourceEl.addEventListener('pointercancel', onPrepareDragEnd);
}

function onPrepareDragMove(e) {
  if (!pendingDrag || pendingDrag.pointerId !== e.pointerId) return;
  const dx = e.clientX - pendingDrag.startX;
  const dy = e.clientY - pendingDrag.startY;
  const adx = Math.abs(dx);
  const ady = Math.abs(dy);
  const dist = Math.sqrt(dx*dx + dy*dy);
  
  if (dist < DRAG_THRESHOLD_PX) return;  // not moved enough yet
  
  // Decide: mostly horizontal = scroll (let browser handle), otherwise = drag
  // Mostly horizontal means: dx > dy AND dy is small
  const mostlyHorizontal = adx > ady * 1.5;
  
  // Tear down the prepare listeners — decision made
  pendingDrag.sourceEl.removeEventListener('pointermove', onPrepareDragMove);
  pendingDrag.sourceEl.removeEventListener('pointerup', onPrepareDragEnd);
  pendingDrag.sourceEl.removeEventListener('pointercancel', onPrepareDragEnd);
  
  if (mostlyHorizontal) {
    // It's a scroll. Let the browser take over. Do nothing.
    pendingDrag = null;
    return;
  }
  
  // Commit to drag — call the existing startDrag, then forward the move
  const pd = pendingDrag;
  pendingDrag = null;
  startDrag(e, pd.card, pd.sourceEl);
  // The move event has already happened. startDrag's onDragMove handler is now attached.
  // Trigger one move immediately to position the ghost correctly:
  onDragMove(e);
}

function onPrepareDragEnd(e) {
  if (!pendingDrag) return;
  // Pointer up without moving enough — treat as a tap (tooltip system already handles)
  pendingDrag.sourceEl.removeEventListener('pointermove', onPrepareDragMove);
  pendingDrag.sourceEl.removeEventListener('pointerup', onPrepareDragEnd);
  pendingDrag.sourceEl.removeEventListener('pointercancel', onPrepareDragEnd);
  pendingDrag = null;
}
```

**Critical considerations:**

- The hand-card already has `touch-action: none` in its current CSS. **Change it to `touch-action: pan-x`** so the browser allows horizontal scrolling but doesn't allow other gestures to interfere.
- The `.hand` container needs no special `touch-action` — it'll allow horizontal pan as expected because the cards now permit it.
- The tooltip system also listens to `pointerdown` on hand-cards (via the global capture-phase listener). The tap-detection threshold (8px, 300ms) should still work because the deferred drag doesn't interfere with tooltip's listeners.

### Edge cases for Part A

1. **Few cards (≤5)**: hand should look natural. With `padding: 2px 12px` and left-aligned cards, 3 cards just sit at the left with the rest of the area empty. If you prefer them centered, use `justify-content: safe center` in the CSS — modern browsers center when no overflow, abandon centering when overflow occurs.
2. **Hand size = 1**: one card sits at the left. No visual issue.
3. **Hand size = 0**: empty hand. No cards rendered, no scroll possible. Edge fades both stay off.
4. **Reduced-motion preference**: keep scrolling functional, just remove `scroll-behavior: smooth`. Use a media query.
5. **Drag from a partially-visible card**: works fine — the drag ghost is attached to `document.body` and positioned by `e.clientX/Y`. Even if the source card is half-off-screen, the drag works.

### Acceptance for Part A

- [ ] With 5 cards, hand displays normally
- [ ] With 6+ cards (test via DevTools: temporarily push extra cards into `state.youHand`), the hand becomes horizontally scrollable
- [ ] Swiping horizontally on a card scrolls the hand, doesn't trigger a drag
- [ ] Swiping vertically (or diagonally up toward the lanes) on a card triggers a drag, doesn't scroll
- [ ] Edge fade gradients appear when there's content to scroll to
- [ ] Tapping a card (no movement) still shows the tooltip
- [ ] Card sizes remain constant — cards do not shrink to fit
- [ ] Scrolling feels smooth and responsive on mobile

---

## Part B: Coin flip replaces dice roll for 2-point conversion

### What's changing

The current 2-point conversion mechanic rolls 2d6 and succeeds on 7+ (about 58% chance). Replace with a 50/50 coin flip where the player **chooses heads or tails**, then a coin animates and lands on a random side. Match = conversion succeeds.

The conversion modal already exists. We're swapping out the dice UI for a coin UI but keeping the rest of the flow intact.

### Visual design

The coin should feel weighty and fun. A simple but polished implementation:

- A circular gold "coin" element, 80px diameter
- Two faces: HEADS (a stylized H or a football icon) and TAILS (a stylized T or a goalpost icon)
- 3D flip animation using CSS `transform: rotateY(...)` with `transform-style: preserve-3d`
- Spins for ~1.4 seconds before landing
- Lands face-up showing the result
- Win = green flash + "CONVERTED!" + 2 pts added
- Loss = red flash + "NO GOOD" + just the PAT (7 pts total from TD + PAT)

### HTML changes

Find the existing `#diceArea` block in the conversion modal:

```html
<div id="diceArea" style="display:none;">
  <div class="dice-container">
    <div class="dice" id="dice1">?</div>
    <div class="dice" id="dice2">?</div>
  </div>
  <div id="diceResult" style="font-family: 'Bebas Neue'; font-size: 20px; color: #ffb800; margin: 12px 0;"></div>
</div>
```

Replace with:

```html
<div id="coinArea" style="display:none;">
  <div class="coin-prompt" id="coinPrompt">CALL IT</div>
  <div class="coin-choice-buttons" id="coinChoiceButtons">
    <button class="coin-call-btn" onclick="callCoin('heads')">HEADS</button>
    <button class="coin-call-btn" onclick="callCoin('tails')">TAILS</button>
  </div>
  <div class="coin-container" id="coinContainer" style="display:none;">
    <div class="coin" id="coinElement">
      <div class="coin-face coin-heads">H</div>
      <div class="coin-face coin-tails">T</div>
    </div>
  </div>
  <div id="coinResult" style="font-family: 'Bebas Neue'; font-size: 20px; color: #ffb800; margin: 12px 0;"></div>
</div>
```

### CSS

Add to the existing styles (replace or remove the `.dice` styles entirely):

```css
.coin-prompt {
  font-family: 'Bebas Neue', sans-serif;
  font-size: 18px; letter-spacing: 2px;
  color: #ffb800; margin-bottom: 12px;
}
.coin-choice-buttons {
  display: flex; justify-content: center; gap: 12px; margin-bottom: 16px;
}
.coin-call-btn {
  background: linear-gradient(180deg, #2a6a4a 0%, #144a2a 100%);
  color: #fff;
  border: 1px solid #4aff8a;
  padding: 12px 24px;
  font-family: 'Bebas Neue', sans-serif;
  font-size: 18px; letter-spacing: 2px;
  cursor: pointer; border-radius: 3px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.5);
  transition: transform 0.1s;
}
.coin-call-btn:active { transform: translateY(1px); }
.coin-container {
  perspective: 800px;
  display: flex; justify-content: center;
  height: 100px; align-items: center;
  margin: 16px 0;
}
.coin {
  width: 80px; height: 80px;
  position: relative;
  transform-style: preserve-3d;
  transition: transform 1.4s cubic-bezier(0.4, 0, 0.2, 1);
}
.coin.flipping-heads { transform: rotateY(1800deg); }
.coin.flipping-tails { transform: rotateY(1980deg); }  /* 1800 + 180 to land on T */
.coin-face {
  position: absolute; inset: 0;
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-family: 'Bebas Neue', sans-serif;
  font-size: 40px; font-weight: 700;
  backface-visibility: hidden;
  border: 3px solid #b8860b;
  box-shadow: inset 0 -4px 8px rgba(0,0,0,0.3), inset 0 4px 8px rgba(255,255,255,0.4), 0 4px 8px rgba(0,0,0,0.5);
}
.coin-heads {
  background: radial-gradient(circle at 30% 30%, #ffe580 0%, #ffd700 50%, #b8860b 100%);
  color: #5c3a00;
}
.coin-tails {
  background: radial-gradient(circle at 30% 30%, #ffe580 0%, #ffd700 50%, #b8860b 100%);
  color: #5c3a00;
  transform: rotateY(180deg);
}
```

### JS — replace the dice functions

Find `goForTwo()` and replace its body with a coin-flip flow. Also remove the dice-related code in `scoreTouchdown` (the AI's 2d6 logic).

```javascript
async function goForTwo() {
  document.getElementById('conversionButtons').style.display = 'none';
  document.getElementById('coinArea').style.display = 'block';
  document.getElementById('coinPrompt').style.display = 'block';
  document.getElementById('coinChoiceButtons').style.display = 'flex';
  document.getElementById('coinContainer').style.display = 'none';
  document.getElementById('coinResult').textContent = '';
  document.getElementById('coinResult').style.color = '#ffb800';
  // Reset coin element rotation
  const coinEl = document.getElementById('coinElement');
  coinEl.classList.remove('flipping-heads', 'flipping-tails');
  // Wait for user to call heads or tails — flow continues in callCoin()
}

async function callCoin(playerCall) {
  // playerCall is 'heads' or 'tails'
  document.getElementById('coinPrompt').style.display = 'none';
  document.getElementById('coinChoiceButtons').style.display = 'none';
  document.getElementById('coinContainer').style.display = 'flex';
  
  // Determine actual result (50/50)
  const result = Math.random() < 0.5 ? 'heads' : 'tails';
  
  // Trigger flip animation — class name selects which side lands up
  const coinEl = document.getElementById('coinElement');
  // Small delay so the user sees the coin before it flips
  await sleep(150);
  coinEl.classList.add('flipping-' + result);
  playSfx('coinFlip');  // synthesize a coin-flip sound (whirring + clink)
  
  // Wait for the CSS transition to complete
  await sleep(1500);
  
  const matched = (playerCall === result);
  const resultEl = document.getElementById('coinResult');
  
  if (matched) {
    resultEl.textContent = result.toUpperCase() + ' — CONVERTED!';
    resultEl.style.color = '#4aff8a';
    state.youScore += 2;
    const lane = window._conversionLane;
    state.scoringLog.push({ team: 'you', type: '2PT', points: 2, lane: lane.name, drive: state.turn });
    playSfx('confirm');
    render();
    await sleep(1400);
    await showScoreBurst('2-PT CONVERSION!', 'touchdown', 1600);
  } else {
    resultEl.textContent = result.toUpperCase() + ' — NO GOOD';
    resultEl.style.color = '#ff4a4a';
    playSfx('discard');
    await sleep(1800);
  }
  
  document.getElementById('conversionModal').classList.remove('show');
  if (window._conversionResolve) { window._conversionResolve(); window._conversionResolve = null; }
}
```

### Add the coin-flip sound effect

Extend the existing `playSfx` helper to include a `'coinFlip'` type. Synthesize using Web Audio:

- A short ascending sine sweep (200ms) representing the spin
- Followed by a brief "clink" — a sharp high-frequency noise burst (50ms)

This is a single-sound implementation — Claude Code can write the oscillator + envelope code following the existing pattern in `playSfx`.

### Update the AI's 2-point logic

In `scoreTouchdown`, replace the dice roll with a coin flip for the AI too:

```javascript
} else if (side === 'ai' && canGoForTwo && !kicker) {
  // AI decides: 50/50 whether to attempt the conversion
  if (Math.random() < 0.5) {
    // Coin flip — AI calls heads/tails randomly, 50% chance to match
    if (Math.random() < 0.5) {
      state.aiScore += 2;
      state.scoringLog.push({ team: 'ai', type: '2PT', points: 2, lane: lane.name, drive: state.turn });
      await showScoreBurst('CPU 2-PT!', 'safety', 1400);
    } else {
      showLog('CPU 2-PT FAILED', 1200);
      await sleep(1200);
    }
  }
}
```

The math simplifies cleanly: 50% chance AI attempts, 50% chance it succeeds = 25% overall. (Compare to the dice version: 50% chance attempts × ~58% success = 29% overall. Almost identical.)

### Update the How To Play modal

Find the conversion description. Currently reads something like:

> "+2 CONVERSION: More OFF cards than they have DEF → roll 7+ on 2d6 → 8 pts."

Change to:

> "+2 CONVERSION: More OFF cards than they have DEF → call HEADS or TAILS → match the coin flip to score → 8 pts."

### Clean up

Remove the `.dice-container`, `.dice`, and `@keyframes diceRoll` CSS rules — they're no longer used. Remove `document.getElementById('diceArea').style.display = 'none';` from `showConversionChoice` since `#diceArea` no longer exists; replace with the equivalent for `#coinArea`.

### Edge cases for Part B

1. **User taps both HEADS and TAILS rapidly**: only the first one should register. Disable both buttons after first tap (set their `disabled` attribute, or remove the click handlers).
2. **Modal dismissed mid-flip**: shouldn't be possible (the modal blocks input during flip), but defensively, clear `window._conversionResolve` in case it's still set when the next conversion starts.
3. **AI coin flip**: silent and instant — no UI, just the result.
4. **Reduced-motion preference**: skip the spin animation; show the result immediately with a brief fade. Sound still plays.

### Acceptance for Part B

- [ ] After scoring a TD with more OFF cards than enemy DEF cards, the conversion modal appears
- [ ] "KICK PAT" gives 7 pts; "GO FOR 2" opens the coin flip
- [ ] CALL IT prompt shows HEADS and TAILS buttons
- [ ] Tapping HEADS or TAILS triggers the coin flip animation
- [ ] Coin spins and lands on a random side (~50% each over multiple tests)
- [ ] Matching the call: green text, +2 pts, score burst
- [ ] Missing the call: red text, no extra pts
- [ ] AI's 2-point attempts work (50% attempt × 50% success ≈ 25% overall)
- [ ] Sound effects play (coin-flip whir + clink, plus success/fail tones)
- [ ] How To Play modal updated to reflect coin flip
- [ ] No dice-related code or CSS remains in the file (search for `dice` to verify cleanup)

---

## At end of all work

- Run the syntax check from CLAUDE.md
- Add markers:
  - `// === SCROLLABLE HAND + GESTURE DISCRIMINATION ===`
  - `// === COIN FLIP CONVERSION (REPLACES 2D6) ===`
- Report to the user with:
  1. Summary of Part A (scrollable hand + gesture discrimination) and Part B (coin flip)
  2. Playtest list:
     - Equip Big Hand to get hand size 6, see the hand auto-scroll horizontally
     - Swipe horizontally on a card → scrolls (no drag triggered)
     - Drag a card up toward a lane → drags (no scroll triggered)
     - Tap a card → tooltip appears
     - Score a TD with extra OFF cards → coin flip option appears
     - Try heads, try tails, confirm 50/50 feel after several attempts

Do not make any other changes.
