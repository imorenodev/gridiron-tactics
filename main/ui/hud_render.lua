-- Rendering helpers, animations, and visual constants shared across the
-- HUD. Phase 5.5 extracted this from hud.gui_script; Phase 5.5
-- continuation extended it with:
--   * compute_stack_position(lane_idx, side, slot_idx) — single source
--     of truth for where any card in a stack lives.
--   * render_slot now handles the portrait-card hierarchy (root + 7
--     children: frame, portrait, pos_icon, ability_star, cost, name, stat).
--   * animate_card_slap_down — used when AI face-down cards spawn.
--   * animate_card_fade_in — used when player-drop ghost finishes its
--     travel and hands off to the spawned card.
--   * animate_lane_reset_exit — synchronized exit when a lane resets.

local animate_helper = require("main.animation.animate_helper")
local modifiers      = require("main.data.modifiers")

local M = {}

-- ---------------------------------------------------------------------------
-- Visual constants
-- ---------------------------------------------------------------------------

local CARD_DIMMED         = vmath.vector4(0.4, 0.4, 0.4, 0.55)
local CARD_FULL           = vmath.vector4(1.0, 1.0, 1.0, 1.0)
local CARD_UNAFFORDABLE   = vmath.vector4(0.45, 0.45, 0.45, 1.0)
local YARD_BAR_WIDTH      = 320
local SLOT_FACE_DOWN_COLOR = vmath.vector4(0.18, 0.18, 0.22, 1.0)

local BURST_SCALE_BASE  = 6.0
local BURST_SCALE_START = 1.8
local BURST_FADE_IN     = 0.3
local BURST_SCALE_IN    = 0.4
local BURST_HOLD        = 0.9
local BURST_FADE_OUT    = 0.5

local SCORE_BASE_SCALE  = vmath.vector3(2.2, 2.2, 1)
local SCORE_PULSE_SCALE = vmath.vector3(2.86, 2.86, 1)
local DRIVE_BASE_SCALE  = vmath.vector3(1.6, 1.6, 1)
local DRIVE_PULSE_SCALE = vmath.vector3(1.84, 1.84, 1)
local BADGE_BASE_SCALE  = vmath.vector3(1.0, 1.0, 1.0)
local BADGE_BUMP_SCALE  = vmath.vector3(1.18, 1.18, 1.0)
local ORB_PULSE_SCALE   = vmath.vector3(1.08, 1.08, 1.0)

local DISCARD_DURATION  = 0.6
local DISCARD_STAGGER   = 0.04
local DRAW_DURATION     = 0.4
local DRAW_STAGGER      = 0.08
local TOAST_FADE_IN     = 0.2
local TOAST_HOLD        = 0.85
local TOAST_FADE_OUT    = 0.25
local TOAST_RISE_PHASE1 = 12
local TOAST_RISE_PHASE2 = 22

-- Phase 5.5.5 fan-layout constants
local LANE_X              = { 195, 585, 975 }
local STACK_OFFSET_Y      = 35
local STACK_JITTER_X      = 5
local STACK_ROTATION      = 2
local PLAYER_STACK_BASE_Y = 800
local AI_STACK_BASE_Y     = 2100

-- Phase 5.5.5 slap-down animation timings
local SLAPDOWN_DURATION       = 0.25
local SLAPDOWN_SETTLE_DURATION = 0.10
local SLAPDOWN_START_SCALE     = vmath.vector3(1.4, 1.4, 1)
local SLAPDOWN_END_SCALE       = vmath.vector3(1.0, 1.0, 1)
local SLAPDOWN_SETTLE_SCALE    = vmath.vector3(1.05, 1.05, 1)

-- Phase 5.5.7 hand-to-lane ghost continuity
local GHOST_TRAVEL_DURATION = 0.30
local CARD_FADE_IN_DELAY    = 0.22
local CARD_FADE_IN_DURATION = 0.08

-- Phase 5.5.6 lane reset exit
local LANE_RESET_EXIT_DURATION = 0.5
local LANE_RESET_POS_SHIFT     = 200
local LANE_RESET_ROT_KICK      = 15

local HAND_X_BY_INDEX = { [1] = 165, [2] = 360, [3] = 555, [4] = 750, [5] = 945 }
local HAND_Y          = 550

M.CARD_DIMMED           = CARD_DIMMED
M.CARD_FULL             = CARD_FULL
M.YARD_BAR_WIDTH        = YARD_BAR_WIDTH
M.HAND_X_BY_INDEX       = HAND_X_BY_INDEX
M.HAND_Y                = HAND_Y
M.DISCARD_DURATION      = DISCARD_DURATION
M.DISCARD_STAGGER       = DISCARD_STAGGER
M.DRAW_DURATION         = DRAW_DURATION
M.DRAW_STAGGER          = DRAW_STAGGER
M.STACK_OFFSET_Y        = STACK_OFFSET_Y
M.PLAYER_STACK_BASE_Y   = PLAYER_STACK_BASE_Y
M.AI_STACK_BASE_Y       = AI_STACK_BASE_Y
M.GHOST_TRAVEL_DURATION = GHOST_TRAVEL_DURATION
M.CARD_FADE_IN_DELAY    = CARD_FADE_IN_DELAY
M.CARD_FADE_IN_DURATION = CARD_FADE_IN_DURATION

