# Claude Code Prompt — Phase 6: Lane Modifiers (Tier 1+2)

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** Every file you create or modify must conform to its conventions. If this prompt conflicts with `CLAUDE.md`, surface the conflict and stop.

Re-read specifically:
- Hard rules (especially #11 about render scripts — default render only)
- Code conventions (snake_case, module-local state, pre-computed hashes, message naming)
- Things I would NOT do
- Phase 0 through 5.5 notes — the established patterns we're extending, especially the helper-module pattern from Phase 5.5 refactor

Also review the existing files this prompt will modify:
- `main/state/match_state.lua`
- `main/state/messages.lua`
- `main/match/match.script`
- `main/ai/cpu.lua`
- `main/ui/hud.gui`
- `main/ui/hud.gui_script`
- `main/ui/hud_render.lua` (the rendering helpers from Phase 5.5)
- `main/ui/hud_drag.lua` (will need affordability updates)

## Context

Phases 0-5.5 built a complete-feeling card game: 8-drive matches, scoring, AI reveal, fan-stacked played cards, real card frames, Marvel Snap-style visuals. **What's missing: strategic variety per match.** Every match plays out with the same baseline rules. The HTML game has 20 lane modifiers that get randomized per match, making each game feel different.

**Phase 6 ports 16 of the 20 modifiers** — the Tier 1 (stat-only) and Tier 2 (cost/reveal) modifiers. The 4 Tier 3 mechanical modifiers (Frozen Tundra, Coin Flip, Turnover, Sudden Death) ship in Phase 6.5.

After Phase 6:
- Match starts with a 1.5s slot-machine reveal animation showing which 3 modifiers landed (one per lane)
- The empty medallion row from Phase 5/5.5 now displays the modifier icon + name in each lane
- Tap a modifier medallion to see its full description in a toast
- Modifiers affect gameplay: stat changes during reveal, cost discounts at card play, immediate reveal for Scouted lanes
- Every match plays differently because the modifier draws vary

## The 16 modifiers in scope

### Tier 1: Pure stat modifiers (12)

These mutate `cur_off`/`cur_def` on revealed cards in their lane during `recompute_lane_sums`.

| ID | Icon | Name | Effect |
|---|---|---|---|
| `homeTurf` | 🏟️ | HOME TURF | Your OFF cards +5, enemy OFF cards -5 |
| `muddyField` | 🌧️ | MUDDY FIELD | All OFF cards ×0.75, all DEF cards ×1.25 |
| `windTunnel` | 💨 | WIND TUNNEL | QB and WR OFF -5 |
| `blindingSun` | 🌞 | BLINDING SUN | WR and TE OFF -8 |
| `redZone` | 🔥 | RED ZONE | All OFF cards +8 |
| `scramble` | 🏃 | SCRAMBLE | QBs OFF +12 |
| `groundPound` | 🏃 | GROUND & POUND | RB OFF +10, OL OFF +5 |
| `airRaid` | ✈️ | AIR RAID | WR and TE OFF +8 |
| `trenches` | 🔨 | TRENCHES | OL OFF +6, DT DEF +6 |
| `secondary` | 🦅 | SECONDARY | CB and S DEF +6 |
| `specialUnit` | 🎯 | ST UNIT | K and ST stat +15 (whichever is their primary stat) |
| `playOfGame` | 🎬 | PLAY OF GAME | Highest-stat revealed card in lane +20 to its primary stat |

### Tier 2: Cost / reveal modifiers (4)

| ID | Icon | Name | Effect | Implementation |
|---|---|---|---|---|
| `hurryUp` | ⚡ | HURRY-UP | OFF cards cost -1 (min 1) in this lane | `effective_cost(card, lane_idx)` returns reduced cost |
| `preventD` | 🛡️ | PREVENT D | DEF cards cost -1 (min 1) in this lane | Same |
| `scouted` | 📋 | SCOUTED | First card placed in this lane reveals immediately at play time | Bypasses `pending_plays` for first card per side |
| `blitzZone` | 🎯 | BLITZ ZONE | DEF SNAP abilities trigger twice (no-op in Phase 6; future-proofs dispatcher) | Adds `trigger_count` parameter; in Phase 6, Clutch Kicker is OFF so this affects nothing |

## Deferred to Phase 6.5 (do NOT implement)

For reference only. NOT in Phase 6 scope:

- `frozenTundra` — disables all abilities in lane
- `coinFlip` — per-drive 50/50 double-or-halve yards
- `turnover` — ball-swap after 3 scoreless drives
- `suddenDeath` — first scorer locks the lane

## Hard rules

1. **No gameplay changes outside modifiers.** Match flow, deck cycle, scoring detection, reveal pipeline, AI heuristic — none of those change unless a modifier specifically requires it. Modifier effects are additive layers on top of existing systems.
2. **All animations use `animate_helper`.** No raw `gui.animate` or `go.animate` calls.
3. **Helper-module pattern from Phase 5.5 must be preserved.** New rendering for medallions goes in `hud_render.lua`. New drag/affordability tweaks go in `hud_drag.lua`. Helper modules take node refs as parameters; they don't store state.
4. **Scouted is the one modifier that touches reveal pipeline.** Handle carefully. The pattern: `play_card` returns a `scouted_revealed` flag when applicable; match.script branches on that flag to skip the pending_plays path.
5. **Affordability check moves to drop time.** Phase 5.5's drag system checks affordability at drag-start. Phase 6 still dims unaffordable cards based on base cost (visual hint), but allows the drag to begin even on borderline cards. The drop validates `effective_cost(card, target_lane)` against current energy. Failed drop → snap-back with toast.
6. **Pre-compute all new hashes** in `main/state/messages.lua`.
7. **No new top-level folders, no third-party libs.**
8. **6 sub-phases with STOP markers.** Do not compress. Each STOP exists for verification.
9. **Do not modify CLAUDE.md mid-prompt.** Update once at the end (Sub-phase 6.6).
10. **Do not start Phase 6.5 or any other phase.**

## Sub-phases

Six sub-phases. STOP after each.

---

### Sub-phase 6.1 — Modifier data + state plumbing

Build the data layer and state functions. No UI changes. After this sub-phase, the match has modifiers internally but they're invisible and don't affect gameplay yet.

**Files to create:**

- `main/data/modifiers.lua` — modifier pool definition and helpers
    ```lua
    local M = {}

    M.POOL = {
        -- Tier 1 (stat modifiers)
        { id = "homeTurf",     icon = "🏟️", name = "HOME TURF",
          desc = "Your OFF cards +5, enemy OFF cards -5",
          category = "field" },
        { id = "muddyField",   icon = "🌧️", name = "MUDDY FIELD",
          desc = "All OFF cards -25%, all DEF cards +25%",
          category = "field" },
        { id = "windTunnel",   icon = "💨", name = "WIND TUNNEL",
          desc = "QB and WR OFF -5",
          category = "field" },
        { id = "blindingSun",  icon = "🌞", name = "BLINDING SUN",
          desc = "WR and TE OFF -8",
          category = "field" },
        { id = "redZone",      icon = "🔥", name = "RED ZONE",
          desc = "All OFF cards +8",
          category = "field" },
        { id = "scramble",     icon = "🏃", name = "SCRAMBLE",
          desc = "QBs OFF +12",
          category = "field" },
        { id = "groundPound",  icon = "🏃", name = "GROUND & POUND",
          desc = "RB OFF +10, OL OFF +5",
          category = "position" },
        { id = "airRaid",      icon = "✈️", name = "AIR RAID",
          desc = "WR and TE OFF +8",
          category = "position" },
        { id = "trenches",     icon = "🔨", name = "TRENCHES",
          desc = "OL OFF +6, DT DEF +6",
          category = "position" },
        { id = "secondary",    icon = "🦅", name = "SECONDARY",
          desc = "CB and S DEF +6",
          category = "position" },
        { id = "specialUnit",  icon = "🎯", name = "ST UNIT",
          desc = "K and ST stat +15",
          category = "position" },
        { id = "playOfGame",   icon = "🎬", name = "PLAY OF GAME",
          desc = "Highest-stat card in lane gets +20",
          category = "wild" },
        -- Tier 2 (cost / reveal)
        { id = "hurryUp",      icon = "⚡", name = "HURRY-UP",
          desc = "OFF cards cost -1 in this lane (min 1)",
          category = "tactical" },
        { id = "preventD",     icon = "🛡️", name = "PREVENT D",
          desc = "DEF cards cost -1 in this lane (min 1)",
          category = "tactical" },
        { id = "scouted",      icon = "📋", name = "SCOUTED",
          desc = "First card placed in this lane reveals immediately",
          category = "tactical" },
        { id = "blitzZone",    icon = "🎯", name = "BLITZ ZONE",
          desc = "DEF SNAP abilities trigger twice",
          category = "tactical" },
    }

    function M.get_by_id(id)
        for _, mod in ipairs(M.POOL) do
            if mod.id == id then return mod end
        end
        return nil
    end

    function M.draw_random(count)
        local copy = {}
        for _, m in ipairs(M.POOL) do table.insert(copy, m) end
        for i = #copy, 2, -1 do
            local j = math.random(i)
            copy[i], copy[j] = copy[j], copy[i]
        end
        local out = {}
        for i = 1, count do table.insert(out, copy[i]) end
        return out
    end

    return M
    ```

**Files to modify:**

#### `main/state/match_state.lua`

- Extend top-level state:
    ```lua
    {
        -- existing...
        modifiers = {},  -- NEW: { [lane_idx] = modifier_record }
    }
    ```
- Extend per-lane state:
    ```lua
    {
        -- existing...
        scouted_first_played_you = false,  -- NEW
        scouted_first_played_ai = false,   -- NEW
    }
    ```
    (Two separate flags because the player and AI each get their "first card" reveal independently in Scouted lanes.)

- Modify `M.new_match()`:
    - Call `modifiers.draw_random(3)` (where `modifiers = require("main.data.modifiers")`)
    - Populate `state.modifiers[1]`, `state.modifiers[2]`, `state.modifiers[3]`
    - Initialize `scouted_first_played_you = false` and `scouted_first_played_ai = false` on each lane

- New function `M.effective_cost(card, lane_idx)`:
    ```lua
    function M.effective_cost(card, lane_idx)
        local modifier = state.modifiers[lane_idx + 1]  -- lane_idx is 0-indexed
        if not modifier then return card.cost end
        if modifier.id == "hurryUp" and card.side == "off" then
            return math.max(1, card.cost - 1)
        end
        if modifier.id == "preventD" and card.side == "def" then
            return math.max(1, card.cost - 1)
        end
        return card.cost
    end
    ```

- New function `M.apply_lane_modifier(lane_idx)`:
    - Called from `M.recompute_lane_sums(lane_idx)` AFTER base stats are reset and BEFORE the sums are computed
    - Switch on `modifier.id`:
        ```lua
        local function apply_lane_modifier(lane_idx)
            local modifier = state.modifiers[lane_idx + 1]
            if not modifier then return end
            local lane = state.lanes[lane_idx + 1]
            local you_cards = revealed_cards(lane.you_cards)
            local ai_cards = revealed_cards(lane.ai_cards)
            local all = concat_arrays(you_cards, ai_cards)

            if modifier.id == "homeTurf" then
                for _, c in ipairs(you_cards) do
                    if c.side == "off" then c.cur_off = c.cur_off + 5 end
                end
                for _, c in ipairs(ai_cards) do
                    if c.side == "off" then c.cur_off = math.max(0, c.cur_off - 5) end
                end
            elseif modifier.id == "muddyField" then
                for _, c in ipairs(all) do
                    c.cur_off = math.floor(c.cur_off * 0.75)
                    c.cur_def = math.floor(c.cur_def * 1.25)
                end
            elseif modifier.id == "windTunnel" then
                for _, c in ipairs(all) do
                    if c.pos == "QB" or c.pos == "WR" then
                        c.cur_off = math.max(0, c.cur_off - 5)
                    end
                end
            elseif modifier.id == "blindingSun" then
                for _, c in ipairs(all) do
                    if c.pos == "WR" or c.pos == "TE" then
                        c.cur_off = math.max(0, c.cur_off - 8)
                    end
                end
            elseif modifier.id == "redZone" then
                for _, c in ipairs(all) do
                    if c.side == "off" then c.cur_off = c.cur_off + 8 end
                end
            elseif modifier.id == "scramble" then
                for _, c in ipairs(all) do
                    if c.pos == "QB" then c.cur_off = c.cur_off + 12 end
                end
            elseif modifier.id == "groundPound" then
                for _, c in ipairs(all) do
                    if c.pos == "RB" then c.cur_off = c.cur_off + 10 end
                    if c.pos == "OL" then c.cur_off = c.cur_off + 5 end
                end
            elseif modifier.id == "airRaid" then
                for _, c in ipairs(all) do
                    if c.pos == "WR" or c.pos == "TE" then c.cur_off = c.cur_off + 8 end
                end
            elseif modifier.id == "trenches" then
                for _, c in ipairs(all) do
                    if c.pos == "OL" then c.cur_off = c.cur_off + 6 end
                    if c.pos == "DT" then c.cur_def = c.cur_def + 6 end
                end
            elseif modifier.id == "secondary" then
                for _, c in ipairs(all) do
                    if c.pos == "CB" or c.pos == "S" then c.cur_def = c.cur_def + 6 end
                end
            elseif modifier.id == "specialUnit" then
                for _, c in ipairs(all) do
                    if c.pos == "K" then c.cur_off = c.cur_off + 15 end
                    if c.pos == "ST" then c.cur_def = c.cur_def + 15 end
                end
            elseif modifier.id == "playOfGame" then
                if #all > 0 then
                    local highest = all[1]
                    local highest_stat = (highest.side == "off") and highest.cur_off or highest.cur_def
                    for _, c in ipairs(all) do
                        local stat = (c.side == "off") and c.cur_off or c.cur_def
                        if stat > highest_stat then
                            highest = c
                            highest_stat = stat
                        end
                    end
                    if highest.side == "off" then highest.cur_off = highest.cur_off + 20
                    else highest.cur_def = highest.cur_def + 20 end
                end
            end
            -- hurryUp, preventD: handled in effective_cost
            -- scouted: handled in play_card / ai_play_card
            -- blitzZone: handled in try_apply_snap_ability
        end
        ```

- Helper functions:
    - `M.is_scouted_lane(lane_idx)` — returns true if the lane's modifier is Scouted
    - `M.is_scouted_first_play(lane_idx, side)` — returns true if Scouted and the side hasn't played their first card yet
    - `M.mark_scouted_first_played(lane_idx, side)` — sets the corresponding flag

- New top-level export `M.get_modifiers()` — returns the `state.modifiers` table for HUD rendering

- `M.recompute_lane_sums(lane_idx)`:
    - Existing logic stays
    - After reset of `cur_off`/`cur_def` to base values on revealed cards, BEFORE summing:
        - Call `apply_lane_modifier(lane_idx)` (the local function above)
    - Then sum as before

#### `main/state/messages.lua`

Add new hashes:
```lua
M.HUD_MODIFIERS_REVEAL = hash("hud.modifiers_reveal")  -- match → hud, payload includes the chosen modifiers
M.MATCH_MODIFIERS_REVEAL_COMPLETE = hash("match.modifiers_reveal_complete")  -- hud → match, after reveal animation finishes
M.HUD_SHOW_MODIFIER_TOAST = hash("hud.show_modifier_toast")  -- triggered by medallion tap
```

**Acceptance criteria for 6.1:**

- [ ] Project builds, no console errors
- [ ] `match_state.get_modifiers()` after a new match returns an array of 3 modifier records
- [ ] Each modifier has id, icon, name, desc, category fields
- [ ] `match_state.effective_cost(card, 0)` returns reduced cost for OFF cards in Hurry-Up lanes
- [ ] `apply_lane_modifier(0)` mutates card stats correctly (verify via temporary print of `you_off_sum` before/after recompute on a lane with a known modifier)
- [ ] No visible UI change yet
- [ ] All existing Phase 5.5 behavior preserved

`// === STOP for developer review ===`

---

### Sub-phase 6.2 — Medallion GUI + tap-for-description

Add the medallion nodes to the HUD. They display the modifier icon + name. Tapping a medallion shows a toast with the full description.

**Files to modify:**

#### `main/ui/hud.gui`

Each lane already has a medallion row chrome from Phase 5 (pill left + middle + right). Add medallion content per lane:

```
lane_X_medallion_root  (existing or new — centered in the pill middle area)
├── lane_X_medallion_icon       (sprite, atlas: icons, initial sprite: mod_homeTurf)
├── lane_X_medallion_name       (text, initial: "MODIFIER")
└── lane_X_medallion_touch      (invisible box, full medallion area, for tap detection)
```

For each of 3 lanes, add this structure. Total 9 new nodes (3 per lane × 3 lanes).

**Sizing:**
- Medallion root: positioned at lane center in the central band (between yardage bars and slot stacks)
- Icon: ~80×80
- Name text: below icon, small font, gold color
- Touch area: ~200×120 (the whole medallion footprint)

**Files to modify:**

#### `main/ui/hud_render.lua`

Add new function:
```lua
function M.render_modifier_medallion(refs, modifier)
    -- refs: { icon, name, touch } node refs for one lane
    -- modifier: modifier record from match_state
    if not modifier then
        gui.set_enabled(refs.icon, false)
        gui.set_enabled(refs.name, false)
        return
    end
    gui.set_enabled(refs.icon, true)
    gui.set_enabled(refs.name, true)
    gui.set_texture(refs.icon, "icons")
    gui.play_flipbook(refs.icon, hash("mod_" .. modifier.id))
    gui.set_text(refs.name, modifier.name)
end

function M.show_modifier_toast(toast_refs, modifier, animate_helper)
    -- Reuse existing toast pattern from Phase 4 (carried_toast) but with longer text
    -- 1.5s display, fade-in 200ms, fade-out 300ms
    gui.set_text(toast_refs.text, modifier.icon .. "  " .. modifier.name .. "\n" .. modifier.desc)
    -- ... animation
end
```

#### `main/ui/hud.gui_script`

- In `init`, cache the medallion refs: `self.modifier_refs[lane_idx] = { icon, name, touch }`
- After receiving initial state (currently happens via `HUD_LANE_UPDATED` or similar), render each medallion:
    ```lua
    for lane_idx, refs in pairs(self.modifier_refs) do
        local modifier = match_state.get_modifier_for_lane(lane_idx)
        hud_render.render_modifier_medallion(refs, modifier)
    end
    ```
    Wait — but `match_state` shouldn't be required from `hud.gui_script` per the helper-module pattern. The clean way: match.script posts `HUD_MODIFIERS_REVEAL { modifiers = [...] }` once at match start, and `hud.gui_script` caches the modifiers + renders.

    Actually, this is the sub-phase where modifiers appear statically (no reveal animation yet — that's 6.3). So for 6.2, on match init, match.script posts `HUD_MODIFIERS_REVEAL` once, HUD caches and renders immediately. The reveal animation comes in 6.3.

- Add `HUD_MODIFIERS_REVEAL { modifiers }` handler:
    ```lua
    if message_id == msgs.HUD_MODIFIERS_REVEAL then
        self.current_modifiers = message.modifiers
        for i = 1, 3 do
            hud_render.render_modifier_medallion(self.modifier_refs[i - 1], message.modifiers[i])
        end
    end
    ```

- In `on_input`, after the existing button-tap checks, add medallion-tap detection:
    ```lua
    for lane_idx = 0, 2 do
        local touch_node = self.modifier_refs[lane_idx].touch
        if gui.pick_node(touch_node, action.x, action.y) then
            if action.released then
                local modifier = self.current_modifiers[lane_idx + 1]
                if modifier then
                    hud_render.show_modifier_toast(self.toast_refs, modifier, animate_helper)
                end
            end
            return true  -- consume input
        end
    end
    ```

#### `main/match/match.script`

- In `init`, after `match_state.new_match()`, post `HUD_MODIFIERS_REVEAL { modifiers = match_state.get_modifiers() }` to HUD

**Acceptance criteria for 6.2:**

- [ ] Tap PLAY → match loads → each lane's medallion shows an icon + name
- [ ] Tap a medallion → toast appears with the full modifier description
- [ ] Toast auto-dismisses after ~1.5s
- [ ] Three different modifiers visible across the three lanes (randomized per match)
- [ ] Replay a match — different modifiers appear (random draw is working)
- [ ] Modifiers don't affect gameplay yet (effects come in 6.4)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 6.3 — Slot-machine reveal animation

At match start, the medallions show a 1.5s slot-machine spinning effect before settling on the chosen modifiers.

**Animation spec:**
- All 3 medallions spin simultaneously
- Phase A (1.0s): rapid cycling through random modifier icons + names at ~16fps (62ms per cycle)
- Phase B (0.5s): deceleration — interval grows from 62ms to 250ms over the 0.5s window
- Phase C: settle on actual chosen modifier; brief scale pulse (1 → 1.15 → 1 over 200ms)
- Total: ~1.5s

During the reveal, the match is in phase `"resolving"` (or similar) — player can't drag. After reveal completes, phase flips to `"play"`.

**Files to modify:**

#### `main/ui/hud_render.lua`

Add new function:
```lua
local modifiers_module = require("main.data.modifiers")

function M.start_modifier_reveal(medallion_refs_by_lane, chosen_modifiers, animate_helper, on_complete)
    -- medallion_refs_by_lane: { [lane_idx] = { icon, name } }
    -- chosen_modifiers: { [lane_idx] = modifier_record }

    if animate_helper.is_reduced_motion() then
        -- Skip animation, just set final state
        for lane_idx, refs in pairs(medallion_refs_by_lane) do
            M.render_modifier_medallion(refs, chosen_modifiers[lane_idx + 1])
        end
        if on_complete then on_complete() end
        return
    end

    -- Phase A: fast cycle
    local cycle_count = 16  -- 16 cycles × 62ms = ~1.0s
    local cycle_interval = 0.062
    local pool = modifiers_module.POOL

    local function set_random(lane_idx)
        local refs = medallion_refs_by_lane[lane_idx]
        local random_mod = pool[math.random(#pool)]
        gui.play_flipbook(refs.icon, hash("mod_" .. random_mod.id))
        gui.set_text(refs.name, random_mod.name)
    end

    -- Schedule fast cycle
    for cycle = 1, cycle_count do
        timer.delay(cycle_interval * cycle, false, function()
            for lane_idx = 0, 2 do
                set_random(lane_idx)
            end
        end)
    end

    -- Phase B: deceleration (0.5s, intervals growing)
    local decel_start = cycle_interval * cycle_count
    local decel_intervals = { 0.08, 0.10, 0.14, 0.18, 0.25 }  -- 5 ticks, totaling ~0.75s but we want 0.5s
    -- Adjust: { 0.07, 0.10, 0.13, 0.20 } sums to 0.5s
    decel_intervals = { 0.07, 0.10, 0.13, 0.20 }
    local accumulated = decel_start
    for _, interval in ipairs(decel_intervals) do
        accumulated = accumulated + interval
        timer.delay(accumulated, false, function()
            for lane_idx = 0, 2 do
                set_random(lane_idx)
            end
        end)
    end

    -- Phase C: settle on the chosen modifier
    local settle_time = accumulated + 0.05
    timer.delay(settle_time, false, function()
        for lane_idx, refs in pairs(medallion_refs_by_lane) do
            local mod = chosen_modifiers[lane_idx + 1]
            M.render_modifier_medallion(refs, mod)
            -- Scale pulse
            local root = refs.icon  -- pulse the icon node
            local original = gui.get_scale(root)
            animate_helper.animate_gui(root, "scale",
                vmath.vector3(original.x * 1.15, original.y * 1.15, 1),
                gui.EASING_OUTQUAD, 0.1, 0, function()
                    animate_helper.animate_gui(root, "scale",
                        vmath.vector3(original.x, original.y, 1),
                        gui.EASING_INQUAD, 0.1, 0, nil)
                end)
        end
        timer.delay(0.25, false, function()
            if on_complete then on_complete() end
        end)
    end)
end
```

#### `main/match/match.script`

- In `init`, after posting `HUD_MODIFIERS_REVEAL`:
    - Set `phase = "resolving"` (or whatever phase prevents input)
    - The HUD will run the reveal animation
    - After reveal completes, HUD posts `MATCH_MODIFIERS_REVEAL_COMPLETE` back
    - On receiving that, set `phase = "play"`

#### `main/ui/hud.gui_script`

- Modify `HUD_MODIFIERS_REVEAL` handler:
    - Instead of rendering instantly, kick off `hud_render.start_modifier_reveal`
    - In the on_complete callback, post `MATCH_MODIFIERS_REVEAL_COMPLETE` to match.script

**Acceptance criteria for 6.3:**

- [ ] Tap PLAY → match screen appears with medallions rapidly cycling
- [ ] After ~1.5s, medallions settle on their final modifiers with a brief scale pulse
- [ ] Player can't drag cards during the reveal animation (input gated)
- [ ] After settle, normal play begins
- [ ] Reduced motion ON: reveal is instant (medallions appear at final state immediately, no spinning)
- [ ] Multiple matches show variety in chosen modifiers
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 6.4 — Tier 1 modifier effects (12 stat-only modifiers)

Wire `apply_lane_modifier` with all 12 Tier 1 cases. Modifiers now affect gameplay.

This sub-phase is mostly testing — the `apply_lane_modifier` switch statement was already drafted in 6.1. Verify all 12 cases work.

**Files to modify:**

#### `main/state/match_state.lua`

- Confirm `apply_lane_modifier` (added in 6.1) has all 12 Tier 1 cases:
    - homeTurf, muddyField, windTunnel, blindingSun, redZone, scramble
    - groundPound, airRaid, trenches, secondary, specialUnit, playOfGame
- Verify the order of operations in `recompute_lane_sums`:
    1. Reset all revealed cards' `cur_off`/`cur_def` to base values (existing)
    2. `apply_lane_modifier(lane_idx)` ← NEW
    3. Sum revealed cards' cur_off/cur_def → store as you_off_sum, ai_off_sum, etc.
    4. Compute net_yards from sums

#### Verification testing

For each of the 12 Tier 1 modifiers, manually verify the effect works. The easiest way: add a temporary cheat-key to force a specific modifier on lane 0 for testing, OR play matches until you draw each modifier naturally.

Add a temporary dev helper (NOT in production):
```lua
-- In loader.script or match.script, on a key like KEY_M:
-- Cycle through modifier IDs and force lane 0 to that modifier
-- Re-render the medallion
-- This is dev-only; remove or guard before shipping
```

Don't add the dev helper unless needed — natural draw should expose modifiers within a few matches.

**Acceptance criteria for 6.4:**

- [ ] Play several matches. Verify each modifier you draw produces the expected stat change:
    - HOME TURF: your OFF cards visibly stronger, AI OFF weaker in that lane
    - RED ZONE: net yards in that lane noticeably higher than other lanes
    - MUDDY FIELD: stalled lane (low OFF, high DEF — slow yard gain)
    - SCRAMBLE: a QB-heavy hand performs much better in that lane
    - AIR RAID: WR/TE-heavy lane performs much better
    - GROUND & POUND: RB-heavy lane performs much better
    - TRENCHES: OL boost on OFF, DT boost on DEF
    - SECONDARY: CB/S cards much stronger in DEF
    - ST UNIT: kickers and specials buffed (rare drop)
    - WIND TUNNEL: QB/WR weaker
    - BLINDING SUN: WR/TE much weaker
    - PLAY OF GAME: the biggest card in the lane gets noticeably bigger
- [ ] Modifier effects are visible in the net-yards pills (post-reveal)
- [ ] Stat changes are correct mathematically (verify by playing a known card into a known modifier lane and checking the resulting net yards)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 6.5 — Tier 2 modifier effects (Hurry-Up, Prevent D, Scouted, Blitz Zone)

Wire the 4 Tier 2 modifiers.

**Files to modify:**

#### `main/state/match_state.lua`

- `M.effective_cost(card, lane_idx)` — already drafted in 6.1, verify it handles Hurry-Up + Prevent D correctly

- `M.play_card(card_uid, lane_idx)`:
    - Calculate `cost = M.effective_cost(card, lane_idx)` instead of `card.cost`
    - Energy check uses `cost`
    - Energy deducts `cost`
    - **Scouted branch:** After removing from hand and deducting energy, check:
        ```lua
        if M.is_scouted_first_play(lane_idx, "you") then
            -- Card spawns face-up immediately
            local lane = state.lanes[lane_idx + 1]
            local card_copy = clone(card_record)
            card_copy.revealed = true
            card_copy._base_off = card_copy.off
            card_copy._base_def = card_copy.def
            card_copy.cur_off = card_copy.off
            card_copy.cur_def = card_copy.def
            table.insert(lane.you_cards, card_copy)
            M.mark_scouted_first_played(lane_idx, "you")
            try_apply_snap_ability(card_copy, lane_idx, "you")
            M.recompute_lane_sums(lane_idx)
            return {
                success = true,
                scouted_revealed = true,  -- flag for match.script to handle differently
                card = card_copy,
                new_energy = state.you_energy,
                lane_idx = lane_idx,
                slot_idx = #lane.you_cards - 1,
            }
        else
            -- Normal face-down path (existing)
        end
        ```

- `M.ai_play_card(card, lane_idx)`:
    - Same Scouted handling for AI's first card per lane (use `"ai"` for the side parameter)

#### `main/match/match.script`

- `MATCH_PLAY_CARD` handler:
    - When `match_state.play_card(...)` returns `scouted_revealed = true`:
        - Spawn the card game object via the factory with `revealed = true` and `side = "you"`
        - Post a single message `HUD_AI_CARDS_SPAWNED { plays = [{ lane_idx, slot_idx, card_data, side = "you", revealed = true }] }` (reusing the existing message; the `revealed` flag tells HUD to render face-up immediately)
        - Post `HUD_LANE_SUMS_UPDATED` since recompute_lane_sums was already called
        - Post `HUD_HAND_CHANGED`, `HUD_ENERGY_CHANGED` as usual
        - No reveal animation needed; the card is already face-up
    - Otherwise existing behavior

- In `start_ai_plays` (where AI plays during END DRIVE):
    - Same handling — if Scouted causes the AI's first card to reveal immediately during the play phase. But wait, AI plays during END DRIVE, not during play phase. So for the AI side, Scouted doesn't really apply the same way. Let me think.

    Actually, the AI plays its cards AT END DRIVE, all at once. So the "first card" concept is sequenced within the AI play loop:
    - Iterate AI's chosen plays
    - For each play, check `is_scouted_first_play(lane_idx, "ai")`
    - If yes, reveal immediately (no face-down spawn, just spawn revealed)
    - If no, normal face-down spawn → reveal at the staggered flip phase

    Implementation:
    ```lua
    for _, play in ipairs(plays) do
        if match_state.is_scouted_first_play(play.lane_idx, "ai") then
            -- Reveal immediately
            ... (similar to player Scouted path)
            match_state.mark_scouted_first_played(play.lane_idx, "ai")
        else
            -- Normal face-down spawn
            match_state.ai_play_card(play.card, play.lane_idx)
            ... (existing)
        end
    end
    ```

#### `main/ui/hud_drag.lua`

- Update affordability check at drag-start to use **base cost** (since we don't know which lane yet)
- The drop validation uses `effective_cost(card, target_lane_idx)`
- If `effective_cost > current_energy` at drop time → snap-back + show toast "Not enough energy"
- The visual "dimmed unaffordable" indicator on hand cards uses base cost (so it errs on the side of "this might be playable somewhere")

#### `main/ai/cpu.lua`

- Update the heuristic to use `effective_cost` when checking affordability:
    ```lua
    local cost = match_state.effective_cost(card, lane_idx_being_evaluated)
    if cost <= energy_left then
        -- ...
    end
    ```
    This means the AI is smart about cost discounts — it'll preferentially play OFF cards in Hurry-Up lanes.

#### Blitz Zone (no-op in Phase 6)

- Add `trigger_count` parameter to `M.try_apply_snap_ability(card, lane_idx, side, trigger_count)`:
    - Default `trigger_count = 1`
    - If lane has Blitz Zone modifier AND card is DEF: trigger_count = 2
    - Loop the ability application `trigger_count` times
- In Phase 6, Clutch Kicker is OFF, so trigger_count is always 1 in practice. But the parameter exists for future ability work.

**Acceptance criteria for 6.5:**

- [ ] HURRY-UP lane: drag a 4-cost OFF card when you have 3 energy → drop succeeds, card plays, energy goes to 0 (cost 3 after discount)
- [ ] PREVENT D lane: same but with a DEF card
- [ ] Try to drag an unaffordable-even-with-discount card → drag starts (since base cost is used for visual), but drop fails with toast
- [ ] SCOUTED lane: drop your first card in that lane → card reveals face-up immediately (no face-down, no pending_plays), the pill updates instantly
- [ ] SCOUTED lane: drop subsequent cards in that lane → they play face-down as normal
- [ ] AI's first card in a SCOUTED lane (during END DRIVE) reveals immediately when AI plays it
- [ ] BLITZ ZONE: no visible effect (Clutch Kicker is OFF, can't be tested with current cards). Verify the trigger_count parameter exists in the dispatcher signature.
- [ ] AI heuristic uses effective_cost (verify: AI plays an OFF-heavy round in a Hurry-Up lane)
- [ ] No console errors

`// === STOP for developer review ===`

---

### Sub-phase 6.6 — CLAUDE.md update

Update CLAUDE.md:

- Phase log entry: `Phase 6: complete (16 lane modifiers — Tier 1 stat changes + Tier 2 cost/reveal)`
- Add `## Phase 6 — Lane modifiers notes` section at the bottom covering:
    - What was built per sub-phase
    - Modifier pool location: `main/data/modifiers.lua`
    - Modifier effect application: `apply_lane_modifier` in match_state.lua, called from `recompute_lane_sums` after base stat reset, before sum
    - Cost discount mechanism: `match_state.effective_cost(card, lane_idx)`, called from `play_card`, `ai_play_card`, and `cpu.choose_plays`
    - Scouted's immediate-reveal: bypasses pending_plays. Tracked per-lane-per-side via `scouted_first_played_you` / `scouted_first_played_ai`
    - Blitz Zone scaffolding: `trigger_count` parameter on `try_apply_snap_ability`, no-op in Phase 6 because Clutch Kicker is OFF
    - Slot-machine animation: 1.0s fast cycle + 0.5s deceleration + settle pulse. Implemented via chained `timer.delay` calls.
    - Affordability check moved to drop time (allows drags even on borderline-affordable cards; effective_cost validated at drop)
    - Medallion tap → toast: reuses existing toast pattern from Phase 4
- Intentional stubs: 4 Tier 3 mechanical modifiers (Frozen Tundra, Coin Flip, Turnover, Sudden Death) deferred to Phase 6.5
- Phase 6.5 follow-ups: Sudden Death (lane lock state + visual + scoring guard), Turnover (drive counter + swap animation), Coin Flip (per-drive randomness, reuses coin animation), Frozen Tundra (per-card ability-disabled flag)
- Phase 7 candidates: card synergies (13 combos that trigger on card stacks), more SNAP/FIELD card abilities, perks system

`// === STOP for developer review ===`

---

## Final acceptance for Phase 6

- [ ] Project opens in Defold editor with no red error markers
- [ ] Builds and runs on macOS
- [ ] Full match plays correctly across 8 drives (all prior phase behavior preserved)
- [ ] Match start: slot-machine reveal animation runs (~1.5s) revealing 3 random modifiers
- [ ] Each lane's medallion displays the chosen modifier's icon + name
- [ ] Tap a medallion → toast appears with full description
- [ ] All 12 Tier 1 modifiers have correct stat effects when they appear in a match
- [ ] Hurry-Up and Prevent D give correct cost discounts
- [ ] Scouted causes first-card-per-side to reveal immediately
- [ ] Blitz Zone parameter exists in dispatcher (no-op in Phase 6)
- [ ] AI heuristic respects effective_cost (plays smart in discount lanes)
- [ ] Reduced motion ON works correctly across new animations
- [ ] All Phase 5.5 visuals preserved (fan stacks, frames, chrome)
- [ ] No third-party libraries added
- [ ] CLAUDE.md updated

## When you're done

Reply with:

1. Summary of what was built per sub-phase
2. Any deviations from the prompt and why
3. Things to verify on Mac (since you can't run Defold)
4. Open items
5. **Honest assessment**: do modifiers actually make matches feel meaningfully different? Or are the effects too subtle to register?

Do not start Phase 6.5 or any other phase.
