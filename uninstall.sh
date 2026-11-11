#!/bin/bash
# Removes what install.sh added. Your docks (~/.config/omext/docks.json) stay,
# for a later install.
set -uo pipefail

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
bin=$HOME/.local/bin
plugin=$HOME/.config/omarchy/plugins/omext.docks
unit=$config_home/systemd/user/omext-docks.service
hypr_conf=$HOME/.config/hypr/hyprland.lua
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
mark=omext-docks

[[ -x $bin/omext-dock ]] && "$bin/omext-dock" release-all  # no window left hidden
systemctl --user disable --now omext-docks.service >/dev/null 2>&1
omarchy plugin disable omext.docks >/dev/null 2>&1
for f in "$bin/omext-dock" "$plugin" "$unit"; do [[ -L $f ]] && rm "$f"; done
systemctl --user daemon-reload
[[ -f $hypr_conf ]] && sed -i "/^-- BEGIN $mark\$/,/^-- END $mark\$/d" "$hypr_conf"
[[ -f $menu_conf ]] && sed -i "\|^ *// BEGIN $mark\$|,\|^ *// END $mark\$|d" "$menu_conf"
hyprctl reload >/dev/null
echo "uninstall: done (your docks are kept in $config_home/omext/docks.json)"
