-- Shared message hashes. Pre-computed so hot paths don't pay the hash() cost.
-- Import via: local msgs = require "main.state.messages"

local M = {}

-- Match / lane / card lifecycle
M.CARD_PLAY = hash("card.play")
M.LANE_CARD_PLAYED = hash("lane.card_played")
M.MATCH_PLAY_TEST_CARD = hash("match.play_test_card")

-- HUD updates
M.HUD_YARDS_CHANGED = hash("hud.yards_changed")

-- Loader / screen transitions
M.SHOW_MENU = hash("show_menu")
M.SHOW_MATCH = hash("show_match")
M.YARDS_GAINED = hash("yards_gained")
M.TOTAL_TAPS_CHANGED = hash("total_taps_changed")

-- Input
M.TOUCH = hash("touch")
M.BACK = hash("back")

-- Collection proxy (built-in Defold messages, cached here for convenience)
M.PROXY_LOADED = hash("proxy_loaded")
M.PROXY_UNLOADED = hash("proxy_unloaded")
M.LOAD = hash("load")
M.UNLOAD = hash("unload")
M.INIT = hash("init")
M.ENABLE = hash("enable")
M.DISABLE = hash("disable")
M.FINAL = hash("final")

return M
