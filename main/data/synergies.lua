-- Phase 7: card synergies. Pure data + helpers — no Defold dependencies.
-- Caller (match_state.recompute_lane_sums) is responsible for filtering
-- input to revealed-and-not-ejected cards. Synergies mutate cur_off /
-- cur_def in place; the surrounding pipeline resets these from base
-- before each recompute so synergy deltas don't compound.
--
-- HTML parity: applySynergies runs PER SIDE (twice — once for you,
-- once for ai). Mixed-side arrays are not supported. The 13 synergies
-- are listed in HTML SYNERGIES order; detection truncation (badge
-- limit) and apply order both follow that ordering.
--
-- No-dedupe rule: a card matched by multiple synergies (e.g., a CB
-- matched by Zone D AND Secondary Support) stacks both buffs
-- additively. This is intentional HTML behavior.

local M = {}

-- ---------------------------------------------------------------------------
-- Small helpers (module-local)
-- ---------------------------------------------------------------------------

local function find_first(cards, pos)
    for _, c in ipairs(cards) do
        if c.pos == pos then return c end
    end
    return nil
end

local function find_first_with_cost(cards, pos, min_cost)
    for _, c in ipairs(cards) do
        if c.pos == pos and (c.cost or 0) >= min_cost then return c end
    end
    return nil
end

local function filter_pos(cards, pos)
    local out = {}
    for _, c in ipairs(cards) do
        if c.pos == pos then table.insert(out, c) end
    end
    return out
end

local function filter_pos_in(cards, pos_set)
    local out = {}
    for _, c in ipairs(cards) do
        if pos_set[c.pos] then table.insert(out, c) end
    end
    return out
end

local function count_pos(cards, pos)
    local n = 0
    for _, c in ipairs(cards) do
        if c.pos == pos then n = n + 1 end
    end
    return n
end

local function count_pos_in(cards, pos_set)
    local n = 0
    for _, c in ipairs(cards) do
        if pos_set[c.pos] then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Synergy descriptors (order matters: matches HTML SYNERGIES order)
-- ---------------------------------------------------------------------------
--
-- match(cards): returns an array of matched cards (truthy → apply) or
--               nil if the synergy is not active. Returning {} is NOT
--               supported as a "not matched" signal — only nil counts.
-- apply(matched): mutates cur_off / cur_def on the matched cards.
--                 Always called with the array returned by match.