-- Per-position fallback color for non-QB cards. Currently unused (non-QB
-- portrait nodes are hidden because Defold's gui.set_texture won't
-- release a texture binding at runtime), but kept for the future blank-
-- portrait swap.
M.POSITION_COLOR = {
    QB = vmath.vector4(0.30, 0.55, 0.85, 1),
    RB = vmath.vector4(0.95, 0.65, 0.25, 1),
    WR = vmath.vector4(0.40, 0.85, 0.50, 1),
    TE = vmath.vector4(0.85, 0.85, 0.40, 1),
    OL = vmath.vector4(0.60, 0.40, 0.30, 1),
    K  = vmath.vector4(0.95, 0.85, 0.30, 1),
    CB = vmath.vector4(0.70, 0.30, 0.85, 1),
    S  = vmath.vector4(0.30, 0.70, 0.85, 1),
    LB = vmath.vector4(0.85, 0.30, 0.30, 1),
    DE = vmath.vector4(0.85, 0.45, 0.30, 1),
    DT = vmath.vector4(0.45, 0.30, 0.85, 1),
    ST = vmath.vector4(0.60, 0.60, 0.70, 1),
}

local BURST_TEXT_BY_TYPE = {
    td          = "TOUCHDOWN",
    safety      = "SAFETY +2",
    pick6       = "PICK SIX +6",
    fg          = "FIELD GOAL +3",
    pat         = "PAT GOOD +1",
    ["2pt"]     = "2-PT CONVERSION!",
    lane_locked = "LANE LOCKED",
}
local BURST_COLOR_BY_TYPE = {
    td      = vmath.vector4(0.29, 1.0,  0.54, 1.0),
    safety  = vmath.vector4(1.0,  0.72, 0.0,  1.0),
    pick6   = vmath.vector4(1.0,  0.42, 0.42, 1.0),
    fg      = vmath.vector4(1.0,  0.84, 0.0,  1.0),
    pat     = vmath.vector4(1.0,  0.84, 0.0,  1.0),
    ["2pt"] = vmath.vector4(0.29, 1.0,  0.54, 1.0),
}

-- ---------------------------------------------------------------------------
-- Card helpers
-- ---------------------------------------------------------------------------

local function stat_color_for_side(side)
    if side == "def" then
        return vmath.vector4(0.4, 0.7, 1.0, 1.0)
    end
    return vmath.vector4(0.95, 0.5, 0.15, 1.0)
end

local function stat_text_for_card(card)
    if card.side == "def" then
        return "DEF " .. tostring(card.def or 0)
    end
    return "OFF " .. tostring(card.off or 0)
end

local function get_card_frame_sprite(card)
    local rarity = card.rarity or "common"
    local side = card.side or "off"
    return "frame_" .. rarity .. "_" .. side
end

local function get_portrait_sprite(card)
    if card.pos == "QB" then return "qb_black_navy" end
    return nil
end

M.get_card_frame_sprite = get_card_frame_sprite
M.get_portrait_sprite   = get_portrait_sprite

-- ---------------------------------------------------------------------------
-- Phase 5.5.5: stack position math
-- ---------------------------------------------------------------------------

-- Computes the world position, z-rotation, and z-order for the slot at
-- `slot_idx` on `side` of `lane_idx`. slot_idx is 0-based to match the
-- rest of the codebase. Caller applies position/rotation to the slot's
-- root node and uses z_order to decide draw order (later draws on top).
function M.compute_stack_position(lane_idx, side, slot_idx)
    local x = LANE_X[lane_idx + 1] or 585
    local jitter_x = (slot_idx % 2 == 0) and -STACK_JITTER_X or STACK_JITTER_X
    local rotation_z = (slot_idx % 2 == 0) and -STACK_ROTATION or STACK_ROTATION

    local y
    if side == "you" then
        y = PLAYER_STACK_BASE_Y + slot_idx * STACK_OFFSET_Y
    else
        y = AI_STACK_BASE_Y - slot_idx * STACK_OFFSET_Y
    end

    return {
        position = vmath.vector3(x + jitter_x, y, 0),
        rotation_z = rotation_z,
        z_order = slot_idx,
    }
end

-- Applies the computed stack position to a slot's root node. The slot is
-- parented to lane_X_root, so the position written is RELATIVE to the
-- lane. The compute_stack_position returns design-space coordinates,
-- which we convert to lane-relative by subtracting the lane's y-center
-- (1500). LANE_X values are already absolute, so x stays unchanged.
local LANE_CENTER_Y = 1500

function M.apply_stack_position(slot_node, lane_idx, side, slot_idx)
    local sp = M.compute_stack_position(lane_idx, side, slot_idx)
    local rel = vmath.vector3(sp.position.x - (LANE_X[lane_idx + 1] or 585),
                              sp.position.y - LANE_CENTER_Y, 0)
    gui.set_position(slot_node, rel)
    gui.set_rotation(slot_node, vmath.vector3(0, 0, sp.rotation_z))
end

-- ---------------------------------------------------------------------------
-- Hand slot rendering (unchanged from Phase 5.5 refactor)
-- ---------------------------------------------------------------------------

function M.render_hand_slot(nodes, card, current_energy)
    if card == nil or card.empty then
        gui.set_color(nodes.root, CARD_DIMMED)
        gui.set_text(nodes.cost, "")
        gui.set_text(nodes.pos, "")
        gui.set_text(nodes.name, "EMPTY")
        gui.set_text(nodes.stat, "")
        if nodes.portrait then gui.set_enabled(nodes.portrait, false) end
        if nodes.pos_icon then gui.set_enabled(nodes.pos_icon, false) end
        if nodes.ability_star then gui.set_enabled(nodes.ability_star, false) end
        return
    end

    local can_afford = (card.cost or 0) <= (current_energy or 0)
    gui.set_color(nodes.root, can_afford and CARD_FULL or CARD_UNAFFORDABLE)
    gui.set_texture(nodes.root, "cards")
    gui.play_flipbook(nodes.root, hash(get_card_frame_sprite(card)))

    gui.set_text(nodes.cost, tostring(card.cost))
    gui.set_text(nodes.pos, "")
    gui.set_text(nodes.name, card.name)
    gui.set_text(nodes.stat, stat_text_for_card(card))
    gui.set_color(nodes.stat, stat_color_for_side(card.side))

    if nodes.portrait then
        local sprite = get_portrait_sprite(card)
        if sprite then
            gui.set_enabled(nodes.portrait, true)
            gui.set_texture(nodes.portrait, "portraits")
            gui.play_flipbook(nodes.portrait, hash(sprite))
            gui.set_color(nodes.portrait, CARD_FULL)
        else
            gui.set_enabled(nodes.portrait, false)
        end
    end

    if nodes.pos_icon then
        gui.set_enabled(nodes.pos_icon, true)
        gui.set_texture(nodes.pos_icon, "icons")
        gui.play_flipbook(nodes.pos_icon, hash("pos_" .. string.lower(card.pos or "qb")))
    end

    if nodes.ability_star then
        local has_ability = card.ability ~= nil and card.ability ~= ""
        gui.set_enabled(nodes.ability_star, has_ability)
    end
