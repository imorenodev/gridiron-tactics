-- Thin wrapper around go.animate / gui.animate that respects the
-- reduced-motion meta flag. When the flag is on the target value is set
-- instantly and the (optional) callback fires via timer.delay so callers
-- don't have to special-case sync vs async completion.
--
-- Note on callback contract: gui.animate / go.animate invoke the callback
-- as `function(self, node)`; timer.delay invokes it as `function(self,
-- handle, time_elapsed)`. Both deliver the script's `self` as the first
-- argument, so callbacks that only read `self` work in both paths. Avoid
-- relying on the second argument in any callback that may run under
-- reduced motion.

local meta_state = require("main.state.meta_state")

local M = {}

local function delayed_callback(callback, delay)
    if not callback then return end
    local d = (delay and delay > 0) and delay or 0.001
    timer.delay(d, false, callback)
end

-- Wraps go.animate. Signature mirrors go.animate.
function M.animate_go(url, property, playback, target, easing, duration, delay, callback)
    if meta_state.is_reduced_motion() then
        go.set(url, property, target)
        delayed_callback(callback, delay)
    else
        go.animate(url, property, playback, target, easing, duration, delay or 0, callback)
    end
end

-- Wraps gui.animate. Note gui.animate has no playback arg.
function M.animate_gui(node, property, target, easing, duration, delay, callback)
    if meta_state.is_reduced_motion() then
        gui.set(node, property, target)
        delayed_callback(callback, delay)
    else
        gui.animate(node, property, target, easing, duration, delay or 0, callback)
    end
end

return M
