-- In-match state. Module-local tables, no bare globals. Mutated via the
-- exported functions only. `shared_state = 1` in game.project means every
-- script that requires this module sees the same instance.
--
-- Phase 2 scope: one drive, AI plays at END DRIVE, cards play face-down,
-- reveal at END DRIVE flips revealed = true and recomputes lane sums.
-- Net yards formula (per side) only counts revealed cards:
--   you_net_yards = floor(you_off_sum / 2.5) - floor(ai_def_sum / 2.5)
--   ai_net_yards  = floor(ai_off_sum  / 2.5) - floor(you_def_sum / 2.5)
-- Scoring is deferred to Phase 3; you_score / ai_score stay 0 here, but
-- are used by reveal_pending_plays() to compute the reveal order so the
-- comparison works once real scores land.

local cards = require "main.data.cards"

math.randomseed(os.time())

local M = {}

local HAND_SIZE = 5
local LANE_COUNT = 3
local LANE_CARD_CAP = 8
local KICKOFF_POS = 25
local STARTING_ENERGY = 12

-- Module-local state (initialized by reset()/new_match()).
local drive = 1
local phase = "play"
local energy = 0
local hand = {}
local played_uids = {}

local ai_hand = {}
local ai_energy = 0
local ai_played_uids = {}

-- pending_plays: array of { card_uid, lane_idx, side = "you" | "ai", slot_idx }
-- Populated as cards are played face-down; consumed in reveal order at END DRIVE.
local pending_plays = {}

local lanes = {}
local drive_summary = nil
local uid_counter = 0

-- Score isn't tracked in Phase 2 (scoring lands in Phase 3) but the reveal-
-- order comparison uses these so the code path is right when they go live.
local you_score = 0
local ai_score = 0

-- ---------------------------------------------------------------------------
-- Helpers (module-local)
-- ---------------------------------------------------------------------------

local function make_uid()
    uid_counter = uid_counter + 1
    return string.format("u%d_%d", uid_counter, math.random(0, 999999))
end

local function make_lane(idx)
    return {
        idx = idx,
        you_pos = KICKOFF_POS,
        ai_pos = KICKOFF_POS,
        you_cards = {},
        ai_cards = {},
        you_off_sum = 0,
        you_def_sum = 0,
        you_net_yards = 0,
        ai_off_sum = 0,
        ai_def_sum = 0,
        ai_net_yards = 0,
    }
end

local function compute_net(off_sum, opp_def_sum)
    return math.floor(off_sum / 2.5) - math.floor(opp_def_sum / 2.5)
end

local function slot_is_filled(slot)
    return slot ~= nil and not slot.empty
end

local function find_in_hand(h, uid)
    for i, slot in ipairs(h) do
        if slot_is_filled(slot) and slot.uid == uid then
            return i
        end
    end
    return nil
end

-- Phase 2 stub: invoked at reveal time for each card. Card abilities (SNAP /
-- on-reveal / on-played) plug in here in a later phase. Intentionally a no-op
-- so the reveal path is in place and exercised, but no behavior runs.
local function try_apply_snap_ability(_card)
    -- TODO Phase TBD: implement card snap abilities here.
end

-- Recompute revealed-only sums for one lane, then derive net yards per side.
-- Called after each reveal so progressive pill updates work.
local function recompute_lane_sums(lane_idx)
    local lane = lanes[lane_idx + 1]
    if not lane then return nil end

    local you_off, you_def = 0, 0
    for _, c in ipairs(lane.you_cards) do
        if c.revealed then
            you_off = you_off + (c.cur_off or c.off or 0)
            you_def = you_def + (c.cur_def or c.def or 0)
        end
    end
    local ai_off, ai_def = 0, 0
    for _, c in ipairs(lane.ai_cards) do
        if c.revealed then
            ai_off = ai_off + (c.cur_off or c.off or 0)
            ai_def = ai_def + (c.cur_def or c.def or 0)
        end
    end

    lane.you_off_sum = you_off
    lane.you_def_sum = you_def
    lane.ai_off_sum = ai_off
    lane.ai_def_sum = ai_def
    lane.you_net_yards = compute_net(you_off, ai_def)
    lane.ai_net_yards = compute_net(ai_off, you_def)

    return {
        lane_idx = lane_idx,
        you_off_sum = you_off,
        you_def_sum = you_def,
        ai_off_sum = ai_off,
        ai_def_sum = ai_def,
        you_net_yards = lane.you_net_yards,
        ai_net_yards = lane.ai_net_yards,
    }
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function M.reset()
    drive = 1
    phase = "play"
    energy = 0
    hand = {}
    played_uids = {}
    ai_hand = {}
    ai_energy = 0
    ai_played_uids = {}
    pending_plays = {}
    lanes = {}
    drive_summary = nil
    you_score = 0
    ai_score = 0
end

