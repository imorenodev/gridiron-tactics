-- In-match state. Module-local tables, no bare globals. Mutated via the
-- exported functions only. `shared_state = 1` in game.project means every
-- script that requires this module sees the same instance.
--
-- Phase 4 expanded: full deck cycle (30-card decks per side, discard,
-- reshuffle on empty) and 8-drive match. Drive 1 starts with 1 energy;
-- subsequent drives grant drive-number energy on top of carryover,
-- capped at MAX_ENERGY_BANK = 10. Cards played to the field are
-- consumed — they don't return to deck or discard; lane reset deletes
-- them. Cards in the unplayed hand at drive end go to discard.
--
-- consume_drive_cards() zeroes out cur_off/cur_def on cards remaining
-- in lanes between drives so they don't keep contributing to net yards
-- after their drive completes. Cards stay visible (for the lane cap and
-- visual continuity) but their offensive/defensive contribution is
-- spent.
--
-- Phase machine still owned by match.script.

local cards = require "main.data.cards"

math.randomseed(os.time())

local M = {}

local HAND_SIZE = 5
local LANE_COUNT = 3
local LANE_CARD_CAP = 8
local KICKOFF_POS = 25

-- Phase 4: per-drive energy escalation. Drive N grants N energy on top
-- of any unspent carryover from the previous drive. Capped at the bank.
local DRIVE1_ENERGY = 1
local MAX_ENERGY_BANK = 10
local DECK_SIZE = 30
local MAX_DRIVES = 8

local KICKOFF_BIG_RETURN_CHANCE = 0.05
local PICK6_DB_THRESHOLD = 4

-- Module-local state.
local drive = 1
local max_drives = MAX_DRIVES
local phase = "play"

local energy = 0
local hand = {}
local you_deck = {}
local you_discard = {}
local you_energy_carried = 0
local played_uids = {}

local ai_energy = 0
local ai_hand = {}
local ai_deck = {}
local ai_discard = {}
local ai_energy_carried = 0
local ai_played_uids = {}

local pending_plays = {}

local lanes = {}
local drive_summary = nil
local uid_counter = 0

local you_score = 0
local ai_score = 0
local score_events = {}
local pending_two_pt = nil

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

local function count_dbs_revealed(cards_arr)
    local n = 0
    for _, c in ipairs(cards_arr) do
        if c.revealed and (c.pos == "CB" or c.pos == "S") then
            n = n + 1
        end
    end
    return n
end

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
-- Ability dispatcher
-- ---------------------------------------------------------------------------

local function try_field_goal(card, lane_idx, side)
    if card.pos ~= "K" then return nil end
    local lane = lanes[lane_idx + 1]
    if not lane then return nil end
    local my_pos = (side == "you") and lane.you_pos or lane.ai_pos
    if my_pos < 50 then return nil end
    local event = { side = side, type = "fg", points = 3, lane_idx = lane_idx }
    M.apply_score_event(event)
    return event
end

function M.try_apply_snap_ability(card, lane_idx, side)
    if not card or not card.desc then return nil end

    if card.desc == "snapFieldGoal" then
        return try_field_goal(card, lane_idx, side)
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function M.reset()
    drive = 1
    max_drives = MAX_DRIVES
    phase = "play"

    energy = 0
    hand = {}
    you_deck = {}
    you_discard = {}
    you_energy_carried = 0
    played_uids = {}

    ai_energy = 0
    ai_hand = {}
    ai_deck = {}
    ai_discard = {}
    ai_energy_carried = 0
    ai_played_uids = {}

    pending_plays = {}
    lanes = {}
    drive_summary = nil
    you_score = 0
    ai_score = 0
    score_events = {}
    pending_two_pt = nil
end

