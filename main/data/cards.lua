-- Static card pool. Phase 3: expanded to 18 cards (still well under any
-- "real deck" threshold). Mandatory shape per CLAUDE.md hard rule #4:
-- 5 DBs (CB/S) across the pool so the pick-6 detection path can actually
-- fire during playtest. One card carries an ability (Clutch Kicker /
-- snapFieldGoal) — first card with a `desc` field; future abilities use
-- the same dispatcher in match_state.try_apply_snap_ability.

local M = {}

-- Card record schema:
--   id      : stable string id, used in save/load when deck cycle lands
--   name    : display
--   pos     : QB / RB / WR / TE / OL / K (offense), CB / S / LB / DE / DT (defense)
--   cost    : 1..5 in Phase 3
--   off     : offensive power (0 for defenders + kickers)
--   def     : defensive power (0 for offensive cards)
--   side    : "off" | "def"
--   rarity  : "common" | "uncommon" | "rare" | "legendary"
--   ability : optional, display string for the SNAP/on-reveal ability
--   desc    : optional, machine id consumed by try_apply_snap_ability
M.POOL = {
    { id = "qb_01", name = "Pocket Passer",  pos = "QB", cost = 3, off = 20, def = 0,  side = "off", rarity = "common" },
    { id = "qb_02", name = "Mobile QB",      pos = "QB", cost = 4, off = 26, def = 0,  side = "off", rarity = "uncommon" },
    { id = "rb_01", name = "Bruiser",        pos = "RB", cost = 2, off = 14, def = 0,  side = "off", rarity = "common" },
    { id = "rb_02", name = "Scat Back",      pos = "RB", cost = 3, off = 18, def = 0,  side = "off", rarity = "common" },
    { id = "rb_03", name = "Bell Cow",       pos = "RB", cost = 5, off = 32, def = 0,  side = "off", rarity = "rare" },
    { id = "wr_01", name = "Possession WR",  pos = "WR", cost = 2, off = 12, def = 0,  side = "off", rarity = "common" },
    { id = "wr_02", name = "Burner",         pos = "WR", cost = 4, off = 24, def = 0,  side = "off", rarity = "uncommon" },
    { id = "te_01", name = "Blocking TE",    pos = "TE", cost = 1, off = 8,  def = 0,  side = "off", rarity = "common" },
    { id = "ol_01", name = "Anchor Tackle",  pos = "OL", cost = 2, off = 10, def = 0,  side = "off", rarity = "common" },

    -- Phase 3: Clutch Kicker carries the project's first SNAP ability.
    -- The ability fires inside match_state.try_apply_snap_ability when
    -- the kicker's side is past midfield at reveal time. off = 0 because
    -- kickers don't contribute to the lane's offense sum; their value is
    -- the PAT after a TD plus this FG ability.
    { id = "k_01",  name = "Clutch Kicker",  pos = "K",  cost = 3, off = 0,  def = 0,  side = "off", rarity = "uncommon",
      ability = "SNAP: 3-pt FG if past midfield", desc = "snapFieldGoal" },

    -- Defensive backs (CB + S): the pick-6 pool. Five total so a 4+ DB
    -- stack in one lane is reachable in playtest.
    { id = "cb_01", name = "Lockdown CB",    pos = "CB", cost = 3, off = 0,  def = 18, side = "def", rarity = "common" },
    { id = "cb_02", name = "Press CB",       pos = "CB", cost = 2, off = 0,  def = 13, side = "def", rarity = "common" },
    { id = "cb_03", name = "Ball Hawk",      pos = "CB", cost = 4, off = 0,  def = 20, side = "def", rarity = "uncommon" },
    { id = "s_01",  name = "Free Safety",    pos = "S",  cost = 2, off = 0,  def = 12, side = "def", rarity = "common" },
    { id = "s_02",  name = "Strong Safety",  pos = "S",  cost = 3, off = 0,  def = 16, side = "def", rarity = "common" },

    -- Front seven
    { id = "lb_01", name = "Run Stuffer",    pos = "LB", cost = 3, off = 0,  def = 16, side = "def", rarity = "common" },
    { id = "de_01", name = "Edge Rusher",    pos = "DE", cost = 4, off = 0,  def = 22, side = "def", rarity = "uncommon" },
    { id = "dt_01", name = "Nose Tackle",    pos = "DT", cost = 2, off = 0,  def = 11, side = "def", rarity = "common" },
}

function M.get_by_id(id)
    for _, c in ipairs(M.POOL) do
        if c.id == id then
            return c
        end
    end
    return nil
end

local function clone_card(src)
    local copy = {
        id = src.id,
        name = src.name,
        pos = src.pos,
        cost = src.cost,
        off = src.off,
        def = src.def,
        side = src.side,
        rarity = src.rarity,
    }
    if src.ability then copy.ability = src.ability end
    if src.desc then copy.desc = src.desc end
    return copy
end

function M.random_hand(size)
    local n = #M.POOL
    if size > n then size = n end

    local indices = {}
    for i = 1, n do indices[i] = i end
    for i = n, 2, -1 do
        local j = math.random(i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    local hand = {}
    for i = 1, size do
        hand[i] = clone_card(M.POOL[indices[i]])
    end
    return hand
end

-- Phase 4: build a deck of `size` cards by sampling from POOL with
-- replacement (duplicates allowed), then shuffle Fisher-Yates. Each
-- card is a fresh clone so callers can attach uids and mutate freely
-- without touching the canonical pool entries.
function M.build_deck(size)
    local n = #M.POOL
    local deck = {}
    for i = 1, size do
        local idx = math.random(n)
        deck[i] = clone_card(M.POOL[idx])
    end
    for i = size, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

return M