function M.new_match()
    M.reset()
    energy = STARTING_ENERGY
    ai_energy = STARTING_ENERGY
    drive = 1
    phase = "play"

    local dealt = cards.random_hand(HAND_SIZE)
    for i = 1, HAND_SIZE do
        local c = dealt[i]
        c.uid = make_uid()
        hand[i] = c
    end

    local ai_dealt = cards.random_hand(HAND_SIZE)
    for i = 1, HAND_SIZE do
        local c = ai_dealt[i]
        c.uid = make_uid()
        ai_hand[i] = c
    end

    for i = 0, LANE_COUNT - 1 do
        lanes[i + 1] = make_lane(i)
    end
end

-- ---------------------------------------------------------------------------
-- Read-only accessors
-- ---------------------------------------------------------------------------

function M.get_drive() return drive end
function M.get_phase() return phase end
function M.set_phase(p) phase = p end

function M.get_energy() return energy end
function M.get_ai_energy() return ai_energy end

function M.spend_energy(amount)
    if amount > energy then return false end
    energy = energy - amount
    return true
end

local function shallow_copy_card(c)
    return {
        id = c.id, name = c.name, pos = c.pos,
        cost = c.cost, off = c.off, def = c.def,
        side = c.side, rarity = c.rarity, uid = c.uid,
    }
end

function M.get_hand()
    local copy = {}
    for i = 1, HAND_SIZE do
        local slot = hand[i]
        if slot_is_filled(slot) then
            copy[i] = shallow_copy_card(slot)
        else
            copy[i] = { empty = true }
        end
    end
    return copy
end

-- AI hand copy. The HUD never renders this, but cpu.lua reads it.
function M.get_ai_hand()
    local copy = {}
    for i = 1, HAND_SIZE do
        local slot = ai_hand[i]
        if slot_is_filled(slot) then
            copy[i] = shallow_copy_card(slot)
        else
            copy[i] = { empty = true }
        end
    end
    return copy
end

function M.get_lane(idx) return lanes[idx + 1] end
function M.get_lane_count() return LANE_COUNT end
function M.get_hand_size() return HAND_SIZE end

-- Shallow-copy the lane state the HUD needs to render a lane.  Cards are
-- copies (with revealed flag intact) so the HUD never sees the live tables.
local function lane_render_copy(lane_idx)
    local lane = lanes[lane_idx + 1]
    if not lane then return nil end

    local function copy_cards(arr)
        local out = {}
        for i, c in ipairs(arr) do
            out[i] = {
                id = c.id, name = c.name, pos = c.pos,
                cost = c.cost, off = c.off, def = c.def,
                side = c.side, rarity = c.rarity, uid = c.uid,
                revealed = c.revealed and true or false,
                cur_off = c.cur_off, cur_def = c.cur_def,
            }
        end
        return out
    end

    return {
        lane_idx = lane_idx,
        you_pos = lane.you_pos,
        ai_pos = lane.ai_pos,
        you_net_yards = lane.you_net_yards,
        ai_net_yards = lane.ai_net_yards,
        you_off_sum = lane.you_off_sum,
        you_def_sum = lane.you_def_sum,
        ai_off_sum = lane.ai_off_sum,
        ai_def_sum = lane.ai_def_sum,
        you_cards = copy_cards(lane.you_cards),
        ai_cards = copy_cards(lane.ai_cards),
    }
end

M.lane_render_copy = lane_render_copy

-- cpu.lua wants 1-indexed lane access with the public lane shape. Return the
-- internal lanes array reference; cpu reads only.
function M.get_lanes_for_cpu()
    return lanes
end

-- ---------------------------------------------------------------------------
-- Plays
-- ---------------------------------------------------------------------------

-- Player plays a card. Phase 2 behavior: card goes face-down into the lane,
-- energy deducts, hand slot empties, sums STAY AT 0 (revealed only). The
-- HUD's net-yards pill stays at +0 until END DRIVE reveal.
function M.play_card(card_uid, lane_idx)
    local slot_idx = find_in_hand(hand, card_uid)
    if slot_idx == nil then
        return { success = false, reason = "card_not_in_hand" }
    end
    local card = hand[slot_idx]
    if energy < card.cost then
        return { success = false, reason = "insufficient_energy" }
    end
    local lane = lanes[lane_idx + 1]
    if lane == nil then
        return { success = false, reason = "invalid_lane" }
    end
    if #lane.you_cards >= LANE_CARD_CAP then
        return { success = false, reason = "lane_full" }
    end

    energy = energy - card.cost
    hand[slot_idx] = { empty = true }
    played_uids[card_uid] = true

    card.revealed = false
    table.insert(lane.you_cards, card)
    local placed_slot_idx = #lane.you_cards - 1

    table.insert(pending_plays, {
        card_uid = card_uid,
        lane_idx = lane_idx,
        side = "you",
        slot_idx = placed_slot_idx,
    })

    return {
        success = true,
        card = card,
        slot_idx = placed_slot_idx,
        new_energy = energy,
        -- Sums intentionally still 0 here — cards are face-down.
        new_off_sum = 0,
        new_net_yards = 0,
    }