-- Build a 30-card deck for `side` and seed `count` cards into its hand.
-- Used at match start. Subsequent draws use draw_cards_to_hand directly.
local function seed_side(side, hand_count)
    if side == "you" then
        you_deck = cards.build_deck(DECK_SIZE)
        you_discard = {}
        hand = {}
        for i = 1, HAND_SIZE do hand[i] = { empty = true } end
    else
        ai_deck = cards.build_deck(DECK_SIZE)
        ai_discard = {}
        ai_hand = {}
        for i = 1, HAND_SIZE do ai_hand[i] = { empty = true } end
    end
    M.draw_cards_to_hand(side, hand_count)
end

function M.new_match()
    M.reset()
    drive = 1
    phase = "play"
    energy = DRIVE1_ENERGY
    ai_energy = DRIVE1_ENERGY
    you_energy_carried = 0
    ai_energy_carried = 0

    seed_side("you", HAND_SIZE)
    seed_side("ai", HAND_SIZE)

    for i = 0, LANE_COUNT - 1 do
        lanes[i + 1] = make_lane(i)
    end
end

-- ---------------------------------------------------------------------------
-- Deck / discard / draw / reshuffle (Phase 4)
-- ---------------------------------------------------------------------------

-- Returns the active deck + discard + hand tables for the given side.
local function refs_for(side)
    if side == "you" then
        return you_deck, you_discard, hand
    end
    return ai_deck, ai_discard, ai_hand
end

-- Moves all cards from the side's discard into the deck (tagging each
-- with discarded_on_drive = nil), then Fisher-Yates shuffles.
function M.reshuffle_discard_into_deck(side)
    local deck, discard, _ = refs_for(side)
    while #discard > 0 do
        local card = table.remove(discard)
        card.discarded_on_drive = nil
        table.insert(deck, card)
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

-- Draws up to `count` cards from the side's deck into its hand. If the
-- deck runs out mid-draw, reshuffles the discard back into the deck
-- and continues. Returns { drawn = { card_records... }, reshuffled = bool }.
-- If both deck AND discard run dry, stops early.
function M.draw_cards_to_hand(side, count)
    local deck, discard, target_hand = refs_for(side)
    local drawn = {}
    local reshuffled = false

    for _ = 1, count do
        if #deck == 0 then
            if #discard == 0 then break end
            M.reshuffle_discard_into_deck(side)
            reshuffled = true
        end
        local card = table.remove(deck)
        card.uid = make_uid()
        card.revealed = false
        table.insert(drawn, card)

        for i = 1, HAND_SIZE do
            if not slot_is_filled(target_hand[i]) then
                target_hand[i] = card
                break
            end
        end
    end

    return { drawn = drawn, reshuffled = reshuffled }
end

-- Moves all of the side's remaining hand cards into discard, tagging each
-- with the current drive number, then leaves the hand fully empty.
function M.discard_hand(side)
    local _, discard, target_hand = refs_for(side)
    for i = 1, HAND_SIZE do
        if slot_is_filled(target_hand[i]) then
            local card = target_hand[i]
            card.discarded_on_drive = drive
            table.insert(discard, card)
            target_hand[i] = { empty = true }
        end
    end
end

-- Advances to the next drive: increments `drive`, grants drive-number
-- energy on top of any carryover (capped at MAX_ENERGY_BANK), records
-- the carried amount on both sides for the toast trigger. Returns the
-- per-side energy info so match.script can drive HUD updates.
function M.advance_drive()
    drive = drive + 1

    local you_carried = energy
    local you_gain = drive
    local you_new = math.min(MAX_ENERGY_BANK, energy + you_gain)
    energy = you_new
    you_energy_carried = you_carried

    local ai_carried = ai_energy
    local ai_gain = drive
    local ai_new = math.min(MAX_ENERGY_BANK, ai_energy + ai_gain)
    ai_energy = ai_new
    ai_energy_carried = ai_carried

    return {
        new_drive = drive,
        max_drives = max_drives,
        you_gain = you_gain,
        you_carried = you_carried,
        you_new_energy = you_new,
        ai_gain = ai_gain,
        ai_carried = ai_carried,
        ai_new_energy = ai_new,
    }
end

function M.is_match_over()
    return drive >= max_drives
end

