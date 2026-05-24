# Dynamic Power Pill Breakdown Tooltips

## Context

The power pills above each lane medallion (the green/red pills showing net yards per drive) currently have static tooltips with a generic formula explanation. We're upgrading them to show the **actual current breakdown** of where the number came from — totals, active bonuses, the math.

The hand-card and other tooltips stay unchanged. Only `powerPillYou` and `powerPillAi` are dynamic.

**Re-read CLAUDE.md and inspect the current rendering code in `gridiron-tactics.html` before editing.** Search for `lane-power-pill`, `youNet`, `aiNet`, `computeLaneStats`, `detectSynergies`. The dynamic-tooltip pattern already exists — the lane medallion uses `data-tooltip-title` and `data-tooltip-body` attributes that override the static `TOOLTIPS` lookup. Follow that same pattern.

---

## The tooltip content design

Each power pill, when tapped, shows a compact breakdown:

```
YOUR NET YARDS: +32

Your OFF · 180
Their DEF · 102

Active bonuses:
🌟 Wildcat (2+ RBs in lane)
🔨 Trenches (DT +6 DEF)

Math: floor(180 ÷ 2.5) − floor(102 ÷ 2.5) = 72 − 40 = +32
```

That's the YOU pill. The AI pill mirrors it from the CPU's perspective:

```
CPU NET YARDS: +19

Their OFF · 48
Your DEF · 0

Active bonuses:
✈️ Air Raid (WR/TE +8 OFF)

Math: floor(48 ÷ 2.5) − floor(0 ÷ 2.5) = 19 − 0 = +19
```

If there are **no active bonuses** for that side, omit the "Active bonuses:" section entirely. Don't print an empty header.

If the net result has been modified by **field ability extras** (currently only `fieldYardBlock` from Lockdown CB), call them out:

```
Math: floor(48 ÷ 2.5) − floor(0 ÷ 2.5) − 5 = 19 − 0 − 5 = +14
        (your Lockdown CB blocks 5 yards)
```

---

## Implementation plan

### Step 1: Build a `breakdownPowerPill(lane, side)` helper

Add a new function that, given a lane and side (`'you'` or `'ai'`), returns an object describing the breakdown. Place it near `computeLaneStats` so the math stays together.

```javascript
function breakdownPowerPill(lane, side) {
  // Run the same math the renderer uses. Note: computeLaneStats mutates
  // curOff/curDef to include modifiers + synergies + field effects.
  // We want the post-modifier totals.
  const stats = computeLaneStats(lane);
  
  const myOff = side === 'you' ? stats.youOff : stats.aiOff;
  const myDef = side === 'you' ? stats.youDef : stats.aiDef;
  const theirOff = side === 'you' ? stats.aiOff : stats.youOff;
  const theirDef = side === 'you' ? stats.aiDef : stats.youDef;
  
  const SCALE = 2.5;
  const gain = Math.floor(myOff / SCALE);
  const loss = Math.floor(theirDef / SCALE);
  let net = gain - loss;
  
  // Lockdown CB yard-block: −5 to the side we're computing FOR
  let yardBlockPenalty = 0;
  const opposingCards = side === 'you' ? lane.aiCards : lane.youCards;
  opposingCards.forEach(c => {
    if (c.desc === 'fieldYardBlock' && c.revealed && !c.ejected) {
      yardBlockPenalty += 5;
    }
  });
  net -= yardBlockPenalty;
  
  // Collect active bonus names
  const bonuses = [];
  
  // Lane modifier — only mention if it affects offense (for OFF totals) or
  // defense (for DEF totals) of the relevant side.
  if (lane.modifier) {
    const mod = lane.modifier;
    // Modifiers that affect attacker's offense (helps `gain`)
    const offBuffMods = ['homeTurf', 'redZone', 'scramble', 'groundPound', 'airRaid', 'trenches', 'specialUnit', 'playOfGame'];
    // Modifiers that affect defender's defense (helps their `loss` to us)
    const defBuffMods = ['muddyField', 'trenches', 'secondary', 'specialUnit'];
    // Modifiers that nerf the side
    const nerfMods = ['windTunnel', 'blindingSun', 'frozenTundra'];
    
    if (offBuffMods.includes(mod.id) || defBuffMods.includes(mod.id) || nerfMods.includes(mod.id)) {
      bonuses.push({ icon: mod.icon, name: mod.name, desc: mod.desc });
    }
    // Always mention wild modifiers since they affect math indirectly
    if (mod.category === 'wild') {
      bonuses.push({ icon: mod.icon, name: mod.name, desc: mod.desc });
    }
  }
  
  // Card synergies for the side we're computing
  const myCards = side === 'you' ? lane.youCards : lane.aiCards;
  const myActiveSyns = detectSynergies(myCards.filter(c => c.revealed && !c.ejected));
  myActiveSyns.forEach(syn => {
    bonuses.push({ icon: syn.icon, name: syn.name });
  });
  
  // Opposing-side synergies that buff their defense (since we lose to it)
  const oppCards = side === 'you' ? lane.aiCards : lane.youCards;
  const oppActiveSyns = detectSynergies(oppCards.filter(c => c.revealed && !c.ejected));
  // Only count their DEF-side synergies as relevant to OUR breakdown
  oppActiveSyns.filter(s => s.side === 'def').forEach(syn => {
    bonuses.push({ icon: syn.icon, name: 'Opp ' + syn.name });
  });
  
  return {
    net,           // final net yards (with all bonuses + yard-block applied)
    myOff,         // post-modifier offense total for this side
    theirDef,      // post-modifier defense total for opposing side
    gain,          // floor(myOff / 2.5)
    loss,          // floor(theirDef / 2.5)
    yardBlockPenalty,  // 0 or positive
    bonuses        // array of {icon, name, desc?} for display
  };
}
```