end

-- AI plays a card directly (skips the hand-find step since cpu.lua hands the
-- card object straight in). Mirrors play_card behavior — face-down, sums
-- unchanged, energy deducted.
function M.ai_play_card(card, lane_idx)
    if ai_energy < (card.cost or 0) then
        return { success = false, reason = "insufficient_energy" }
    end
    local lane = lanes[lane_idx + 1]
    if lane == nil then
        return { success = false, reason = "invalid_lane" }
    end
    if #lane.ai_cards >= LANE_CARD_CAP then
        return { success = false, reason = "lane_full" }
    end

    -- Mirror find_in_hand: locate this card by uid in ai_hand and empty its slot.
    local slot_in_hand = find_in_hand(ai_hand, card.uid)
    if slot_in_hand then
        ai_hand[slot_in_hand] = { empty = true }
    end
    ai_energy = ai_energy - card.cost
    ai_played_uids[card.uid] = true

    card.revealed = false
    table.insert(lane.ai_cards, card)
    local placed_slot_idx = #lane.ai_cards - 1

    table.insert(pending_plays, {
        card_uid = card.uid,
        lane_idx = lane_idx,
        side = "ai",
        slot_idx = placed_slot_idx,
    })

    return {
        success = true,
        card = card,
        slot_idx = placed_slot_idx,
        new_ai_energy = ai_energy,
    }
end

-- ---------------------------------------------------------------------------
-- Reveal
-- ---------------------------------------------------------------------------

-- Determine reveal order. "Winner reveals first" — if scores are tied
-- (Phase 2 always: 0-0), defaults to player-first.
function M.reveal_pending_plays()
    local player_first = (you_score >= ai_score)

    local ordered = {}
    local function add_side(side)
        for _, p in ipairs(pending_plays) do
            if p.side == side then
                table.insert(ordered, p)
            end
        end
    end

    if player_first then
        add_side("you")
        add_side("ai")
    else
        add_side("ai")
        add_side("you")
    end

    -- Caller walks `ordered` and calls reveal_single_play per entry; we keep
    -- pending_plays around in case the caller wants to re-query. It's
    -- cleared by resolve_drive() so a fresh new_match() starts empty.
    return ordered
end

-- Flip one specific play face-up, run its (no-op for now) ability hook,
-- recompute its lane's sums, and return the updated lane sums so the caller
-- can push the new numbers to the HUD.
function M.reveal_single_play(play)
    local lane = lanes[play.lane_idx + 1]
    if not lane then return nil end

    local arr = (play.side == "ai") and lane.ai_cards or lane.you_cards
    local card = arr[play.slot_idx + 1]
    if not card then return nil end

    card.revealed = true
    card._base_off = card.off
    card._base_def = card.def
    card.cur_off = card.off
    card.cur_def = card.def

    try_apply_snap_ability(card)

    local sums = recompute_lane_sums(play.lane_idx)
    return sums
end

-- Convenience: used by sub-phase 2.2 (and any caller that wants an immediate
-- full reveal without animation). Walks reveal_pending_plays in order and
-- flips them all. Returns the per-lane sums after the full reveal.
function M.reveal_all_now()
    local ordered = M.reveal_pending_plays()
    local last_sums = {}
    for _, play in ipairs(ordered) do
        local s = M.reveal_single_play(play)
        if s then last_sums[play.lane_idx] = s end
    end
    return ordered, last_sums
end

-- ---------------------------------------------------------------------------
-- Resolve drive
-- ---------------------------------------------------------------------------

-- Advance each lane's two ball positions by their (already-computed) net
-- yards, clamp 0..100, mark the drive ended, and return a summary.
function M.resolve_drive()
    local summary = { lanes = {} }
    for i = 0, LANE_COUNT - 1 do
        local lane = lanes[i + 1]
        local you_gained = lane.you_net_yards
        local ai_gained = lane.ai_net_yards

        local new_you = lane.you_pos + you_gained
        if new_you > 100 then new_you = 100 end
        if new_you < 0 then new_you = 0 end
        lane.you_pos = new_you

        local new_ai = lane.ai_pos + ai_gained
        if new_ai > 100 then new_ai = 100 end
        if new_ai < 0 then new_ai = 0 end
        lane.ai_pos = new_ai

        table.insert(summary.lanes, {
            idx = i,
            you_yards_gained = you_gained,
            ai_yards_gained = ai_gained,
            new_you_pos = new_you,
            new_ai_pos = new_ai,
        })
    end
    phase = "ended"
    drive_summary = summary
    pending_plays = {}
    return summary
end

function M.get_drive_summary() return drive_summary end

return M