function M.get_max_drives() return max_drives end
function M.get_deck_count(side)
    local deck, _, _ = refs_for(side)
    return #deck
end
function M.get_discard_count(side)
    local _, discard, _ = refs_for(side)
    return #discard
end
function M.get_you_energy_carried() return you_energy_carried end
function M.get_ai_energy_carried() return ai_energy_carried end

-- Per-drive count summary for the discard text modal. Returns
-- { total = N, per_drive = { [drive_num] = count, ... } }.
function M.get_discard_summary(side)
    local _, discard, _ = refs_for(side)
    local per_drive = {}
    for _, c in ipairs(discard) do
        local d = c.discarded_on_drive or 0
        per_drive[d] = (per_drive[d] or 0) + 1
    end
    return { total = #discard, per_drive = per_drive }
end

-- Zero out cur_off/cur_def on previously-revealed cards left in lanes
-- so they don't keep contributing yards in subsequent drives. Resets
-- per-side lane sums too so the HUD pills snap back to +0 for the next
-- drive. Ball positions (you_pos / ai_pos) stay — they're cumulative.
function M.consume_drive_cards()
    for i = 1, LANE_COUNT do
        local lane = lanes[i]
        if lane then
            for _, c in ipairs(lane.you_cards) do
                if c.revealed then
                    c.cur_off = 0
                    c.cur_def = 0
                end
            end
            for _, c in ipairs(lane.ai_cards) do
                if c.revealed then
                    c.cur_off = 0
                    c.cur_def = 0
                end
            end
            lane.you_off_sum = 0
            lane.you_def_sum = 0
            lane.ai_off_sum = 0
            lane.ai_def_sum = 0
            lane.you_net_yards = 0
            lane.ai_net_yards = 0
        end
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

function M.get_you_score() return you_score end
function M.get_ai_score() return ai_score end

function M.spend_energy(amount)
    if amount > energy then return false end
    energy = energy - amount
    return true
end

local function shallow_copy_card(c)
    local copy = {
        id = c.id, name = c.name, pos = c.pos,
        cost = c.cost, off = c.off, def = c.def,
        side = c.side, rarity = c.rarity, uid = c.uid,
    }
    if c.ability then copy.ability = c.ability end
    if c.desc then copy.desc = c.desc end
    return copy
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

function M.get_lanes_for_cpu()
    return lanes
end

-- ---------------------------------------------------------------------------
-- Plays
-- ---------------------------------------------------------------------------

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
        new_off_sum = 0,
        new_net_yards = 0,
    }
end

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

    return ordered
end

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

    local sums = recompute_lane_sums(play.lane_idx)
    return sums
end

function M.reveal_all_now()
    local ordered = M.reveal_pending_plays()
    local last_sums = {}
    for _, play in ipairs(ordered) do
        local s = M.reveal_single_play(play)
        if s then last_sums[play.lane_idx] = s end
    end
    return ordered, last_sums
end

function M.cancel_pending_plays_for_lane(lane_idx)
    local filtered = {}
    for _, p in ipairs(pending_plays) do
        if p.lane_idx ~= lane_idx then
            table.insert(filtered, p)
        end
    end
    pending_plays = filtered
end

-- ---------------------------------------------------------------------------
-- Resolve drive
-- ---------------------------------------------------------------------------

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
    drive_summary = summary
    pending_plays = {}
    return summary
end

function M.get_drive_summary() return drive_summary end

-- ---------------------------------------------------------------------------
-- Scoring (Phase 3)
-- ---------------------------------------------------------------------------

function M.kickoff_return()
    if math.random() < KICKOFF_BIG_RETURN_CHANCE then
        return math.random(40, 60)
    end
    return math.random(15, 35)
end

function M.apply_score_event(event)
    if event.side == "you" then
        you_score = you_score + (event.points or 0)
    else
        ai_score = ai_score + (event.points or 0)
    end
    table.insert(score_events, event)
end

