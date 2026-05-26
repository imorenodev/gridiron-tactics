-- Persistence layer. Reads/writes a single Lua table via sys.save.
-- All saves carry a version field; future schema changes require a
-- migration here.
--
-- save.lua delegates the `meta` sub-table to meta_state.lua: on load we
-- hand the read-back save to meta_state.load() so its module-local
-- defaults absorb any missing fields; on save we ask meta_state for the
-- serialized form and slot it in before writing. The two modules stay
-- decoupled from callers (loader.script) which doesn't need to know
-- meta_state is the source of the `meta` field.

local meta_state = require("main.state.meta_state")

local M = {}

local SAVE_DIR = "gridiron_tactics"
local SAVE_FILE = "save.dat"
local CURRENT_VERSION = 1

local function default_save()
    return {
        version = CURRENT_VERSION,
        total_drives_played = 0,
        meta = {},  -- Phase 2.5: filled by meta_state.serialize() at write time.
    }
end

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
    if type(data) ~= "table" or not data.version then
        data = default_save()
    else
        data = merge_defaults(data)
    end
    meta_state.load(data)
    return data
end

function M.save(data)
    data.meta = meta_state.serialize() or {}
    return sys.save(M.get_save_path(), data)
end

return M
