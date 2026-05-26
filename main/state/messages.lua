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

-- Lane events (hooks for Phase 2+ modifier/synergy work)
M.LANE_RESOLVE          = hash("lane.resolve")

-- Card lifecycle
M.CARD_SPAWN            = hash("card.spawn")

-- Phase 2: internal match-state messages for the reveal sequence
M.MATCH_PLAY_AI_CARDS   = hash("match.play_ai_cards")
M.MATCH_REVEAL          = hash("match.reveal")

-- Phase 3: scoring + 2-pt conversion + spawned-card tracking
M.MATCH_SCORE_LANE      = hash("match.score_lane")
M.MATCH_PAT_RESULT      = hash("match.pat_result")
M.MATCH_TWO_PT_CHOICE   = hash("match.two_pt_choice")
M.MATCH_CARD_SPAWNED    = hash("match.card_spawned")

-- HUD render updates (state → HUD)
M.HUD_HAND_CHANGED      = hash("hud.hand_changed")
M.HUD_ENERGY_CHANGED    = hash("hud.energy_changed")
M.HUD_LANE_UPDATED      = hash("hud.lane_updated")
M.HUD_LANE_RESOLVED     = hash("hud.lane_resolved")
M.HUD_MATCH_ENDED       = hash("hud.match_ended")
M.HUD_AI_CARDS_SPAWNED  = hash("hud.ai_cards_spawned")
M.HUD_REVEAL_CARD       = hash("hud.reveal_card")
M.HUD_LANE_SUMS_UPDATED = hash("hud.lane_sums_updated")
M.HUD_PHASE_CHANGED     = hash("hud.phase_changed")
-- Phase 3
M.HUD_SCORE_BURST       = hash("hud.score_burst")
M.HUD_SCORE_UPDATED     = hash("hud.score_updated")
M.HUD_LANE_RESET        = hash("hud.lane_reset")
M.HUD_TWO_PT_PROMPT     = hash("hud.two_pt_prompt")
M.HUD_TWO_PT_RESULT     = hash("hud.two_pt_result")
-- Phase 4: multi-drive + deck cycle
M.HUD_DECK_COUNT_CHANGED    = hash("hud.deck_count_changed")
M.HUD_DISCARD_COUNT_CHANGED = hash("hud.discard_count_changed")
M.HUD_START_DISCARD_ANIM    = hash("hud.start_discard_anim")
M.HUD_START_DRAW_ANIM       = hash("hud.start_draw_anim")
M.HUD_RESHUFFLE             = hash("hud.reshuffle")
M.HUD_CARRIED_TOAST         = hash("hud.carried_toast")
M.HUD_DRIVE_CHANGED         = hash("hud.drive_changed")
M.HUD_ENERGY_AT_CAP         = hash("hud.energy_at_cap")
M.HUD_OPEN_DISCARD_MODAL    = hash("hud.open_discard_modal")

-- Phase 6: lane modifiers
M.HUD_MODIFIERS_REVEAL            = hash("hud.modifiers_reveal")
M.MATCH_MODIFIERS_REVEAL_COMPLETE = hash("match.modifiers_reveal_complete")
M.HUD_SHOW_MODIFIER_TOAST         = hash("hud.show_modifier_toast")

-- Phase 6.5: Tier 3 mechanical modifiers
M.HUD_TURNOVER_SWAP               = hash("hud.turnover_swap")
M.HUD_LANE_LOCKED                 = hash("hud.lane_locked")

-- Loader / screen transitions
M.SHOW_MENU             = hash("show_menu")
M.SHOW_MATCH            = hash("show_match")
M.DRIVES_PLAYED_CHANGED = hash("drives_played_changed")

-- Input
M.TOUCH                  = hash("touch")
M.BACK                   = hash("back")
M.TOGGLE_REDUCED_MOTION  = hash("toggle_reduced_motion")

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
