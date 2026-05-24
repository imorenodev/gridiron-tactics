# Gridiron Tactics — Claude Context

Hey Claude. This is a single-file HTML5 football card game (Marvel Snap × NFL, sort of). Below is what you need to know to make changes without breaking anything.

## The one rule that matters most

**Everything lives in one file: `gridiron-tactics.html`** (~3500 lines, HTML/CSS/JS all together). When in doubt, `grep` first — there is no module system, no build step, no bundler. The whole game opens in a browser by double-clicking the file. Do not split it into multiple files unless explicitly asked.

## What this game is

A turn-based football card game on mobile Safari (primary target) and desktop. Two opposing teams play cards across **three lanes**. Each lane has its own ball, its own field position (0–100), and a random **lane modifier**. Cards are placed face-down each drive and revealed at end of turn. After **8 drives**, whoever has more points wins.

The closest design parallel is *Marvel Snap* (locations = lanes, energy curve, simultaneous reveal). The football reskin adds touchdowns, safeties, pick-sixes, field goals, and PATs.

## File anatomy

The file has four big sections, in order:

1. **`<head>` + CSS** (top ~1100 lines): one giant `<style>` block. Mobile-first, fixed viewport, lots of `font-family: 'Bebas Neue'` for scoreboards.
2. **Screens (HTML)** (~1100–1300): each game state is a `<div class="screen" id="...">`. Only one is `.active` at a time. Screens: `menu`, `game`, `result`, `draft`, `season`, `roster`, `howModal`.
3. **Game logic (JS)** (~1450–end): one big inline `<script>`. Everything is in the global scope — there is no `import`, no closure wrapping, no module pattern. Functions call each other directly by name.
4. **Bootstrap** (last few lines): `DOMContentLoaded` listener wires up the menu and shows the start screen.

When you edit, you'll usually be in one of:
- A specific CSS rule → use `grep` to find the class name
- A specific game function → use `grep -n "function fnName"`
- A specific game screen → search for `id="screenId"`

## Architecture: the core state model

There is **one mutable global** for the active match: `state`. It looks roughly like:

```js
state = {
  turn: 1,                  // current drive (1-8)
  youEnergy, youEnergyMax,  // your energy this drive
  aiEnergy,  aiEnergyMax,
  youScore, aiScore,
  youDeck:    [...cards],   // draw pile
  aiDeck:     [...cards],
  youHand:    [...cards],   // fixed-size hand (HAND_SIZE) drawn each drive
  aiHand:     [...cards],
  youDiscard: [...cards],   // cards discarded from hand at end of drive
  aiDiscard:  [...cards],   //   (reshuffles back into deck when deck empties)
  lanes: [                  // always exactly 3
    {
      idx, name, flavor,
      modifier: {...},      // one of LANE_MODIFIERS
      youCards: [...],      // cards placed in this lane (face-down until reveal)
      aiCards:  [...],
      youPos:   25,         // ball position 0-100
      aiPos:    25,
      driveSinceScore: 0,   // for TURNOVER modifier
      lockedFor: null       // 'you' | 'ai' for SUDDEN DEATH
    },
    // ...3 lanes total
  ],
  pendingPlays: [...],      // cards staged but not yet revealed this drive
  scoringLog: [...],
  busy: false,              // disables input during animations
};
```

`state` is created by `newState(...)` in `startGame(...)`. It is replaced wholesale on game end and on quit. Never `Object.assign` into the old state — always replace.

There is also `seasonState` (persisted to localStorage as `gridiron_season_v1`) for the season run, and `draftState` for the active draft.

## The render loop

There is **no framework**. The pattern is:

1. Mutate `state` directly.
2. Call `render()` (or one of its parts: `renderLanes()`, `renderHand()`, `renderEnergy()`).
3. The render functions wipe the relevant container's `innerHTML` and rebuild it from `state`.

This means **every change requires a manual `render()` call** to be visible. Most game-loop functions end with one. If you add a new state mutation and nothing shows up on screen, you forgot to call `render()`.

Render functions don't do diffing — they fully rebuild. This is fine because the DOM is small (3 lanes × ~8 cards + hand). Don't try to optimize this with virtual DOM stuff. Direct innerHTML is simplest and fast enough.

## How a turn works (the canonical flow)

This is the most important sequence in the game. When the player clicks **END TURN**:

1. `endTurn()` is called (search for it).
2. AI picks cards: `aiMakePlays()` adds AI's plays to `state.pendingPlays`.
3. **Reveal phase** — for each pending play, in order:
   - Card flips face-up (`card.revealed = true`).
   - `applyCardSnapAbility(play)` triggers SNAP abilities. Note: BLITZ ZONE lane modifier doubles DEF SNAP triggers. FROZEN TUNDRA modifier disables all abilities.
