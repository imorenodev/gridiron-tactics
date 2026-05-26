-- CPU heuristic. Ported verbatim from the HTML prototype's aiMakePlays():
-- sort hand by total power desc, score each affordable card across all 3
-- lanes (offensive cards score off + position/defense bonuses, defensive
-- cards score def + threat/DB-stacking bonuses), pick the best lane.
--
-- Pure function. Reads `ai_hand`, `ai_energy`, and the lanes array (which
-- it does not mutate); returns an array of { card, lane_idx } in play order.
-- The caller (match.script) applies the plays to real state via
-- match_state.ai_play_card. The `lane_idx` in each returned play is
-- 1-indexed (matching the Lua iteration in this file); the caller converts
-- to the 0-indexed form match_state expects.

local match_state = require("main.state.match_state")

local M = {}

local MAX_SLOTS = 8

function M.choose_plays(ai_hand, ai_energy, lanes)
    -- Build a playable list, skipping empty slots, then sort by power desc.
    local playable = {}
    for _, c in ipairs(ai_hand) do
        if c and not c.empty then
            table.insert(playable, c)
        end
    end
    table.sort(playable, function(a, b)
        return ((a.off or 0) + (a.def or 0)) > ((b.off or 0) + (b.def or 0))
    end)

    local energy_left = ai_energy
    local plays = {}

    -- Track lane fill in a working copy so we don't double-fill within a
    -- single decision pass.
    local lane_fill = {}
    for i, lane in ipairs(lanes) do
        lane_fill[i] = #lane.ai_cards
    end

    for _, card in ipairs(playable) do
        do
            local best_lane = -1
            local best_score = -math.huge
            local best_cost = card.cost or 0

            for i = 1, 3 do
                local lane = lanes[i]
                -- Phase 6: cost is per-lane (Hurry-Up / Prevent D).
                local zero_idx = i - 1
                local lane_cost = match_state.effective_cost(card, zero_idx)
                if lane and lane_fill[i] < MAX_SLOTS and lane_cost <= energy_left then
                    local score = 0
                    if card.side == "off" then
                        score = card.off or 0
                        -- Close-to-scoring bonus
                        if lane.ai_pos >= 70 then
                            score = score + 18
                        elseif lane.ai_pos >= 50 then
                            score = score + 8
                        end
                        -- Weak player defense → press the advantage
                        if (lane.you_def_sum or 0) < (card.off or 0) / 2 then
                            score = score + 6
                        end
                        -- Kicker positioning
                        if card.pos == "K" and lane.ai_pos >= 50 then
                            score = score + 14
                        end
                    else
                        -- Defensive card
                        score = card.def or 0
                        -- Urgent if player is threatening
                        if (lane.you_pos or 0) >= 70 then
                            score = score + 22
                        elseif (lane.you_pos or 0) >= 50 then
                            score = score + 10
                        end
                        -- Near own endzone → defense helps avoid safety
                        if (lane.ai_pos or 0) <= 30 then
                            score = score + 6
                        end
                        -- DB stacking for pick-6 potential
                        if (card.pos == "CB" or card.pos == "S") and (lane.ai_pos or 0) <= 50 then
                            local dbs_here = 0
                            for _, c2 in ipairs(lane.ai_cards) do
                                if c2.pos == "CB" or c2.pos == "S" then
                                    dbs_here = dbs_here + 1
                                end
                            end
                            score = score + dbs_here * 5
                        end
                    end

                    -- Tiny random tiebreaker
                    score = score + math.random() * 3

                    if score > best_score then
                        best_score = score
                        best_lane = i
                        best_cost = lane_cost
                    end
                end
            end

            if best_lane >= 1 then
                table.insert(plays, { card = card, lane_idx = best_lane })
                lane_fill[best_lane] = lane_fill[best_lane] + 1
                energy_left = energy_left - best_cost
            end
        end
    end

    return plays
end

return M
