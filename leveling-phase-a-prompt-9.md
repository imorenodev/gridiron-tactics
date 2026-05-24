# Leveling System — Phase A: Cash + Coach Level + 7 Perks + Locker Room + Match Summary

## Context

This is the foundation phase of the leveling/perks system designed in `leveling-system-design.md`. Read that design doc first if you haven't.

What we're shipping in this phase:
1. **Player data persistence** — `gridiron_player_v1` localStorage save, separate from existing season data
2. **Cash currency** — earned from matches, displayed in UI
3. **Coach Level + XP** — single progression spine, level 1 → 50 curve
4. **7 Tier 1 perks** — Big Hand, Banker, Air It Out, Ground Game, Run Stuffer, Coverage Coach, Quick Reads
5. **Locker Room** — new menu screen with Loadout tab (other tabs come in later phases)
6. **Match-end summary screen** — dopamine moment: animated XP bar, ticking cash, level-up flash
7. **Perk effect integration** — getter functions replace direct constant reads; perks modify match logic

**Read CLAUDE.md and `leveling-system-design.md` before writing any code.** Inspect the current state of `gridiron-tactics.html` to understand existing references to `HAND_SIZE`, `MAX_ENERGY_BANK`, `computeLaneStats`, the season screen, and the match-end flow.

This is a substantial change touching many parts of the codebase. **Build in the sub-phase order below. Do not skip sub-phases.** After each sub-phase, run the syntax check and stop for the user to playtest before continuing.

---

## Hard rules

1. **Single file. No build tooling. No modules.** Follow CLAUDE.md.
2. **Don't break existing functionality.** Quick Play, Season mode, Draft, in-match game logic — all must work end-to-end after each sub-phase.
3. **Player data is sacred.** Wrap every `localStorage.setItem` and `localStorage.getItem` in try/catch. Never throw from a save/load operation — degrade gracefully, never corrupt.
4. **Backward compatibility.** A player who already has an in-progress season (`gridiron_season_v1`) should not lose it. Player data starts fresh (level 1, $0) on first load only if the player key doesn't exist yet.
5. **No new dependencies.** Synthesize sounds via existing Web Audio helpers. Use DOM/CSS for any animations.
6. **Phase A perk effects only.** Don't speculatively code Tier 2 or Tier 3 perk hooks — keep the perk-application code lean for now.

---

## Sub-phase 1: Player data layer

### Add the data structure and persistence functions

Place a new section near the top of the JS, after `MAX_ENERGY_BANK` and `HAND_SIZE`:

```javascript
// ============================================================
// PLAYER DATA — meta-progression that persists across matches
// Saved to localStorage under 'gridiron_player_v1'.
// Separate from in-progress season state (gridiron_season_v1).
// ============================================================

const PLAYER_DATA_KEY = 'gridiron_player_v1';
const PLAYER_DATA_VERSION = 1;

function defaultPlayerData() {
  return {
    version: PLAYER_DATA_VERSION,
    cash: 0,
    coachLevel: 1,
    coachXp: 0,
    prestigeLevel: 0,
    perksUnlocked: ['bigHand'],   // Big Hand is the starter perk, unlocked at level 1
    perksEquipped: [],            // empty until player equips one
    trophies: {},                  // populated in Phase B
    stats: {
      totalMatches: 0,
      totalWins: 0,
      totalLosses: 0,
      currentWinStreak: 0,
      longestWinStreak: 0,
      pickSixes: 0,
      shutouts: 0,
      comebacks: 0
    },
    daily: {},                     // populated in Phase C
    seasonPass: {},                // populated in Phase D
    cosmeticsUnlocked: []          // populated in Phase F
  };
}

let playerData = null;  // populated by loadPlayerData() at app start

function loadPlayerData() {
  try {
    const raw = localStorage.getItem(PLAYER_DATA_KEY);
    if (!raw) {
      playerData = defaultPlayerData();
      savePlayerData();
      return;
    }
    const parsed = JSON.parse(raw);
    // Migration check
    if (!parsed.version || parsed.version < PLAYER_DATA_VERSION) {
      playerData = migratePlayerData(parsed);
      savePlayerData();
      return;
    }
    // Validation: ensure required top-level fields exist
    playerData = Object.assign(defaultPlayerData(), parsed);
    // Fill missing nested fields with defaults
    playerData.stats = Object.assign(defaultPlayerData().stats, parsed.stats || {});
  } catch (e) {
    console.error('Failed to load player data, starting fresh:', e);
    playerData = defaultPlayerData();
    try { savePlayerData(); } catch (e2) { /* swallow */ }
  }
}

function savePlayerData() {
  try {
    localStorage.setItem(PLAYER_DATA_KEY, JSON.stringify(playerData));
  } catch (e) {
    console.error('Failed to save player data:', e);
    // Don't throw — degrade gracefully. Player can continue this session.
  }
}

function migratePlayerData(oldData) {
  // For Phase A, just merge with defaults. Future migrations branch on version.
  const fresh = defaultPlayerData();
  return Object.assign(fresh, oldData, { version: PLAYER_DATA_VERSION });
}
```