4. **Yardage phase** — `processYardageAndScoring()`:
   - For each lane, computes `youOff/youDef/aiOff/aiDef` via `computeLaneStats(lane)`.
   - Math: `yourGain = floor(stats.youOff / 2.5)`, `yourLoss = floor(stats.aiDef / 2.5)`. `yourDelta = yourGain - yourLoss`. Apply to `lane.youPos`. Symmetric for AI.
   - Special modifiers apply here: COIN FLIP doubles/halves; TURNOVER swaps positions on inactivity.
   - `checkScoring(lane)` checks if anyone scored. Returns `'you'`, `'ai'`, or null.
5. **Draw/discard cycle** — `animateDiscardHand()` arcs unplayed hand cards to the discard pile; AI's discard/draw happens silently. Then `animateDrawHand()` draws `HAND_SIZE` cards from the deck (reshuffling discard back in if needed via `reshuffleDiscardIntoDeck`).
6. **Cleanup** — `state.turn++`, energy grant (drive N grants +N, capped at `MAX_ENERGY_BANK`), render.
7. If `state.turn > 8` → `endGame()`.

When in doubt about scoring math, trace through `computeLaneStats` → `processYardageAndScoring` → `checkScoring`. These are the source of truth.

## The card data model

A card is a plain object:

```js
{
  uid: 'a3k9z2',           // unique per instance
  id: 'card_qb_5',         // shared across all copies (for portraits)
  name: 'Patrick Mahomes',
  pos: 'QB',               // QB|RB|WR|TE|OL|DE|DT|LB|CB|S|K|ST
  team: 'KC',              // 3-letter NFL-style code
  cost: 5,                 // energy cost 1-6
  side: 'off',             // 'off' or 'def' (NEVER both)
  off: 30,                 // base offensive stat (off-side cards)
  def: 0,
  rarity: 'rare',          // common|uncommon|rare|legendary
  ability: 'SNAP: +6 OFF to this lane',  // human-readable
  desc: 'snapBuffOffLane', // ability identifier, switch on in applyCardSnapAbility
}
```

Once placed, the card gets transient fields: `curOff`, `curDef`, `revealed`, `ejected`, `flagged`, `_baseOff` (modified by snap abilities), `_fieldOff` (modified by field abilities), `_effectiveCost` (after lane discount), `_abilitiesDisabled` (frozen tundra).

Cards are generated procedurally by `generateCard(side)` using `FIRST_NAMES`, `LAST_NAMES`, `NFL_TEAMS`, `STAT_BY_COST`, `RARITY_DISTRIBUTION`, and `ABILITY_POOL`. The pool is balanced so cost roughly corresponds to power.

## Subsystems and where they live

| Subsystem | Where to look |
|---|---|
| Card generation | `generateCard`, `generateMasterPool` |
| Lane modifiers (20 total) | `LANE_MODIFIERS` array, `applyLaneModifier(lane)` |
| Card synergies (13 combos) | `SYNERGIES` array, `detectSynergies`, `applySynergies` |
| SNAP / FIELD card abilities | `applyCardSnapAbility(play)`, `applyLaneFieldEffects(lane)` |
| Scoring (TD/FG/safety/pick-6/PAT/conversion) | `processYardageAndScoring`, `checkScoring`, `scoreTouchdown`, `scoreDefense`, `kickPAT` |
| AI decision-making | `aiMakePlays()` — current heuristic is simple; needs work for harder difficulty |
| Drag and drop | `startDrag` / `onDragMove` / `onDragEnd`, plus `dragState` global |
| Tooltips | `TOOLTIPS` object, `showTooltip(key, targetEl)`, `data-tooltip="..."` attrs in HTML |
| Card portraits | `generatePortraitSVG(card, size)` returns raw SVG string, deterministic by `seedRandom(card.id)` |
| Season mode | `seasonState`, `loadSeason/saveSeason`, `OPPONENT_TEAMS`, `playSeasonMatch` |
| Draft (pack-rip) | `draftState`, `generateDraftPack`, `PACK_RARITY_TABLE`, `startPack`, `tapPackCard`, `confirmPackPicks`, `applyCardLayout`, `runAutoPickFastForward` |
| Energy: escalating gain + carryover (`MAX_ENERGY_BANK` cap) | `MAX_ENERGY_BANK` declaration, drive-transition block in `endTurn` (drive N grants +N energy, carryover capped), `renderEnergy` cap pulse, `showCarriedToast` |
| Draw / discard cycle (`HAND_SIZE` per drive, discard reshuffles when deck empties) | `HAND_SIZE` declaration, `drawCardsToHand`, `discardHand`, `reshuffleDiscardIntoDeck`, `animateDiscardHand`, `animateDrawHand`, `showReshuffleAnimation`, `openDiscardModal` |

