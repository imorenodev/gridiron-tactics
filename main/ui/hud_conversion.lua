-- 2-pt conversion modal: state machine + coin flip animation.
-- Phase 5.5 extracted this from hud.gui_script. The module is pure-
-- functional: it stores no GUI state internally. Callers (hud.gui_script)
-- own the state object and the node-reference table, and pass them in
-- on every call. This keeps the module testable and lets the HUD reuse
-- the same modal scene across multiple matches without leakage.
--
-- State machine:
--   "hidden"   — modal not visible
--   "initial"  — "GO FOR 2?" choice between GO and KICK PAT
--   "calling"  — "CALL IT" choice between HEADS and TAILS
--   "flipping" — coin animating
--   "result"   — outcome shown, waiting for tap to dismiss
--
-- Result codes passed to the on_complete callback:
--   "skip"      — player chose KICK PAT, no conversion attempted
--   "converted" — coin landed on the player's call, +2 awarded
--   "failed"    — coin landed on the other face

local animate_helper = require("main.animation.animate_helper")
local msgs = require("main.state.messages")

local M = {}

local COIN_FLIP_DURATION = 1.4
local CONVERTED_COLOR = vmath.vector4(0.29, 1.0, 0.54, 1.0)
local FAILED_COLOR    = vmath.vector4(1.0,  0.42, 0.42, 1.0)

-- ---------------------------------------------------------------------------
-- State object
-- ---------------------------------------------------------------------------

function M.new()
    return {
        state = "hidden",
        context = nil,        -- { side, lane_idx } once a modal is shown
        player_call = nil,    -- "heads" | "tails"
        coin_result = nil,
        matched = nil,
    }
end

function M.is_visible(state)
    return state.state ~= "hidden"
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function set_state(state, nodes, new_state)
    state.state = new_state
    local n = nodes

    gui.set_enabled(n.go_for_2_btn, false)
    gui.set_enabled(n.kick_pat_btn, false)
    gui.set_enabled(n.heads_btn, false)
    gui.set_enabled(n.tails_btn, false)
    gui.set_enabled(n.coin, false)
    if n.coin_tails then gui.set_enabled(n.coin_tails, false) end
    gui.set_enabled(n.result_text, false)
    gui.set_enabled(n.result_hint, false)

    if new_state == "initial" then
        gui.set_text(n.title, "GO FOR 2?")
        gui.set_text(n.subtitle, "MORE OFF THAN THEIR DEF")
        gui.set_enabled(n.go_for_2_btn, true)
        gui.set_enabled(n.kick_pat_btn, true)
    elseif new_state == "calling" then
        gui.set_text(n.title, "CALL IT")
        gui.set_text(n.subtitle, "HEADS OR TAILS?")
        gui.set_enabled(n.heads_btn, true)
        gui.set_enabled(n.tails_btn, true)
    elseif new_state == "flipping" then
        gui.set_text(n.title, "FLIPPING...")
        gui.set_text(n.subtitle, "")
        gui.set_enabled(n.coin, true)
        if n.coin_tails then gui.set_enabled(n.coin_tails, true) end
    elseif new_state == "result" then
        gui.set_enabled(n.result_text, true)
        gui.set_enabled(n.result_hint, true)
    end
end

local function on_flip_complete(state, nodes)
    state.matched = (state.player_call == state.coin_result)
    set_state(state, nodes, "result")

    if state.matched then
        gui.set_text(nodes.result_text, "CONVERTED +2")
        gui.set_color(nodes.result_text, CONVERTED_COLOR)
    else
        gui.set_text(nodes.result_text, "NO GOOD")
        gui.set_color(nodes.result_text, FAILED_COLOR)
    end
end

local function start_coin_flip(state, nodes)
    -- Two synchronized sprite nodes. Heads sprite starts at 0°, tails at
    -- 180°. Both spin together; backface culling shows whichever is
    -- currently facing the camera.
    local heads_final = (state.coin_result == "heads") and 720 or 900
    local tails_final = heads_final + 180

    animate_helper.animate_gui(nodes.coin, "rotation.y", heads_final,
        gui.EASING_OUTQUAD, COIN_FLIP_DURATION, 0,
        function(_s) on_flip_complete(state, nodes) end)
    if nodes.coin_tails then
        animate_helper.animate_gui(nodes.coin_tails, "rotation.y", tails_final,
            gui.EASING_OUTQUAD, COIN_FLIP_DURATION, 0, nil)
    end
end

local function do_coin_call(state, nodes, call)
    state.player_call = call
    state.coin_result = (math.random() < 0.5) and "heads" or "tails"
    set_state(state, nodes, "flipping")
    start_coin_flip(state, nodes)
end

local function send_result(state, nodes, result, on_complete)
    local context = state.context
    if on_complete then
        on_complete({
            result = result,
            side = context.side,
            lane_idx = context.lane_idx,
            call = state.player_call,
            outcome = state.coin_result,
        })
    end
    M.hide(state, nodes)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.show(state, nodes, context)
    state.context = context
    state.player_call = nil
    state.coin_result = nil
    state.matched = nil

    gui.set_enabled(nodes.root, true)
    gui.set_text(nodes.coin_face, "")
    gui.set_rotation(nodes.coin, vmath.vector3(0, 0, 0))
    if nodes.coin_tails then
        gui.set_rotation(nodes.coin_tails, vmath.vector3(0, 180, 0))
    end
    set_state(state, nodes, "initial")
end

function M.hide(state, nodes)
    gui.set_enabled(nodes.root, false)
    state.state = "hidden"
end

-- Returns true if the tap was consumed (caller should NOT process other
-- input). `on_complete` is fired when the player completes the flow.
function M.handle_input(state, nodes, action, on_complete)
    if state.state == "hidden" then return false end
    if not action.released then return true end  -- consume during press too

    local s = state.state
    local n = nodes
    local x, y = action.x, action.y

    if s == "initial" then
        if gui.pick_node(n.go_for_2_btn, x, y) then
            set_state(state, nodes, "calling")
        elseif gui.pick_node(n.kick_pat_btn, x, y) then
            send_result(state, nodes, "skip", on_complete)
        end
        return true
    elseif s == "calling" then
        if gui.pick_node(n.heads_btn, x, y) then
            do_coin_call(state, nodes, "heads")
        elseif gui.pick_node(n.tails_btn, x, y) then
            do_coin_call(state, nodes, "tails")
        end
        return true
    elseif s == "flipping" then
        -- Lock input during the spin so a stray tap doesn't fast-forward.
        return true
    elseif s == "result" then
        local result = state.matched and "converted" or "failed"
        send_result(state, nodes, result, on_complete)
        return true
    end

    return false
end

return M