A few important notes about this helper:

- **Use the existing `computeLaneStats(lane)` call** — that already applies modifiers, synergies, snap abilities, and field effects to `curOff`/`curDef`. You don't need to re-do the math.
- **Avoid recomputing inside `computeLaneStats`** — if called twice in close succession (once for net display, once for tooltip), the mutations might compound. Inspect `computeLaneStats` carefully: if it already handles being called repeatedly idempotently (e.g., resetting `_fieldOff = 0` first), you're fine. If not, call it once and pass the stats into both consumers. **My recommendation**: cache the result on `lane._lastStats = stats` during the render pass so the tooltip can read it without re-invoking the function.
- **The `yardBlockPenalty` mirrors what `processYardageAndScoring` does** but it's stored separately because we display it as a distinct line in the tooltip math.

### Step 2: Update `renderLanes` to embed dynamic tooltip data

Find where the power pills are rendered:

```javascript
<div class="lane-power-pill ai ${aiNet > 0 ? 'winning' : ''} ${aiNet < 0 ? 'losing' : ''}" data-tooltip="powerPillAi">${aiNet > 0 ? '+' : ''}${aiNet}</div>
```

Change to embed the breakdown via `data-tooltip-title` and `data-tooltip-body`. Build helper functions to format the strings, since template literals get unwieldy:

```javascript
function buildPowerPillTooltipBody(breakdown, side) {
  const sideLabel = side === 'you' ? 'Your' : 'Their';
  const oppLabel = side === 'you' ? 'Their' : 'Your';
  const sign = breakdown.net >= 0 ? '+' : '';
  
  let body = '';
  body += '<strong>' + sideLabel + ' OFF</strong> · ' + breakdown.myOff + '<br>';
  body += '<strong>' + oppLabel + ' DEF</strong> · ' + breakdown.theirDef + '<br>';
  
  if (breakdown.bonuses.length > 0) {
    body += '<br><em>Active bonuses:</em><br>';
    breakdown.bonuses.forEach(b => {
      body += b.icon + ' ' + b.name + '<br>';
    });
  }
  
  body += '<br><strong>Math:</strong> ⌊' + breakdown.myOff + '÷2.5⌋ − ⌊' + breakdown.theirDef + '÷2.5⌋';
  if (breakdown.yardBlockPenalty > 0) {
    body += ' − ' + breakdown.yardBlockPenalty;
  }
  body += '<br>= ' + breakdown.gain + ' − ' + breakdown.loss;
  if (breakdown.yardBlockPenalty > 0) {
    body += ' − ' + breakdown.yardBlockPenalty + ' <em>(Lockdown CB)</em>';
  }
  body += ' = <strong>' + sign + breakdown.net + '</strong> yards/drive';
  
  return body;
}
```

Then in the lane render template:

```javascript
const aiBreakdown = breakdownPowerPill(lane, 'ai');
const youBreakdown = breakdownPowerPill(lane, 'you');
const aiTitle = 'CPU NET YARDS: ' + (aiBreakdown.net >= 0 ? '+' : '') + aiBreakdown.net;
const youTitle = 'YOUR NET YARDS: ' + (youBreakdown.net >= 0 ? '+' : '') + youBreakdown.net;
const aiTipBody = buildPowerPillTooltipBody(aiBreakdown, 'ai');
const youTipBody = buildPowerPillTooltipBody(youBreakdown, 'you');
```