function M.check_lane_for_scoring(lane_idx)
    local lane = lanes[lane_idx + 1]
    if not lane then return {} end

    local you_events = {}
    local ai_events = {}

    if lane.you_pos >= 100 then
        lane.you_pos = 100
        table.insert(you_events, { side = "you", type = "td", points = 6, lane_idx = lane_idx })
    end

    if lane.ai_pos <= 0 then
        lane.ai_pos = 0
        local db_count = count_dbs_revealed(lane.you_cards)
        if db_count >= 3 then
            print(string.format("[pick6 setup] lane=%d side=you db_count=%d safety_triggered=%s",
                lane_idx, db_count, tostring(true)))
        end
        if db_count >= PICK6_DB_THRESHOLD then
            table.insert(you_events, { side = "you", type = "pick6", points = 6, lane_idx = lane_idx })
        else
            table.insert(you_events, { side = "you", type = "safety", points = 2, lane_idx = lane_idx })
        end
    end

    if lane.ai_pos >= 100 then
        lane.ai_pos = 100
        table.insert(ai_events, { side = "ai", type = "td", points = 6, lane_idx = lane_idx })
    end

    if lane.you_pos <= 0 then
        lane.you_pos = 0
        local db_count = count_dbs_revealed(lane.ai_cards)
        if db_count >= 3 then
            print(string.format("[pick6 setup] lane=%d side=ai db_count=%d safety_triggered=%s",
                lane_idx, db_count, tostring(true)))
        end
        if db_count >= PICK6_DB_THRESHOLD then
            table.insert(ai_events, { side = "ai", type = "pick6", points = 6, lane_idx = lane_idx })
        else
            table.insert(ai_events, { side = "ai", type = "safety", points = 2, lane_idx = lane_idx })
        end
    end

    local events = {}
    for _, e in ipairs(you_events) do table.insert(events, e) end
    for _, e in ipairs(ai_events) do table.insert(events, e) end
    return events
end

function M.check_pat(side, lane_idx)
    local lane = lanes[lane_idx + 1]
    if not lane then return nil end
    local cards_arr = (side == "you") and lane.you_cards or lane.ai_cards
    for _, card in ipairs(cards_arr) do
        if card.pos == "K" and card.revealed then
            local event = { side = side, type = "pat", points = 1, lane_idx = lane_idx }
            M.apply_score_event(event)
            return event
        end
    end
    return nil
end

function M.check_two_pt_eligibility(side, lane_idx)
    local lane = lanes[lane_idx + 1]
    if not lane then return false end
    local scoring_cards = (side == "you") and lane.you_cards or lane.ai_cards
    local defender_cards = (side == "you") and lane.ai_cards or lane.you_cards

    local off_count = 0
    for _, c in ipairs(scoring_cards) do
        if c.revealed and c.side == "off" then
            off_count = off_count + 1
        end
    end
    local def_count = 0
    for _, c in ipairs(defender_cards) do
        if c.revealed and c.side == "def" then
            def_count = def_count + 1
        end
    end

    return off_count > def_count
end

function M.apply_two_pt_conversion(side, lane_idx, player_call, coin_result)
    local matched = (player_call == coin_result)
    print(string.format("[2pt attempt] side=%s lane=%d call=%s coin=%s matched=%s",
        tostring(side), lane_idx, tostring(player_call), tostring(coin_result), tostring(matched)))
    if matched then
        local event = { side = side, type = "2pt", points = 2, lane_idx = lane_idx }
        M.apply_score_event(event)
        return event
    end
    return nil
end

function M.reset_lane_after_score(lane_idx)
    local lane = lanes[lane_idx + 1]
    if not lane then return nil end
    lane.you_cards = {}
    lane.ai_cards = {}
    lane.you_off_sum = 0
    lane.you_def_sum = 0
    lane.you_net_yards = 0
    lane.ai_off_sum = 0
    lane.ai_def_sum = 0
    lane.ai_net_yards = 0
    lane.you_pos = M.kickoff_return()
    lane.ai_pos = M.kickoff_return()
    return { you_pos = lane.you_pos, ai_pos = lane.ai_pos }
end

return M
