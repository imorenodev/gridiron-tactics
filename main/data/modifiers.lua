-- Phase 6: lane modifier pool. Pure data + draw helper. 16 modifiers
-- (Tier 1 stat changes + Tier 2 cost/reveal). The 4 Tier 3 mechanical
-- modifiers (frozenTundra, coinFlip, turnover, suddenDeath) are
-- deferred to Phase 6.5 and intentionally NOT listed here yet.
--
-- Each record:
--   id        — stable string key, also used as the icons.atlas sprite
--               name as "mod_<id>" (e.g. "mod_homeTurf").
--   icon      — emoji fallback (used in toast text alongside the sprite).
--   name      — uppercase display name shown on the medallion.
--   desc      — full toast description.
--   category  — loose grouping for future filtering (not used in 6.x).

local M = {}

M.POOL = {
    -- Tier 1 (stat modifiers)
    { id = "homeTurf",    icon = "HOME", name = "HOME TURF",
      desc = "Your OFF cards +5, enemy OFF cards -5",
      category = "field" },
    { id = "muddyField",  icon = "MUD",  name = "MUDDY FIELD",
      desc = "All OFF cards -25%, all DEF cards +25%",
      category = "field" },
    { id = "windTunnel",  icon = "WIND", name = "WIND TUNNEL",
      desc = "QB and WR OFF -5",
      category = "field" },
    { id = "blindingSun", icon = "SUN",  name = "BLINDING SUN",
      desc = "WR and TE OFF -8",
      category = "field" },
    { id = "redZone",     icon = "RED",  name = "RED ZONE",
      desc = "All OFF cards +8",
      category = "field" },
    { id = "scramble",    icon = "RUN",  name = "SCRAMBLE",
      desc = "QBs OFF +12",
      category = "field" },
    { id = "groundPound", icon = "RB",   name = "GROUND & POUND",
      desc = "RB OFF +10, OL OFF +5",
      category = "position" },
    { id = "airRaid",     icon = "AIR",  name = "AIR RAID",
      desc = "WR and TE OFF +8",
      category = "position" },
    { id = "trenches",    icon = "OL",   name = "TRENCHES",
      desc = "OL OFF +6, DT DEF +6",
      category = "position" },
    { id = "secondary",   icon = "CB",   name = "SECONDARY",
      desc = "CB and S DEF +6",
      category = "position" },
    { id = "specialUnit", icon = "ST",   name = "ST UNIT",
      desc = "K and ST stat +15",
      category = "position" },
    { id = "playOfGame",  icon = "MVP",  name = "PLAY OF GAME",
      desc = "Highest-stat card in lane gets +20",
      category = "wild" },
    -- Tier 2 (cost / reveal)
    { id = "hurryUp",     icon = "FAST", name = "HURRY-UP",
      desc = "OFF cards cost -1 in this lane (min 1)",
      category = "tactical" },
    { id = "preventD",    icon = "PRV",  name = "PREVENT D",
      desc = "DEF cards cost -1 in this lane (min 1)",
      category = "tactical" },
    { id = "scouted",     icon = "SPY",  name = "SCOUTED",
      desc = "First card placed in this lane reveals immediately",
      category = "tactical" },
    { id = "blitzZone",   icon = "BLZ",  name = "BLITZ ZONE",
      desc = "DEF SNAP abilities trigger twice",
      category = "tactical" },
    -- Tier 3 (mechanical — Phase 6.5)
    { id = "frozenTundra", icon = "ICE", name = "FROZEN TUNDRA",
      desc = "All card abilities disabled in this lane",
      category = "mechanical" },
    { id = "coinFlip",     icon = "FLIP", name = "COIN FLIP",
      desc = "Each drive, 50/50 doubles or halves the net yards",
      category = "mechanical" },
    { id = "turnover",     icon = "TOV",  name = "TURNOVER",
      desc = "After 3 scoreless drives, ball positions swap",
      category = "mechanical" },
    { id = "suddenDeath",  icon = "SD",   name = "SUDDEN DEATH",
      desc = "First side to score locks this lane permanently",
      category = "mechanical" },
}

function M.get_by_id(id)
    for _, mod in ipairs(M.POOL) do
        if mod.id == id then return mod end
    end
    return nil
end

-- Returns `count` modifier records drawn without replacement from POOL.
-- Fisher-Yates on a copy so the live POOL table stays untouched.
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
