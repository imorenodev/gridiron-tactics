# Phase 7 — Card Synergies (Defold port of Gridiron Tactics)

You are working on the Defold port of Gridiron Tactics. **Phase 6 just shipped** (lane modifiers Tier 1 + 2 + 3). All 20 lane modifiers work, slot-machine reveal animation works, fan layout works. **Phase 7 adds card synergies** — combos of cards in the same lane that trigger stat buffs.

## Reference source

The HTML prototype at `https://raw.githubusercontent.com/imorenodev/gridiron-tactics/main/index.html` is the source of truth. Search for `SYNERGIES`, `detectSynergies`, `applySynergies`, `computeLaneStats`, and `snapFieldGoal` to confirm anything you're unsure about. **Do not invent semantics that aren't in the HTML.**

## Locked design decisions

1. **Scope:** All 13 synergies (7 OFF + 5 DEF + 1 ST) — full HTML parity.
2. **Per-side independent application.** Your synergies only buff your cards. Their synergies only buff theirs. The HTML calls `applySynergies(lane.youCards.filter(...))` and `applySynergies(lane.aiCards.filter(...))` as TWO separate calls. Do the same. Do NOT pass mixed arrays.
3. **Filter:** Only `revealed && !ejected` cards count for both detection and application. Pending (face-down) cards do NOT contribute to synergies.
4. **No deduping.** A card matched by multiple synergies (e.g., a QB matched by Play Action AND Pocket) gets ALL the buffs additively. This is the HTML behavior.
5. **Visual feedback:** Up to 2 text badges per side per lane, below the lane medallion. If 3+ synergies are active on one side, show the first 2 by HTML array order (truncation is acceptable — synergies that overlap rarely all matter in one frame). Badge text is the synergy `name` only (e.g. `"PLAY ACTION"`, no icon, no " ACTIVE" suffix). Style: player badge green, AI badge red — match the convention used by `lane_synergies` in the HTML CSS.
6. **Kicking Unit special:** the K + ST combo gives the K `+5 OFF` AND lowers the in-lane FG range from 50+ to 35+. This is the ONE synergy that interacts with scoring logic.
7. **Recompute timing:** synergies (re)apply in EVERY call to `recompute_lane_sums`. Same trigger pattern as Phase 6 modifiers — do not wire a new hook.

## The 13 synergies (exact HTML semantics)

| id | name | side | match | apply |
|---|---|---|---|---|
| `play_action` | PLAY ACTION | off | ≥1 QB AND ≥1 RB | first QB + first RB get +12 OFF each |
| `spread_offense` | SPREAD | off | ≥3 WR | all WRs get +6 OFF each |
| `protected_pocket` | POCKET | off | ≥1 QB AND ≥2 OL | first QB gets +15 OFF (OLs unchanged) |
| `red_zone_threat` | RED ZONE | off | ≥1 TE AND ≥1 QB | first TE + first QB get +8 OFF each |
| `wildcat` | WILDCAT | off | ≥2 RB | all RBs get +10 OFF each |
| `trick_play` | TRICK PLAY | off | ≥1 WR AND ≥1 RB AND ≥1 TE | first of each gets +5 OFF |
| `field_general` | FIELD GEN | off | ≥1 QB w/ cost ≥5 AND ≥2 (WR or TE) | the qualifying QB gets +15 OFF |
| `zone_defense` | ZONE D | def | ≥2 CB | all CBs get +5 DEF each |
| `strong_safety` | STRONG SAFETY | def | ≥1 S AND ≥1 LB | first S + first LB get +6 DEF each |
| `stacked_front` | STACKED FRONT | def | ≥3 (DE or DT) | all matched DL get +8 DEF each |
| `blitz_package` | BLITZ | def | ≥1 LB AND ≥1 DE | first LB + first DE get +7 DEF each |
| `secondary_support` | SECONDARY | def | ≥2 CB AND ≥1 S | all matched CBs + Ss get +5 DEF each |
| `kicking_unit` | KICKING UNIT | st | ≥1 K AND ≥1 ST | first K gets +5 OFF; FG range becomes 35+ in this lane |

**`secondary_support` overlap with `zone_defense` is intentional.** With 2+ CB + 1+ S in a lane, BOTH fire — CBs get +5 (Zone D) + +5 (Secondary) = +10. Do not dedupe.

## Pipeline order in `recompute_lane_sums` (do not change anything before step 5)

