-- Persistence layer. Reads/writes a single Lua table via sys.save.
-- All saves carry a version field; future schema changes require a migration here.

local M = {}

local SAVE_DIR = "gridiron_tactics"
local SAVE_FILE = "save.dat"
local CURRENT_VERSION = 1

local function default_save()
    return {
        version = CURRENT_VERSION,
        total_drives_played = 0,
    }
end

-- Fill in any default fields missing from `loaded`. Lets us add new fields
-- to the schema (within version 1) without breaking older save files.
local function merge_defaults(loaded)
    local defaults = default_save()
    for k, v in pairs(defaults) do
        if loaded[k] == nil then
            loaded[k] = v
        end
    end
    return loaded
end

function M.get_save_path()
    return sys.get_save_file(SAVE_DIR, SAVE_FILE)
end

function M.load()
    local path = M.get_save_path()
    local data = sys.load(path)
    -- sys.load returns an empty table when the file is missing or corrupt.
    if type(data) ~= "table" or not data.version then
        return default_save()
    end
    return merge_defaults(data)
end

function M.save(data)
    return sys.save(M.get_save_path(), data)
end

return M
