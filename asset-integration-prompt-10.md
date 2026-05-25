# Integrate Real UI Assets into Gridiron Tactics

## Context

The user has generated UI assets in Gemini and post-processed them with chroma-key transparency. They live as PNG files. We're swapping them into the existing CSS to replace the procedural/gradient visuals.

**Read CLAUDE.md before editing.** Then read the rest of this prompt.

The user has 30+ assets in a folder structure. Only **one portrait** is generated so far (`26_portraits/qb_black_navy.png`) — every other card portrait must fall back to the existing procedural SVG portrait generator (`generatePortraitSVG`) so the game stays playable while the user generates more portraits over time.

This is a big visual reskin that touches a lot of CSS. **Build in the sub-phase order below. Stop for playtest between each sub-phase.** Don't combine sub-phases.

---

## One-time architectural decision: external image files

Until now, `gridiron-tactics.html` was a true single file. We're breaking that invariant — UI assets live as PNG files in an `src/src/assets/ui/` folder next to the HTML.

Why: inlining 30+ PNGs as base64 would balloon the HTML to 15-25MB. Unworkable for development. The single-file ideal served us through pure code; visual assets are different.

The shipping story is still clean: when Capacitor wraps the app for App Store later, the assets folder is bundled with the HTML. Players never see a "missing assets" warning.

**Update CLAUDE.md** at the end of this work to reflect this. Specifically:
- The "one rule that matters most" section needs a softer caveat: "Code lives in one file. Visual assets (PNGs) live in `src/src/assets/ui/`."
- "Things I would NOT do" should keep "Don't add modules / build tooling" but remove any implication that all assets must be inline.

---

## Required file structure

The user has placed assets here:

```
gridiron-tactics.html
assets/
  ui/
    01_scoreboard_frame.png
    02_endzone_red.png
    03_endzone_green.png
    04_stadium_bg.png
    05_medallion_pill.png
    06_yardage_strip.png
    07_button_concede.png
    08_button_snap.png
    09_energy_orb_frame.png
    10_football_icon.png
    11_football_scoreboard.png
    12_ring_you.png
    13_ring_cpu.png
    14_power_circle_red.png
    15_power_circle_green.png
    16_badge_deck.png
    17_badge_discard.png
    18_card_common_off.png
    19_card_common_def.png
    20_card_uncommon_off.png
    21_card_uncommon_def.png
    22_card_rare_off.png
    23_card_rare_def.png
    24_card_legendary_off.png
    25_card_legendary_def.png
    26_portraits/
      qb_black_navy.png       <-- ONLY portrait that exists right now
    27_star_ability.png
    28_position_icons_grid.png
    29_modifier_icons_grid.png
    30_coin_heads.png
    31_coin_tails.png
```

If any expected file is missing, Claude Code should:
1. Note which files are missing in a comment near the CSS rule that would reference them
2. Leave the existing CSS fallback in place for that element  
3. Proceed with the rest of the work
4. Report the missing files at the end so the user knows what to regenerate

---

## Hard rules

1. **Don't break the existing game.** After every sub-phase, Quick Play / Season / Draft / Match all work end-to-end.
2. **Use `background-image: url('src/src/assets/ui/...')` patterns.** Don't try to inline base64.
3. **Preserve graceful fallbacks.** If an asset fails to load (404, corrupt, etc.), the layout should still be functional — the background just shows the old CSS color/gradient.
4. **Don't rip out the procedural SVG portrait generator.** It's the fallback for cards without a real portrait yet.
5. **Watch for mobile rendering quirks.** Test against 375px iPhone width mentally as you write CSS. Don't hardcode pixel dimensions where percentages or aspect-ratios would do.
6. **The user wants to see fast progress.** Sub-phase 1 alone (field background + endzones) is a visible upgrade. Ship that first to keep momentum.

---

## Sub-phase 1: Field & endzone textures (fast win — ship first)

The lowest-risk, highest-impact swap. Just change a few CSS `background:` rules.

