-- Drag-from-hand-to-lane: try-start / update / end / cancel.
-- Phase 5.5 extracted this from hud.gui_script. Pure functional: state
-- is owned by hud.gui_script as `self.drag_state` and passed in on every
-- call. nil drag_state means no drag is active.
--
-- The lane drop-detection rectangles live here too because lane picking
-- is intrinsic to the drag flow. The HUD passes in node refs (ghost
-- node, hand-card root nodes, lane root nodes).

local animate_helper = require("main.animation.animate_helper")
local hud_render     = require("main.ui.hud_render")
local match_state    = require("main.state.match_state")
local msgs           = require("main.state.messages")

local M = {}

-- Ghost shrinks from hand-card size (180x280) to played-card size
-- (140x200) during the handoff animation in end_drag.
local GHOST_SHRINK_SCALE = vmath.vector3(140 / 180, 200 / 280, 1)
local GHOST_FADE_OUT_DURATION = 0.08

-- Visual constants — also referenced by render code via the HUD; kept
-- here as the source of truth for drag UX.
local CARD_DIMMED = vmath.vector4(0.4, 0.4, 0.4, 0.55)
local CARD_FULL   = vmath.vector4(1.0, 1.0, 1.0, 1.0)

-- Lane drop-zones in design-space coordinates. The drag's drop test
-- uses these rectangles directly rather than gui.pick_node on lane roots
-- so the player can drop into the lane "area" even past slot bounds.
local LANE_REGION_RECT = {
    [0] = { x0 = 10,  x1 = 380,  y0 = 800, y1 = 2200 },
    [1] = { x0 = 400, x1 = 770,  y0 = 800, y1 = 2200 },
    [2] = { x0 = 790, x1 = 1160, y0 = 800, y1 = 2200 },
}

local LANE_BASE_COLOR  = vmath.vector4(0.13, 0.32, 0.13, 1.0)
local LANE_HOVER_COLOR = vmath.vector4(0.25, 0.55, 0.25, 1.0)

-- Hand slot home positions for ghost snap-back. Hud caches these per-
-- slot and passes them in via the `hand_slots_home` map for flexibility.
-- This module's responsibility is just to read them.

-- ---------------------------------------------------------------------------
-- Picking
-- ---------------------------------------------------------------------------

local function point_in_rect(x, y, r)
    return x >= r.x0 and x <= r.x1 and y >= r.y0 and y <= r.y1
end

local function pick_lane_at(x, y)
    for i = 0, 2 do
        if point_in_rect(x, y, LANE_REGION_RECT[i]) then
            return i
        end
    end
    return nil
end
M.pick_lane_at = pick_lane_at

local function update_lane_hover(lane_root_nodes, hovered_idx)
    for i = 0, 2 do
        if lane_root_nodes[i] then
            if i == hovered_idx then
                gui.set_color(lane_root_nodes[i], LANE_HOVER_COLOR)
            else
                gui.set_color(lane_root_nodes[i], LANE_BASE_COLOR)
            end
        end
    end
end

local function clear_lane_hover(lane_root_nodes)
    update_lane_hover(lane_root_nodes, -1)
end

-- Phase 6: a card is draggable if ANY lane's effective_cost is within
-- the player's energy. The drop callback validates the specific lane.
local function affordable_anywhere(card, current_energy)
    if not card or card.empty then return false end
    for lane_idx = 0, 2 do
        if match_state.effective_cost(card, lane_idx) <= (current_energy or 0) then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Attempt to start a drag at (action.x, action.y). Returns a drag_state
-- table or nil. Caller stores the returned value as `self.drag_state`.
--
-- Args:
--   refs.hand_nodes        — array (1..5) of { root = ... } per hand slot
--   refs.ghost             — ghost root node
--   refs.ghost_text        — ghost text node
--   refs.current_hand      — array (1..5) of card data
--   refs.current_energy    — number
--   action                 — Defold input action
function M.try_start_drag(refs, action)
    local hand_nodes = refs.hand_nodes
    local current_hand = refs.current_hand or {}
    local current_energy = refs.current_energy or 0
    local x, y = action.x, action.y

    for i = 1, 5 do
        local slot = hand_nodes[i]
        if slot and gui.pick_node(slot.root, x, y) then
            local card = current_hand[i]
            -- Phase 6: drag if ANY lane's effective_cost is affordable.
            -- The drop validates against the chosen lane's exact cost.
            if affordable_anywhere(card, current_energy) then
                gui.set_enabled(refs.ghost, true)
                gui.set_position(refs.ghost, vmath.vector3(x, y, 0))
                gui.set_text(refs.ghost_text,
                    tostring(card.pos) .. " c" .. tostring(card.cost) ..
                    "\n" .. tostring(card.name))
                gui.set_color(slot.root, CARD_DIMMED)
                return {
                    card_uid = card.uid,
                    source_index = i,
                    card = card,
                }
            end
            return nil  -- card unaffordable even with the best discount
        end
    end
    return nil  -- no hand card under cursor
end

