-- Static card pool. Phase 1 picks 5 random cards from POOL at match start;
-- there's no deck, no draw, no discard. Card records are plain data tables;
-- runtime per-card state (uid, "played" flag) is attached when a hand is
-- dealt or when a card is played, never to the pool entries themselves.

local M = {}

-- Stable string ids ("qb_01", "rb_03") so save/load is forward-compatible
-- once we have a deck. side="off" cards have off>0 and def=0; side="def"
-- cards are the inverse. cost is 1..5 in Phase 1 (no 6-cost yet).
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
    { id = "k_01",  name = "Kicker",         pos = "K",  cost = 1, off = 6,  def = 0,  side = "off", rarity = "common" },
    { id = "cb_01", name = "Lockdown CB",    pos = "CB", cost = 3, off = 0,  def = 18, side = "def", rarity = "common" },
    { id = "s_01",  name = "Free Safety",    pos = "S",  cost = 2, off = 0,  def = 12, side = "def", rarity = "common" },
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

-- Clone so the caller can attach a uid and (later) mutate without touching
-- the canonical pool entry.
local function clone_card(src)
    return {
        id = src.id,
        name = src.name,
        pos = src.pos,
        cost = src.cost,
        off = src.off,
        def = src.def,
        side = src.side,
        rarity = src.rarity,
    }
end

-- Returns `size` shuffled clones from POOL. Uses Fisher-Yates on an index
-- array so we never pick the same pool entry twice.
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

return M
