# Medallion Pill Fix

## Files to add
Save these to `src/assets/ui/`:
- `05_pill_left.png` (400×400, contains the red well)
- `05_pill_right.png` (400×400, contains the green well)
- `05_pill_middle.png` (20×400, plain metal frame strip)

You can delete or keep `05_medallion_pill.png` — the new approach doesn't use it.

## Replace this CSS block

```css
.lane-medallion-row {
  display: flex; justify-content: center; align-items: center;
  padding: 4px 2px; gap: 4px;
  background-color: transparent;
  background-image: url('src/assets/ui/05_medallion_pill.png');
  background-size: 100% 100%;
  background-repeat: no-repeat;
  background-position: center;
  border: none;
  position: relative;
  flex-shrink: 0;
}
```

## With this:

```css
/* The pill row is now a 3-column grid: left cap | middle (stretches) | right cap.
   Each cap maintains its square aspect ratio so the circles never deform.
   The middle strip stretches horizontally — it's a thin uniform metal slice
   so stretching it doesn't reveal any features that would look squished. */
.lane-medallion-row {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: stretch;
  height: 38px;          /* sets the pill height — caps lock to this as squares */
  padding: 0;
  gap: 0;
  position: relative;
  flex-shrink: 0;
}

/* Left and right caps are square (aspect-ratio matches the 400×400 source).
   ::before holds the cap art so the .lane-power-pill text can sit inside via
   absolute positioning, centered over the well. */
.lane-medallion-row::before,
.lane-medallion-row::after {
  content: '';
  display: block;
  aspect-ratio: 1 / 1;
  height: 100%;
  background-size: contain;
  background-repeat: no-repeat;
  background-position: center;
}
.lane-medallion-row::before {
  background-image: url('src/assets/ui/05_pill_left.png');
  grid-column: 1;
}
.lane-medallion-row::after {
  background-image: url('src/assets/ui/05_pill_right.png');
  grid-column: 3;
}

/* A wrapper for the middle area that holds the medallion AND uses the metal
   strip as its background so the strip tiles cleanly behind whatever's there. */
.lane-medallion-row > .pill-middle {
  grid-column: 2;
  background-image: url('src/assets/ui/05_pill_middle.png');
  background-size: auto 100%;       /* keep vertical scale; horizontal repeats */
  background-repeat: repeat-x;
  background-position: center;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 2px 4px;
  min-width: 0;
}

/* Power pills overlay the caps. They're positioned absolutely inside the row
   so they can sit directly on top of the red/green wells in the cap art. */
.lane-power-pill {
  position: absolute;
  top: 50%;
  width: 34px;
  height: 34px;
  transform: translateY(-50%);
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Bebas Neue', sans-serif;
  font-size: 14px;
  line-height: 1;
  background: transparent;
  border: none;
  box-shadow: none;
  z-index: 2;
  letter-spacing: 0.5px;
  text-shadow: 0 1px 2px rgba(0,0,0,0.9), 0 0 4px rgba(0,0,0,0.7);
}
/* Position each pill over its matching well. The cap is square and equal to
   the row height (38px), so the well center sits at half the row height
   from each edge. */
.lane-power-pill.ai  { left: 2px;  color: #ff6a6a; }   /* over red well */
.lane-power-pill.you { right: 2px; color: #4aff8a; }   /* over green well */
.lane-power-pill.you.losing { color: #ff6a6a; opacity: 0.8; }
.lane-power-pill.ai.losing  { color: #4aff8a; opacity: 0.8; }
.lane-power-pill.winning {
  animation: pillPulse 1.5s ease-in-out infinite;
}
```

## Update the HTML in `renderLanes()`

Inside the `lane-medallion-row` div, wrap the medallion in a `.pill-middle` and drop
the surrounding spacer div. Change this:

```html
<div class="lane-medallion-row">
  <div class="lane-power-pill ai ...">${aiNet}</div>
  ${mod ? `
    <div class="lane-medallion cat-${mod.category}" ...>
      ...
    </div>
  ` : `<div style="flex:1;"></div>`}
  <div class="lane-power-pill you ...">${youNet}</div>
</div>
```

To this:

```html
<div class="lane-medallion-row">
  <div class="lane-power-pill ai ...">${aiNet}</div>
  <div class="pill-middle">
    ${mod ? `
      <div class="lane-medallion cat-${mod.category}" ...>
        ...
      </div>
    ` : ''}
  </div>
  <div class="lane-power-pill you ...">${youNet}</div>
</div>
```

## Why this works

- **Caps stay square** via `aspect-ratio: 1 / 1`, so the circular wells never
  distort no matter how wide the lane is.
- **Middle stretches** with a thin repeat-x strip that has no features to
  distort.
- **The lane-medallion sits on top** of the metal strip in the middle, which
  is what your existing category gradients are designed to look like — a
  dark inset panel against the brushed metal.
- **Power pill text sits over the wells** via absolute positioning, with
  z-index keeping them above the cap art.