```
1. reset _field_off / _field_def on revealed cards
2. apply per-lane field abilities
3. apply cross-lane field abilities
4. recompute cur_off/cur_def from _base + _field
5. apply_lane_modifier(lane)              -- Phase 6
6. apply_perk_stat_buffs(lane)            -- Locker Room (you-side only)
7. synergies.apply(filter_revealed_unejected(lane.you_cards))   -- NEW
8. synergies.apply(filter_revealed_unejected(lane.ai_cards))    -- NEW
9. sum totals
```

## Hard constraints (do not break)

- **No gameplay changes outside synergies.** No touching scoring detection, reveal pipeline, AI heuristic, match flow, draw/discard, energy, or modifiers.
- **All animations use `animate_helper`.** Synergy badges are simple text show/hide — if you add any fade or pop, route it through `animate_helper.gui_animate`.
- **Default render only.** No custom render scripts.
- **Helper-module pattern preserved from Phase 5.5.** Synergy detection lives in `main/data/synergies.lua` (new module). Badge rendering lives in `main/ui/hud_render.lua` (existing module). `match_state.lua` calls into `synergies` but does not host synergy data.
- **No new top-level folders.** No third-party libs.
- **snake_case throughout.** Lua module names, function names, table fields — all snake_case. The HTML uses camelCase (`playAction`, `curOff`) — convert to snake_case (`play_action`, `cur_off`) when porting.
- **No new message hashes.** The HUD reads synergies from lane state on render, same as it reads modifiers.
- **`shared_state = 1` is set in game.project** — your modules can require each other freely.
- **Do not start Phase 8.** When you hit the final STOP, stop. Do not propose follow-up phases. Do not pre-emptively wire perks, audio, fonts, or anything else.

## Sub-phase structure

Five sub-phases. **Each sub-phase ends with a `STOP` marker. When you hit a STOP marker, output a sub-phase report (see template at the bottom) and HALT.** Do not roll into the next sub-phase. Wait for me to verify and instruct you to proceed.

**Previous Claude Code instances have shipped multiple sub-phases in one pass.** Do not do this. Each STOP is a hard barrier. Output the report, then halt.

---

## Sub-phase 7.1 — Data module

Create `main/data/synergies.lua`. This module is pure Lua data + helpers — no Defold dependencies (`go.*`, `gui.*`, `msg.*`, `hash`, etc. are forbidden in this file).

The module structure:

```lua
local M = {}

-- Array of 13 synergy descriptors. Order matters: detection iterates this
-- array and badge truncation uses array order. Match HTML SYNERGIES order:
-- play_action, spread_offense, protected_pocket, red_zone_threat, wildcat,
-- trick_play, field_general, zone_defense, strong_safety, stacked_front,
-- blitz_package, secondary_support, kicking_unit.
M.synergies = {
  {
    id = "play_action",
    name = "PLAY ACTION",
    side = "off",
    match = function(cards)
      -- return matched cards array, or nil if no match
    end,
    apply = function(matched)
      -- mutate cur_off / cur_def on the matched cards in place
    end,
  },
  -- ... 12 more
}

-- Returns an array of synergy descriptors active for the given cards.
-- `cards` should already be filtered to revealed and not-ejected.
function M.detect(cards) end

-- Mutates cur_off / cur_def in place on cards in the given list.
-- `cards` should already be filtered to revealed and not-ejected.
function M.apply(cards) end

-- Returns true if the given same-side card list contains a revealed,
-- non-ejected ST card. Used by FG range check; the K's own presence is
-- implicit at the call site (the K is the card running the FG ability).
function M.has_kicking_unit(side_cards) end

return M
```

### Implementation notes

- Use Lua `for _, c in ipairs(cards) do` patterns. No `Array.prototype.find` — write small helpers if needed:
  ```lua
  local function find_first(cards, pos)
    for _, c in ipairs(cards) do if c.pos == pos then return c end end
    return nil
  end
  local function filter_pos(cards, pos)
    local out = {}
    for _, c in ipairs(cards) do if c.pos == pos then table.insert(out, c) end end
    return out
  end
  ```
- `match` returns either an array of cards (truthy, will be applied) or `nil` (not active). An empty table `{}` is truthy in Lua — do NOT use that as a "no match" signal; use `nil`.
- `apply` mutates `c.cur_off` or `c.cur_def` directly on each matched card. Use `+=` semantics: `c.cur_off = c.cur_off + 12`.
- `M.detect` walks `M.synergies`, calls each `match`, collects descriptors where match returned non-nil.
- `M.apply` walks `M.synergies`, calls each `match`, and if non-nil calls the descriptor's `apply` on the matched list.
- `M.has_kicking_unit(side_cards)` is a single-pass scan looking for a revealed, non-ejected ST. Filtering is the caller's responsibility for `detect`/`apply` but for `has_kicking_unit` the filter is INSIDE the function (since the call site passes raw `lane.you_cards`).

