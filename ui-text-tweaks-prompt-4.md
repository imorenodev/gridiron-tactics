# UI Text Tweaks — Deck Counter & Drive Counter

## Context

Two small UI text changes in `index.html`. Re-read CLAUDE.md if it's been a while.

These are surgical edits — find the element, change the surrounding markup and the render-time text update. Don't touch any logic.

---

## Change 1: Deck info row

**Find this line** (search for `deck-info-row` or `deckCount`):

```html
<div class="deck-info-row">DECK: <span id="deckCount">47</span> · DRIVE <span id="turnNum">1</span>/8</div>
```

**Replace with:**

```html
<div class="deck-info-row">DECK REMAINING: <span id="deckCount">47</span></div>
```

Then **find every place in the JS that updates `turnNum`** (likely in `render()` — search for `document.getElementById('turnNum')`). Remove the line that updates `turnNum.textContent` since the element no longer exists. Leave the `deckCount` update alone.

**Watch out**: if any code still expects `#turnNum` to exist, you'll get a null-reference error. Search the entire file for `'turnNum'` and `"turnNum"` to confirm there are no other references. If the second header (`#quarterNum`, see Change 2 below) is the only other drive-counter UI, you're safe.

---

## Change 2: Drive counter in the top scoreboard

**Find this line** (in the top scoreboard area):

```html
<div class="drive-num" id="quarterNum">DRIVE 1</div>
```

**No HTML change needed** — keep the same element and ID. Just change what the JS writes into it.

**Find the JS line that updates it** (search for `quarterNum`):

```javascript
document.getElementById('quarterNum').textContent = 'DRIVE ' + state.turn;
```

**Replace with:**

```javascript
document.getElementById('quarterNum').textContent = 'DRIVE ' + state.turn + ' OF 8';
```

The element CSS may need a slightly smaller font size to fit "DRIVE 8 OF 8" without overflowing on a 375px viewport. Check the `.drive-num` rule — if the current font size is comfortably large, drop it a notch (e.g., 14px → 12px) or add a `white-space: nowrap` rule so it stays on one line. Verify visually that "DRIVE 10 OF 8" fits as well, since that's the worst-case width (even though the game caps at 8 — defensive sizing).

---

## At end of work

- Run the syntax check from CLAUDE.md
- Verify by mentally walking through `render()`: does it still try to write to `#turnNum`? If yes, that line must be removed.
- Report to the user:
  - Confirmation of the two text changes
  - Note any CSS adjustments you made for fit
  - List one thing to playtest: open a game, look at both the top scoreboard ("DRIVE 1 OF 8") and the bottom deck row ("DECK REMAINING: 47"), play through a few drives and confirm both update correctly.

Do not make any other changes.