end

-- ---------------------------------------------------------------------------
-- Lane slot (played card) — portrait layout
-- ---------------------------------------------------------------------------

-- Hide every child of a portrait slot. Used for face-down + empty states.
local function hide_slot_children(slot)
    if slot.frame then gui.set_enabled(slot.frame, false) end
    if slot.portrait then gui.set_enabled(slot.portrait, false) end
    if slot.pos_icon then gui.set_enabled(slot.pos_icon, false) end
    if slot.ability_star then gui.set_enabled(slot.ability_star, false) end
    if slot.cost then gui.set_text(slot.cost, "") end
    if slot.name then gui.set_text(slot.name, "") end
    if slot.stat then gui.set_text(slot.stat, "") end
end

-- Reveal-state render: shows the card frame + portrait + position icon
-- + ability star + cost/name/stat text. Caller has already enabled the
-- slot.root and set its position/rotation via apply_stack_position.
local function render_face_up(slot, card_data)
    gui.set_color(slot.root, CARD_FULL)

    if slot.frame then
        gui.set_enabled(slot.frame, true)
        gui.set_texture(slot.frame, "cards")
        gui.play_flipbook(slot.frame, hash(get_card_frame_sprite(card_data)))
    end

    if slot.portrait then
        local sprite = get_portrait_sprite(card_data)
        if sprite then
            gui.set_enabled(slot.portrait, true)
            gui.set_texture(slot.portrait, "portraits")
            gui.play_flipbook(slot.portrait, hash(sprite))
            gui.set_color(slot.portrait, CARD_FULL)
        else
            gui.set_enabled(slot.portrait, false)
        end
    end

    if slot.pos_icon then
        gui.set_enabled(slot.pos_icon, true)
        gui.set_texture(slot.pos_icon, "icons")
        gui.play_flipbook(slot.pos_icon, hash("pos_" .. string.lower(card_data.pos or "qb")))
    end

    if slot.ability_star then
        local has_ability = card_data.ability ~= nil and card_data.ability ~= ""
        gui.set_enabled(slot.ability_star, has_ability)
    end

    if slot.cost then gui.set_text(slot.cost, tostring(card_data.cost or "")) end
    if slot.name then gui.set_text(slot.name, card_data.name or "") end
    if slot.stat then
        gui.set_text(slot.stat, stat_text_for_card(card_data))
        gui.set_color(slot.stat, stat_color_for_side(card_data.side))
    end
end

-- Render a lane slot. `slot` is the cached node-ref table for one slot
-- (root, frame, portrait, pos_icon, ability_star, cost, name, stat,
-- plus the bookkeeping fields card_data + revealed). The lane_idx /
-- side / slot_idx are passed so we can apply the stack position.
--
-- Phase 5.5.7: if a previously-empty slot is becoming filled (the
-- player just dropped a card into it), the rendered slot fades in
-- from alpha 0 with CARD_FADE_IN_DELAY. This is the handoff target
-- for the hand-to-lane ghost animation in hud_drag.lua.
function M.render_slot(slot, card_data, revealed, lane_idx, side, slot_idx)
    if not slot then return end

    if not card_data then
        gui.set_enabled(slot.root, false)
        gui.set_scale(slot.root, vmath.vector3(1, 1, 1))
        hide_slot_children(slot)
        slot.card_data = nil
        slot.revealed = false
        return
    end

    local was_empty = (slot.card_data == nil)

    slot.card_data = card_data
    slot.revealed = revealed and true or false

    gui.set_enabled(slot.root, true)
    gui.set_scale(slot.root, vmath.vector3(1, 1, 1))

    if lane_idx ~= nil and side and slot_idx ~= nil then
        M.apply_stack_position(slot.root, lane_idx, side, slot_idx)
    end

    if slot.revealed then
        render_face_up(slot, card_data)
    else
        gui.set_color(slot.root, SLOT_FACE_DOWN_COLOR)
        hide_slot_children(slot)
    end

    if was_empty then
        -- Newly placed in this slot — fade in to match the hand-to-lane
        -- ghost handoff timing (CARD_FADE_IN_DELAY synced to ghost
        -- travel; CARD_FADE_IN_DURATION is the cross-fade window).
        local base = slot.revealed and CARD_FULL or SLOT_FACE_DOWN_COLOR
        gui.set_color(slot.root, vmath.vector4(base.x, base.y, base.z, 0))
        animate_helper.animate_gui(slot.root, "color.w", base.w,
            gui.EASING_OUTQUAD, CARD_FADE_IN_DURATION, CARD_FADE_IN_DELAY)
    end
end

