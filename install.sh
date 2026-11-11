#!/bin/bash
# Installs omext docks (omarchy-extended) on Omarchy, from this folder: links,
# so a git pull here updates it. Safe to run again. To undo: ./uninstall.sh
set -euo pipefail

dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
bin=$HOME/.local/bin
plugin=$HOME/.config/omarchy/plugins/omext.docks
unit=$config_home/systemd/user/omext-docks.service
config=$config_home/omext/docks.json
hypr_conf=$HOME/.config/hypr/hyprland.lua
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
mark=omext-docks

die() { echo "install: $*" >&2; exit 1; }
info() { echo "install: $*"; }

for cmd in python3 jq hyprctl omarchy omarchy-shell systemctl; do
  command -v "$cmd" >/dev/null || die "needs $cmd (Omarchy, with python and jq)"
done

# omext core (what the omext addons share): installed too when it's missing,
# and brought up to date when it's the copy installed this way.
core=${XDG_DATA_HOME:-$HOME/.local/share}/omext-core
if [[ ! -e $HOME/.config/omarchy/plugins/omext.core ]]; then
  [[ -d $core ]] || git clone -q https://github.com/omarchy-extended/core.git "$core" || die "needs omext core (https://github.com/omarchy-extended/core)"
  "$core/install.sh" >/dev/null || die "omext core's install failed"
elif [[ -d $core/.git && $(readlink -f "$HOME/.config/omarchy/plugins/omext.core") == "$core"/* ]]; then
  git -C "$core" pull -q --ff-only 2>/dev/null || info "couldn't update omext core (run: git -C $core pull)"
fi
[[ -e $HOME/.local/share/omarchy-addons/enabled/docks ]] && die "the docks are already deployed by omx here"
[[ -f $hypr_conf ]] || die "no $hypr_conf"

link() {  # link <source> <target>: ours, or nothing there yet
  if [[ -e $2 && ! -L $2 ]]; then die "$2 is there already (not a link); move it away first"; fi
  mkdir -p "$(dirname "$2")"
  ln -sfn "$1" "$2"
}
link "$dir/bin/omext-dock" "$bin/omext-dock"
link "$dir/plugins/omext.docks" "$plugin"
link "$dir/systemd/omext-docks.service" "$unit"

# Hyprland: this folder's hypr/*.lua, loaded at every (re)load, between marks
# (uninstall.sh removes them).
sed -i "/^-- BEGIN $mark\$/,/^-- END $mark\$/d" "$hypr_conf"
{
  echo "-- BEGIN $mark"
  for f in "$dir"/hypr/*.lua; do echo "pcall(dofile, \"$f\")"; done
  echo "-- END $mark"
} >> "$hypr_conf"
info "loads its Hyprland rules from $hypr_conf"

# The Omarchy menu: a Docks entry (on or off), before the file's last brace.
mkdir -p "$(dirname "$menu_conf")"
[[ -s $menu_conf ]] || printf '{\n}\n' > "$menu_conf"
sed -i "\|^ *// BEGIN $mark\$|,\|^ *// END $mark\$|d" "$menu_conf"
block=$(sed '1d;$d' "$dir/menu.jsonc")
tmp=$(mktemp)
# The block through the environment: awk -v would take its backslashes as escapes.
BLOCK=$block awk -v begin="  // BEGIN $mark" -v end="  // END $mark" '
  { lines[NR] = $0 }
  /^[[:space:]]*}[[:space:]]*$/ { last = NR }
  END {
    # The entry before ours needs its comma (JSON has no trailing one to rely on).
    p = last - 1
    while (p > 0 && lines[p] ~ /^[[:space:]]*(\/\/.*)?$/) p--
    if (p > 0 && lines[p] !~ /[,{][[:space:]]*$/) lines[p] = lines[p] ","
    for (i = 1; i <= NR; i++) { if (i == last) { print begin; print ENVIRON["BLOCK"]; print end } print lines[i] } }
' "$menu_conf" > "$tmp"
cat "$tmp" > "$menu_conf"
rm "$tmp"
info "added Docks to the Omarchy menu"

# A first dock, on the right of the focused screen, if there are none yet.
if [[ ! -e $config ]]; then
  "$bin/omext-dock" new right >/dev/null
  info "made a dock on the right edge ($config)"
fi

systemctl --user daemon-reload
systemctl --user enable omext-docks.service >/dev/null 2>&1
"$bin/omext-dock" enable  # the plugin on, the watcher started, Hyprland reloaded
info "done. Hover the right screen edge: + on its bar adds an app, the gear under it has the settings."
