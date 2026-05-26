-- Shared message hashes. Pre-computed so hot paths don't pay the hash() cost.
-- Import via: local msgs = require "main.state.messages"

local M = {}

-- Match lifecycle
M.MATCH_PLAY_CARD       = hash("match.play_card")
M.MATCH_END_DRIVE       = hash("match.end_drive")
M.MATCH_DRIVE_RESOLVED  = hash("match.drive_resolved")
M.MATCH_DRIVE_COMPLETED = hash("match.drive_completed")
M.MATCH_ENDED           = hash("match.ended")
M.MATCH_RETURN_TO_MENU  = hash("match.return_to_menu")

-- Lane events (hooks for Phase 2 modifier/synergy work)
M.LANE_RESOLVE          = hash("lane.resolve")

-- Card lifecycle
M.CARD_SPAWN            = hash("card.spawn")

-- HUD render updates (state → HUD)
M.HUD_HAND_CHANGED      = hash("hud.hand_changed")
M.HUD_ENERGY_CHANGED    = hash("hud.energy_changed")
M.HUD_LANE_UPDATED      = hash("hud.lane_updated")
M.HUD_LANE_RESOLVED     = hash("hud.lane_resolved")
M.HUD_MATCH_ENDED       = hash("hud.match_ended")

-- Loader / screen transitions
M.SHOW_MENU             = hash("show_menu")
M.SHOW_MATCH            = hash("show_match")
M.DRIVES_PLAYED_CHANGED = hash("drives_played_changed")

-- Input
M.TOUCH                 = hash("touch")
M.BACK                  = hash("back")

-- Collection proxy (built-in Defold messages, cached here for convenience)
M.PROXY_LOADED          = hash("proxy_loaded")
M.PROXY_UNLOADED        = hash("proxy_unloaded")
M.LOAD                  = hash("load")
M.UNLOAD                = hash("unload")
M.INIT                  = hash("init")
M.ENABLE                = hash("enable")
M.DISABLE               = hash("disable")
M.FINAL                 = hash("final")

return M