-- Phase 5.5.5: when a card spawns (player play or AI face-down), this
-- runs the slap-down animation. Caller passes the slot's stack indices
-- so we can land at the correct stack position.
--
-- For AI face-down spawn, this is the spawn animation.
-- For player play, sub-phase 5.5.7 uses a different path (ghost handoff);
-- the spawned card uses animate_card_fade_in instead.
function M.animate_card_slap_down(slot, card_data, lane_idx, side, slot_idx, revealed)
    if not slot then return end

    -- Mutate state + content first so the animation animates the correct
    -- visual.
    slot.card_data = card_data
    slot.revealed = revealed and true or false
    gui.set_enabled(slot.root, true)
    if slot.revealed then
        render_face_up(slot, card_data)
    else
        gui.set_color(slot.root, SLOT_FACE_DOWN_COLOR)
        hide_slot_children(slot)
    end

    -- Compute target stack position; start the card a bit above and big.
    local sp = M.compute_stack_position(lane_idx, side, slot_idx)
    local lane_x = LANE_X[lane_idx + 1] or 585
    local target_rel_x = sp.position.x - lane_x
    local target_rel_y = sp.position.y - LANE_CENTER_Y

    -- Start ~80px above target on player side, ~80px below on AI side.
    local start_offset = (side == "you") and 80 or -80
    gui.set_position(slot.root, vmath.vector3(target_rel_x, target_rel_y + start_offset, 0))
    gui.set_rotation(slot.root, vmath.vector3(0, 0, sp.rotation_z))
    gui.set_scale(slot.root, SLAPDOWN_START_SCALE)

    -- Make the root briefly transparent for the fade-in. Color is the
    -- face-up white or face-down dark; we modify .w only.
    local base_color = slot.revealed and CARD_FULL or SLOT_FACE_DOWN_COLOR
    gui.set_color(slot.root, vmath.vector4(base_color.x, base_color.y, base_color.z, 0))

    -- Animate to final stack position + scale + alpha.
    animate_helper.animate_gui(slot.root, gui.PROP_POSITION,
        vmath.vector3(target_rel_x, target_rel_y, 0),
        gui.EASING_OUTBACK, SLAPDOWN_DURATION)
    animate_helper.animate_gui(slot.root, gui.PROP_SCALE, SLAPDOWN_END_SCALE,
        gui.EASING_OUTBACK, SLAPDOWN_DURATION)
    animate_helper.animate_gui(slot.root, "color.w", base_color.w,
        gui.EASING_OUTQUAD, SLAPDOWN_DURATION, 0,
        function(_s)
            -- Brief settle pulse after landing.
            animate_helper.animate_gui(slot.root, gui.PROP_SCALE, SLAPDOWN_SETTLE_SCALE,
                gui.EASING_OUTQUAD, SLAPDOWN_SETTLE_DURATION / 2, 0,
                function(_s2)
                    animate_helper.animate_gui(slot.root, gui.PROP_SCALE, SLAPDOWN_END_SCALE,
                        gui.EASING_INQUAD, SLAPDOWN_SETTLE_DURATION / 2)
                end)
        end)
end

-- Phase 5.5.7: used by the player drop path. The card visual is already
-- in place (render_slot just ran with the new card data); we just fade
-- in alpha 0 → 1 over CARD_FADE_IN_DURATION with CARD_FADE_IN_DELAY.
-- The delay matches the ghost's travel duration so the visual handoff
-- is continuous from the player's perspective.
function M.animate_card_fade_in(slot)
    if not slot then return end
    -- Pre-set alpha 0; animate to 1.
    local base = slot.revealed and CARD_FULL or SLOT_FACE_DOWN_COLOR
    gui.set_color(slot.root, vmath.vector4(base.x, base.y, base.z, 0))
    animate_helper.animate_gui(slot.root, "color.w", base.w,
        gui.EASING_OUTQUAD, CARD_FADE_IN_DURATION, CARD_FADE_IN_DELAY)
end

function M.flip_slot(slot)
    if not slot or not slot.card_data then return end
    local card_data = slot.card_data
    animate_helper.animate_gui(slot.root, "scale.x", 0,
        gui.EASING_INQUAD, 0.14, 0,
        function(_s)
            slot.revealed = true
            render_face_up(slot, card_data)
            animate_helper.animate_gui(slot.root, "scale.x", 1,
                gui.EASING_OUTQUAD, 0.14)
        end)
end

-- Phase 5.5.6: synchronized exit animation for all cards in a lane when
-- the lane resets after a score. `slots_for_lane` is the lane's
-- { you = {[0..4]={slot}, ...}, ai = {[0..4]={slot}, ...} } table.
-- on_complete fires when the slowest animation finishes.
function M.animate_lane_reset_exit(slots_for_lane, on_complete)
    local active = 0
    local done = false

    local function tick()
        active = active - 1
        if active <= 0 and not done then
            done = true
            if on_complete then on_complete() end
        end
    end

    local function exit_one(slot, side)
        if not slot or not slot.card_data then return end

        local current_pos = gui.get_position(slot.root)
        local shift = (side == "you") and LANE_RESET_POS_SHIFT or -LANE_RESET_POS_SHIFT
        local target_pos = vmath.vector3(current_pos.x, current_pos.y + shift, current_pos.z)

        local current_rot = gui.get_rotation(slot.root)
        local rot_kick = (current_rot.z >= 0) and LANE_RESET_ROT_KICK or -LANE_RESET_ROT_KICK
        local target_rot = vmath.vector3(0, 0, current_rot.z + rot_kick)

        active = active + 1
        animate_helper.animate_gui(slot.root, gui.PROP_POSITION, target_pos,
            gui.EASING_INQUAD, LANE_RESET_EXIT_DURATION)
        animate_helper.animate_gui(slot.root, gui.PROP_ROTATION, target_rot,
            gui.EASING_INQUAD, LANE_RESET_EXIT_DURATION)
        animate_helper.animate_gui(slot.root, gui.PROP_SCALE,
            vmath.vector3(0.6, 0.6, 1),
            gui.EASING_INQUAD, LANE_RESET_EXIT_DURATION)
        animate_helper.animate_gui(slot.root, "color.w", 0,
            gui.EASING_INQUAD, LANE_RESET_EXIT_DURATION, 0,
            function(_s)
                tick()
            end)
    end

    for s = 0, 4 do
        if slots_for_lane.you and slots_for_lane.you[s] then
            exit_one(slots_for_lane.you[s], "you")
        end
        if slots_for_lane.ai and slots_for_lane.ai[s] then
            exit_one(slots_for_lane.ai[s], "ai")
        end
    end

    -- If no cards exited, fire on_complete immediately on the next frame
    -- so the caller's flow doesn't stall.
    if active == 0 then
        timer.delay(0.001, false, function()
            if not done then
                done = true
                if on_complete then on_complete() end
            end
        end)
    end
