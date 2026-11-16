#!/usr/bin/env bash
# Fetch dyad-ui-shot's pinned dependencies into the cache directory
# (default: <clone root>/.cache/dyad-ui-shot, override with DYAD_UI_SHOT_CACHE),
# verifying every download against versions.env.
#
#   setup.sh              standalone mode: Dyad Studio .vsix, chrome-headless-shell,
#                         Node packages (puppeteer-core, vscode-jsonrpc)
#   setup.sh --dyad-cli   also the Dyad CLI, for --render-png (needs `gh` logged
#                         in with access to JuliaComputing/dyad-lang)
#   setup.sh --studio     also openvscode-server and Studio's extension
#                         dependencies, for --mode studio
#   setup.sh --all        everything
set -euo pipefail

TOOL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=versions.env
source "$TOOL_DIR/versions.env"
CACHE=${DYAD_UI_SHOT_CACHE:-$(cd "$TOOL_DIR/../.." && pwd)/.cache/dyad-ui-shot}

WANT_CLI=0 WANT_STUDIO=0
for a in "$@"; do
  case $a in
    --dyad-cli) WANT_CLI=1 ;;
    --studio) WANT_STUDIO=1 ;;
    --all) WANT_CLI=1 WANT_STUDIO=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done

mkdir -p "$CACHE/dl" "$CACHE/tmp"
# Keep every large temporary file inside the cache.
export TMPDIR="$CACHE/tmp"
export npm_config_cache="$CACHE/npm-cache"
export PUPPETEER_SKIP_DOWNLOAD=1 PUPPETEER_CACHE_DIR="$CACHE/puppeteer"