### Verification (don't write code that requires running the game)

After writing the module, add a temporary print-test block at the END of the file (commented out by default; uncomment for verification):

```lua
-- DEBUG: uncomment to verify on load
-- local function test()
--   local cards = {
--     { pos = "QB", cost = 5, cur_off = 50, cur_def = 0, revealed = true, ejected = false },
--     { pos = "RB", cost = 3, cur_off = 25, cur_def = 0, revealed = true, ejected = false },
--   }
--   local active = M.detect(cards)
--   print("Active synergies:", #active)
--   for _, s in ipairs(active) do print("  -", s.id, s.name) end
--   M.apply(cards)
--   print("After apply: QB off =", cards[1].cur_off, "(expect 62)")
--   print("After apply: RB off =", cards[2].cur_off, "(expect 37)")
-- end
-- test()
```

**Do not leave this uncommented.** It's for your one-time verification only.

### Sub-phase 7.1 deliverable

The new `main/data/synergies.lua` file. No other files touched.

**STOP — 7.1 complete. Output sub-phase report. Do not start 7.2.**

---

## Sub-phase 7.2 — Wire into `recompute_lane_sums`

Edit `main/state/match_state.lua`:

1. At the top of the file, add `local synergies = require("main.data.synergies")` (matching the existing require style for sibling modules).
2. Locate `recompute_lane_sums` (the function that computes per-lane totals — exists since Phase 3, modified in Phase 6 to call lane modifiers).
3. Find the step that applies perk stat buffs (the call should look like `apply_perk_stat_buffs(lane)` or similar — match the existing function name).
4. AFTER that call and BEFORE the sum step, add:

```lua
-- Phase 7: per-side synergy application. Mirrors HTML applySynergies,
-- called twice (once per side) with revealed+unejected cards only.
local function revealed_unejected(cards)
  local out = {}
  for _, c in ipairs(cards) do
    if c.revealed and not c.ejected then table.insert(out, c) end
  end
  return out
end
synergies.apply(revealed_unejected(lane.you_cards))
synergies.apply(revealed_unejected(lane.ai_cards))
```

(If a similar local filter helper already exists at the top of `match_state.lua`, reuse it instead of redeclaring `revealed_unejected` inline.)