### Call `loadPlayerData()` at app start

Find the `DOMContentLoaded` listener at the bottom of the file. Add `loadPlayerData()` as the first thing that runs:

```javascript
document.addEventListener('DOMContentLoaded', () => {
  loadPlayerData();
  // ... existing setup
});
```

### Add a clear-progress debug option

Add to settings (or wherever menu options live) a hidden/double-confirm "Clear Player Progress" option. Three tap confirmations required. This is for testing and player-requested resets. Hide it behind a small "Reset" link in the bottom of the Locker Room (we'll build the Locker Room next).

```javascript
function clearPlayerData() {
  try {
    localStorage.removeItem(PLAYER_DATA_KEY);
    playerData = defaultPlayerData();
    savePlayerData();
    location.reload();  // simplest way to reset all UI state
  } catch (e) {
    console.error(e);
  }
}
```

### Acceptance for Sub-phase 1

- [ ] On first load of the updated app, `gridiron_player_v1` is created in localStorage with the default shape
- [ ] On subsequent loads, the existing player data is read back correctly
- [ ] `gridiron_season_v1` is unaffected — players with an in-progress season can still resume it
- [ ] `savePlayerData()` survives a corrupted JSON without crashing the game
- [ ] `loadPlayerData()` survives a missing key without crashing
- [ ] Add marker: `// === LEVELING PHASE A — SUB-PHASE 1 (DATA LAYER) ===`
- [ ] Run syntax check
- [ ] **Stop. Tell the user to playtest: open the app, verify the game still works normally, then inspect localStorage in DevTools to confirm the `gridiron_player_v1` key exists. Wait for confirmation before continuing.**

---

## Sub-phase 2: The 7 perks + getter functions

### Define the perk pool

Add this near the player data section:

```javascript
// ============================================================
// PERKS — equippable bonuses that modify match behavior
// Phase A ships 7 Tier 1 perks; more added in Phase B / E.
// ============================================================

const PERK_POOL = [
  { id: 'bigHand',       name: 'BIG HAND',        icon: '🃏', tier: 1, unlockLevel: 1,  desc: 'Hand size +1' },
  { id: 'banker',        name: 'BANKER',          icon: '💰', tier: 1, unlockLevel: 3,  desc: 'Energy bank +2' },
  { id: 'airItOut',      name: 'AIR IT OUT',      icon: '🏈', tier: 1, unlockLevel: 5,  desc: 'WR and TE cards +3 OFF' },
  { id: 'groundGame',    name: 'GROUND GAME',     icon: '💪', tier: 1, unlockLevel: 7,  desc: 'RB cards +3 OFF' },
  { id: 'runStuffer',    name: 'RUN STUFFER',     icon: '🛡️', tier: 1, unlockLevel: 9,  desc: 'DL cards +3 DEF' },
  { id: 'coverageCoach', name: 'COVERAGE COACH',  icon: '🦅', tier: 1, unlockLevel: 11, desc: 'DB cards +3 DEF' },
  { id: 'quickReads',    name: 'QUICK READS',     icon: '⚡', tier: 1, unlockLevel: 13, desc: '+2 extra energy on drive 1' }
];

function getPerk(perkId) {
  return PERK_POOL.find(p => p.id === perkId);
}

function hasPerk(perkId) {
  return playerData && playerData.perksEquipped && playerData.perksEquipped.includes(perkId);
}
```

### Add getter functions

These replace direct constant reads. **Find every existing reference to `HAND_SIZE` and `MAX_ENERGY_BANK` in the file** and replace them with the getter functions.

```javascript
function getHandSize() {
  let size = HAND_SIZE;
  if (hasPerk('bigHand')) size += 1;
  return size;
}

function getMaxEnergyBank() {
  let cap = MAX_ENERGY_BANK;
  if (hasPerk('banker')) cap += 2;
  return cap;
}
```

**Critical**: grep for `HAND_SIZE` and `MAX_ENERGY_BANK`:
- Every read becomes `getHandSize()` or `getMaxEnergyBank()`
- The original `const HAND_SIZE = 5` and `const MAX_ENERGY_BANK = 10` declarations stay as the base values
- Don't accidentally replace the declarations themselves

### Add `applyPerkStatBuffs(lane)` to the match logic

This applies stat-modifier perks (Air It Out, Ground Game, Run Stuffer, Coverage Coach) to the player's revealed cards in a lane. Insert it during `computeLaneStats(lane)` — specifically, AFTER lane modifier effects but BEFORE synergy effects (so synergies stack on top of perk buffs, which feels right).

```javascript
function applyPerkStatBuffs(lane) {
  // Only buffs YOUR cards. CPU plays vanilla.
  const youCards = lane.youCards.filter(c => c.revealed && !c.ejected);
  
  if (hasPerk('airItOut')) {
    youCards.filter(c => c.pos === 'WR' || c.pos === 'TE').forEach(c => { c.curOff += 3; });
  }
  if (hasPerk('groundGame')) {
    youCards.filter(c => c.pos === 'RB').forEach(c => { c.curOff += 3; });
  }
  if (hasPerk('runStuffer')) {
    youCards.filter(c => c.pos === 'DE' || c.pos === 'DT').forEach(c => { c.curDef += 3; });
  }
  if (hasPerk('coverageCoach')) {
    youCards.filter(c => c.pos === 'CB' || c.pos === 'S').forEach(c => { c.curDef += 3; });
  }
}
```

Wire it into `computeLaneStats` right after `applyLaneModifier(lane)` and before `applySynergies(...)`.

### Wire Quick Reads into match start

The "+2 extra energy on drive 1" perk should grant bonus energy when drive 1 begins. Find the match-start energy initialization (it likely lives in `newState()` or in the drive-transition code where `state.turn === 1`). Add:

```javascript
if (hasPerk('quickReads')) {
  state.youEnergy += 2;
  // Cap at MAX_ENERGY_BANK using the getter
  state.youEnergy = Math.min(getMaxEnergyBank(), state.youEnergy);
}
```

### Acceptance for Sub-phase 2

- [ ] All references to `HAND_SIZE` and `MAX_ENERGY_BANK` in the JS are now `getHandSize()` and `getMaxEnergyBank()` — verify with grep
- [ ] The constants themselves are still declared (as base values)
- [ ] With `bigHand` equipped, the hand draws 6 cards instead of 5
- [ ] With `banker` equipped, energy bank cap is 12 instead of 10
- [ ] With `airItOut` equipped, WR/TE cards get +3 OFF in `computeLaneStats` output
- [ ] With `quickReads` equipped, you start drive 1 with 3 energy (1 base + 2 bonus)
- [ ] Without any perks equipped, the game plays identically to before this phase
- [ ] Add marker: `// === LEVELING PHASE A — SUB-PHASE 2 (PERKS DEFINED) ===`
- [ ] Run syntax check
- [ ] **Stop. Tell the user to playtest: temporarily set `playerData.perksEquipped = ['bigHand', 'banker', 'airItOut']` via DevTools console, start a match, verify hand size, energy cap, and WR/TE buffs. Wait for confirmation.**

---

## Sub-phase 3: Locker Room screen (Loadout tab only)

### Add the screen HTML

Add a new `<div class="screen" id="lockerRoom">` to the HTML, similar to the existing menu/game/season screens. Mark up the structure for three tabs but only populate the Loadout tab in Phase A.

```html
<div class="screen" id="lockerRoom">
  <div class="locker-header">
    <button class="back-btn" onclick="showScreen('menu')">← BACK</button>
    <h1>LOCKER ROOM</h1>
    <div class="locker-cash">💵 <span id="lockerCashDisplay">0</span></div>
  </div>
  <div class="locker-tabs">
    <button class="locker-tab active" data-tab="loadout" onclick="switchLockerTab('loadout')">LOADOUT</button>
    <button class="locker-tab" data-tab="trophies" onclick="switchLockerTab('trophies')" disabled>TROPHIES <span class="coming-soon">SOON</span></button>
    <button class="locker-tab" data-tab="progress" onclick="switchLockerTab('progress')" disabled>PROGRESS <span class="coming-soon">SOON</span></button>
  </div>
  <div class="locker-content">
    <div class="locker-tab-content" id="loadoutTab">
      <div class="loadout-equipped">
        <h3>EQUIPPED (3 SLOTS)</h3>
        <div class="equipped-slots" id="equippedSlots"></div>
      </div>
      <div class="loadout-pool">
        <h3>YOUR PERKS</h3>
        <div class="perk-pool-grid" id="perkPoolGrid"></div>
      </div>
      <div class="locker-footer">
        <button class="reset-link" onclick="confirmClearProgress()">Reset Progress</button>
      </div>
    </div>
  </div>
</div>
```

### Add a menu button

Add a "LOCKER ROOM" button to the main menu, positioned alongside the existing Quick Play / Season / Draft / Roster buttons.

### CSS

Match the existing menu/game/season aesthetic. Bebas Neue headers, dark backgrounds, gold accents. The equipped slots are 3 horizontal card-shaped boxes — empty slots show a dashed border + "EMPTY" label; filled slots show the perk icon + name. The pool grid is a responsive grid of perk cards.

Each perk card:
- Locked: silhouette with "Unlock at Coach Level X" overlay, grayed out, non-interactive
- Unlocked but unequipped: full color, tap to equip (costs 25 Cash if all 3 slots are full — show confirm modal in that case)
- Unlocked and equipped: gold border + "EQUIPPED" badge, tap to unequip (free)

### JS: render and interaction

```javascript
function renderLockerRoom() {
  document.getElementById('lockerCashDisplay').textContent = playerData.cash.toLocaleString();
  renderEquippedSlots();
  renderPerkPool();
}

function renderEquippedSlots() {
  const cont = document.getElementById('equippedSlots');
  cont.innerHTML = '';
  for (let i = 0; i < 3; i++) {
    const perkId = playerData.perksEquipped[i];
    const slot = document.createElement('div');
    slot.className = 'equipped-slot';
    if (perkId) {
      const perk = getPerk(perkId);
      slot.classList.add('filled');
      slot.innerHTML = `
        <div class="perk-icon">${perk.icon}</div>
        <div class="perk-name">${perk.name}</div>
        <div class="perk-desc">${perk.desc}</div>
        <button class="unequip-btn" onclick="unequipPerk('${perkId}')">UNEQUIP</button>
      `;
    } else {
      slot.classList.add('empty');
      slot.innerHTML = `<div class="empty-label">EMPTY</div>`;
    }
    cont.appendChild(slot);
  }
}

function renderPerkPool() {
  const cont = document.getElementById('perkPoolGrid');
  cont.innerHTML = '';
  PERK_POOL.forEach(perk => {
    const unlocked = playerData.perksUnlocked.includes(perk.id);
    const equipped = playerData.perksEquipped.includes(perk.id);
    const card = document.createElement('div');
    card.className = 'perk-card' + (unlocked ? '' : ' locked') + (equipped ? ' equipped' : '');
    card.innerHTML = `
      <div class="perk-card-icon">${perk.icon}</div>
      <div class="perk-card-name">${perk.name}</div>
      <div class="perk-card-desc">${perk.desc}</div>
      ${unlocked ? '' : `<div class="lock-overlay">UNLOCK AT LV ${perk.unlockLevel}</div>`}
      ${equipped ? '<div class="equipped-badge">EQUIPPED</div>' : ''}
    `;
    if (unlocked && !equipped) {
      card.addEventListener('click', () => tryEquipPerk(perk.id));
    }
    cont.appendChild(card);
  });
}

function tryEquipPerk(perkId) {
  const emptySlot = playerData.perksEquipped.findIndex(p => !p);
  if (emptySlot === -1 && playerData.perksEquipped.length < 3) {
    // there's room
    playerData.perksEquipped.push(perkId);
    savePlayerData();
    renderLockerRoom();
    return;
  }
  if (playerData.perksEquipped.length < 3) {
    playerData.perksEquipped.push(perkId);
    savePlayerData();
    renderLockerRoom();
    return;
  }
  // All 3 slots are full — show swap modal
  showSwapPerkModal(perkId);
}

function showSwapPerkModal(newPerkId) {
  // Show a modal listing the 3 equipped perks; tapping one swaps it for newPerkId for 25 cash
  // If player has <25 cash, disable the modal options and show "Need $25 to swap"
  // Implementation: similar to existing modals in the codebase
  // After swap: deduct 25 cash, save, re-render
}

function unequipPerk(perkId) {
  playerData.perksEquipped = playerData.perksEquipped.filter(p => p !== perkId);
  savePlayerData();
  renderLockerRoom();
}

function switchLockerTab(tab) {
  // Only 'loadout' is active in Phase A; others are disabled
  // Update tab classes and content visibility
}

function confirmClearProgress() {
  // 3-step confirmation: "Are you sure?" → "Really sure?" → "Type DELETE to confirm" or similar friction
  // Calls clearPlayerData() on full confirmation
}
```

### Acceptance for Sub-phase 3

- [ ] Locker Room button visible on main menu
- [ ] Tapping it opens the Locker Room screen
- [ ] Loadout tab shows 3 equipped slots (initially all empty)
- [ ] Perk pool shows all 7 perks; Big Hand is unlocked at level 1, others show "Unlock at Coach Level X"
- [ ] Tapping an unlocked perk equips it (if a slot is empty)
- [ ] When all 3 slots are full, tapping a new perk shows a swap modal (costs 25 Cash)
- [ ] Tapping EQUIPPED on a slot unequips it (free)
- [ ] Trophies and Progress tabs show as disabled with "SOON" label
- [ ] Reset Progress link works with 3-step confirmation
- [ ] Back button returns to main menu
- [ ] All changes save to localStorage immediately
- [ ] Add marker: `// === LEVELING PHASE A — SUB-PHASE 3 (LOCKER ROOM) ===`
- [ ] Run syntax check
- [ ] **Stop. Tell the user to playtest: open the Locker Room, equip Big Hand, start a match, verify hand size is 6 not 5. Wait for confirmation.**

---

## Sub-phase 4: Match-end summary screen (the dopamine moment)

This replaces or augments the existing "Match Result" screen with a richer, more rewarding experience.

### XP and Cash calculation

After every match, calculate rewards:

```javascript
function calculateMatchRewards(matchResult) {
  // matchResult: { won: bool, opponent: opponentObj, finalScore: {you, ai}, stats: {...} }
  const opponentTier = matchResult.opponent ? matchResult.opponent.tier : 1;  // 1 for Quick Play
  
  let baseXp = matchResult.won ? 75 : 25;
  let baseCash = matchResult.won ? 150 : 50;
  
  let xpEarned = baseXp * opponentTier;
  let cashEarned = baseCash;
  
  const breakdown = [
    { label: matchResult.won ? 'Match Won' : 'Match Played', xp: baseXp, cash: baseCash }
  ];
  if (opponentTier > 1) {
    const tierBonus = baseXp * (opponentTier - 1);
    breakdown.push({ label: `Tier ${opponentTier} Opponent`, xp: tierBonus, cash: 0 });
  }
  
  // Daily first-match bonus
  if (!playerDataPlayedAMatchToday()) {
    xpEarned += 50;
    cashEarned += 200;
    breakdown.push({ label: 'First Match Today', xp: 50, cash: 200 });
    markPlayerPlayedToday();
  }
  
  // Perfect shutout bonus
  if (matchResult.won && matchResult.finalScore.ai === 0) {
    xpEarned += 50;
    breakdown.push({ label: 'Perfect Shutout', xp: 50, cash: 0 });
  }
  
  // Comeback bonus
  if (matchResult.won && matchResult.stats.wasTrailingBy14AtHalftime) {
    xpEarned += 50;
    breakdown.push({ label: 'Comeback Win', xp: 50, cash: 0 });
  }
  
  return { xpEarned, cashEarned, breakdown };
}

function playerDataPlayedAMatchToday() {
  const today = new Date().toISOString().slice(0,10);
  return playerData.daily && playerData.daily.lastMatchDate === today;
}

function markPlayerPlayedToday() {
  if (!playerData.daily) playerData.daily = {};
  playerData.daily.lastMatchDate = new Date().toISOString().slice(0,10);
}
```

### XP curve and level-up logic

```javascript
function xpRequiredForLevel(level) {
  if (level <= 5) return 100;
  if (level <= 15) return 200 + (level - 5) * 50;  // 250, 300, 350...
  if (level <= 30) return 800 + (level - 15) * 100;  // 900, 1000...
  if (level <= 50) return 2500 + (level - 30) * 200;
  return 7000;
}

function applyXpAndLevelUp(xpToAdd) {
  // Returns array of { newLevel, perkUnlocked, cashReward } for each level-up
  const levelUps = [];
  playerData.coachXp += xpToAdd;
  while (playerData.coachLevel < 50 && playerData.coachXp >= xpRequiredForLevel(playerData.coachLevel + 1)) {
    playerData.coachXp -= xpRequiredForLevel(playerData.coachLevel + 1);
    playerData.coachLevel++;
    const cashReward = 100 * playerData.coachLevel;
    playerData.cash += cashReward;
    let perkUnlocked = null;
    // Unlock perks at their unlockLevel
    PERK_POOL.forEach(perk => {
      if (perk.unlockLevel === playerData.coachLevel && !playerData.perksUnlocked.includes(perk.id)) {
        playerData.perksUnlocked.push(perk.id);
        perkUnlocked = perk;
      }
    });
    levelUps.push({ newLevel: playerData.coachLevel, perkUnlocked, cashReward });
  }
  if (playerData.coachLevel >= 50) {
    // Cap XP at level 50 for now; Phase E adds prestige
    playerData.coachXp = 0;
  }
  savePlayerData();
  return levelUps;
}
```

### Match-end summary screen

When a match ends, instead of jumping straight to the menu / season hub, show a polished summary screen with sequenced animations.

```html
<div class="screen" id="matchSummary">
  <div class="summary-header">
    <div class="summary-result" id="summaryResult">VICTORY</div>
    <div class="summary-score" id="summaryScore">YOU 24 — CPU 17</div>
    <div class="summary-opponent" id="summaryOpponent">vs. Wildcats</div>
  </div>
  
  <div class="summary-rewards">
    <div class="reward-row">
      <span class="reward-label">XP Earned</span>
      <span class="reward-value" id="xpEarnedDisplay">+0</span>
    </div>
    <div class="reward-row">
      <span class="reward-label">Cash Earned</span>
      <span class="reward-value" id="cashEarnedDisplay">+$0</span>
    </div>
    <div class="reward-breakdown" id="rewardBreakdown"></div>
  </div>
  
  <div class="summary-level">
    <div class="level-label">COACH LEVEL <span id="summaryLevelNum">1</span></div>
    <div class="xp-bar-container">
      <div class="xp-bar-fill" id="xpBarFill"></div>
      <div class="xp-bar-text" id="xpBarText">0 / 100</div>
    </div>
    <div class="next-perk-hint" id="nextPerkHint"></div>
  </div>
  
  <div class="level-up-banner" id="levelUpBanner" style="display:none">
    <div class="level-up-text">LEVEL UP!</div>
    <div class="level-up-detail" id="levelUpDetail"></div>
  </div>
  
  <button class="summary-continue" onclick="returnFromSummary()">CONTINUE</button>
</div>
```

### Summary screen animation sequence

When the summary screen opens, run this sequence:

1. **t = 0**: Fade in result banner ("VICTORY" or "DEFEAT") with brief scale-bounce
2. **t = 500ms**: Score and opponent fade in
3. **t = 900ms**: "XP Earned" row appears; the number ticks up from 0 to the total over 800ms with `playSfx('tick')` per ~100ms
4. **t = 1700ms**: "Cash Earned" row appears; same ticking treatment
5. **t = 2500ms**: Reward breakdown lines appear sequentially (200ms stagger)
6. **t = 2500ms + N×200ms**: XP bar fills from previous value to new value over 1000ms; if level-up occurs mid-fill, pause at 100% with a gold flash, increment the level number with `playSfx('confirm')` or a synthesized fanfare, then continue filling
7. **t = end**: Continue button slides up with subtle glow

If a perk was unlocked during the level-ups, show a separate "NEW PERK UNLOCKED" banner after the XP bar animation completes. Visualize the perk icon and name. Tap to dismiss.

### Sound design

Add new sfx types via `playSfx`:
- `'tick'` — already exists (single short beep)
- `'levelUp'` — 3-note ascending arpeggio, ~400ms
- `'perkUnlock'` — 5-note triumphant flourish, ~600ms

### Integrate into match flow

Find the `endGame()` or equivalent function that ends a match. After determining the winner, calculate rewards, update player data, then show the summary screen instead of the existing result screen.

```javascript
function endGame() {
  const matchResult = {
    won: state.youScore > state.aiScore,
    opponent: state.opponent || null,
    finalScore: { you: state.youScore, ai: state.aiScore },
    stats: { wasTrailingBy14AtHalftime: state._wasTrailingBy14 || false }
  };
  
  // Update lifetime stats
  playerData.stats.totalMatches++;
  if (matchResult.won) {
    playerData.stats.totalWins++;
    playerData.stats.currentWinStreak++;
    playerData.stats.longestWinStreak = Math.max(playerData.stats.longestWinStreak, playerData.stats.currentWinStreak);
    if (matchResult.finalScore.ai === 0) playerData.stats.shutouts++;
    if (matchResult.stats.wasTrailingBy14AtHalftime) playerData.stats.comebacks++;
  } else {
    playerData.stats.totalLosses++;
    playerData.stats.currentWinStreak = 0;
  }
  
  // Calculate rewards
  const rewards = calculateMatchRewards(matchResult);
  playerData.cash += rewards.cashEarned;
  const levelUps = applyXpAndLevelUp(rewards.xpEarned);
  
  savePlayerData();
  
  // Show summary screen with animation
  showMatchSummary(matchResult, rewards, levelUps);
}

function showMatchSummary(matchResult, rewards, levelUps) {
  // Populate the summary DOM, then trigger the animation sequence
  // ... (build out per the design above)
}

function returnFromSummary() {
  // Return to the appropriate place:
  // - If this was a Season match: go back to season hub OR show next opponent
  // - If this was a Quick Play match: return to main menu
  // - If this was the final game of a Season (won 7): show season-complete celebration
}
```

### "wasTrailingBy14AtHalftime" tracking

To support the Comeback bonus, you need to know if the player was trailing by 14+ points at the end of drive 4. Add this tracking:

```javascript
// At end of drive 4 (just before drive 5 begins):
if (state.turn === 4) {  // or wherever drive 4 ends
  state._halftimeYouScore = state.youScore;
  state._halftimeAiScore = state.aiScore;
  state._wasTrailingBy14 = (state.aiScore - state.youScore) >= 14;
}
```

Find the appropriate point in the drive-transition code and add this.

### Acceptance for Sub-phase 4

- [ ] After a match, the summary screen appears with score, opponent, rewards breakdown
- [ ] XP and cash numbers tick up with sound
- [ ] XP bar fills correctly; level-ups trigger mid-fill with visual flash + sound
- [ ] Level-up grants Cash (100 × new level) — verify the cash total increases
- [ ] Perk unlocks at the appropriate level (e.g., reach level 3 → Banker unlocks) — confirm in Locker Room
- [ ] "Continue" button returns to the right place (menu for Quick Play, season hub for Season)
- [ ] Player stats update correctly (matches played, wins, win streak, shutouts, comebacks)
- [ ] Comeback bonus triggers correctly when conditions are met
- [ ] Daily first-match bonus triggers once per day
- [ ] All player data saves correctly
- [ ] Add marker: `// === LEVELING PHASE A — SUB-PHASE 4 (MATCH SUMMARY) ===`
- [ ] Run syntax check
- [ ] **Stop. Tell the user to playtest: play a Quick Play match end-to-end, observe the summary screen animation, verify XP and cash. Play 2-3 more to confirm level-up triggers. Wait for confirmation.**

---

## Sub-phase 5: Cash + Level display on main menu

Small final touch. The main menu should now show the player's current Cash and Coach Level somewhere prominent (top right corner, similar to the Locker Room header).

```html
<div class="menu-stats-bar">
  <span class="menu-level">LV <span id="menuCoachLevel">1</span></span>
  <span class="menu-cash">💵 <span id="menuCashDisplay">0</span></span>
</div>
```

Populate in `renderMenu()` or wherever the menu is rendered.

### Acceptance for Sub-phase 5

- [ ] Menu shows current Coach Level and Cash
- [ ] Values update correctly after a match (return to menu, verify reflected)
- [ ] Add marker: `// === LEVELING PHASE A COMPLETE ===`
- [ ] Run final syntax check

---

## Update CLAUDE.md

After all sub-phases ship, update CLAUDE.md:

1. Add `playerData` to the state model documentation (mention it's separate from `state` and persists in localStorage)
2. Add to "Subsystems and where they live":
   - `Player progression (Cash, Level, XP)` → `loadPlayerData`, `savePlayerData`, `applyXpAndLevelUp`
   - `Perks system` → `PERK_POOL`, `hasPerk`, `getHandSize`, `getMaxEnergyBank`, `applyPerkStatBuffs`
   - `Match-end summary` → `calculateMatchRewards`, `showMatchSummary`
3. Add to "Things I would NOT do":
   - `Don't read HAND_SIZE or MAX_ENERGY_BANK directly — use the getters getHandSize()/getMaxEnergyBank() so perks apply correctly.`
   - `Don't introduce new currencies. Cash is the only currency, ever.`
4. In "Roadmap", mark Phase A as complete and list Phase B (more perks + trophies + stats) as next.

---

## Final acceptance for Phase A

- [ ] All 5 sub-phases shipped with their own markers
- [ ] Existing game features (Quick Play, Season, Draft) work end-to-end
- [ ] Player data persists across browser reloads
- [ ] 7 perks defined; Big Hand unlocked at level 1, others unlock by leveling
- [ ] Equipping a perk affects gameplay (verified for Big Hand, Banker, Air It Out, Quick Reads)
- [ ] Match-end summary animates smoothly with sound
- [ ] CLAUDE.md updated

---

## Report at end

Tell the user:
1. Summary of what was built across all 5 sub-phases
2. What to playtest:
   - Play a Quick Play match. After it ends, watch the summary screen carefully — XP tick, cash tick, XP bar fill
   - Open Locker Room, equip Big Hand, play a match, confirm hand size is 6
   - Play several matches in a row, level up, watch for new perks unlocking
   - Reach level 3 to unlock Banker, equip it, verify energy cap is 12 in a match
   - Test the reset progress option (3-confirm) to confirm it clears cleanly
3. **Do not proceed to Phase B without explicit confirmation.**
