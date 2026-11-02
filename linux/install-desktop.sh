#!/usr/bin/env bash
set -euo pipefail

bundle_dir="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")" && pwd -P)"
data_home="\${XDG_DATA_HOME:-$HOME/.local/share}"
icon_source="$bundle_dir/share/icons/hicolor/scalable/apps/com.ericg2.vaulton.svg"

if [[ ! -x "$bundle_dir/vaulton" || ! -f "$icon_source" ]]; then
  printf 'Run this script from a complete extracted Vaulton Linux bundle.\n' >&2
  exit 1
fi

install -Dm644 "$icon_source" "$data_home/icons/hicolor/scalable/apps/com.ericg2.vaulton.svg"
mkdir -p "$data_home/applications"
cat > "$data_home/applications/com.ericg2.vaulton.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Vaulton
Comment=Manage Vaulton storage, files, and backups.
Exec="$bundle_dir/vaulton"
Icon=com.ericg2.vaulton
Terminal=false
Categories=Utility;System;
StartupNotify=true
StartupWMClass=com.ericg2.vaulton
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data_home/applications" || true
fi

printf 'Vaulton is registered in your application menu. Restart it to refresh the window icon.\n'
