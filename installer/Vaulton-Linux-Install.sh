#!/usr/bin/env bash
set -euo pipefail

repo="ericg2/Vaulton-UI"
mode="install"
archive=""
target="${HOME}/.local/opt/vaulton"
app_pid=""

while (($#)); do
  case "$1" in
    --update) mode="update"; shift ;;
    --pid) app_pid="${2:?Missing process ID}"; shift 2 ;;
    --archive) archive="${2:?Missing archive path}"; shift 2 ;;
    --target) target="${2:?Missing install directory}"; shift 2 ;;
    -h|--help)
      echo "Install Vaulton to ~/.local/opt/vaulton, or use --update --pid PID --archive FILE --target DIR."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum is required." >&2; exit 1; }
command -v tar >/dev/null || { echo "tar is required." >&2; exit 1; }

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

if [[ "$mode" == "install" ]]; then
  release="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/${repo}/releases/latest")"
  archive_url="$(printf '%s' "$release" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((a["browser_download_url"] for a in d.get("assets",[]) if a.get("name")=="Vaulton-Linux.tar.gz"), ""))')"
  checksum_url="$(printf '%s' "$release" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((a["browser_download_url"] for a in d.get("assets",[]) if a.get("name")=="Vaulton-Linux.tar.gz.sha256"), ""))')"
  [[ -n "$archive_url" && -n "$checksum_url" ]] || { echo "The latest GitHub Release has no Linux package yet." >&2; exit 1; }
  archive="${tmp}/Vaulton-Linux.tar.gz"
  curl -fsSL "$archive_url" -o "$archive"
  curl -fsSL "$checksum_url" -o "${archive}.sha256"
  (cd "$tmp" && sha256sum -c "Vaulton-Linux.tar.gz.sha256")
elif [[ "$mode" == "update" ]]; then
  [[ "$app_pid" =~ ^[0-9]+$ ]] || { echo "A valid --pid is required." >&2; exit 2; }
  [[ -f "$archive" ]] || { echo "Update archive not found: $archive" >&2; exit 1; }
  while kill -0 "$app_pid" 2>/dev/null; do sleep 0.25; done
else
  echo "Unsupported mode." >&2
  exit 2
fi

[[ -n "$target" && "$target" != "/" ]] || { echo "Unsafe install directory." >&2; exit 2; }
parent="$(dirname "$target")"
name="$(basename "$target")"
mkdir -p "$parent"
stage="$(mktemp -d "${parent}/.${name}.new.XXXXXX")"
tar -xzf "$archive" -C "$stage"
[[ -x "${stage}/vaulton" ]] || { echo "The Linux archive does not contain an executable vaulton." >&2; exit 1; }

backup="${parent}/.${name}.old.$$"
if [[ -e "$target" ]]; then mv "$target" "$backup"; fi
if ! mv "$stage" "$target"; then
  [[ ! -e "$backup" ]] || mv "$backup" "$target"
  echo "Could not replace the Vaulton installation." >&2
  exit 1
fi
[[ ! -e "$backup" ]] || rm -rf "$backup"

if [[ "$mode" == "install" ]]; then
  mkdir -p "${HOME}/.local/share/applications"
  cat > "${HOME}/.local/share/applications/vaulton.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Vaulton
Comment=Vaulton client
Exec="${target}/vaulton"
Terminal=false
Categories=Utility;Network;
EOF
  chmod 644 "${HOME}/.local/share/applications/vaulton.desktop"
  echo "Vaulton installed to $target. You can launch it from your application menu."
else
  echo "Vaulton updated successfully."
fi