end

function M.clear_lane_card_slots(slots_for_lane)
    for s = 0, 4 do
        if slots_for_lane.you and slots_for_lane.you[s] then
            M.render_slot(slots_for_lane.you[s], nil, false)
        end
        if slots_for_lane.ai and slots_for_lane.ai[s] then
            M.render_slot(slots_for_lane.ai[s], nil, false)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Lane meta (pills, yard bars, position text)
-- ---------------------------------------------------------------------------

function M.render_lane_meta(nodes, you_pos, ai_pos, you_net, ai_net)
    if not nodes then return end
    local you_w = math.max(0, math.min(YARD_BAR_WIDTH, (you_pos or 0) / 100 * YARD_BAR_WIDTH))
    local ai_w = math.max(0, math.min(YARD_BAR_WIDTH, (ai_pos or 0) / 100 * YARD_BAR_WIDTH))
    gui.set_size(nodes.p_yard_fill, vmath.vector3(you_w, 25, 0))
    gui.set_size(nodes.ai_yard_fill, vmath.vector3(ai_w, 25, 0))
    gui.set_text(nodes.p_pos_text, tostring(you_pos or 0))
    gui.set_text(nodes.ai_pos_text, tostring(ai_pos or 0))
    gui.set_text(nodes.p_pill_text, "+" .. tostring(you_net or 0))
    gui.set_text(nodes.ai_pill_text, "+" .. tostring(ai_net or 0))
end

function M.animate_lane_resolved(nodes, new_you_pos, new_ai_pos)
    if not nodes then return end
    local target_you_w = math.max(0, math.min(YARD_BAR_WIDTH,
        (new_you_pos or 0) / 100 * YARD_BAR_WIDTH))
    local target_ai_w = math.max(0, math.min(YARD_BAR_WIDTH,
        (new_ai_pos or 0) / 100 * YARD_BAR_WIDTH))
    animate_helper.animate_gui(nodes.p_yard_fill, "size.x", target_you_w,
        gui.EASING_OUTQUAD, 0.6)
    animate_helper.animate_gui(nodes.ai_yard_fill, "size.x", target_ai_w,
        gui.EASING_OUTQUAD, 0.6)
    gui.set_text(nodes.p_pos_text, tostring(new_you_pos or 0))
    gui.set_text(nodes.ai_pos_text, tostring(new_ai_pos or 0))
end

-- After the lane reset exit animation completes, the slots have been
-- repositioned/scaled/faded by exit. This clears their state and resets
-- their transforms so they're ready for the next drive's cards.
function M.finalize_lane_reset(slots_for_lane, nodes, new_you_pos, new_ai_pos)
    M.clear_lane_card_slots(slots_for_lane)
    -- Reset each slot's transform so a future spawn doesn't inherit the
    -- exited transform.
    for s = 0, 4 do
        for _, side in ipairs({ "you", "ai" }) do
            local slot = slots_for_lane[side] and slots_for_lane[side][s]
            if slot and slot.root then
                gui.set_scale(slot.root, vmath.vector3(1, 1, 1))
                gui.set_rotation(slot.root, vmath.vector3(0, 0, 0))
            end
        end
    end
    if not nodes then return end
    local target_you_w = math.max(0, math.min(YARD_BAR_WIDTH,
        (new_you_pos or 0) / 100 * YARD_BAR_WIDTH))
    local target_ai_w = math.max(0, math.min(YARD_BAR_WIDTH,
        (new_ai_pos or 0) / 100 * YARD_BAR_WIDTH))
    animate_helper.animate_gui(nodes.p_yard_fill, "size.x", target_you_w,
        gui.EASING_OUTQUAD, 0.4)
    animate_helper.animate_gui(nodes.ai_yard_fill, "size.x", target_ai_w,
        gui.EASING_OUTQUAD, 0.4)
    gui.set_text(nodes.p_pos_text, tostring(new_you_pos or 0))
    gui.set_text(nodes.ai_pos_text, tostring(new_ai_pos or 0))
    gui.set_text(nodes.p_pill_text, "+0")
    gui.set_text(nodes.ai_pill_text, "+0")
end

-- Legacy entry point used by HUD_LANE_RESET handler; preserved for
-- backwards compat with the message vocabulary. Identical to
-- finalize_lane_reset for now.
function M.animate_lane_reset(slots_for_lane, nodes, new_you_pos, new_ai_pos)
    M.finalize_lane_reset(slots_for_lane, nodes, new_you_pos, new_ai_pos)
end

-- ---------------------------------------------------------------------------
-- Score burst
-- ---------------------------------------------------------------------------