# If the cache sits inside a git clone, keep it out of git.
if top=$(git -C "$CACHE" rev-parse --show-toplevel 2>/dev/null); then
  exclude=$(git -C "$top" rev-parse --git-path info/exclude)
  case $exclude in /*) ;; *) exclude="$top/$exclude" ;; esac
  rel=${CACHE#"$top"/}
  first=${rel%%/*}
  mkdir -p "$(dirname "$exclude")"
  grep -qxF "/$first/" "$exclude" 2>/dev/null || echo "/$first/" >> "$exclude"
fi

log() { echo "setup: $*" >&2; }

# fetch URL FILE SHA256: download into dl/ unless already there with the right hash.
fetch() {
  local url=$1 out="$CACHE/dl/$2" sum=$3
  if [[ -f $out ]] && echo "$sum  $out" | sha256sum -c --status; then return; fi
  log "downloading $url"
  curl -fL --retry 3 -sS -o "$out.part" "$url"
  if ! echo "$sum  $out.part" | sha256sum -c --status; then
    rm -f "$out.part"
    echo "setup: checksum mismatch for $url" >&2
    exit 1
  fi
  mv "$out.part" "$out"
}

# --- Dyad Studio (the diagram bundle and the language server) ---------------
STUDIO_DIR="$CACHE/studio-$DYAD_STUDIO_VERSION"
STUDIO_VSIX="JuliaComputing.dyad-studio-$DYAD_STUDIO_VERSION.vsix"
if [[ ! -f $STUDIO_DIR/.ok || ! -f $STUDIO_DIR/extension/out/dyad-ui.js ]]; then
  fetch "https://open-vsx.org/api/JuliaComputing/dyad-studio/$DYAD_STUDIO_VERSION/file/$STUDIO_VSIX" \
    "$STUDIO_VSIX" "$DYAD_STUDIO_SHA256"
  rm -rf "$STUDIO_DIR"
  mkdir -p "$STUDIO_DIR"
  unzip -q "$CACHE/dl/$STUDIO_VSIX" 'extension/*' -d "$STUDIO_DIR"
  touch "$STUDIO_DIR/.ok"
  log "Dyad Studio $DYAD_STUDIO_VERSION unpacked"
fi

# --- chrome-headless-shell ---------------------------------------------------
CHROME_DIR="$CACHE/chrome-$CHROME_VERSION"
if [[ ! -f $CHROME_DIR/.ok ]]; then
  fetch "https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chrome-headless-shell-linux64.zip" \
    chrome-headless-shell-linux64.zip "$CHROME_SHA256"
  rm -rf "$CHROME_DIR"
  mkdir -p "$CHROME_DIR"
  unzip -q "$CACHE/dl/chrome-headless-shell-linux64.zip" -d "$CHROME_DIR"
  rm "$CACHE/dl/chrome-headless-shell-linux64.zip"
  touch "$CHROME_DIR/.ok"
  log "chrome-headless-shell $CHROME_VERSION unpacked"
fi

# --- Node packages, from the committed lockfile ------------------------------
NODE_DIR="$CACHE/node"
mkdir -p "$NODE_DIR"
if ! cmp -s "$TOOL_DIR/package-lock.json" "$NODE_DIR/package-lock.json" || [[ ! -d $NODE_DIR/node_modules ]]; then
  cp "$TOOL_DIR/package.json" "$TOOL_DIR/package-lock.json" "$NODE_DIR/"
  (cd "$NODE_DIR" && npm ci --ignore-scripts --no-audit --no-fund --loglevel=error)
  log "Node packages installed"
fi

# --- Dyad CLI (optional) -----------------------------------------------------
if (( WANT_CLI )); then
  CLI_DIR="$CACHE/dyad-cli-$DYAD_CLI_VERSION"
  if [[ ! -x $CLI_DIR/dyad ]]; then
    rm -rf "$CLI_DIR" "$CACHE/dl/cli"
    mkdir -p "$CLI_DIR" "$CACHE/dl/cli"
    log "downloading Dyad CLI v$DYAD_CLI_VERSION"
    gh release download "v$DYAD_CLI_VERSION" -R JuliaComputing/dyad-lang \
      -p dyad-linux-x64 -p SHA256SUMS.txt -D "$CACHE/dl/cli"
    (cd "$CACHE/dl/cli" && grep ' dyad-linux-x64$' SHA256SUMS.txt | sha256sum -c --status) || {
      echo "setup: dyad-linux-x64 does not match SHA256SUMS.txt" >&2
      exit 1
    }
    mv "$CACHE/dl/cli/dyad-linux-x64" "$CLI_DIR/dyad"
    chmod +x "$CLI_DIR/dyad"
    rm -rf "$CACHE/dl/cli"
    log "Dyad CLI $("$CLI_DIR/dyad" --version) installed"
  fi
fi

# --- openvscode-server + Studio's extension dependencies (optional) -----------
if (( WANT_STUDIO )); then
  OVS_DIR="$CACHE/openvscode-server-$OPENVSCODE_VERSION"
  OVS_TGZ="openvscode-server-v$OPENVSCODE_VERSION-linux-x64.tar.gz"
  if [[ ! -f $OVS_DIR/.ok ]]; then
    fetch "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v$OPENVSCODE_VERSION/$OVS_TGZ" \
      "$OVS_TGZ" "$OPENVSCODE_SHA256"
    rm -rf "$OVS_DIR"
    mkdir -p "$OVS_DIR"
    tar -xzf "$CACHE/dl/$OVS_TGZ" -C "$OVS_DIR" --strip-components=1
    rm "$CACHE/dl/$OVS_TGZ"
    touch "$OVS_DIR/.ok"
    log "openvscode-server $OPENVSCODE_VERSION unpacked"
  fi
  EXT_DIR="$OVS_DIR/extensions-installed"
  # Reinstall when the pinned extensions or the driver extension change.
  stamp="$EXT_DIR/.ok-$DYAD_STUDIO_VERSION-$({ echo "$STUDIO_DEPS"; cat "$TOOL_DIR"/driver-extension/*; } | sha256sum | cut -c1-12)"
  if [[ ! -f $stamp ]]; then
    rm -rf "$EXT_DIR"
    mkdir -p "$EXT_DIR"
    vsixes=()
    for dep in $STUDIO_DEPS; do
      id=${dep%@*} rest=${dep#*@}
      ver=${rest%%=*} sum=${rest#*=}
      ns=${id%%.*} name=${id#*.}
      file="$id-$ver.vsix"
      fetch "https://open-vsx.org/api/$ns/$name/$ver/file/$file" "$file" "$sum"
      vsixes+=("$CACHE/dl/$file")
    done
    # The Studio .vsix may have been removed after unpacking; refetch it.
    fetch "https://open-vsx.org/api/JuliaComputing/dyad-studio/$DYAD_STUDIO_VERSION/file/$STUDIO_VSIX" \
      "$STUDIO_VSIX" "$DYAD_STUDIO_SHA256"
    vsixes+=("$CACHE/dl/$STUDIO_VSIX")
    # The driver extension ships as a folder; zip it into a .vsix.
    python3 -I "$TOOL_DIR/driver-extension/make-vsix.py" "$TOOL_DIR/driver-extension" "$CACHE/dl/dyad-ui-shot-driver.vsix"
    vsixes+=("$CACHE/dl/dyad-ui-shot-driver.vsix")
    for v in "${vsixes[@]}"; do
      "$OVS_DIR/bin/openvscode-server" --server-data-dir "$OVS_DIR/data" --user-data-dir "$OVS_DIR/data" \
        --extensions-dir "$EXT_DIR" --install-extension "$v" >&2
      rm -f "$v"
    done
    touch "$stamp"
    log "Studio extensions installed into $EXT_DIR"
  fi
  # Standalone mode can use the copy of Studio installed here; drop the
  # duplicate unpacked one.
  installed="$EXT_DIR/juliacomputing.dyad-studio-$DYAD_STUDIO_VERSION"
  if [[ -d $installed && ! -L $STUDIO_DIR/extension ]]; then
    rm -rf "$STUDIO_DIR/extension"
    ln -s "$installed" "$STUDIO_DIR/extension"
    log "linked $STUDIO_DIR/extension -> $installed"
  fi
fi

# The downloaded .vsix is not needed once unpacked.
rm -f "$CACHE/dl/$STUDIO_VSIX"
du -sh "$CACHE" 2>/dev/null | sed 's/^/setup: cache size /' >&2
log "done"
