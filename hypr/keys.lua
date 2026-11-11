-- omext docks: the keys that open a dock and close it again, for the docks
-- that have them set (Settings > the dock > Key, or omext-dock key). None by
-- default. omext-dock writes them to a file of its own, loaded here.
local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
pcall(dofile, state .. "/omext/docks/keys.lua")