function M.show_score_burst(burst_node, event_type, _points, side)
    local text = BURST_TEXT_BY_TYPE[event_type] or "SCORE!"
    local base_color = BURST_COLOR_BY_TYPE[event_type] or vmath.vector4(1, 1, 1, 1)
    -- Phase 6.5.4: LANE LOCKED uses the locker's color (green / red).
    if event_type == "lane_locked" then
        if side == "you" then
            base_color = vmath.vector4(0.3, 0.85, 0.4, 1)
        else
            base_color = vmath.vector4(0.95, 0.3, 0.3, 1)
        end
    end

    gui.set_enabled(burst_node, true)
    gui.set_text(burst_node, text)
    gui.set_scale(burst_node, vmath.vector3(BURST_SCALE_START, BURST_SCALE_START, 1))

    local start_color = vmath.vector4(base_color.x, base_color.y, base_color.z, 0)
    gui.set_color(burst_node, start_color)

    animate_helper.animate_gui(burst_node, "scale",
        vmath.vector3(BURST_SCALE_BASE, BURST_SCALE_BASE, 1),
        gui.EASING_OUTBACK, BURST_SCALE_IN)

    local full_color = vmath.vector4(base_color.x, base_color.y, base_color.z, 1)
    animate_helper.animate_gui(burst_node, "color",
        full_color, gui.EASING_OUTQUAD, BURST_FADE_IN, 0,
        function(_s)
            timer.delay(BURST_HOLD, false, function(_s2)
                local fade_color = vmath.vector4(base_color.x, base_color.y, base_color.z, 0)
                animate_helper.animate_gui(burst_node, "color",
                    fade_color, gui.EASING_INQUAD, BURST_FADE_OUT)
            end)
        end)
end

-- ---------------------------------------------------------------------------
-- Phase 6: lane modifier medallion + reveal animation
-- ---------------------------------------------------------------------------

-- Set the medallion's icon + name. `refs` is the cached medallion node
-- table for one lane: { root, icon, name }. Passing modifier=nil hides
-- the medallion (the .gui file has them disabled by default).
function M.render_modifier_medallion(refs, modifier)
    if not refs then return end
    if not modifier then
        if refs.icon then gui.set_enabled(refs.icon, false) end
        if refs.name then gui.set_enabled(refs.name, false) end
        return
    end
    if refs.icon then
        gui.set_enabled(refs.icon, true)
        gui.set_texture(refs.icon, "icons")
        gui.play_flipbook(refs.icon, hash("mod_" .. modifier.id))
    end
    if refs.name then
        gui.set_enabled(refs.name, true)
        gui.set_text(refs.name, modifier.name)
    end
end

local MODIFIER_TOAST_FADE_IN  = 0.2
local MODIFIER_TOAST_HOLD     = 1.5
local MODIFIER_TOAST_FADE_OUT = 0.3

-- Generic text toast reusing the modifier_toast nodes. Used for medallion
-- description popups, the "Not enough energy" invalid-drop feedback, and
-- (Phase 6.5) Coin Flip / Turnover / Sudden Death event messages.
-- `options` (optional): { duration = N, pulse = bool }.
function M.show_text_toast(refs, text, options)
    if not refs or not text then return end
    options = options or {}
    local hold_duration = options.duration or MODIFIER_TOAST_HOLD
    local do_pulse = options.pulse == true

    gui.set_text(refs.text, text)
    gui.set_enabled(refs.root, true)
    gui.set_color(refs.root, vmath.vector4(0.08, 0.08, 0.12, 0))
    gui.set_color(refs.text, vmath.vector4(1.0, 0.85, 0.2, 0))
    gui.set_scale(refs.root, vmath.vector3(1, 1, 1))

    animate_helper.animate_gui(refs.root, "color.w", 0.95,
        gui.EASING_OUTQUAD, MODIFIER_TOAST_FADE_IN)
    animate_helper.animate_gui(refs.text, "color.w", 1,
        gui.EASING_OUTQUAD, MODIFIER_TOAST_FADE_IN, 0,
        function(_s)
            if do_pulse then
                animate_helper.animate_gui(refs.root, gui.PROP_SCALE,
                    vmath.vector3(1.15, 1.15, 1),
                    gui.EASING_OUTBACK, 0.15, 0,
                    function(_s2)
                        animate_helper.animate_gui(refs.root, gui.PROP_SCALE,
                            vmath.vector3(1, 1, 1),
                            gui.EASING_INQUAD, 0.15)
                    end)
            end
            timer.delay(hold_duration, false, function(_s2)
                animate_helper.animate_gui(refs.root, "color.w", 0,
                    gui.EASING_INQUAD, MODIFIER_TOAST_FADE_OUT)
                animate_helper.animate_gui(refs.text, "color.w", 0,
                    gui.EASING_INQUAD, MODIFIER_TOAST_FADE_OUT, 0,
                    function(_s3)
                        gui.set_enabled(refs.root, false)
                    end)
            end)
        end)
end

-- Show the modifier description toast. `refs` is { root, text }.
function M.show_modifier_toast(refs, modifier)
    if not refs or not modifier then return end
    gui.set_text(refs.text, modifier.name .. "\n" .. modifier.desc)
    gui.set_enabled(refs.root, true)
    gui.set_color(refs.root, vmath.vector4(0.08, 0.08, 0.12, 0))
    gui.set_color(refs.text, vmath.vector4(1.0, 0.85, 0.2, 0))

    animate_helper.animate_gui(refs.root, "color.w", 0.95,
        gui.EASING_OUTQUAD, MODIFIER_TOAST_FADE_IN)
    animate_helper.animate_gui(refs.text, "color.w", 1,
        gui.EASING_OUTQUAD, MODIFIER_TOAST_FADE_IN, 0,
        function(_s)
            timer.delay(MODIFIER_TOAST_HOLD, false, function(_s2)
                animate_helper.animate_gui(refs.root, "color.w", 0,
                    gui.EASING_INQUAD, MODIFIER_TOAST_FADE_OUT)
                animate_helper.animate_gui(refs.text, "color.w", 0,
                    gui.EASING_INQUAD, MODIFIER_TOAST_FADE_OUT, 0,
                    function(_s3)
                        gui.set_enabled(refs.root, false)
                    end)
            end)
        end)
end