## Conventions to follow

Match the existing style, don't introduce new patterns. Specifically:

**JavaScript:**
- `function name(args) { }` declarations. No arrow functions for top-level definitions, no classes.
- `let state = null` lives at module scope. Don't replace this with a class.
- Async operations use `await sleep(ms)` for animation pacing. The pattern `render(); await sleep(700);` is everywhere — keep it.
- Lock the UI during animations with `state.busy = true; ... ; state.busy = false`. This is checked in render to disable input.
- Errors during animations are silently swallowed. Don't add throwing.

**CSS:**
- BEM-ish hyphenated classes (`lane-medallion`, `fc-portrait`, `hc-stat-num`). No CSS modules, no Tailwind.
- Mobile-first; the only `@media` query so far is `max-width: 480px` to simplify medallions on phones. Keep that threshold.
- Heavy use of `linear-gradient` and `radial-gradient`. Layered backgrounds with `,` are normal here.
- Animations: `@keyframes name { 0%,100% {...} 50% {...} }` — keep them short (<2s, repeating).

**HTML:**
- Single root `#app` div. Screens are siblings inside it.
- Use semantic class names, but don't be precious about it. `lane-power-pill` is fine even though it's actually a rounded rect.
- For dynamic tooltips, use `data-tooltip-title` and `data-tooltip-body` attributes. They override the static `TOOLTIPS` lookup. **Always escape attribute values with `escAttr(...)`** — modifier names like "GROUND & POUND" have ampersands.

## Mobile-specific gotchas (don't undo these)

This game runs on a real phone, in real Safari. Things I learned the hard way:

- `position: fixed` on `html, body` to prevent scroll-bounce.
- `-webkit-tap-highlight-color: transparent` to kill the iOS blue flash.
- `touch-action: none` on draggable cards.
- `padding-top: calc(env(safe-area-inset-top) + 8px)` on the top bar so the notch doesn't cover the score.
- All interactive elements use `pointerdown` + `pointerup`, not `click`. Click events fire 300ms late on iOS Safari.
- The drag-vs-tap heuristic: if pointer moves <8px and releases <300ms, it's a tap. This is what makes hand-cards both draggable AND tooltippable.

## The IP concern (read before adding content)

**The current build uses real NFL team codes (KC, BUF, PHI, etc.) and real player surnames pulled from NFL rosters** (Mahomes, Allen, Hurts, etc.). This is fine for development and personal use but is **not safe to ship to App Store / Play Store**. The NFL aggressively enforces.

If the user mentions "ship", "publish", "App Store", "Google Play", or "release":
1. Flag this IP issue immediately.
2. Suggest the IP rebrand path: fictional league name, fake team codes (BLZ, RPT, KNG…), made-up player names.
3. Don't proceed with store-submission steps until the rebrand is done.

The rebrand plan is partially started but not committed — see "Roadmap" below.

## Adding a new lane modifier

The pattern:

1. Add an entry to `LANE_MODIFIERS` (id, icon, name, desc, category — one of `field|tactical|position|wild`).
2. Add a `case 'yourId':` to `applyLaneModifier(lane)` if it affects card stats.
3. If it affects scoring math instead, add handling in `processYardageAndScoring` (see COIN FLIP, TURNOVER, SUDDEN DEATH for examples).
4. If it affects abilities, check in `applyCardSnapAbility` (see FROZEN TUNDRA, BLITZ ZONE).
5. If it affects card costs, check in `effectiveCost(card, laneIdx)` (see HURRY-UP, PREVENT D).
6. Update the How To Play modal so users can learn about it.

Each modifier should be **clearly different** from existing ones in feel. Don't add "OFF +6" if one already exists. Aim for new strategic levers.

## Adding a new card synergy

1. Add an object to `SYNERGIES` with `id`, `icon`, `name`, `side`, `match(cards)`, `apply(matched)`.
2. `match` returns the matched cards (truthy) or `null`. `apply` mutates `curOff`/`curDef` on those cards.
3. Add to the How To Play modal's synergy list.
4. Test: in `computeLaneStats`, synergies are applied AFTER lane modifiers but BEFORE stat totals. If your synergy should override a modifier, that order matters.

## Things I would NOT do (until asked)