### What to change

**The lane endzones (slot rows where cards are placed):**

Currently the `.lane-side.ai-side .slot-row` rule has a layered red gradient + diagonal hash stripes. Replace with the red endzone texture:

```css
.lane-side.ai-side .slot-row {
  background-image: url('src/src/assets/ui/02_endzone_red.png');
  background-size: cover;
  background-position: center;
  background-repeat: no-repeat;
  /* Keep the existing border, border-radius, padding, etc. */
  /* Remove the linear-gradient + repeating-linear-gradient declarations */
}
```

Same treatment for the bottom (your) endzone:

```css
.lane-side.you-side .slot-row {
  background-image: url('src/assets/ui/03_endzone_green.png');
  background-size: cover;
  background-position: center;
  background-repeat: no-repeat;
}
```

The pseudo-element watermark text ("CPU"/"HOME") currently rendered via CSS `::after` can either stay (overlapping the texture, which may look fine) or be removed since the texture already has "HOME" baked in. Inspect the green endzone PNG — if the user's generated asset has the "HOME" text in it, **remove the `::after` watermark text** for the YOU side. Same logic for CPU.

**The field background behind the lanes:**

The `.field` element currently uses a CSS gradient + repeating stripes. Leave that as a fallback but layer the stadium background image on top:

```css
.field {
  background-image: 
    url('src/assets/ui/04_stadium_bg.png'),
    /* keep existing gradients as fallback */
    radial-gradient(ellipse at 30% 20%, rgba(120,200,80,0.15) 0%, transparent 50%),
    radial-gradient(ellipse at 70% 80%, rgba(60,140,40,0.15) 0%, transparent 50%),
    repeating-linear-gradient(180deg, ...);
  background-size: cover, auto, auto, auto;
  background-position: top center, ...;
  background-repeat: no-repeat, ...;
}
```

