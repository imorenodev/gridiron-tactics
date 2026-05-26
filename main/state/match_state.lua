-- In-match state. Module-local tables, no bare globals. Mutated via the
-- exported functions only. `shared_state = 1` in game.project means every
-- script that requires this module sees the same instance, so this is the
-- canonical "what's happening in the current match" store.
--
-- Phase 1 scope: one drive, no AI, no scoring. Net yards formula is
-- floor(you_off_sum / 2.5) because theirLaneDEF is always 0 in Phase 1.

local cards = require "main.data.cards"

-- Seed the global RNG once per process. Modules under shared_state load
-- exactly once, so consecutive matches within a single launch keep walking
-- the same stream (different hands) and separate launches start from a
-- different point. Without this, hands would repeat across launches.
math.randomseed(os.time())

local M = {}

local HAND_SIZE = 5
local LANE_COUNT = 3
local LANE_CARD_CAP = 8
local KICKOFF_POS = 25
local STARTING_ENERGY = 12  -- Phase 1 override: flat 12. Real game uses drive-scaled energy.

-- Module-local state (initialized by reset()/new_match()).
local drive = 1
local phase = "play"
local energy = 0
local hand = {}              -- array of HAND_SIZE entries; played slots become { empty = true }
local played_uids = {}       -- set keyed by uid string
local lanes = {}             -- array of LANE_COUNT lane records
local drive_summary = nil
local uid_counter = 0

local function make_uid()
    uid_counter = uid_counter + 1
    return string.format("u%d_%d", uid_counter, math.random(0, 999999))
end

local function make_lane(idx)
    return {
        idx = idx,
        you_pos = KICKOFF_POS,
        you_cards = {},          -- array of card records that have been played here
        you_off_sum = 0,
        you_net_yards = 0,
    }
end

local function compute_net_yards(off_sum)
    return math.floor(off_sum / 2.5)
end

local function slot_is_filled(slot)
    return slot ~= nil and not slot.empty
end

-- Find a hand slot index by uid. Returns nil if not in hand or empty.
local function find_hand_slot(uid)
    for i, slot in ipairs(hand) do
        if slot_is_filled(slot) and slot.uid == uid then
            return i
        end
    end
    return nil
end

function M.reset()
    drive = 1
    phase = "play"
    energy = 0
    hand = {}
    played_uids = {}
    lanes = {}
    drive_summary = nil
end

function M.new_match()
    M.reset()
    energy = STARTING_ENERGY
    drive = 1
    phase = "play"

    local dealt = cards.random_hand(HAND_SIZE)
    hand = {}
    for i = 1, HAND_SIZE do
        local c = dealt[i]
        c.uid = make_uid()
        hand[i] = c
    end

    for i = 0, LANE_COUNT - 1 do
        lanes[i + 1] = make_lane(i)
    end
end

function M.get_drive() return drive end
function M.get_phase() return phase end

function M.set_phase(p)
    phase = p
end

function M.get_energy() return energy end

function M.spend_energy(amount)
    if amount > energy then return false end
    energy = energy - amount
    return true
end

-- Shallow-copy the hand so callers can iterate / send via msg.post without
-- holding a reference into our internal table.
function M.get_hand()
    local copy = {}
    for i = 1, HAND_SIZE do
        local slot = hand[i]
        if slot_is_filled(slot) then
            copy[i] = {
                id = slot.id, name = slot.name, pos = slot.pos,
                cost = slot.cost, off = slot.off, def = slot.def,
                side = slot.side, rarity = slot.rarity, uid = slot.uid,
            }
        else
            copy[i] = { empty = true }
        end
    end
    return copy
end

function M.get_lane(idx)
    -- lanes are 1-indexed internally but exposed as idx 0/1/2 to match the
    -- HUD/Defold convention from Phase 0's prompt.
    return lanes[idx + 1]
end

function M.get_lane_count() return LANE_COUNT end
function M.get_hand_size() return HAND_SIZE end

-- Attempt to play a card from hand into a lane. Returns a result table; the
-- caller (match.script) drives the HUD/factory updates from this.
function M.play_card(card_uid, lane_idx)
    local slot_idx = find_hand_slot(card_uid)
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

    -- Commit: deduct energy, remove from hand, append to lane, recompute lane.
    energy = energy - card.cost
    hand[slot_idx] = { empty = true }
    played_uids[card_uid] = true

    table.insert(lane.you_cards, card)
    lane.you_off_sum = lane.you_off_sum + (card.off or 0)
    lane.you_net_yards = compute_net_yards(lane.you_off_sum)

    return {
        success = true,
        card = card,
        slot_idx = #lane.you_cards - 1,  -- 0-based for the factory call
        new_energy = energy,
        new_off_sum = lane.you_off_sum,
        new_net_yards = lane.you_net_yards,
        you_cards_count = #lane.you_cards,
    }
end

-- Advance each lane's ball by its net yards, clamp 0..100, mark the drive
-- ended, and return a per-lane summary.
function M.resolve_drive()
    local summary = { lanes = {} }
    for i = 0, LANE_COUNT - 1 do
        local lane = lanes[i + 1]
        local gained = lane.you_net_yards
        local new_pos = lane.you_pos + gained
        if new_pos > 100 then new_pos = 100 end
        if new_pos < 0 then new_pos = 0 end
        lane.you_pos = new_pos
        table.insert(summary.lanes, {
            idx = i,
            yards_gained = gained,
            new_pos = new_pos,
        })
    end
    phase = "ended"
    drive_summary = summary
    return summary
end

function M.get_drive_summary() return drive_summary end

return M
