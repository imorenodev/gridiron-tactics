# Quarter Labels in Scoreboard

## Context

Small UI flavor change in `gridiron-tactics.html`. The top scoreboard currently shows "1ST HALF" / "2ND HALF" beneath the drive number. Replace this with quarter labels mapped from the current drive.

This is purely cosmetic — no gameplay changes, no halftime moment, no possession swap. Just text.

Re-read CLAUDE.md if needed.

---

## The mapping

| Drive | Quarter Label |
|---|---|
| 1, 2 | `1ST QUARTER` |
| 3, 4 | `2ND QUARTER` |
| 5, 6 | `3RD QUARTER` |
| 7, 8 | `4TH QUARTER` |

A clean expression for this is `Math.ceil(state.turn / 2)` → returns 1, 2, 3, or 4. Then a small helper maps the number to its ordinal label.

## Implementation

### Add a helper

Place near other UI helpers (next to `formatYardLine` or similar):

```javascript
function quarterLabel(drive) {
  const q = Math.ceil(drive / 2);
  const labels = { 1: '1ST QUARTER', 2: '2ND QUARTER', 3: '3RD QUARTER', 4: '4TH QUARTER' };
  return labels[q] || '1ST QUARTER';
}
```

The defensive fallback handles any edge case where `drive` is out of range (shouldn't happen, but defensive code is free).

### Update the render

Find where the half label is written. Search for `halfLabel` — there should be one line in `render()` like:

```javascript
document.getElementById('halfLabel').textContent = state.turn <= 4 ? '1ST HALF' : '2ND HALF';
```

Replace with:

```javascript
document.getElementById('halfLabel').textContent = quarterLabel(state.turn);
```

The element ID stays `halfLabel` — no need to rename. The CSS rule for it (font, color, sizing) keeps working unchanged.

### Width check

"3RD QUARTER" and "4TH QUARTER" are longer than "1ST HALF". On the 375px viewport, the top scoreboard center area is narrow. Check the `.center-status` or whatever class wraps the label — if the text overflows or wraps unwantedly, drop the font size by a notch or add `white-space: nowrap`. Verify visually that all four quarter labels fit on a single line beneath "DRIVE N OF 8".

If the label genuinely doesn't fit, abbreviate to `Q1` / `Q2` / `Q3` / `Q4`. Mention this in the report if you go that route.

---

## Acceptance

- [ ] Drives 1-2 show "1ST QUARTER"
- [ ] Drives 3-4 show "2ND QUARTER"
- [ ] Drives 5-6 show "3RD QUARTER"
- [ ] Drives 7-8 show "4TH QUARTER"
- [ ] No layout breakage in the top scoreboard at 375px width
- [ ] Existing "DRIVE N OF 8" text above the label still updates correctly

## At end

- Run the syntax check from CLAUDE.md
- Report to the user with confirmation and one playtest item: "Start a match, end a few turns, and watch the quarter label update at the drive transitions (2→3, 4→5, 6→7)."

Do not make any other changes.