-- Called during drag (action.pressed = false, action.released = false).
-- Moves the ghost and updates lane hover highlight.
function M.update_drag(drag_state, refs, action)
    if not drag_state then return end
    gui.set_position(refs.ghost, vmath.vector3(action.x, action.y, 0))
    local hovered = pick_lane_at(action.x, action.y)
    update_lane_hover(refs.lane_root_nodes, hovered or -1)
end

-- Called on action.released while drag_state is active.
-- For a valid drop:
--   1. Fire on_drop(card_uid, lane_idx) immediately so match.script
--      can post MATCH_PLAY_CARD and the lane re-renders with the
--      newly-played slot starting at alpha 0.
--   2. Animate the ghost from cursor to stack target position over
--      hud_render.GHOST_TRAVEL_DURATION (300ms): position + shrink to
--      played-card size + rotation to match stack rotation.
--   3. In the last 80ms, cross-fade ghost alpha 1→0 while the spawned
--      slot fades 0→1 (via render_slot's was_empty branch).
--   4. Reset ghost transform when the fade completes so a fresh drag
--      starts clean.
-- For an invalid drop: ghost snaps back to the source hand slot.
function M.end_drag(drag_state, refs, action, target_stack_pos, on_drop)
    if not drag_state then return end

    local target_lane = pick_lane_at(action.x, action.y)
    clear_lane_hover(refs.lane_root_nodes)

    -- Phase 6.5.4: a Sudden-Death-locked lane rejects all drops.
    -- Checked first so the energy-toast doesn't fire on a locked lane.
    if target_lane ~= nil and match_state.is_lane_locked(target_lane) then
        if refs.on_invalid_drop then
            refs.on_invalid_drop("lane_locked")
        end
        target_lane = nil
    end

    -- Phase 6: validate against the specific lane's effective_cost.
    -- A drag may start on a card that's affordable in some lane but not
    -- in this one (cost discounts vary per lane).
    if target_lane ~= nil and drag_state.card then
        local cost = match_state.effective_cost(drag_state.card, target_lane)
        if cost > (refs.current_energy or 0) then
            if refs.on_invalid_drop then
                refs.on_invalid_drop("insufficient_energy")
            end
            target_lane = nil  -- fall through to snap-back path
        end
    end

    if target_lane ~= nil and on_drop and target_stack_pos then
        -- Drop is valid AND caller pre-computed the stack target.
        on_drop(drag_state.card_uid, target_lane)

        local travel = hud_render.GHOST_TRAVEL_DURATION
        local fade_out = GHOST_FADE_OUT_DURATION
        local target_rotation = vmath.vector3(0, 0, target_stack_pos.rotation_z)

        animate_helper.animate_gui(refs.ghost, gui.PROP_POSITION,
            target_stack_pos.position, gui.EASING_OUTQUAD, travel)
        animate_helper.animate_gui(refs.ghost, gui.PROP_SCALE,
            GHOST_SHRINK_SCALE, gui.EASING_OUTQUAD, travel)
        animate_helper.animate_gui(refs.ghost, gui.PROP_ROTATION,
            target_rotation, gui.EASING_OUTQUAD, travel)
        -- Fade out during the last `fade_out` seconds of the travel.
        animate_helper.animate_gui(refs.ghost, "color.w", 0,
            gui.EASING_INQUAD, fade_out, travel - fade_out,
            function(_s)
                gui.set_enabled(refs.ghost, false)
                gui.set_scale(refs.ghost, vmath.vector3(1, 1, 1))
                gui.set_rotation(refs.ghost, vmath.vector3(0, 0, 0))
                gui.set_color(refs.ghost, vmath.vector4(1, 1, 1, 1))
            end)
        return
    end

    if target_lane ~= nil and on_drop then
        -- Fallback for when caller didn't compute a target stack pos
        -- (shouldn't happen post-5.5.7; keeps the API forgiving).
        gui.set_enabled(refs.ghost, false)
        on_drop(drag_state.card_uid, target_lane)
        return
    end

    -- Snap ghost back, restore source slot opacity.
    local source_index = drag_state.source_index
    local home = refs.hand_slots_home and refs.hand_slots_home[source_index]
        or vmath.vector3(585, 550, 0)
    animate_helper.animate_gui(refs.ghost, gui.PROP_POSITION, home,
        gui.EASING_OUTQUAD, 0.2, 0,
        function(_s)
            gui.set_enabled(refs.ghost, false)
            local slot = refs.hand_nodes[source_index]
            local card = (refs.current_hand or {})[source_index]
            if slot and card and not card.empty then
                gui.set_color(slot.root, CARD_FULL)
            end
        end)
end

-- Force-cancel a drag (e.g., phase changed out from under the player).
function M.cancel_drag(drag_state, refs)
    if not drag_state then return end
    gui.set_enabled(refs.ghost, false)
    local slot = refs.hand_nodes[drag_state.source_index]
    local card = (refs.current_hand or {})[drag_state.source_index]
    if slot and card and not card.empty then
        gui.set_color(slot.root, CARD_FULL)
    end
    clear_lane_hover(refs.lane_root_nodes)
end

return M
