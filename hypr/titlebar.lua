-- "Send to dock" buttons on the titlebars Omarchy gives floating windows: one
-- for the dock on the left edge, one for the right (each only if there is such a
-- dock). The window goes into that dock (the one on its screen where there are
-- more) and the dock opens on it. The plugin is there only once something has
-- floated this session, and its buttons reset on every config load, so this
-- runs on each load. The same colours Omarchy picks for its buttons
-- (default/hypr/workspace-modes.lua).
local home = os.getenv("HOME")
-- omext-dock from this addon's own bin/ (next to this file's hypr/).
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or "."
local tool = here .. "/../bin/omext-dock"
local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

-- Not while the docks are turned off (omext-dock disable). Nor with omext arrange
-- installed: its zones button's map has the docks too, beside each screen's zones.
local arrange = exists(home .. "/.local/bin/omext-zone")
if hl.plugin and hl.plugin.hyprbars and not arrange and not exists(state_home .. "/omext/docks/disabled") then
  -- Which edges have a dock that's on: docks.json (read with jq).
  local edges = {}
  local path = os.getenv("OMEXT_DOCKS_FILE") or (config_home .. "/omext/docks.json")
  local jq = io.popen("jq -r '.docks[] | select(.off != true) | .edge' '" .. path .. "' 2>/dev/null")
  if jq then
    for edge in jq:lines() do
      edges[edge] = true
    end
    jq:close()
  end

  local colors = {}
  local file = io.open(home .. "/.local/state/omarchy/current/theme/colors.toml", "r")
  if file then
    for line in file:lines() do
      local key, value = line:match('^%s*([%w_]+)%s*=%s*"#(%x%x%x%x%x%x)"')
      if key then
        colors[key] = "rgb(" .. value .. ")"
      end
    end
    file:close()
  end
  local background = colors.background or "rgb(1a1b26)"
  local titlebar = colors.lighter_background
  if not titlebar or titlebar == background then
    titlebar = colors.selection or background
  end
  -- A dim divider between Omarchy's buttons and ours (these, and any other
  -- addon's buttons added after them): a button that does nothing.
  if edges.left or edges.right then
    hl.plugin.hyprbars.add_button({
      bg_color = titlebar,
      fg_color = colors.dark_foreground or colors.muted or "rgb(555555)",
      size = 12,
      icon = "│",
      action = "true",
    })
  end
  -- Added right to left: the right dock's nearer the window's own buttons.
  for _, b in ipairs({ { edge = "right", icon = "⇥" }, { edge = "left", icon = "⇤" } }) do
    if edges[b.edge] then
      hl.plugin.hyprbars.add_button({
        bg_color = titlebar,
        fg_color = colors.foreground or "rgb(c0caf5)",
        size = 20,
        icon = b.icon,
        action = tool .. " send --edge " .. b.edge .. " --window %WINDOW%",
      })
    end
  end
end