If the stadium background looks wrong at this position (e.g., it's a wide horizontal banner meant for the top only), consider applying it via a pseudo-element positioned at the top of `.field` instead. Inspect the asset's aspect ratio before deciding.

### Sub-phase 1 acceptance

- [ ] Endzone PNGs replace the CSS gradients in `.slot-row` rules
- [ ] No JS errors; game still plays end-to-end
- [ ] Cards placed in lanes still visible against the new textures (the textures may need a slight dark overlay if cards get lost — add one via `box-shadow: inset 0 0 0 1000px rgba(0,0,0,0.15)` on the slot-row if needed)
- [ ] Empty card slots' dashed borders still visible against the colored backgrounds
- [ ] Field background updated with stadium texture (or left if it looks worse than the gradient — judgement call)
- [ ] Add marker: `// === ASSET PHASE 1: FIELD + ENDZONES ===`
- [ ] Run syntax check
- [ ] **Stop. Tell the user to playtest: start a match, look at the field, place a card or two, confirm it looks better. Wait for their go-ahead before continuing.**

---

## Sub-phase 2: Top scoreboard + avatar rings

### The top bar swap

The `.top-bar` element has a CSS gradient and a row of HTML elements (team blocks + center scoreboard center). We're keeping the HTML structure but replacing the styling with the scoreboard frame asset.

**Replace the `.top-bar` background:**

```css
.top-bar {
  background-image: url('src/assets/ui/01_scoreboard_frame.png');
  background-size: 100% 100%;  /* stretch to fit; the frame is a 9-slice-style chrome */
  background-repeat: no-repeat;
  background-position: center;
  background-color: transparent;  /* remove old gradient */
  /* Keep existing flex layout, padding, etc. */
}
```

If the scoreboard PNG includes the three internal "wells" baked in (i.e., the panel interiors aren't transparent in the final asset), the existing `.team-avatar`, score numbers, and center info should sit inside those wells naturally because of the existing flex positioning. Inspect the asset and adjust padding/positioning if elements don't align with the wells.

**Avatar rings (YOU and CPU circles):**

The existing `.team-avatar` rules use a CSS radial-gradient. Replace with the PNG ring assets:

```css
.team-avatar {
  background-image: url('src/assets/ui/12_ring_you.png');
  background-size: contain;
  background-position: center;
  background-repeat: no-repeat;
  background-color: transparent;
  border: none;  /* remove the existing solid border, the PNG provides it */
  box-shadow: none;  /* same */
}
.team-block.ai .team-avatar {
  background-image: url('src/assets/ui/13_ring_cpu.png');
}
```

The existing inner text ("YOU" / "CPU") rendered inside the rings should still work — it sits on top of the background image. May need a slight font-size or position tweak so it centers inside the ring's hollow area. Inspect and adjust.

**Football icon in the center:**

The existing `.center-icon` uses an emoji 🏈. Replace with the PNG:

```css
.center-icon {
  background-image: url('src/assets/ui/11_football_scoreboard.png');
  background-size: contain;
  background-position: center;
  background-repeat: no-repeat;
  /* Hide the emoji text content if it's still there */
  color: transparent;
  /* Or change the innerHTML in the JS to empty string */
}
```

If easier, change the HTML directly: `<div class="center-icon">🏈</div>` becomes `<div class="center-icon"></div>` and the CSS just shows the PNG.

### Sub-phase 2 acceptance

- [ ] Top bar shows the scoreboard frame PNG
- [ ] Avatar rings show the YOU and CPU ring PNGs
- [ ] Score numbers ("0" and "0") align correctly inside the avatar rings or wherever they're supposed to be
- [ ] Football icon in the center shows the PNG (not the emoji)
- [ ] DRIVE N OF 8 and quarter label are still readable inside the center panel
- [ ] No layout breakage on a 375px viewport
- [ ] Add marker: `// === ASSET PHASE 2: SCOREBOARD + RINGS ===`
- [ ] Run syntax check
- [ ] **Stop. Tell the user to playtest: start a match, look at the top scoreboard, score a point (or use DevTools to bump the score), confirm everything aligns. Wait for go-ahead.**

---

## Sub-phase 3: Buttons + energy orb + medallion pill + yardage strips

### Buttons

The CONCEDE and SNAP buttons currently have CSS gradients. Replace with the PNG button assets:

```css
.concede-btn {
  background-image: url('src/assets/ui/07_button_concede.png');
  background-size: 100% 100%;
  background-color: transparent;
  border: none;
  /* Keep text styling, padding for the label inside */
  box-shadow: none;
}
.play-btn {
  background-image: url('src/assets/ui/08_button_snap.png');
  background-size: 100% 100%;
  background-color: transparent;
  border: none;
  /* Keep the existing :disabled and .ready states — but you may need to add */
  /* a separate disabled-button asset later, or just dim the existing button via opacity */
}
.play-btn:disabled {
  opacity: 0.5;
}
```

The button label text ("CONCEDE" / "SNAP!") still renders on top of the PNG background. Position/color/size should be adjusted so the text sits in the visual center of the button shape.

### Energy orb (the football holder)

```css
.energy-orb {
  background-image: url('src/assets/ui/09_energy_orb_frame.png');
  background-size: contain;
  background-position: center;
  background-repeat: no-repeat;
  background-color: transparent;
  border: none;
  box-shadow: none;
}
```

The energy number text still renders inside the orb. May need to be repositioned slightly to sit inside the recessed center of the frame. Add a small football icon (`11_football_scoreboard.png` or `10_football_icon.png`) inside the orb behind the number — use a `::before` pseudo-element to layer it.

Actually, looking at the design: the energy orb in the mockup has a FOOTBALL inside it, not a number. The number is overlaid on the football. Implement it like this:

```css
.energy-orb {
  position: relative;
  background-image: url('src/assets/ui/09_energy_orb_frame.png');
  background-size: contain;
  background-position: center;
  background-repeat: no-repeat;
}
.energy-orb::before {
  content: '';
  position: absolute;
  inset: 20%;  /* football fills inner area */
  background-image: url('src/assets/ui/10_football_icon.png');
  background-size: contain;
  background-position: center;
  background-repeat: no-repeat;
  z-index: 0;
}
.energy-orb {
  /* the number text needs to sit on top of the football */
  z-index: 1;
}
```

Be careful with the z-index layering — the number must be readable on top of the football. May need a text-shadow or a small dark circle behind the number.

### Lane modifier medallion pill

The `.lane-medallion-row` is the bar that holds the two power pills and the modifier name. Replace its CSS gradient with the medallion pill PNG:

```css
.lane-medallion-row {
  background-image: url('src/assets/ui/05_medallion_pill.png');
  background-size: 100% 100%;
  background-repeat: no-repeat;
  background-color: transparent;
  border: none;
  /* Keep existing layout — power pills on each side, modifier text in middle */
}
```

The two power circle wells in the PNG should align with the existing `.lane-power-pill` elements visually. May need to remove the existing `.lane-power-pill` CSS background/border (they're already in the PNG) and just keep the text styling:

```css
.lane-power-pill {
  background: transparent !important;
  border: none !important;
  box-shadow: none !important;
  /* keep font, color, size for the +N text inside */
}
```

The existing `.lane-power-pill.you` (green color), `.lane-power-pill.ai` (red color), `.winning`, and `.losing` classes still affect the text color of the number inside the well — keep those.

The modifier name + icon + description rendered inside the medallion: should still appear correctly because the PNG's center section is supposed to be empty (a chroma-key zone now transparent). Verify the modifier text isn't clipped or off-center.

### Yardage strips ("CPU OWN 28")

The `.yardage-bar` already has substantial CSS. We're NOT replacing the yardage bar itself (that needs to dynamically show the ball position via JS). We're only replacing the "CPU OWN 28" / "YOU OWN 16" indicator strip *above* and *below* the bar.

Actually, looking at the existing code, those values are rendered INSIDE the yardage-bar element as `.yardage-text`. We don't need a separate strip asset for them — the existing layout already shows them as text overlays on the bar.

**Skip the yardage strip swap for now.** The mockup shows a separate metallic strip with the yardage indicator, but our current implementation embeds it in the bar itself. Either approach works; rebuilding the layout to use a separate strip is more work than it's worth for this phase.

Note this skip in a comment near the `.yardage-bar` CSS: `/* Yardage strip asset (06_yardage_strip.png) not used — yardage display is embedded in the yardage-bar for now. */`

### Sub-phase 3 acceptance

- [ ] CONCEDE button shows the PNG, label still readable
- [ ] SNAP button shows the PNG, label still readable, disabled state visibly dimmed
- [ ] Energy orb shows the football PNG inside the chrome ring frame, number readable on top
- [ ] Lane medallion row uses the pill PNG, power numbers and modifier text aligned correctly
- [ ] No layout breakage
- [ ] Add marker: `// === ASSET PHASE 3: BUTTONS + ORB + MEDALLIONS ===`
- [ ] Run syntax check
- [ ] **Stop. Playtest. Wait for go-ahead.**

---

## Sub-phase 4: Deck/discard badges + power circles

### Deck and discard badges

Replace the existing badge CSS:

```css
.deck-badge {
  background-image: url('src/assets/ui/16_badge_deck.png');
  background-size: 100% 100%;
  background-repeat: no-repeat;
  background-color: transparent;
  border: none;
  /* keep the text styling for "DECK" label and count number */
}
.discard-badge {
  background-image: url('src/assets/ui/17_badge_discard.png');
  background-size: 100% 100%;
  background-repeat: no-repeat;
  background-color: transparent;
  border: none;
}
```

The existing label + count text should still render. Adjust padding/positioning if they don't align with the badge's recessed wells.

### Power circles (red and green inside the medallion row)

Already handled in Sub-phase 3 by making the `.lane-power-pill` transparent (the circles are part of the medallion pill PNG). However, if the user wants standalone power circle assets (e.g., for a tooltip preview or future feature), keep `14_power_circle_red.png` and `15_power_circle_green.png` available in CSS as fallback rules. They're not used in this phase but should be referenced in a commented-out CSS block for easy enablement later.

```css
/* Power circle standalone assets (not currently used — pills are part of the medallion PNG)
.lane-power-pill.standalone.ai { background-image: url('src/assets/ui/14_power_circle_red.png'); ... }
.lane-power-pill.standalone.you { background-image: url('src/assets/ui/15_power_circle_green.png'); ... }
*/
```

### Sub-phase 4 acceptance

- [ ] DECK badge shows the PNG with label + count
- [ ] DISCARD badge shows the PNG with label + count
- [ ] Tapping the DISCARD badge still opens the discard pile modal (no functional break)
- [ ] Add marker: `// === ASSET PHASE 4: BADGES ===`
- [ ] Run syntax check
- [ ] **Stop. Playtest. Wait for go-ahead.**

---

## Sub-phase 5: Card frames (the big one)

This is the biggest CSS rework. Cards are layered: portrait → frame overlay → text overlays. The current implementation has the SVG portrait generator producing the portrait inline; we need to add a card frame PNG on top of that, with the cost badge, position, name, and stat text rendered as overlays.

### Card layer structure (target)

```
.field-card or .hand-card
  ├── portrait layer (z-index: 0) — SVG portrait OR PNG portrait
  ├── frame overlay (z-index: 1) — the card frame PNG (transparent center)
  └── text overlays (z-index: 2)
        ├── cost badge (top-left)
        ├── position label (top-right)
        ├── name strip (bottom)
        ├── stat number (very bottom)
        └── ability star (if has ability)
```

### Build the layered structure

Modify `buildFieldCard(card, side, hidden)` (and `renderHand()` similarly) to add a frame layer between the portrait and the overlays:

```javascript
function buildFieldCard(card, side, hidden) {
  const el = document.createElement('div');
  const sideClass = card.side === 'off' ? 'off-card' : 'def-card';
  el.className = 'field-card ' + side + ' ' + sideClass + (hidden ? ' hidden-card' : '');
  if (hidden) return el;

  const statValue = card.side === 'off' ? card.curOff : card.curDef;
  const statClass = card.side === 'off' ? 'off' : 'def';
  const lastName = card.name.split(' ').slice(-1)[0].toUpperCase();
  const rarity = card.rarity || 'common';
  const frameAsset = `${rarity}_${card.side}`;  // 'common_off', 'rare_def', etc.

  el.innerHTML = `
    <div class="fc-portrait">${getPortraitMarkup(card, 100)}</div>
    <div class="fc-frame fc-frame-${frameAsset}"></div>
    <div class="fc-overlay">
      <div class="fc-top">
        <span class="fc-cost">${card.cost}</span>
        <span class="fc-pos">${card.pos}</span>
      </div>
      <div class="fc-name">${lastName}</div>
      <div class="fc-stats ${statClass}">${card.ejected ? '—' : statValue}</div>
    </div>
    <div class="fc-badges">
      ${card.flagged ? '<div class="fc-badge flag">!</div>' : ''}
      ${card.ejected ? '<div class="fc-badge ejected">X</div>' : ''}
      ${card.ability ? '<div class="fc-ability-star"></div>' : ''}
    </div>
  `;
  return el;
}

function getPortraitMarkup(card, size) {
  // Try to use a real PNG portrait if one exists for this card.
  // Otherwise fall back to the SVG portrait generator.
  const portraitId = getPortraitIdForCard(card);  // returns a string like 'qb_black_navy' or null
  if (portraitId) {
    return `<img src="src/assets/ui/26_portraits/${portraitId}.png" 
                 onerror="this.outerHTML='${generatePortraitSVG(card, size).replace(/'/g, '&#39;')}'"
                 style="width:100%; height:100%; object-fit:cover;">`;
  }
  return generatePortraitSVG(card, size);
}

function getPortraitIdForCard(card) {
  // Returns the portrait filename ID (without extension) for a given card,
  // or null if no real portrait exists for this card yet.
  // 
  // For now (only one portrait generated), match QB-positioned cards to the
  // single existing portrait. The user will expand this mapping as they
  // generate more portraits.
  if (card.pos === 'QB') return 'qb_black_navy';
  return null;
}
```

The `onerror` fallback ensures that if a PNG portrait is mapped but doesn't exist (network error, typo in filename, etc.), the SVG generator's portrait is substituted automatically.

### CSS for the layered card

Replace the existing `.field-card` and `.hand-card` CSS:

```css
.field-card, .hand-card {
  position: relative;
  aspect-ratio: 3 / 4;
  /* Other existing layout properties */
}

.fc-portrait {
  position: absolute;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  /* Match the frame's inner portrait region — approximately top 65% */
  /* But layered with the frame on top so it's effectively that area */
}
.fc-portrait img, .fc-portrait svg {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.fc-frame {
  position: absolute;
  inset: 0;
  z-index: 1;
  pointer-events: none;
  background-size: 100% 100%;
  background-repeat: no-repeat;
  background-position: center;
}
.fc-frame-common_off { background-image: url('src/assets/ui/18_card_common_off.png'); }
.fc-frame-common_def { background-image: url('src/assets/ui/19_card_common_def.png'); }
.fc-frame-uncommon_off { background-image: url('src/assets/ui/20_card_uncommon_off.png'); }
.fc-frame-uncommon_def { background-image: url('src/assets/ui/21_card_uncommon_def.png'); }
.fc-frame-rare_off { background-image: url('src/assets/ui/22_card_rare_off.png'); }
.fc-frame-rare_def { background-image: url('src/assets/ui/23_card_rare_def.png'); }
.fc-frame-legendary_off { background-image: url('src/assets/ui/24_card_legendary_off.png'); }
.fc-frame-legendary_def { background-image: url('src/assets/ui/25_card_legendary_def.png'); }

.fc-overlay {
  position: absolute;
  inset: 0;
  z-index: 2;
  pointer-events: none;
  /* Existing overlay text styling */
}

.fc-ability-star {
  /* Replace the old gold star emoji/text with the PNG */
  position: absolute;
  bottom: 24px;
  right: 6px;
  width: 16px;
  height: 16px;
  background-image: url('src/assets/ui/27_star_ability.png');
  background-size: contain;
  background-repeat: no-repeat;
  filter: drop-shadow(0 1px 2px rgba(0,0,0,0.8));
}
```

**Critical positioning calibration:** the overlay text (cost, position, name, stat) needs to align with the recessed wells in the card frame PNG. The existing positions may not line up perfectly. Spend time tuning the CSS positions (top/right/bottom values) for `.fc-cost`, `.fc-pos`, `.fc-name`, `.fc-stats` so they sit inside the frame's text wells, not on top of the chrome border.

**Visual debug tip:** during this calibration, temporarily set `border: 1px dashed magenta` on each overlay element to see where they're positioned relative to the frame. Remove the debug border before declaring done.

### Apply same treatment to `renderHand()` cards

The hand-card structure mirrors the field-card. Add the same layered structure to `renderHand()` and use the same CSS class names (`.fc-portrait`, `.fc-frame`, `.fc-overlay`, etc.) or duplicate with `.hc-` prefixes if you'd rather keep them separate. Either approach works — pick whichever results in less CSS duplication.

### Sub-phase 5 acceptance

- [ ] Cards in hand show the frame PNG with portrait visible inside
- [ ] Cards placed in lanes show the frame PNG
- [ ] Cost badge, position label, name, and stat values are all positioned inside their respective wells (not on the chrome border)
- [ ] The single existing QB portrait (`qb_black_navy.png`) appears on QB-position cards
- [ ] All non-QB cards fall back to the procedural SVG portrait correctly
- [ ] If `qb_black_navy.png` is somehow missing or fails to load, the onerror fallback substitutes the SVG portrait
- [ ] Rarity-correct frames are used (common → common frame, legendary → legendary frame, etc.)
- [ ] Offense and defense variants use the correct frame variant
- [ ] Ability star PNG appears in the bottom-right of cards with abilities
- [ ] No JS errors when playing through a match
- [ ] Add marker: `// === ASSET PHASE 5: CARD FRAMES + PORTRAITS ===`
- [ ] Run syntax check
- [ ] **Stop. Playtest. Wait for go-ahead.**

---

## Sub-phase 6: Coin flip + position/modifier icons

### Coin flip assets

The coin flip 2-point conversion already exists in JS. Replace the CSS-only coin face (which currently shows "H" and "T" text on a gold gradient) with the PNG assets:

```css
.coin-face {
  background-size: contain;
  background-position: center;
  background-repeat: no-repeat;
  background-color: transparent;
  border: none;
  box-shadow: none;
  color: transparent;  /* hide the H/T text since it's in the PNG */
}
.coin-heads {
  background-image: url('src/assets/ui/30_coin_heads.png');
}
.coin-tails {
  background-image: url('src/assets/ui/31_coin_tails.png');
  transform: rotateY(180deg);
}
```

The 3D flip animation still works because it operates on the `.coin` parent element.

### Position icons grid

The `28_position_icons_grid.png` is a single 4×3 grid containing all 12 position silhouettes. Use CSS `background-position` to extract individual icons:

```css
.position-icon {
  width: 24px; height: 24px;
  background-image: url('src/assets/ui/28_position_icons_grid.png');
  background-size: 400% 300%;  /* 4 columns × 3 rows */
  display: inline-block;
}
.position-icon.pos-qb { background-position: 0% 0%; }
.position-icon.pos-rb { background-position: 33.33% 0%; }
.position-icon.pos-wr { background-position: 66.67% 0%; }
.position-icon.pos-te { background-position: 100% 0%; }
.position-icon.pos-ol { background-position: 0% 50%; }
.position-icon.pos-de { background-position: 33.33% 50%; }
.position-icon.pos-dt { background-position: 66.67% 50%; }
.position-icon.pos-lb { background-position: 100% 50%; }
.position-icon.pos-cb { background-position: 0% 100%; }
.position-icon.pos-s  { background-position: 33.33% 100%; }
.position-icon.pos-k  { background-position: 66.67% 100%; }
.position-icon.pos-st { background-position: 100% 100%; }
```

These can be used in the existing position badges on cards OR in a future "filter by position" UI. For now, just define the CSS and leave the existing position text labels in place. Don't actively replace anything — these are reserved for future use.

### Modifier icons grid

Same approach for `29_modifier_icons_grid.png` (5×4 grid of 20 modifier icons). Create CSS classes for each modifier:

```css
.modifier-icon {
  width: 32px; height: 32px;
  background-image: url('src/assets/ui/29_modifier_icons_grid.png');
  background-size: 500% 400%;  /* 5 columns × 4 rows */
  display: inline-block;
}
.modifier-icon.mod-homeTurf { background-position: 0% 0%; }
.modifier-icon.mod-muddyField { background-position: 25% 0%; }
.modifier-icon.mod-windTunnel { background-position: 50% 0%; }
.modifier-icon.mod-frozenTundra { background-position: 75% 0%; }
.modifier-icon.mod-blindingSun { background-position: 100% 0%; }
.modifier-icon.mod-redZone { background-position: 0% 33.33%; }
/* ... continue for all 20, matching the grid layout from the prompt */
```

Then update the `LANE_MODIFIERS` array (or wherever modifier icons are rendered) to optionally use the CSS class instead of the emoji icon. Make this opt-in: add a config flag like `USE_PNG_MODIFIER_ICONS = true` that toggles between emoji and PNG. This lets the user A/B test which feels better.

Actually, keeping both options is more code than it's worth. Just replace the emoji directly:

In the lane medallion render, where you currently have `${mod.icon}` (the emoji), replace with:

```html
<div class="modifier-icon mod-${mod.id}"></div>
```

The existing emoji stays in the `LANE_MODIFIERS` array as a fallback/comment, but isn't rendered.

### Sub-phase 6 acceptance

- [ ] Coin flip animation uses the PNG coin faces (not text)
- [ ] Position icon classes defined for all 12 positions (used in CSS, available for future features)
- [ ] Modifier icon classes defined for all 20 modifiers
- [ ] Lane medallions show PNG modifier icons instead of emoji
- [ ] No layout breakage in the medallion display
- [ ] Add marker: `// === ASSET PHASE 6: COIN + ICONS ===`
- [ ] Run syntax check
- [ ] **Stop. Playtest specifically: score a touchdown to trigger the coin flip; play matches to see the medallions with their new icons.**

---

## Update CLAUDE.md at the end

After all sub-phases ship:

1. Update the "one rule that matters most" section:
   ```
   The game's CODE lives in one file: `gridiron-tactics.html`. Visual assets 
   (PNGs) live in `src/assets/ui/` next to the HTML. When in doubt about code 
   architecture, grep the HTML file first.
   ```

2. Add to "Subsystems and where they live":
   ```
   UI assets — PNGs in `src/assets/ui/`, referenced via CSS `url(...)` rules. 
   See ASSET_INTEGRATION_MARKERS in HTML for which CSS rules use which assets.
   ```

3. Add to "Common tasks":
   ```
   "Swap in a new asset PNG" → save to `src/assets/ui/`, find the CSS rule that 
   references it (grep for the filename), no JS changes needed.
   "Add a new card portrait" → save to `src/assets/ui/26_portraits/<id>.png`, 
   update `getPortraitIdForCard(card)` to return the new ID for matching 
   cards.
   ```

4. Add to "Things I would NOT do":
   ```
   Don't inline assets as base64 — keep them as external PNGs in `src/assets/ui/`. 
   The HTML stays code-only.
   Don't remove the SVG portrait fallback (`generatePortraitSVG`) — it's the 
   safety net for cards without a real portrait asset yet.
   ```

---

## Final acceptance for the whole integration

- [ ] All 6 sub-phases completed with their own markers
- [ ] Existing gameplay (Quick Play, Season, Draft, Match) works end-to-end
- [ ] All 30+ referenced PNGs are loaded (no 404s in DevTools network tab)
- [ ] At least one card shows the real QB portrait; all other cards use the SVG fallback
- [ ] CLAUDE.md updated
- [ ] No JS errors when playing a full match
- [ ] Visual quality is substantially better than pre-integration (subjective but should be obvious)

## Report at end

Tell the user:
1. Summary of what was swapped in each sub-phase
2. Any assets that appeared to have issues (e.g., magenta spillover, wrong aspect ratio, hard to align text overlays) — recommend regeneration if so
3. The list of cards that show the real QB portrait vs the SVG fallback
4. What to playtest:
   - Field background and endzones look upgraded
   - Top scoreboard with new chrome frame and avatar rings
   - Buttons (CONCEDE, SNAP, energy orb) all show PNG assets
   - Lane medallions show modifier icons + power values
   - DECK and DISCARD badges
   - Cards in hand and field show real frame PNGs with portraits inside (most fall back to SVG since only one portrait exists)
   - Score a TD with extra OFF cards to trigger the coin flip
5. Next steps:
   - User should generate more portraits over time and update the `getPortraitIdForCard` mapping
   - User should inspect assets for spillover/issues and regenerate problem ones
   - Once all 30+ assets are visually solid, consider App Store packaging via Capacitor