And update the HTML in the template:

```javascript
<div class="lane-power-pill ai ${aiNet > 0 ? 'winning' : ''} ${aiNet < 0 ? 'losing' : ''}"
     data-tooltip="powerPillAi"
     data-tooltip-title="${escAttr(aiTitle)}"
     data-tooltip-body="${escAttr(aiTipBody)}">${aiNet > 0 ? '+' : ''}${aiNet}</div>
```

Same pattern for the YOU pill. **Always wrap dynamic title/body in `escAttr(...)`** — bonus names like "GROUND & POUND" contain ampersands that would otherwise break the HTML attribute.

### Step 3: Don't touch the static `TOOLTIPS.powerPillYou` / `TOOLTIPS.powerPillAi` entries

The existing tooltip system already prefers `data-tooltip-title`/`data-tooltip-body` when present, falling back to the static `TOOLTIPS` object otherwise. **Keep the static entries** as a safety net — if for some reason the dynamic attributes aren't populated (e.g., empty lane, edge case during state transition), the tooltip system gracefully falls back. Leave the static text as-is.

### Step 4: Handle the empty-lane case

If a lane has no cards on either side:

- `myOff = 0`, `theirDef = 0`, `net = 0`
- No bonuses to list
- Math would read: "0 − 0 = +0 yards/drive"

This is correct and informative. Don't suppress it. The player should be able to tap an empty pill and see "0 OFF, 0 DEF, no bonuses, no yards" and understand why.

If only the modifier exists but no cards: include the modifier in bonuses (e.g., "🌧️ Muddy Field — All OFF −25%, DEF +25%") so the player knows the field is set up but no math is happening yet.

### Step 5: Be careful with `computeLaneStats` side effects

This is the riskiest part. `computeLaneStats` mutates the `curOff` and `curDef` of cards in the lane. If we call it once for the render and again for the tooltip data:

- First call: cards' `curOff`/`curDef` set to base + all modifiers
- Second call: cards reset `_fieldOff/_fieldDef`, recompute — should produce same result IF the function is idempotent

Check whether `computeLaneStats` is idempotent. The original implementation should be (it resets transient fields before applying), but verify. If it's not idempotent, the safe pattern is:

```javascript
const stats = computeLaneStats(lane);
const aiBreakdown = breakdownPowerPill(lane, 'ai', stats);  // pass stats in
const youBreakdown = breakdownPowerPill(lane, 'you', stats);
```

Modify `breakdownPowerPill` to accept an optional pre-computed `stats` parameter to avoid double-mutation.

---

## Acceptance checks

- [ ] Tap on a YOU power pill → tooltip shows `YOUR NET YARDS: +X` title and a body with totals, bonuses, math
- [ ] Tap on a CPU power pill → tooltip shows `CPU NET YARDS: +X` title with the inverse breakdown
- [ ] The displayed `net` in the tooltip matches the number shown on the pill itself (no discrepancy)
- [ ] If a lane has Wildcat synergy active (2+ RBs), it shows up in "Active bonuses"
- [ ] If a lane has Air Raid modifier, it shows up in "Active bonuses"
- [ ] If a Lockdown CB is on the opposing side, the "−5 (Lockdown CB)" appears in the math line
- [ ] Tooltip with no bonuses just omits the "Active bonuses:" section entirely (no empty header)
- [ ] Modifier names with `&` (e.g., GROUND & POUND) render correctly without breaking HTML
- [ ] Empty lanes show "0 OFF · 0 DEF · 0 − 0 = +0 yards/drive"
- [ ] No JS errors when tooltips are tapped repeatedly across different lanes
- [ ] Mobile viewport (375px wide): the tooltip body fits without horizontal scroll and is fully readable
- [ ] Existing hand-card, score, energy-orb, yardage-bar, lane-medallion tooltips still work unchanged

---

## At end of work

- Run the syntax check from CLAUDE.md
- Add marker: `// === POWER PILL BREAKDOWN TOOLTIPS ===` near the new helper functions
- Report to the user with:
  - Confirmation of the change
  - One thing to playtest: in a live game, tap each of the 6 power pills (3 lanes × 2 sides) and confirm that the breakdown matches the pill's displayed value, especially in a lane with active synergies and a lane modifier.

Do not make any other changes.