-- Phase 6.5.4: Sudden Death lane lock overlay + badge. `refs` is the
-- cached { overlay, badge } pair for one lane. Passing locked_for=nil
-- hides both; passing "you" / "ai" enables both with the appropriate
-- winner tint on the overlay box.
function M.render_lane_lock_state(refs, locked_for)
    if not refs then return end
    if locked_for == nil then
        if refs.overlay then gui.set_enabled(refs.overlay, false) end
        if refs.badge then gui.set_enabled(refs.badge, false) end
        return
    end
    if refs.overlay then
        gui.set_enabled(refs.overlay, true)
        if locked_for == "you" then
            gui.set_color(refs.overlay, vmath.vector4(0.2, 0.8, 0.3, 0.45))
        else
            gui.set_color(refs.overlay, vmath.vector4(0.85, 0.2, 0.2, 0.45))
        end
    end
    if refs.badge then
        gui.set_enabled(refs.badge, true)
    end
end

-- Phase 6.3 slot-machine reveal. `medallion_refs_by_lane` is a 0-indexed
-- table { [0] = {root, icon, name}, [1] = ..., [2] = ... } and
-- `chosen_modifiers` is 1-indexed { [1] = mod, [2] = mod, [3] = mod }
-- (matching match_state.get_modifiers()).
--
-- Reduced motion: skip the animation entirely and call on_complete on
-- the next frame so the caller's flow stays consistent.
function M.start_modifier_reveal(medallion_refs_by_lane, chosen_modifiers, on_complete)
    if animate_helper.is_reduced_motion() then
        for lane_idx = 0, 2 do
            M.render_modifier_medallion(medallion_refs_by_lane[lane_idx],
                chosen_modifiers[lane_idx + 1])
        end
        timer.delay(0.001, false, function()
            if on_complete then on_complete() end
        end)
        return
    end

    local pool = modifiers.POOL
    local cycle_interval = 0.062
    local cycle_count = 16

    local function set_random_for_lane(lane_idx)
        local refs = medallion_refs_by_lane[lane_idx]
        if not refs then return end
        local random_mod = pool[math.random(#pool)]
        if refs.icon then
            gui.set_enabled(refs.icon, true)
            gui.set_texture(refs.icon, "icons")
            gui.play_flipbook(refs.icon, hash("mod_" .. random_mod.id))
        end
        if refs.name then
            gui.set_enabled(refs.name, true)
            gui.set_text(refs.name, random_mod.name)
        end
    end

    -- Phase A: fast cycle. Each scheduled tick cycles all 3 lanes.
    for cycle = 1, cycle_count do
        timer.delay(cycle_interval * cycle, false, function()
            for lane_idx = 0, 2 do
                set_random_for_lane(lane_idx)
            end
        end)
    end

    -- Phase B: deceleration. 4 ticks at growing intervals summing ~0.5s.
    local decel_intervals = { 0.07, 0.10, 0.13, 0.20 }
    local accumulated = cycle_interval * cycle_count
    for _, interval in ipairs(decel_intervals) do
        accumulated = accumulated + interval
        timer.delay(accumulated, false, function()
            for lane_idx = 0, 2 do
                set_random_for_lane(lane_idx)
            end
        end)
    end

    -- Phase C: settle on final modifiers + scale pulse.
    local settle_time = accumulated + 0.05
    timer.delay(settle_time, false, function()
        for lane_idx = 0, 2 do
            local mod = chosen_modifiers[lane_idx + 1]
            local refs = medallion_refs_by_lane[lane_idx]
            M.render_modifier_medallion(refs, mod)
            if refs and refs.icon then
                animate_helper.animate_gui(refs.icon, gui.PROP_SCALE,
                    vmath.vector3(1.15, 1.15, 1),
                    gui.EASING_OUTQUAD, 0.1, 0,
                    function(_s)
                        animate_helper.animate_gui(refs.icon, gui.PROP_SCALE,
                            vmath.vector3(1, 1, 1),
                            gui.EASING_INQUAD, 0.1)
                    end)
            end
        end
        timer.delay(0.25, false, function()
            if on_complete then on_complete() end
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Pulses + badge bumps
-- ---------------------------------------------------------------------------

function M.pulse_score_node(node)
    animate_helper.animate_gui(node, gui.PROP_SCALE, SCORE_PULSE_SCALE,
        gui.EASING_OUTQUAD, 0.15, 0,
        function(_s)
            animate_helper.animate_gui(node, gui.PROP_SCALE, SCORE_BASE_SCALE,
                gui.EASING_INQUAD, 0.15)
        end)
end

function M.pulse_drive_node(node)
    animate_helper.animate_gui(node, gui.PROP_SCALE, DRIVE_PULSE_SCALE,
        gui.EASING_OUTQUAD, 0.125, 0,
        function(_s)
            animate_helper.animate_gui(node, gui.PROP_SCALE, DRIVE_BASE_SCALE,
                gui.EASING_INQUAD, 0.125)
        end)
end

function M.bump_badge(badge_node)
    animate_helper.animate_gui(badge_node, gui.PROP_SCALE, BADGE_BUMP_SCALE,
        gui.EASING_OUTQUAD, 0.11, 0,
        function(_s)
            animate_helper.animate_gui(badge_node, gui.PROP_SCALE, BADGE_BASE_SCALE,
                gui.EASING_INQUAD, 0.11)
        end)
end

-- ---------------------------------------------------------------------------
-- Carried toast + reshuffle visual
-- ---------------------------------------------------------------------------

function M.show_carried_toast(toast_node, base_pos, amount)
    if not amount or amount <= 0 then return end
    gui.set_text(toast_node, "+" .. tostring(amount) .. " CARRIED")
    gui.set_enabled(toast_node, true)
    gui.set_position(toast_node, base_pos)
    gui.set_color(toast_node, vmath.vector4(1, 0.85, 0.2, 0))

    local pos1 = vmath.vector3(base_pos.x, base_pos.y + TOAST_RISE_PHASE1, base_pos.z)
    animate_helper.animate_gui(toast_node, gui.PROP_POSITION, pos1,
        gui.EASING_OUTQUAD, TOAST_FADE_IN)
    animate_helper.animate_gui(toast_node, "color.w", 1,
        gui.EASING_OUTQUAD, TOAST_FADE_IN, 0,
        function(_s)
            timer.delay(TOAST_HOLD, false, function(_s2)
                local pos2 = vmath.vector3(base_pos.x, base_pos.y + TOAST_RISE_PHASE2, base_pos.z)
                animate_helper.animate_gui(toast_node, gui.PROP_POSITION, pos2,
                    gui.EASING_INQUAD, TOAST_FADE_OUT)
                animate_helper.animate_gui(toast_node, "color.w", 0,
                    gui.EASING_INQUAD, TOAST_FADE_OUT, 0,
                    function(_s3)
                        gui.set_position(toast_node, base_pos)
                        gui.set_enabled(toast_node, false)
                    end)
            end)
        end)
end

function M.show_reshuffle_visual(reshuffle_node, discard_badge_node)
    gui.set_enabled(reshuffle_node, true)
    gui.set_color(reshuffle_node, vmath.vector4(1, 0.85, 0.2, 0))

    animate_helper.animate_gui(reshuffle_node, "color.w", 1,
        gui.EASING_OUTQUAD, 0.3, 0,
        function(_s)
            timer.delay(0.4, false, function(_s2)
                animate_helper.animate_gui(reshuffle_node, "color.w", 0,
                    gui.EASING_INQUAD, 0.3, 0,
                    function(_s3)
                        gui.set_enabled(reshuffle_node, false)
                    end)
            end)
        end)
    M.bump_badge(discard_badge_node)
end

-- ---------------------------------------------------------------------------
-- Energy orb pulse loop
-- ---------------------------------------------------------------------------

local orb_pulse_step
orb_pulse_step = function(orb_node, orb_state)
    if not orb_state.active then
        gui.set_scale(orb_node, vmath.vector3(1, 1, 1))
        return
    end
    animate_helper.animate_gui(orb_node, gui.PROP_SCALE, ORB_PULSE_SCALE,
        gui.EASING_INOUTQUAD, 0.5, 0,
        function(_s)
            if not orb_state.active then return end
            animate_helper.animate_gui(orb_node, gui.PROP_SCALE,
                vmath.vector3(1, 1, 1),
                gui.EASING_INOUTQUAD, 0.5, 0,
                function(_s2)
                    if not orb_state.active then return end
                    orb_pulse_step(orb_node, orb_state)
                end)
        end)
end

function M.start_orb_pulse(orb_node, orb_state, reduced_motion)
    if orb_state.active then return end
    if reduced_motion then return end
    orb_state.active = true
    orb_pulse_step(orb_node, orb_state)
end

function M.stop_orb_pulse(orb_node, orb_state)
    orb_state.active = false
    gui.set_scale(orb_node, vmath.vector3(1, 1, 1))
end

-- ---------------------------------------------------------------------------
-- Discard / draw arc animations
-- ---------------------------------------------------------------------------

function M.handle_discard_anim(hand_nodes, current_hand, discard_badge_node)
    if not current_hand then return end
    local discard_pos = gui.get_position(discard_badge_node)

    for i = 1, 5 do
        local card = current_hand[i]
        if card and not card.empty then
            local node = hand_nodes[i].root
            local delay = (i - 1) * DISCARD_STAGGER
            animate_helper.animate_gui(node, gui.PROP_POSITION, discard_pos,
                gui.EASING_INQUAD, DISCARD_DURATION, delay)
            animate_helper.animate_gui(node, "rotation.z", 30,
                gui.EASING_INQUAD, DISCARD_DURATION, delay)
            animate_helper.animate_gui(node, gui.PROP_SCALE,
                vmath.vector3(0.4, 0.4, 1),
                gui.EASING_INQUAD, DISCARD_DURATION, delay)
            animate_helper.animate_gui(node, "color.w", 0,
                gui.EASING_INQUAD, DISCARD_DURATION, delay)
        end
    end
end

function M.handle_draw_anim(hand_nodes, drawn_cards, deck_badge_node, current_energy)
    local deck_pos = gui.get_position(deck_badge_node)
    drawn_cards = drawn_cards or {}

    for i = 1, 5 do
        local node = hand_nodes[i].root
        local card = drawn_cards[i]
        local target_pos = vmath.vector3(HAND_X_BY_INDEX[i], HAND_Y, 0)

        if card and not card.empty then
            gui.set_position(node, deck_pos)
            gui.set_rotation(node, vmath.vector3(0, 0, 0))
            gui.set_scale(node, vmath.vector3(0.4, 0.4, 1))
            gui.set_color(node, vmath.vector4(1, 1, 1, 0.35))
            M.render_hand_slot(hand_nodes[i], card, current_energy)

            local delay = (i - 1) * DRAW_STAGGER
            animate_helper.animate_gui(node, gui.PROP_POSITION, target_pos,
                gui.EASING_OUTQUAD, DRAW_DURATION, delay)
            animate_helper.animate_gui(node, gui.PROP_SCALE,
                vmath.vector3(1, 1, 1),
                gui.EASING_OUTQUAD, DRAW_DURATION, delay)
            animate_helper.animate_gui(node, "color.w", 1,
                gui.EASING_OUTQUAD, DRAW_DURATION, delay)
        else
            gui.set_position(node, target_pos)
            gui.set_rotation(node, vmath.vector3(0, 0, 0))
            gui.set_scale(node, vmath.vector3(1, 1, 1))
            gui.set_color(node, vmath.vector4(1, 1, 1, 1))
            M.render_hand_slot(hand_nodes[i], nil, current_energy)
        end
    end
end

return M
