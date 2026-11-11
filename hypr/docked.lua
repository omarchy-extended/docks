-- Windows in a dock (omext-dock tags them omext-docked): no border, which would
-- show as a faint frame inside the dock, and no animations, so they appear and
-- go in place as the dock opens and closes. And no titlebar: Omarchy tags every
-- window carried onto a floating workspace for one, and hyprbars takes the
-- bar's room inside the window, shifting the app's content down and back until
-- omext-dock clears the tag. A docked app has the dock's header instead.
-- (hyprbars' field only while the plugin is loaded: Omarchy loads it once
-- something floats, and an unknown field would drop the whole rule.)
local rule = { match = { tag = "omext-docked" }, border_size = 0, no_anim = true }
if hl.plugin and hl.plugin.hyprbars then
  rule["hyprbars:no_bar"] = true
end
hl.window_rule(rule)
