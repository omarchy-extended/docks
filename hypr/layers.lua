-- The docks (omext.docks) never unmap: the panel only grows and shrinks, and
-- animates its own parts in QML. No Hyprland animation on top of that.
hl.layer_rule({ match = { namespace = "omext-docks" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "omext-docks-backdrop" }, no_anim = true, animation = "none" })