5. Add a public helper at the bottom of `match_state.lua` (or near other public lane helpers — match the file's existing layout):

```lua
-- Returns the array of synergy descriptors active for `side` ("you" or "ai")
-- in this lane. HUD render uses this to draw badges. Returns at most 13
-- entries; callers typically truncate to the badge slot count.
function M.get_lane_synergies(lane, side)
  local cards = (side == "you") and lane.you_cards or lane.ai_cards
  local filtered = {}
  for _, c in ipairs(cards) do
    if c.revealed and not c.ejected then table.insert(filtered, c) end
  end
  return synergies.detect(filtered)
end
```

### Do NOT change in 7.2

- The FG range check (that's 7.3)
- `try_field_goal` or `snap_field_goal` or wherever Clutch Kicker scores
- The HUD (that's 7.4)
- `messages.lua`
- The reveal pipeline, AI, match flow

### Verification (manual)

Run a Quick Play match. In the Defold console or via temporary `print` statements:
- Play a QB and an RB in the same lane on the player side
- After reveal, `lane.you_cards[1].cur_off` (the QB) and `lane.you_cards[2].cur_off` (the RB) should each be `base_off + 12` (plus any other bonuses from modifiers/perks)
- The AI cards in the same lane should NOT be affected by the player's Play Action
- Remove one of the two cards (play a different match if needed) — synergy no longer applies, stats are back to baseline

**STOP — 7.2 complete. Output sub-phase report. Do not start 7.3.**

---

## Sub-phase 7.3 — Kicking Unit FG range

Edit `main/state/match_state.lua`. Locate the Clutch Kicker / `snap_field_goal` / `try_field_goal` logic from Phase 3 — the code path that:
1. Checks for `WIND TUNNEL` modifier (FGs disabled if set)
2. Checks if the kicker's same-side position is past 50 (the hardcoded FG threshold)
3. Awards 3 points and resets the lane

Replace the hardcoded `50` threshold with a check that consults `synergies.has_kicking_unit`:

```lua
-- Phase 7: KICKING UNIT synergy lowers FG range to 35+ (HTML parity).
-- The K's own presence is implicit (this code runs because the K fired
-- its Clutch Kicker ability). Look only for an ST on the same side.
local same_side = (side == "you") and lane.you_cards or lane.ai_cards
local fg_threshold = synergies.has_kicking_unit(same_side) and 35 or 50
if my_pos >= fg_threshold then
  -- existing scoring code
end
```

(Variable names like `my_pos` and `side` are placeholders — match what's already in your function.)

### Do NOT change in 7.3

- The Wind Tunnel check (it still disables FGs entirely regardless of synergy)
- The +3 point award value
- The lane reset after a FG
- The HUD (that's 7.4)

### Verification

In a Quick Play match:
1. **Case A (synergy present):** Get a K with Clutch Kicker AND an ST card into the same lane on the player side. Push the player's ball to between 35 and 49. Play the K. → FG should score.
2. **Case B (synergy absent):** Same setup but no ST card. Push to 35-49. Play the K. → FG should NOT score (still requires 50+).
3. **Case C (synergy + Wind Tunnel):** Same as Case A but with Wind Tunnel modifier in that lane. → FG should NOT score (Wind Tunnel still wins).
4. **Case D (synergy on AI side):** AI has K + ST. AI's ball at 35-49. → AI's FG should score.

**STOP — 7.3 complete. Output sub-phase report. Do not start 7.4.**

---

## Sub-phase 7.4 — HUD badges

Two files: `main/ui/hud.gui` (add nodes) and `main/ui/hud_render.lua` (add render function).

### 7.4a — Add badge text nodes in `hud.gui`

For each of the 3 lanes (existing lane node group), add 4 new text nodes — 2 for player side, 2 for AI side. Naming convention (match existing per-lane naming):

```
lane_1_synergy_you_badge_1
lane_1_synergy_you_badge_2
lane_1_synergy_ai_badge_1
lane_1_synergy_ai_badge_2
lane_2_synergy_you_badge_1
lane_2_synergy_you_badge_2
lane_2_synergy_ai_badge_1
lane_2_synergy_ai_badge_2
lane_3_synergy_you_badge_1
lane_3_synergy_you_badge_2
lane_3_synergy_ai_badge_1
lane_3_synergy_ai_badge_2
```

For each node:
- Type: text
- Parent: the existing lane node (so the badges follow lane positioning)
- Anchor: below the lane modifier medallion, with the `you` badges below the medallion on the player side and `ai` badges above the medallion on the AI side (mirrors HTML layout)
- Default text: empty string `""`
- Default alpha: 0 (hidden by default; render code sets to 1 when active)
- Font: match the small-label font used elsewhere in `hud.gui` (e.g., the same font used for modifier description text)
- Color:
  - Player badges (`you_badge_*`): green — match the modifier text used for the player's side. Use RGB tuple `0.29, 1.0, 0.54` (approximately `#4aff8a`, the HTML `synergy-badge.you` color).
  - AI badges (`ai_badge_*`): red — RGB tuple `1.0, 0.42, 0.42` (approximately `#ff6a6a`).
- Pivot / alignment: center horizontally, vertically anchored below medallion (you-side) or above medallion (ai-side). Match the existing HUD per-lane layout conventions.
- Size: pick a width that fits "STACKED FRONT" (longest synergy name, 14 chars) without truncation at the standard match HUD scale; use a node line break with auto-shrink only if your existing convention does so.

If your `hud.gui` uses templates for lane content, follow the template pattern. If lanes are duplicated inline, duplicate inline.

### 7.4b — Add render function in `hud_render.lua`

Add a new function:

```lua
local match_state = require("main.state.match_state")

-- Renders synergy badges for a single lane. Called from the lane render path
-- (find where modifier text is rendered and add this call alongside).
function M.render_lane_synergies(lane_idx, lane)
  local sides = { "you", "ai" }
  for _, side in ipairs(sides) do
    local active = match_state.get_lane_synergies(lane, side)
    for slot = 1, 2 do
      local node_id = string.format("lane_%d_synergy_%s_badge_%d", lane_idx, side, slot)
      local node = gui.get_node(node_id)
      local syn = active[slot]
      if syn then
        gui.set_text(node, syn.name)
        gui.set_alpha(node, 1.0)
      else
        gui.set_text(node, "")
        gui.set_alpha(node, 0.0)
      end
    end
  end
end
```

(If `gui.set_alpha` isn't the right call in your codebase, use the equivalent — `gui.set_color` with alpha 0, or `gui.set_enabled`. Match whatever pattern `hud_render.lua` already uses for showing/hiding lane elements.)

### 7.4c — Call `render_lane_synergies` from the main lane render path

In `hud_render.lua`, locate the per-lane render function (the function that renders modifier text, power pills, etc. — likely called `render_lane(lane_idx, lane)` or similar). Add a call:

```lua
M.render_lane_synergies(lane_idx, lane)
```

Place it near the modifier rendering — order doesn't matter for correctness (badges are independent of modifier text), but proximity helps future maintenance.

### Do NOT change in 7.4

- Power pill rendering
- Modifier medallion rendering
- Card rendering
- Fan layout
- The Phase 6 slot-machine modifier reveal animation
- Any timing or animation logic

### Verification

In a Quick Play match:
1. Play a QB + RB on player side, same lane → green "PLAY ACTION" badge appears below medallion on player side
2. AI plays a 2nd RB to a lane that already has one → red "WILDCAT" badge appears above medallion on AI side
3. Trigger overlapping synergies (e.g., player plays 2 CBs + 1 S → both Zone D and Secondary fire) → both badges visible on player side
4. Trigger 3+ synergies on one side (rare but possible — e.g., QB + RB + 3 WR + 2 OL fires Play Action, Spread, Pocket, plus possibly Field Gen if QB cost ≥5) → only the first 2 badges show; rest are truncated
5. After a TD when the lane clears → badges should disappear

**STOP — 7.4 complete. Output sub-phase report. Do not start 7.5.**

---

## Sub-phase 7.5 — CLAUDE.md update + final verification

Edit `CLAUDE.md`. Add a new section:

```markdown
### Phase 7 — Card synergies

13 synergies from HTML (`SYNERGIES` array) ported to `main/data/synergies.lua`. Module
exposes `synergies`, `detect(cards)`, `apply(cards)`, `has_kicking_unit(side_cards)`.

**Recompute order** (in `match_state.recompute_lane_sums`):
1. Field abilities (per-lane + cross-lane)
2. Lane modifier (Phase 6)
3. Perk stat buffs (Locker Room)
4. **Synergies — applied PER SIDE** (`synergies.apply(your_revealed)` then
   `synergies.apply(ai_revealed)`)
5. Sum totals

**Per-side independence:** the HTML calls applySynergies separately on each side's
filtered cards. Do not pass mixed arrays — your synergies do not buff their cards.

**No-dedupe rule:** `secondary_support` overlaps with `zone_defense` (CBs get
+5 from each = +10 total). This is intentional HTML behavior.

**Kicking Unit FG range:** the only synergy that touches scoring. K + ST in the
same side of a lane lowers the FG threshold from 50+ to 35+ in
`snap_field_goal`. Wind Tunnel still disables FGs entirely.

**Badges:** up to 2 badges per side per lane, truncated by HTML array order.
Rendered by `hud_render.render_lane_synergies(lane_idx, lane)`, which reads from
`match_state.get_lane_synergies(lane, side)`. No new messages.

**Files added/touched:**
- NEW `main/data/synergies.lua`
- EDIT `main/state/match_state.lua` (require + 2-line insert in recompute_lane_sums
  + FG threshold check + `get_lane_synergies` helper)
- EDIT `main/ui/hud.gui` (12 new badge text nodes, 4 per lane)
- EDIT `main/ui/hud_render.lua` (new render_lane_synergies function, called from
  the per-lane render path)
```

(Match the formatting of existing phase sections — heading level, bullet style, code-fence usage. The above is a guide; conform to your existing CLAUDE.md conventions.)

### Final regression verification

Confirm nothing earlier-phase broke:
- [ ] Fan layout still positions cards correctly
- [ ] Slot-machine modifier reveal animation still plays
- [ ] Phase 6 modifier badges still show
- [ ] Phase 6.5 modifiers (Frozen Tundra, Coin Flip, Turnover, Sudden Death, Wind Tunnel) still work
- [ ] Drag-to-play still works
- [ ] Energy escalation + carryover still works
- [ ] Discard/draw arcs still play
- [ ] Coin flip 2-pt conversion still works
- [ ] Pick-6 still triggers
- [ ] Clutch Kicker still triggers FGs at 50+ when no ST is present
- [ ] Perk stat buffs (if any perks are equipped via Locker Room) still apply

**STOP — Phase 7 complete. Output final report. Do NOT propose Phase 8. Do NOT start any other work.**

---

## Sub-phase report template (use this format at every STOP)

```
## Sub-phase 7.X report

### Files touched
- path/to/file.ext (created | edited)
- ...

### What was done
- Concise bullets of what changed

### Deviations from prompt
- Anything you did differently and why. If none, write "None."

### Verification steps for the user
1. ...
2. ...

### Open questions / blockers
- Anything that needs the user's input before the next sub-phase. If none, write "None."

### Next sub-phase
7.(X+1) — [name from prompt], gated on user verification.
```

If you ship a sub-phase that "should also include" something from a later sub-phase, **don't**. Stop at the marker. Output the report. Wait.