- **Don't add a backend.** Right now everything is client-only with localStorage. PvP/leaderboards/auth are explicitly planned for later.
- **Don't add ads, analytics, or telemetry.** Not in scope.
- **Don't refactor into modules.** It's a single file on purpose — easy to ship, easy to debug. Stay in the file.
- **Don't add npm/build tooling.** No package.json. The user opens the HTML file directly.
- **Don't add TypeScript.** Same reason.
- **Don't replace innerHTML rendering with a framework.** React/Vue/Svelte would be massive over-engineering for this.
- **Don't generate real player photos.** SVG silhouettes only. Even AI-generated photos invite NIL claims.
- **Don't add a "save card from discard" mechanic.** The discard cycle is the core tension — circumventing it (e.g., a Tutor ability that pulls from discard, an extra-card-per-drive perk that hoards, etc.) defeats the design's purpose. New perks should affect *what enters the cycle* (deck composition, draw quality) or *what flows through it* (hand size, draw count), not bypass it.

## Common tasks and where to start

- **"Make cards bigger/smaller"** → CSS `.field-card`, `.hand-card`, possibly `.slot-row` grid. There's also `MAX_SLOTS = 8` that affects layout.
- **"Add a new card position (e.g., FB)"** → extend `ABILITY_POOL` keys, add to `STAT_BY_COST` if needed, add to position pickers in `generateCard`.
- **"Change scoring rules"** → `scoreTouchdown`, `scoreDefense`, `kickPAT`. The `SCALE = 2.5` constant in `processYardageAndScoring` controls yardage tempo.
- **"AI is too easy/hard"** → `aiMakePlays()`. Current heuristic just plays affordable cards in the lane where it's losing. Smarter AI is open territory.
- **"Add a tooltip to X"** → add `data-tooltip="key"` to the element, add an entry to the `TOOLTIPS` object. For dynamic content, also set `data-tooltip-title` and `data-tooltip-body` with `escAttr(...)`.
- **"Change the energy cap or curve"** → the cap is a single constant: `MAX_ENERGY_BANK` (declared near `MAX_SLOTS`). The per-drive grant is `state.turn` energy (drive N grants +N), set in the `endTurn` drive-transition block. When adding leveling/perks, modify the constant (or wrap it in a getter that checks active perks). **Do not introduce a parallel cap variable** — keep this as the single source of truth. The tooltip body interpolates it (`'... up to a max of ' + MAX_ENERGY_BANK`) so user-facing copy stays in sync.
- **"Change hand size"** → modify the `HAND_SIZE` constant (declared next to `MAX_ENERGY_BANK`). It's used everywhere the cycle draws cards (`newState` initial draw, `endTurn` per-drive draw, the `deckPile` tooltip body). To make hand size depend on perks later, wrap it in a getter (e.g., `getHandSize()` that consults active perks). Don't hardcode 5 elsewhere.

## Testing

There are no automated tests. The user playtests on their phone. Before committing a change, at minimum:

```bash
# Syntax check the JS
node -e "
const fs = require('fs');
const html = fs.readFileSync('gridiron-tactics.html', 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (m) { try { new Function(m[1]); console.log('JS: OK'); } catch(e) { console.log('JS error:', e.message); } }
"
```

If that prints `JS: OK`, the file at least parses. After that, open it in a browser and play a few drives manually.

## Roadmap (what we're building toward)

In rough order:

1. **IP rebrand.** Replace NFL teams/names with fictional ones. Decisions pending: league flavor (retro-futurist / grounded / mascot / none), name style (realistic / nicknames / archetypes), possibly rename game. Files to touch: `NFL_TEAMS`, `FIRST_NAMES`, `LAST_NAMES`, `TEAM_COLORS`, `OPPONENT_TEAMS`, and the game title in `<title>`/`.menu-title`.
2. **PvP.** Will need a backend (likely Firebase Realtime DB or Supabase). Match-making, turn sync, anti-cheat (server-authoritative scoring). Beware: this breaks the "single file, no backend" simplicity. Plan it carefully.
3. **In-app purchases.** Cosmetic packs, possibly card-back skins, possibly draft chest rerolls. Don't go pay-to-win.
4. **App Store / Play Store submission.** Wrap with Capacitor. Apple Developer Program ($99/yr), Google Play ($25 once). Privacy policy required.

Any of these is multi-session work. Don't rush.

## Quick reference: filenames and IDs

- Main file: `gridiron-tactics.html`
- localStorage key: `gridiron_season_v1`
- Top-level screen IDs: `menu`, `game`, `result`, `draft`, `season`, `roster`
- Modals: `howModal`
- Important DOM IDs: `lanes`, `hand`, `youScore`, `aiScore`, `energyOrb`, `playBtn`, `tooltipOverlay`, `tooltipBubble`

That's the lay of the land. When in doubt: grep, read the relevant function, then make the smallest possible change.
