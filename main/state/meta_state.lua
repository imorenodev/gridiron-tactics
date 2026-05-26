-- Player-level meta-progression and settings. Phase 2.5 introduces only
-- one field (reduced_motion); Phase 3+ extends this with cash, XP,
-- perks, etc. The schema lives in M.load()'s defaults — extending it
-- means adding a key there and any consumer accessor below.
--
-- save.lua orchestrates the disk round trip: on load it passes the
-- read-back save table here; on save it asks for M.serialize() and
-- writes the result under save_data.meta.

local M = {}

local data = nil

local function defaults()
    return {
        reduced_motion = false,
        -- future: cash = 0, coach_xp = 0, coach_level = 1,
        --         perks_unlocked = {}, perks_equipped = {}, ...
    }
end

-- Initialize from a save-data table (the table returned by sys.load via
-- save.lua). Missing fields fall back to defaults so an older save loads
-- cleanly without a migration.
function M.load(loaded_save_data)
    data = defaults()
    if loaded_save_data and type(loaded_save_data.meta) == "table" then
        for k, v in pairs(loaded_save_data.meta) do
            data[k] = v
        end
    end
end

-- Returns the table to be saved under save_data.meta. Returns nil if
-- meta_state hasn't been loaded yet (which would mean someone is asking
-- to serialize before init order has settled; caller should treat nil as
-- "no meta to write").
function M.serialize()
    return data
end

function M.is_reduced_motion()
    if not data then return false end
    return data.reduced_motion and true or false
end

-- Returns the new value so the caller can log / toast it.
function M.toggle_reduced_motion()
    if not data then
        data = defaults()
    end
    data.reduced_motion = not data.reduced_motion
    return data.reduced_motion
end

return M