M.synergies = {
    -- 1) PLAY ACTION — ≥1 QB AND ≥1 RB → first QB + first RB +12 OFF
    {
        id = "play_action",
        name = "PLAY ACTION",
        side = "off",
        match = function(cards)
            local qb = find_first(cards, "QB")
            local rb = find_first(cards, "RB")
            if qb and rb then return { qb, rb } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 12
            end
        end,
    },

    -- 2) SPREAD — ≥3 WR → all WRs +6 OFF each
    {
        id = "spread_offense",
        name = "SPREAD",
        side = "off",
        match = function(cards)
            local wrs = filter_pos(cards, "WR")
            if #wrs >= 3 then return wrs end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 6
            end
        end,
    },

    -- 3) POCKET — ≥1 QB AND ≥2 OL → first QB +15 OFF (OLs unchanged)
    {
        id = "protected_pocket",
        name = "POCKET",
        side = "off",
        match = function(cards)
            local qb = find_first(cards, "QB")
            local ol_count = count_pos(cards, "OL")
            if qb and ol_count >= 2 then return { qb } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 15
            end
        end,
    },

    -- 4) RED ZONE — ≥1 TE AND ≥1 QB → first TE + first QB +8 OFF each
    {
        id = "red_zone_threat",
        name = "RED ZONE",
        side = "off",
        match = function(cards)
            local te = find_first(cards, "TE")
            local qb = find_first(cards, "QB")
            if te and qb then return { te, qb } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 8
            end
        end,
    },

    -- 5) WILDCAT — ≥2 RB → all RBs +10 OFF each
    {
        id = "wildcat",
        name = "WILDCAT",
        side = "off",
        match = function(cards)
            local rbs = filter_pos(cards, "RB")
            if #rbs >= 2 then return rbs end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 10
            end
        end,
    },

    -- 6) TRICK PLAY — ≥1 WR AND ≥1 RB AND ≥1 TE → first of each +5 OFF
    {
        id = "trick_play",
        name = "TRICK PLAY",
        side = "off",
        match = function(cards)
            local wr = find_first(cards, "WR")
            local rb = find_first(cards, "RB")
            local te = find_first(cards, "TE")
            if wr and rb and te then return { wr, rb, te } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 5
            end
        end,
    },

    -- 7) FIELD GEN — QB w/ cost ≥5 AND ≥2 (WR or TE) → that QB +15 OFF
    {
        id = "field_general",
        name = "FIELD GEN",
        side = "off",
        match = function(cards)
            local qb = find_first_with_cost(cards, "QB", 5)
            if not qb then return nil end
            local receivers = count_pos_in(cards, { WR = true, TE = true })
            if receivers >= 2 then return { qb } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 15
            end
        end,
    },

    -- 8) ZONE D — ≥2 CB → all CBs +5 DEF each
    {
        id = "zone_defense",
        name = "ZONE D",
        side = "def",
        match = function(cards)
            local cbs = filter_pos(cards, "CB")
            if #cbs >= 2 then return cbs end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_def = (c.cur_def or 0) + 5
            end
        end,
    },

    -- 9) STRONG SAFETY — ≥1 S AND ≥1 LB → first S + first LB +6 DEF each
    {
        id = "strong_safety",
        name = "STRONG SAFETY",
        side = "def",
        match = function(cards)
            local s = find_first(cards, "S")
            local lb = find_first(cards, "LB")
            if s and lb then return { s, lb } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_def = (c.cur_def or 0) + 6
            end
        end,
    },

    -- 10) STACKED FRONT — ≥3 (DE or DT) → all matched DL +8 DEF each
    {
        id = "stacked_front",
        name = "STACKED FRONT",
        side = "def",
        match = function(cards)
            local dl = filter_pos_in(cards, { DE = true, DT = true })
            if #dl >= 3 then return dl end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_def = (c.cur_def or 0) + 8
            end
        end,
    },

    -- 11) BLITZ — ≥1 LB AND ≥1 DE → first LB + first DE +7 DEF each
    {
        id = "blitz_package",
        name = "BLITZ",
        side = "def",
        match = function(cards)
            local lb = find_first(cards, "LB")
            local de = find_first(cards, "DE")
            if lb and de then return { lb, de } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_def = (c.cur_def or 0) + 7
            end
        end,
    },

    -- 12) SECONDARY — ≥2 CB AND ≥1 S → all matched CBs + Ss +5 DEF each
    -- Overlaps with ZONE D intentionally; CBs stack both buffs (+10 total).
    {
        id = "secondary_support",
        name = "SECONDARY",
        side = "def",
        match = function(cards)
            local cbs = filter_pos(cards, "CB")
            local ss = filter_pos(cards, "S")
            if #cbs >= 2 and #ss >= 1 then
                local out = {}
                for _, c in ipairs(cbs) do table.insert(out, c) end
                for _, c in ipairs(ss) do table.insert(out, c) end
                return out
            end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_def = (c.cur_def or 0) + 5
            end
        end,
    },

    -- 13) KICKING UNIT — ≥1 K AND ≥1 ST → first K +5 OFF.
    -- The FG-range lowering (50+ → 35+) is handled in match_state's
    -- try_field_goal via M.has_kicking_unit; nothing to mutate here for
    -- that side of the effect.
    {
        id = "kicking_unit",
        name = "KICKING UNIT",
        side = "st",
        match = function(cards)
            local k = find_first(cards, "K")
            local st = find_first(cards, "ST")
            if k and st then return { k } end
            return nil
        end,
        apply = function(matched)
            for _, c in ipairs(matched) do
                c.cur_off = (c.cur_off or 0) + 5
            end
        end,
    },
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Returns an array of synergy descriptors whose match returned non-nil
-- for the given card list. `cards` MUST already be filtered to
-- revealed-and-not-ejected (caller's responsibility). Result preserves
-- HTML SYNERGIES order so callers can safely truncate to N badges.
function M.detect(cards)
    local active = {}
    for _, syn in ipairs(M.synergies) do
        if syn.match(cards) ~= nil then
            table.insert(active, syn)
        end
    end
    return active
end

-- Walks M.synergies, calls each match, and on truthy result invokes the
-- descriptor's apply on the matched list. Mutates cur_off / cur_def in
-- place. `cards` MUST already be filtered to revealed-and-not-ejected.
function M.apply(cards)
    for _, syn in ipairs(M.synergies) do
        local matched = syn.match(cards)
        if matched ~= nil then
            syn.apply(matched)
        end
    end
end

-- Single-pass scan over a raw same-side card list (NOT pre-filtered) for
-- a revealed, non-ejected ST. Used by try_field_goal to determine
-- whether the Kicking Unit synergy lowers the FG threshold from 50+ to
-- 35+. The K's own presence is implicit at the call site (this is
-- consulted because the K is firing its Clutch Kicker ability).
function M.has_kicking_unit(side_cards)
    if not side_cards then return false end
    for _, c in ipairs(side_cards) do
        if c.pos == "ST" and c.revealed and not c.ejected then
            return true
        end
    end
    return false
end

return M
