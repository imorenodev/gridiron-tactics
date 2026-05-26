# Claude Code Prompt — Phase 5: Asset Integration

## Read first

**Read `CLAUDE.md` in the repo root before writing any code.** Every file you create or modify must conform to its conventions. If this prompt conflicts with `CLAUDE.md`, surface the conflict and stop.

Re-read specifically:
- Hard rules (especially #11 about render scripts — default render only)
- Code conventions (snake_case, module-local state, pre-computed hashes, message naming)
- Things I would NOT do
- Phase 0 / 1 / 2 / 2.5 / 3 / 4 notes — the established patterns we're extending

Also list the contents of `assets/images/ui/` before starting. There are ~38 PNGs migrated from `src/assets/` during Phase 2.5. Confirm they're present before building atlases.

## Context

Phases 0–4 built the complete gameplay loop. The game plays correctly: drag, reveal, score, multi-drive cycle, deck cycle, energy escalation. **But it looks like programmer art.** Every card is a box with text. The field is a green rectangle. The scoreboard is a dark bar. The energy orb is a yellow text node.

Phase 5 replaces all of that with the real PNG assets sitting unused in `assets/images/ui/`.

**Phase 5 is purely visual.** No gameplay changes. No new state. No new messages (well, almost — one for atlas-loaded notifications). The same game runs, it just looks like a real product.

## What ships

- 5 atlases built from the 38 PNGs
- Real card frames on hand cards and played cards (8 variants: rarity × side)
- Stadium background image behind the field
- Painted endzone PNGs in the slot row backgrounds
- Broadcast-style scoreboard frame with 9-slice (top bar)
- Concede + Snap (END DRIVE) buttons with 9-slice and proper chrome
- Deck and discard badge backgrounds (no 9-slice — baked fixed size)
- Energy orb frame PNG
- Team rings on score displays
- Power circles behind lane power pills
- Football icon in scoreboard center (replaces emoji)
- Position icons on each card (top-right corner)
- Ability star icon on cards with SNAP/FIELD abilities
- One real portrait (`qb_black_navy.png`) for QB cards
- Solid-color portrait fallback for all non-QB cards (per position)
- Real coin face PNGs in the 2-pt conversion modal flip animation

## What stays out (deferred)

- **Fonts** — Phase 5 keeps the default Defold font. Real fonts (Bebas Neue, Oswald, JetBrains Mono) ship in Phase 5.5.
- **hud.gui_script refactor** — script is ~1050 lines. Splitting deferred to Phase 5.5.
- **Procedural SVG portraits** — non-QB cards get solid color per position. Real portrait PNGs added as they're generated.
- **Modifier icons used in gameplay** — atlas is built (sliced from `29_modifier_icons_grid.png`) but modifiers themselves are Phase 6.
- **Audio** — no SFX added.
- **Game-over splash** — match summary still the Phase 3/4 layout.
- **New screens** — no settings screen, no locker room visuals.

## Hard rules

1. **No gameplay changes.** If you find yourself touching `match_state.lua`, `cpu.lua`, or the match.script orchestration logic, stop and ask. Phase 5 is rendering only.
2. **All new animations use `animate_helper`** (from Phase 2.5). No raw `gui.animate` or `go.animate` calls.
3. **9-slice only on scoreboard frame and buttons.** Everything else (badges, orb, rings, pills) uses baked fixed sizes. Per the locked design decision.
4. **Solid-color portraits per position** for non-QB cards. Do NOT port the procedural SVG generation logic. Define a `POSITION_COLOR` table and use that.
5. **Default Defold font everywhere.** Phase 5.5 handles real fonts.
6. **Atlas sprite trim mode must be Off** for any 9-slice sprite. Otherwise Defold's 9-slice breaks.
7. **Atlas inner padding must be 0** for any 9-slice atlas. Per the known Defold quirk.
8. **No new top-level folders.**
9. **Pre-compute any new hashes.**
10. **Do not modify CLAUDE.md mid-prompt.** Update once at the end (Sub-phase 5.6).
11. **Do not start Phase 6.**

## Sub-phases

Six sub-phases with `// === STOP for developer review ===` markers between each.

---

### Sub-phase 5.1 — Atlas inventory + field atlas

Inventory what's actually present, then build the field atlas as the first atlas — lowest risk because the field background and endzones are simple sprite swaps without 9-slice.

**Tasks:**

1. **Inventory:** list every file in `assets/images/ui/` and report the count. Expected: ~38 PNGs. Note which match the expected names from the design doc and which don't. If files are missing, surface them — don't fail silently.

2. **Build `assets/field.atlas`:** Defold atlas text-protobuf file. Sprite trim mode Off, inner padding 0 (these are the global atlas settings; per-sprite trim is also Off). Add entries:
    - `stadium_bg` → `assets/images/ui/04_stadium_bg.png`
    - `endzone_red` → `assets/images/ui/02_endzone_red.png`
    - `endzone_green` → `assets/images/ui/03_endzone_green.png`
    - `football_field_bg` → `assets/images/ui/football-field-bg.png` (might be in `assets/images/` instead of `ui/`; check both)

3. **Wire field background:** in `main/ui/hud.gui`, the existing field background (currently a solid color box node) should reference the `stadium_bg` sprite from `field.atlas`. The exact node depends on the existing structure — find the largest box node behind the lanes and assign the texture.

4. **Wire endzone slot rows:** each lane has a player slot row (bottom) and an AI slot row (top). In `hud.gui`, these are currently colored box nodes. Replace the texture of:
    - Each AI-side slot row → `endzone_red`
    - Each player-side slot row → `endzone_green`
    - Three lanes × two sides = 6 slot row nodes get textured

5. **Menu screen field background:** if `menu.gui` uses a field photo background, wire it to `football_field_bg`. The HTML uses this as a backdrop with a dark vignette overlay; Defold equivalent is a textured box node with a semi-transparent black box on top.

**Acceptance criteria for 5.1:**

- [ ] `assets/field.atlas` exists and parses without editor errors
- [ ] All 4 sprites visible in the Defold editor's atlas preview
- [ ] Match screen field area shows the stadium background image (not solid green)
- [ ] Slot rows on all 3 lanes show the painted endzones (red top, green bottom)
- [ ] Menu screen has a field photo background (if applicable)
- [ ] No console errors
- [ ] All gameplay behavior unchanged

`// === STOP for developer review ===`

---

### Sub-phase 5.2 — UI chrome atlas (scoreboard + buttons with 9-slice; badges/orb/rings/pills baked)

Build the chrome atlas. Apply 9-slice configuration ONLY to scoreboard frame and the two buttons. Everything else is baked fixed-size.

**Tasks:**

1. **Build `assets/ui_chrome.atlas`:**
    - Atlas-level settings: sprite trim mode Off, inner padding 0 (because 9-slice sprites need this)
    - Entries:
        - `scoreboard_frame` → `assets/images/ui/01_scoreboard_frame.png` — **9-slice sprite** (see step 2)
        - `pill_left` → `assets/images/ui/05_pill_left.png`
        - `pill_middle` → `assets/images/ui/05_pill_middle.png`
        - `pill_right` → `assets/images/ui/05_pill_right.png`
        - `button_concede` → `assets/images/ui/07_button_concede.png` — **9-slice sprite** (see step 2)
        - `button_snap` → `assets/images/ui/07_button_snap.png` — **9-slice sprite** (see step 2). Note: both buttons have the same prefix `07_*`; double-check filenames in the actual directory.
        - `energy_orb_frame` → `assets/images/ui/09_energy_orb_frame.png`
        - `ring_you` → `assets/images/ui/12_ring_you.png`
        - `ring_cpu` → `assets/images/ui/13_ring_cpu.png`
        - `power_circle_red` → `assets/images/ui/14_power_circle_red.png`
        - `power_circle_green` → `assets/images/ui/15_power_circle_green.png`
        - `badge_deck` → `assets/images/ui/16_badge_deck.png`
        - `badge_discard` → `assets/images/ui/17_badge_discard.png`
        - `star_ability` → `assets/images/ui/27_star_ability.png`

2. **9-slice configuration for the 3 stretching pieces:**

    For Defold GUI box nodes, 9-slice is set as a `slice9` property on the BOX NODE, not on the atlas entry. The atlas just provides the texture. Set the box node's `slice9 = (left, top, right, bottom)` in pixel margins from the texture's edges.
    
    Inspect each PNG's pixel dimensions:
    - **`scoreboard_frame`**: typical broadcast scoreboard with rounded corners and detailed borders. Set `slice9 = (32, 32, 32, 32)` initially. If the corners look stretched after wiring, increase to 48; if the middle looks compressed, decrease to 24.
    - **`button_concede`** and **`button_snap`**: button chrome. Set `slice9 = (16, 16, 16, 16)`. Adjust if needed.
    
    **Important: Defold has a known bug where atlas packing can rotate ("sideways") images, which breaks 9-slice rendering**. If the scoreboard or buttons render rotated 180° or with artifacts after building the atlas, the workaround is: add a dummy image entry to the atlas to change the pack order, OR move the affected image to its own atlas. Surface this if it happens.

3. **Wire scoreboard frame into top bar:**
    - In `hud.gui`, find the top bar background box node (where YOU SCORE / DRIVE / CPU SCORE live)
    - Set its texture to `ui_chrome/scoreboard_frame`
    - Set its `slice9` to (32, 32, 32, 32)
    - Verify the corner art doesn't stretch when the node is wider than the source PNG

4. **Wire buttons:**
    - Find the CONCEDE button node → set texture to `ui_chrome/button_concede`, slice9 to (16, 16, 16, 16)
    - Find the END DRIVE / SNAP button node → set texture to `ui_chrome/button_snap`, slice9 same
    - The button's text label stays as a child text node; the box node provides the chrome

5. **Wire baked-size chrome (no 9-slice):**
    - Energy orb background → `ui_chrome/energy_orb_frame`, baked to its native size
    - Deck badge background → `ui_chrome/badge_deck`, baked
    - Discard badge background → `ui_chrome/badge_discard`, baked
    - Team avatar for player score → `ui_chrome/ring_you`, baked behind the score number
    - Team avatar for AI score → `ui_chrome/ring_cpu`, baked behind the AI score number
    - Power circles behind each lane's pills → `ui_chrome/power_circle_red` (AI pill background), `ui_chrome/power_circle_green` (player pill background)
    - Ability star → `ui_chrome/star_ability`, placed on cards that have an ability (you'll add this in the card rendering function in sub-phase 5.4 — for now just confirm the sprite is in the atlas)

6. **Pill row 3-part stretchable layout:**
    - The lane medallion row in the HTML uses three pieces: left cap (square), middle (stretchable strip), right cap (square)
    - In Defold, this is three separate box nodes positioned side-by-side
    - Left cap: `ui_chrome/pill_left` at fixed size
    - Middle: `ui_chrome/pill_middle` stretched horizontally to fill the space (this is NOT a 9-slice; the middle PNG is designed to tile horizontally OR stretch cleanly because it's a uniform strip)
    - Right cap: `ui_chrome/pill_right` at fixed size
    - The lane medallion (modifier display) sits centered on the middle strip
    - The power pills (red on left, green on right) overlay the caps

**Acceptance criteria for 5.2:**

- [ ] `assets/ui_chrome.atlas` builds and is visible in editor
- [ ] Top bar shows the broadcast scoreboard frame, with corners crisp at any rendered width
- [ ] CONCEDE and END DRIVE buttons show real chrome, corners crisp at button label width
- [ ] Energy orb shows its frame PNG (with the energy count text on top)
- [ ] Deck and discard badges show real backgrounds with count text on top
- [ ] Team avatars on score displays show the ring PNGs
- [ ] Lane medallion row has the three-part pill (caps + stretchable middle)
- [ ] Lane power pills sit on the red/green power circles
- [ ] No console errors
- [ ] All gameplay behavior unchanged

`// === STOP for developer review ===`

---

### Sub-phase 5.3 — Cards atlas

Build the card frames atlas. Replace the box+text card visuals on both hand cards and played cards.

**Tasks:**

1. **Build `assets/cards.atlas`:**
    - Atlas-level settings: sprite trim mode Off (some card frames have transparent borders that should be preserved), inner padding 0
    - Entries — 8 card frame variants, one per rarity-side combination:
        - `frame_common_off` → `assets/images/ui/18_card_common_off.png`
        - `frame_common_def` → `assets/images/ui/19_card_common_def.png`
        - `frame_uncommon_off` → `assets/images/ui/20_card_uncommon_off.png`
        - `frame_uncommon_def` → `assets/images/ui/21_card_uncommon_def.png`
        - `frame_rare_off` → `assets/images/ui/22_card_rare_off.png`
        - `frame_rare_def` → `assets/images/ui/23_card_rare_def.png`
        - `frame_legendary_off` → `assets/images/ui/24_card_legendary_off.png`
        - `frame_legendary_def` → `assets/images/ui/25_card_legendary_def.png`
    - **Important:** verify these filenames exist. If the actual files are named differently (e.g., the numbering varies), use the actual names — surface the discrepancy.

2. **Card frame helper in `hud.gui_script`:**

    Add a helper function that returns the atlas sprite name for a card's rarity + side:
    ```lua
    local function get_card_frame_sprite(card)
        local rarity = card.rarity or "common"
        local side = card.side  -- "off" or "def"
        return "cards/frame_" .. rarity .. "_" .. side
    end
    ```

3. **Update hand card rendering (`render_hand_slot` or equivalent):**
    - The existing hand card is a box node with text children (cost, position, name, stat)
    - Add a child box node (or modify the root) to use the card frame sprite as its texture
    - The frame should be the bottom layer; text and badges sit on top
    - Z-order: frame at back, then portrait (sub-phase 5.5), then text overlays, then cost/position badges, then ability star

4. **Update played card rendering (`render_slot` or equivalent):**
    - Played cards in lane slots also need frame textures
    - Smaller scale than hand cards but same frame sprite
    - When face-down: no frame, just a darker placeholder (or use a card back sprite if one exists; otherwise solid dark color is fine)
    - When face-up: full frame + portrait + text + badges

5. **Ability star on cards with abilities:**
    - If `card.ability` is non-empty (e.g., Clutch Kicker has the FG ability), show a small star icon in the top-left or top-right of the card
    - Sprite: `ui_chrome/star_ability` (added in 5.2)
    - Size: ~20 design pixels

6. **Position badge on cards:**
    - The position abbreviation (QB, RB, WR, etc.) is currently a text node on the card
    - Keep as text for now — position icons get added in sub-phase 5.4 via the `icons.atlas`
    - This is so we can develop the card frame integration first, then add position icons on top in the next sub-phase

**Acceptance criteria for 5.3:**

- [ ] `assets/cards.atlas` builds and is visible in editor
- [ ] Hand cards show real frame textures, color-tinted per rarity (common = gray-ish, uncommon = green-tinted, rare = blue-tinted, legendary = gold-tinted)
- [ ] Hand cards show frame textures matching both rarity AND side (off vs def have different orange/blue tints)
- [ ] Played cards in lanes show real frame textures (face-up) and solid dark color (face-down)
- [ ] Cards with abilities (notably Clutch Kicker) show the ability star icon
- [ ] No console errors
- [ ] Drag-and-drop still works
- [ ] All gameplay behavior unchanged

`// === STOP for developer review ===`

---

### Sub-phase 5.4 — Icons atlas (position icons sliced from grid, modifier icons sliced for Phase 6, football icons, coin faces)

Build the icons atlas. The position icon grid PNG is one image with 12 icons in a 4x3 layout — slice it into 12 named sprites within the atlas. Same for modifier icon grid.

**Tasks:**

1. **Build `assets/icons.atlas`:**

    For sprite grids, Defold's atlas supports either:
    - Adding each sliced region as a separate sprite (manual slicing in the atlas file)
    - OR adding the grid as a single image with sub-image animation frames (Defold's "animation" entry in atlas)
    
    Use **separate sprites** approach for clarity — each position and modifier icon becomes its own atlas entry. This means slicing the source PNG into 12 individual PNG files OR computing the UV regions in the `.atlas` file.

    The cleanest approach in Defold: add each grid PNG once as a regular sprite, then create additional atlas entries that reference the same PNG with different `geometries` (defining sub-rectangles). However, this is complex.
    
    **Alternative simpler approach:** pre-slice the grid PNG into 12 individual files using a small Python script or ImageMagick. Then add each as a separate atlas entry.
    
    **Use the alternative approach.** Create 12 sliced files in `assets/images/ui/icons/` directory:
    - `pos_qb.png`, `pos_rb.png`, `pos_wr.png`, `pos_te.png`, `pos_ol.png`, `pos_k.png`
    - `pos_cb.png`, `pos_s.png`, `pos_lb.png`, `pos_de.png`, `pos_dt.png`, `pos_st.png`
    
    The slicing math: `28_position_icons_grid.png` is presumably 4 columns × 3 rows = 12 icons. Each icon is `(grid_width / 4)` × `(grid_height / 3)`. If you can't determine the grid dimensions, surface this as a question rather than guess.
    
    Same for the modifier grid `29_modifier_icons_grid.png`: 5 columns × 4 rows = 20 modifier icons. Slice to `mod_<id>.png` for each of the 20 modifier IDs from the HTML's `LANE_MODIFIERS` array. **These are atlas-only in Phase 5** — they're not used in gameplay until Phase 6 (lane modifiers).
    
    Atlas entries:
    - `football_icon` → `assets/images/ui/10_football_icon.png`
    - `football_scoreboard` → `assets/images/ui/11_football_scoreboard.png`
    - `coin_heads` → `assets/images/ui/30_coin_heads.png`
    - `coin_tails` → `assets/images/ui/31_coin_tails.png`
    - `pos_qb`, `pos_rb`, `pos_wr`, `pos_te`, `pos_ol`, `pos_k`, `pos_cb`, `pos_s`, `pos_lb`, `pos_de`, `pos_dt`, `pos_st` — 12 sliced position icons
    - `mod_homeTurf`, `mod_muddyField`, `mod_windTunnel`, `mod_frozenTundra`, `mod_blindingSun`, `mod_redZone`, `mod_hurryUp`, `mod_preventD`, `mod_scouted`, `mod_blitzZone`, `mod_scramble`, `mod_groundPound`, `mod_airRaid`, `mod_trenches`, `mod_secondary`, `mod_specialUnit`, `mod_coinFlip`, `mod_turnover`, `mod_suddenDeath`, `mod_playOfGame` — 20 sliced modifier icons (atlas-only; not wired in this phase)

2. **Position icon on cards:**

    In `hud.gui_script`, in the card rendering function:
    - Where the position abbreviation text was, add a sprite node showing the position icon
    - Helper:
        ```lua
        local function get_position_icon(card)
            return "icons/pos_" .. string.lower(card.pos)
        end
        ```
    - Position: top-right corner of the card
    - Size: ~32×32 design pixels
    - Optionally also keep the position text label below for clarity (designer call — leave it if it doesn't crowd)

3. **Football icon in scoreboard:**
    - In `hud.gui`, the scoreboard center area has a football icon. Replace with the `football_scoreboard` sprite from the atlas.

4. **Set up coin atlas entries** (the coin sprites get wired in sub-phase 5.6's flip upgrade)

**Acceptance criteria for 5.4:**

- [ ] `assets/icons.atlas` builds and is visible in editor
- [ ] All 12 position icons visible as separate sprites in the atlas
- [ ] All 20 modifier icons visible as separate sprites
- [ ] Football icons visible
- [ ] Coin face sprites visible
- [ ] Hand cards now show position icons in the top-right (e.g., a QB card has the QB icon)
- [ ] Played cards in lanes also show position icons
- [ ] Scoreboard center shows the football icon (not text/emoji)
- [ ] No console errors
- [ ] All gameplay behavior unchanged

`// === STOP for developer review ===`

---

### Sub-phase 5.5 — Portrait integration + position color fallback

Wire the existing portrait PNG for QBs. Add solid-color portrait fallback for all other positions.

**Tasks:**

1. **Build `assets/portraits.atlas`:**
    - `qb_black_navy` → `assets/images/ui/26_portraits/qb_black_navy.png`
    - This is the only portrait that exists. Future portraits get added here.

2. **Position color table** in `hud.gui_script` (or a shared module):
    ```lua
    local POSITION_COLOR = {
        QB = vmath.vector4(0.30, 0.55, 0.85, 1),  -- blue
        RB = vmath.vector4(0.95, 0.65, 0.25, 1),  -- orange
        WR = vmath.vector4(0.40, 0.85, 0.50, 1),  -- green
        TE = vmath.vector4(0.85, 0.85, 0.40, 1),  -- yellow
        OL = vmath.vector4(0.60, 0.40, 0.30, 1),  -- brown
        K =  vmath.vector4(0.95, 0.85, 0.30, 1),  -- gold
        CB = vmath.vector4(0.70, 0.30, 0.85, 1),  -- purple
        S =  vmath.vector4(0.30, 0.70, 0.85, 1),  -- cyan
        LB = vmath.vector4(0.85, 0.30, 0.30, 1),  -- red
        DE = vmath.vector4(0.85, 0.45, 0.30, 1),  -- red-orange
        DT = vmath.vector4(0.45, 0.30, 0.85, 1),  -- indigo
        ST = vmath.vector4(0.60, 0.60, 0.70, 1),  -- gray
    }
    ```

3. **Portrait helper:**
    ```lua
    local function get_portrait_sprite(card)
        -- Currently only QB has a real portrait
        if card.pos == "QB" then return "portraits/qb_black_navy" end
        return nil  -- caller uses position color fallback
    end
    ```

4. **Card portrait rendering:**
    - In each card slot (hand and played), add a portrait area (~80×80 design pixels on hand cards, smaller on played cards)
    - If `get_portrait_sprite(card)` returns a sprite name: render a sprite node with that texture
    - Otherwise: render a solid-color box node with the position's color from `POSITION_COLOR[card.pos]`
    - Either way, position it in the card's portrait area
    - Z-order: portrait sits between the card frame (back) and the text overlays (front)

**Acceptance criteria for 5.5:**

- [ ] `assets/portraits.atlas` builds
- [ ] QB cards in hand or in lanes show the real `qb_black_navy` portrait
- [ ] All other cards (RB, WR, TE, OL, K, CB, S, LB, DE, DT, ST) show a solid-color portrait matching the POSITION_COLOR table
- [ ] No console errors
- [ ] All gameplay behavior unchanged

`// === STOP for developer review ===`

---

### Sub-phase 5.6 — 2-pt coin flip upgrade + CLAUDE.md

Replace the rotating-text-box in the 2-pt conversion modal with real coin face PNGs.

**Tasks:**

1. **Coin flip animation upgrade:**

    In `hud.gui_script`, locate the conversion modal flip code (Phase 3's `start_coin_flip` and `flip_face_swap` or equivalent).

    Current behavior: a single text node rotates from 0 to 720° over 1.4s, with text content swapped at the 0.7s midpoint via `timer.delay`.

    New behavior:
    - Two sprite nodes: `conversion_coin_heads` (sprite: `icons/coin_heads`) and `conversion_coin_tails` (sprite: `icons/coin_tails`)
    - Both positioned at the same center point in the modal
    - The tails sprite starts with `rotation = (0, 180, 0)` so it's facing away (back of the coin)
    - The heads sprite starts at `rotation = (0, 0, 0)` so it's facing the camera
    - On flip start: animate both sprites' `rotation.y` from current value to current + 720 (two full spins)
    - At the midpoint of each 180° rotation, the visible face naturally swaps from one sprite to the other (this is how 3D coin flips work — heads face is visible 0°-90° and 270°-360°, tails face is visible 90°-270°)
    - When animation completes, the front-facing sprite matches the random `coin_result` value
        - To land on heads: total rotation = 720° (back to heads-facing)
        - To land on tails: total rotation = 540° or 900° (offset by 180°)
    - Compute final rotation:
        ```lua
        local final_rotation = (self.coin_result == "heads") and 720 or 900
        ```
    - Animate via `animate_helper`:
        ```lua
        animate_helper.animate_gui(coin_heads_node, "rotation.y", final_rotation, gui.EASING_OUTQUAD, 1.4, 0, on_complete)
        animate_helper.animate_gui(coin_tails_node, "rotation.y", final_rotation + 180, gui.EASING_OUTQUAD, 1.4, 0, nil)
        ```
    - The mid-flip face-swap timer is no longer needed — the 3D rotation handles it automatically
    - Reduced motion: skips the rotation animation and just sets the final state directly (handled by `animate_helper`)

2. **Remove the rotating-text-box code** from Phase 3 if it's still there as a fallback.

3. **CLAUDE.md update:**

    Add Phase log entry: `Phase 5: complete (asset integration — atlases, card frames, portraits, coin upgrade)`
    
    Add a new section `## Phase 5 — Asset integration notes` at the bottom covering:
    - What was built per sub-phase
    - Atlases built and their contents
    - Key architectural choices:
        - 9-slice ONLY on scoreboard frame and buttons (per Decision C hybrid)
        - Solid-color portraits per position for non-QB cards (no procedural SVG)
        - Pill row uses 3-piece layout (left cap + middle strip + right cap) not 9-slice
        - Position icons pre-sliced into 12 individual PNGs (`assets/images/ui/icons/pos_*.png`)
        - Modifier icons pre-sliced into 20 individual PNGs but NOT wired (deferred to Phase 6)
        - Coin flip uses two sprite nodes with synchronized 3D rotation; tails offsets by +180° from heads
        - Fonts deferred to Phase 5.5
        - `hud.gui_script` split deferred to Phase 5.5
    - What's still stubbed: real fonts, more portraits, audio, hud.gui_script refactor, modifiers/synergies/perks/season
    - Phase 5.5 follow-ups: font integration, hud.gui_script split, real portrait generation pipeline
    - Phase 6 candidate: lane modifiers (the atlas is built; the gameplay system isn't)

**Acceptance criteria for 5.6:**

- [ ] Score a TD with no Kicker, then choose GO FOR 2 in the conversion modal
- [ ] Coin face PNG visible in the modal during the flip animation
- [ ] During the 1.4s flip, both heads and tails faces become visible at appropriate angles (you'll see the coin "edge" as it rotates through 90° / 270°)
- [ ] Coin lands on the correct face matching the random result
- [ ] Result text and PAT/score updates as before
- [ ] Reduced motion ON: coin lands instantly on the result face (no rotation)
- [ ] CLAUDE.md updated with Phase 5 notes
- [ ] No console errors
- [ ] All gameplay behavior unchanged

`// === STOP for developer review ===`

---

## Final acceptance for Phase 5

- [ ] Project opens in Defold editor with no red error markers
- [ ] Builds and runs on macOS
- [ ] Full match plays out correctly across 8 drives (all Phase 4 behavior preserved)
- [ ] Visual transformation complete:
    - Stadium background image visible behind lanes
    - Painted endzones in slot rows (red top, green bottom)
    - Broadcast scoreboard frame on top bar with 9-slice
    - Real chrome on CONCEDE and END DRIVE buttons with 9-slice
    - Energy orb has its frame image
    - Deck and discard badges have backgrounds
    - Team rings around score numbers
    - Real card frames on all cards (rarity + side combinations visible)
    - Position icons on top-right of every card
    - Ability star visible on Clutch Kicker (the one card with an ability)
    - QB cards show the real portrait; other cards show position-colored portrait
    - 2-pt coin flip uses real coin face PNGs
- [ ] No fonts changes (default font still used; that's Phase 5.5)
- [ ] No hud.gui_script split (still ~1050 lines; that's Phase 5.5)
- [ ] Reduced motion ON still works correctly
- [ ] All gameplay behavior unchanged
- [ ] No third-party libraries added
- [ ] CLAUDE.md updated

## When you're done

Reply with:

1. Summary of what was built per sub-phase
2. Any deviations from the prompt and why
3. Atlas inventory: what got built, what file names mapped to what sprite names
4. Things to verify on Mac (since you can't run Defold)
5. Specific concerns about visual rendering (9-slice corner artifacts, atlas packing oddities, sprite alignment issues)
6. Open items
7. **Honest assessment**: does the game now look like a real game, or does the visual still feel uneven (e.g., card frames look polished but the rest feels flat)?

Do not start Phase 5.5 or Phase 6.
