# Gridiron Tactics — Phaser Build-Out Prompt

You're continuing work on **Gridiron Tactics**, a card-based football game I started rebuilding in Phaser 3 from a vanilla-DOM original. Phase 1 (core match loop) is done. Your job is to bring the Phaser build up to feature-parity with the original DOM version, then polish.

## Repository layout

```
index.html              # Phaser game — single HTML file with inline <script>
assets/ui/*.png         # Card frames, portraits, icons, UI panels (already optimized)
assets/ui/icons/        # Position icons (pos_*.png), modifier icons (mod_*.png)
assets/ui/26_portraits/ # Player portraits (currently just qb_black_navy.png)
ORIGINAL.html           # The vanilla-DOM source — game logic reference only
                        # (Note: you write Phaser code, not DOM code. ORIGINAL.html
                        #  exists only to look up rules, ability effects, formulas,
                        #  and content tables that aren't yet ported.)
```

If `ORIGINAL.html` isn't in the repo yet, ask me for it — it's the source of truth for game rules and content.

## Ground rules

1. **Keep it a single-file Phaser app.** All code in `index.html`'s inline `<script>`. Phaser is loaded from CDN. No build step, no bundler, no npm.
2. **Don't break what works.** Run a smoke test after each feature: load the menu, start a match, play 8 drives end-to-end, return to menu, replay. If any of that breaks, fix before continuing.
3. **Reuse existing helpers.** `buildCard()`, `sfx()`, `showFloat()`, `showScoreBurst()`, `CARD_LAYOUT`, `POS_ICON_MAP`, `LANE_MODIFIERS` are already there. Extend them; don't reinvent.
4. **Asset-first rendering.** Where the original uses graphics primitives but an asset exists in `assets/ui/`, prefer the asset. (Example: pill UI for power values uses `power_circle_green`/`power_circle_red`, not a drawn circle.)
5. **State lives in `G`.** The single global `G` object holds match state. Persistent player progress goes in `playerData` (load/save via `localStorage` — see the original's `loadPlayerData`/`savePlayerData`).
6. **Phaser scenes are the unit of UI.** Add a new scene for each major screen (DraftScene, SeasonHubScene, LockerRoomScene, etc.) rather than overloading existing scenes.
7. **Touch + mouse parity.** All input must work with both pointer events. Use Phaser's `setInteractive` and `setDraggable` — don't add raw DOM event listeners.
8. **No dead code.** If you port something from the original, port the working version, not the commented-out one.

## What's already done (don't redo)

- BootScene with full asset preload + progress bar
- MenuScene (logo, stadium bg, PLAY / HOW TO PLAY buttons, modal)
- GameScene with: 3 lanes, drag-and-drop hand → lane, snap reveal, AI plays, scoring (TDs / PATs via Kicker / safeties / pick-sixes when ≥3 DBs), 8-drive flow, energy escalation + bank cap, discard/draw cycle, lane modifiers (11 of them — see `LANE_MODIFIERS`), procedural card generation w/ 4 rarities, power-pill net yards display, yardage bars w/ football marker, scoreboard
- EndScene with VICTORY / DEFEAT / TIE result + replay/menu buttons
- Web Audio synth SFX (play, snap, td, fg, safety, click, reveal)
- Card frame rendering via `buildCard()` — frame asset + portrait + cost + position + name + stat + ability star, anchored by `CARD_LAYOUT` hole fractions

## What to build (in this order)

### Phase 1 — Card abilities (high impact, all logic, no new UI)

The original has SNAP abilities (fire on reveal) and FIELD abilities (passive while in lane). They're defined in `ABILITY_POOL` in `ORIGINAL.html`. Port the full ability system.

**Acceptance criteria:**
- `generateCard()` rolls an ability based on rarity (common 15% / uncommon 35% / rare 70% / legendary 100%, matching the original)
- Card object gains an `ability` (display string) and `desc` (effect id like `snapDraw`, `fieldBuffOff`) field
- `applyCardSnapAbility()` exists in GameScene and runs during reveal in winner-first order (matching original's `revealAllPending`)
- All 9 OFF + 7 DEF effects from the original work: `snapDraw`, `snapBuffOffLane`, `snapStealYards`, `snapFieldGoal`, `snapBuffAllOff`, `fieldBuffOff`, `fieldBuffOffAll`, `fieldBuffAllOff`, `snapDebuffEnemyOff`, `snapDefYards`, `snapPunt`, `fieldBuffDef`, `fieldYardBlock`, `fieldDebuffAll`, `fieldBuffAllDef`
- Lane modifiers `frozenTundra` (abilities disabled) and `blitzZone` (DEF SNAP abilities trigger twice) are respected
- Kickers with a clear field position auto-attempt a 3-pt FG on reveal, ending the drive in that lane if successful (per `snapFieldGoal` in original)
- The gold ability star already drawn by `buildCard()` continues to appear for cards with abilities (not just rare/legendary — update the `hasAbility` flag logic)

### Phase 2 — Card synergies

The original has 13 synergies (PLAY ACTION, SPREAD, POCKET, RED ZONE, WILDCAT, TRICK PLAY, FIELD GEN, ZONE D, STRONG SAFETY, STACKED FRONT, BLITZ, SECONDARY, KICKING UNIT). They're defined in `SYNERGIES` in `ORIGINAL.html`. Port them.

**Acceptance criteria:**
- `detectSynergies(cards)` and `applySynergies(cards)` exist in the Phaser code
- Each lane shows active synergies as small badges near that side's row (similar to the original's `.synergy-badge`)
- Stats reflect synergy bonuses in `computeLaneStats()` and therefore in the power pills
- KICKING UNIT synergy lowers the FG threshold from 50 to 35 yards (per original)

### Phase 3 — 2-point conversion coin flip

After a TD without a Kicker, if the scorer has more OFF cards in the lane than the opponent has DEF cards, offer a 2-pt conversion.

**Acceptance criteria:**
- Player TDs open a modal scene (or modal layer) showing the lane's matchup, a "GO FOR 2" / "KICK PAT" choice. PAT is auto-good (+1). 2-pt opens a coin-flip mini-game.
- Coin flip uses `assets/ui/30_coin_heads.png` and `31_coin_tails.png`. Player taps HEADS or TAILS; coin spins (CSS-style 3D flip in Phaser — rotate Y and swap sprite at midpoint, or use a scale-X trick); match = +2 points, miss = no points.
- AI TDs auto-resolve: 50% chance to attempt, 50% chance to convert (matches original's odds).
- Sound effect on flip start + on result (use the synth, no extra audio assets).

### Phase 4 — Draft mode

A 10-pack draft that builds a 50-card deck for Season mode. See `startSeasonDraft` and friends in `ORIGINAL.html`.

**Acceptance criteria:**
- New `DraftScene` reachable from a "DRAFT & PLAY SEASON" button on the menu
- 30 starter commons granted up front (15 OFF + 15 DEF, balanced positions per `STARTER_POSITION_PLAN`)
- 10 packs of 6 cards each (3 OFF + 3 DEF), escalating rarity per `PACK_RARITY_TABLE`
- Per pack: cards reveal one at a time with flip animation (back → front), rare cards get a flash, legendaries get screen shake + a stronger flash (use `cameras.main.shake()` for the shake)
- Player picks 1 OFF + 1 DEF per pack. Tapping a card highlights it; tapping another card on the same side swaps the pick.
- 12-second timer per pack (15s for final pack); auto-picks highest stat on timeout
- "AUTO-PICK REMAINING" button to fast-forward through remaining packs (preserves user picks so far)
- After 10 packs: 30 + 10*2 = 50-card deck saved to `seasonState.roster` in localStorage
- Use `assets/ui/07_button_snap.png` and `07_button_concede.png` for action buttons, and the card frame assets for pack cards

### Phase 5 — Season mode

A 7-game gauntlet using the drafted deck. See `OPPONENT_TEAMS`, `enterSeason`, `playSeasonMatch` in `ORIGINAL.html`.

**Acceptance criteria:**
- New `SeasonHubScene` showing: current week (1-7), trophies earned, next opponent name + tier (1-7 stars) + flavor text
- Match button starts a GameScene with `state.mode = 'season'`, the drafted roster as the player deck, and an AI deck whose stat bonus scales with opponent tier
- Win → advance to next opponent, save season state to localStorage
- Loss → season ends, clear state, return to menu with a "BETTER LUCK NEXT TIME" toast
- Win after week 7 (Dynasty) → "CHAMPIONS!" banner in the end-of-match summary, then back to menu with cleared season state
- "CONTINUE SEASON" button on menu appears when a season is in progress (check localStorage on menu load)
- "VIEW ROSTER" button in the hub opens a RosterScene listing all 50 cards grouped by OFF/DEF and sorted by cost

### Phase 6 — Match summary screen

Replace the current direct-to-EndScene flow with the original's animated post-match dopamine screen. See `showMatchSummary` and `runSummarySequence` in `ORIGINAL.html`.

**Acceptance criteria:**
- New `MatchSummaryScene` that runs between GameScene end and EndScene/MenuScene
- Sequence: result banner pops in → score + opponent fade in → XP earned ticks up → cash earned ticks up → reward breakdown lines stagger in → XP bar animates filling toward next level (pausing for level-ups) → perk-unlock banner appears if a perk unlocked → CONTINUE button slides up
- XP curve per `xpRequiredForLevel()` in original
- Match rewards per `calculateMatchRewards()`: base XP/cash scaled by opponent tier, +50 XP +$200 first match of day, +50 XP shutout bonus, +50 XP comeback win
- "First match today" tracked in `playerData.daily.lastMatchDate`
- Level-ups grant cash (`100 * newLevel`) and unlock perks at preset levels (per `PERK_POOL`)
- Tick SFX during XP/cash counters, level-up SFX on each level boundary
- Save `playerData` after applying rewards

### Phase 7 — Locker Room (perk loadout)

See the locker-room section of `ORIGINAL.html` (`openLockerRoom`, `renderLockerRoom`, `tryEquipPerk`, etc.).

**Acceptance criteria:**
- New `LockerRoomScene` reachable from a "LOCKER ROOM" button on the menu
- Shows current cash, 3 equipped-perk slots, and a grid of all 7 Tier 1 perks from `PERK_POOL`
- Locked perks show "UNLOCK AT LV X" overlay
- Tapping an unlocked perk: empty slot → equip free; all slots full → "swap?" modal asking which to replace, costs $25, blocks if not enough cash
- Tapping an equipped slot's UNEQUIP button removes the perk (free)
- Equipped perks take effect in matches:
  - `bigHand` → `getHandSize('you')` returns 6 instead of 5
  - `banker` → `getMaxEnergyBank('you')` returns 12 instead of 10
  - `airItOut`, `groundGame`, `runStuffer`, `coverageCoach` → `+3` to relevant stat in `computeLaneStats` (port `applyPerkStatBuffs`)
  - `quickReads` → `+2` extra energy on drive 1 of new matches
- "RESET PROGRESS" link triple-confirms (confirm + confirm + type "DELETE") before nuking `playerData`

### Phase 8 — Polish & feel

Once everything functional is in, focus on game feel:

- **Card draw/discard animation:** cards arc from deck-badge position to hand on draw, arc from hand to discard-badge on drive end (the original does this — see `animateDiscardHand` and `animateDrawHand`)
- **Reshuffle moment:** when deck empties and discard reshuffles in, pulse the discard badge + play a swish SFX
- **Tap-to-inspect cards:** in hand and on field, a tap (not drag) opens a larger card view as a modal overlay
- **Tooltips:** tappable explanations for score, energy, yardage bar, modifier medallion, etc. (port `TOOLTIPS` from original — use Phaser containers as bubbles)
- **Tutorial first-run flag:** if `playerData.tutorialSeen` is false, queue a couple of contextual hints on the player's first match
- **Reduced motion:** respect `window.matchMedia('(prefers-reduced-motion: reduce)').matches` — skip the longer tween animations
- **High-DPI sharpness:** check that card text doesn't look blurry on retina displays; bump card frame texture resolution if needed

## How to test as you go

After each phase, do a "real-world" pass:

1. `python3 -m http.server 8000` in the repo root
2. Open `http://localhost:8000` in Chrome and in mobile Safari (or Chrome's mobile emulation)
3. Run through the new feature end-to-end
4. Open DevTools console — must be zero red errors during normal play (warnings are OK)
5. Check localStorage tabs after the run; confirm save shape matches the original (`gridiron_player_v1`, `gridiron_season_v1`)

## Style guide

- **Comments where intent isn't obvious**, not where the code is self-explanatory. ("Why" notes good; "increment x" bad.)
- **No `var`.** `const` by default, `let` only when reassigning.
- **Avoid magic numbers** that the original has as named constants (`MAX_SLOTS`, `HAND_SIZE`, `MAX_DRIVES`, etc.). Reuse the existing ones.
- **Phaser idioms:**
  - Containers for grouped elements that move/scale together
  - `setInteractive({ useHandCursor: true })` for clickable things
  - Tweens over `setTimeout` for any visual animation
  - `scene.time.delayedCall(ms, fn)` over `setTimeout` for non-visual delays
- **Names match the original** where possible — makes diffing easier. (`G`, `playerData`, `seasonState`, `draftState`, `LANE_MODIFIERS`, `SYNERGIES`, `PERK_POOL`.)

## When you're stuck

- **Game logic question:** look in `ORIGINAL.html` first. The function names there should match what you're porting.
- **Asset placement question:** the `CARD_LAYOUT` constant has hole-region fractions measured from the actual card frame PNG. Other UI assets use natural aspect ratios — read width/height from `scene.textures.get(key).source[0]`.
- **Phaser API question:** [phaser.io/learn](https://phaser.io/learn) and [labs.phaser.io](https://labs.phaser.io/) — favor 3.70+ examples.
- **Anything else:** ask me. Don't guess on rules — better to clarify than to ship a subtly-wrong port that I have to unwind later.

Start with Phase 1. Show me what you have when SNAP abilities + FIELD abilities both work end-to-end, then we'll move on.
