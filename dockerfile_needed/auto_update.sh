#!/bin/bash
# auto_update.sh — background update checker + applier for Akiba.
#
# Three modes:
#   --daemon   Background loop: check GitHub every 3 days, download
#              new artifacts to a staging directory.  Started by the
#              container entrypoint.
#   --check    One-shot check (manual trigger from the Settings API).
#              Downloads artifacts if a newer release exists.
#   --apply    Apply staged artifacts (called by entrypoint on startup
#              before services start).  Swaps daemon/framework/mods
#              in place, preserving ghidra_projects/.
#
# Updates are NEVER applied while services are running — only on the
# next container restart via --apply.  The frontend shows a
# notification when an update is staged and tells the user to restart.

set -euo pipefail

# ---- Configuration ----
GITHUB_REPO="IoTS-P/Akiba"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
UPDATE_DIR="/home/akiba/.akiba/updates"
STAGING_DIR="$UPDATE_DIR/staging"
STATUS_FILE="$UPDATE_DIR/status.json"
VERSION_FILE="/home/akiba/.akiba/current_version"
CHECK_INTERVAL_SECONDS=$((3 * 24 * 60 * 60))  # 3 days
DOWNLOAD_TIMEOUT=300  # 5 minutes per artifact

# Asset name patterns (regex) — only download what we need.
ASSET_PATTERNS=(
    'akiba_db_daemon-[0-9].*\.zip'
    'akiba-[0-9].*\.zip'
    'amod-AkibaUtils-[0-9].*\.jar'
)

mkdir -p "$UPDATE_DIR" "$STAGING_DIR"

# ---- Helpers ----

log()  { printf '[auto-update] %s\n' "$*"; }
err()  { printf '[auto-update] ERROR: %s\n' "$*" >&2; }

get_current_version() {
    cat "$VERSION_FILE" 2>/dev/null | tr -d '[:space:]' || echo "unknown"
}

# Write the status JSON file consumed by the backend API.
# Args: lastCheck currentVersion latestVersion updateAvailable(staged_json) error_json
write_status() {
    local last_check="$1" current="$2" latest="$3" available="$4" staged_json="$5" error_json="$6"
    cat > "$STATUS_FILE" <<EOF
{
  "lastCheck": "$last_check",
  "currentVersion": "$current",
  "latestVersion": "$latest",
  "updateAvailable": $available,
  "stagedArtifacts": $staged_json,
  "error": $error_json
}
EOF
}

# Compare two semver-like strings.  Prints "newer", "older", or "equal".
version_cmp() {
    python3 -c "
import sys
def p(v):
    parts = v.lstrip('v').split('.')
    return tuple(int(x) for x in parts if x.isdigit())
a, b = p(sys.argv[1]), p(sys.argv[2])
print('newer' if a < b else 'older' if a > b else 'equal')
" "$1" "$2" 2>/dev/null || echo "unknown"
}

# ---- Core: check GitHub and download ----

do_check() {
    local current_version
    current_version=$(get_current_version)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    log "Checking for updates (current: $current_version)..."

    # Query GitHub releases API
    local release_json
    release_json=$(curl -fsS --max-time 30 \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$GITHUB_API" 2>/dev/null) || {
        err "Failed to query GitHub API"
        write_status "$now" "$current_version" "" false "[]" '"Failed to query GitHub API"'
        return 1
    }

    # Parse tag_name and assets with python3 (available in the container)
    local parsed
    parsed=$(echo "$release_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tag = data.get('tag_name', '')
print(tag)
for a in data.get('assets', []):
    print(a['name'] + '|' + a['browser_download_url'])
" 2>/dev/null) || {
        err "Failed to parse release JSON"
        write_status "$now" "$current_version" "" false "[]" '"Failed to parse release info"'
        return 1
    }

    local latest_version
    latest_version=$(echo "$parsed" | head -1)

    if [ -z "$latest_version" ]; then
        err "No release tag found"
        write_status "$now" "$current_version" "" false "[]" '"No release tag found"'
        return 1
    fi

    # Compare versions
    local cmp
    cmp=$(version_cmp "$current_version" "$latest_version")

    if [ "$cmp" != "newer" ]; then
        log "Up to date (current: $current_version, latest: $latest_version)"
        write_status "$now" "$current_version" "$latest_version" false "[]" "null"
        return 0
    fi

    log "New version available: $latest_version (current: $current_version)"

    # Download matching assets to staging
    # Use a temp file to avoid the pipe subshell issue with arrays.
    local assets_tmp
    assets_tmp=$(mktemp)
    echo "$parsed" | tail -n +2 > "$assets_tmp"

    local downloaded=0
    while IFS='|' read -r name url; do
        [ -z "$name" ] && continue
        for pattern in "${ASSET_PATTERNS[@]}"; do
            if echo "$name" | grep -qE "^${pattern}$"; then
                log "  Downloading $name..."
                # Download to a temp file first, then move on success
                local tmp_dl="$STAGING_DIR/.${name}.tmp"
                if curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" "$url" -o "$tmp_dl"; then
                    mv "$tmp_dl" "$STAGING_DIR/$name"
                    downloaded=$((downloaded + 1))
                else
                    err "  Failed to download $name"
                    rm -f "$tmp_dl"
                fi
                break
            fi
        done
    done < "$assets_tmp"
    rm -f "$assets_tmp"

    # Build staged artifacts JSON from what's actually in the staging dir
    local staged_json
    staged_json=$(ls -1 "$STAGING_DIR" 2>/dev/null | python3 -c "
import json, sys
print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))
" 2>/dev/null || echo "[]")

    write_status "$now" "$current_version" "$latest_version" true "$staged_json" "null"
    log "Staged $downloaded artifact(s). Restart the container to apply."
    return 0
}

# ---- Apply staged updates (called by entrypoint on startup) ----

do_apply() {
    if [ ! -d "$STAGING_DIR" ] || [ -z "$(ls -A "$STAGING_DIR" 2>/dev/null)" ]; then
        return 0  # nothing staged
    fi

    log "Applying staged updates..."
    cd /home/akiba

    # Locate staged artifacts
    local daemon_zip fw_zip utils_jar
    daemon_zip=$(find "$STAGING_DIR" -name 'akiba_db_daemon-*.zip' 2>/dev/null | head -1)
    # Framework zip may be named akiba-*.zip or akiba_framework-*.zip
    fw_zip=$(find "$STAGING_DIR" \( -name 'akiba-*.zip' -o -name 'akiba_framework-*.zip' \) 2>/dev/null | head -1)
    utils_jar=$(find "$STAGING_DIR" -name 'amod-AkibaUtils-*.jar' 2>/dev/null | head -1)

    # --- Daemon ---
    if [ -n "$daemon_zip" ] && [ -f "$daemon_zip" ]; then
        local dd
        dd=$(basename "$daemon_zip" .zip)
        log "  Updating daemon: $dd"
        rm -rf "/home/akiba/$dd"
        unzip -q -o "$daemon_zip" -d /home/akiba
        rm -rf akiba_db_daemon_old
        [ -d akiba_db_daemon ] && mv akiba_db_daemon akiba_db_daemon_old
        mv "/home/akiba/$dd" akiba_db_daemon
        rm -rf akiba_db_daemon_old
    fi

    # --- Framework (preserve ghidra_projects/) ---
    if [ -n "$fw_zip" ] && [ -f "$fw_zip" ]; then
        local fd
        fd=$(basename "$fw_zip" .zip)
        log "  Updating framework: $fd"
        rm -rf "/home/akiba/$fd"
        unzip -q -o "$fw_zip" -d /home/akiba
        rm -rf akiba_framework_old ghidra_projects_rescue
        if [ -d akiba_framework ]; then
            if [ -d akiba_framework/ghidra_projects ]; then
                mv akiba_framework/ghidra_projects ghidra_projects_rescue
            fi
            mv akiba_framework akiba_framework_old
        fi
        mv "/home/akiba/$fd" akiba_framework
        if [ -d ghidra_projects_rescue ]; then
            mv ghidra_projects_rescue akiba_framework/ghidra_projects
        fi
        rm -rf akiba_framework_old
    fi

    # --- Util mod ---
    if [ -n "$utils_jar" ] && [ -f "$utils_jar" ]; then
        log "  Updating util mod: $(basename "$utils_jar")"
        mkdir -p akiba_framework/modules
        rm -f akiba_framework/modules/amod-AkibaUtils-*.jar
        cp "$utils_jar" akiba_framework/modules/
    fi

    # Update version file from status.json
    local new_version
    new_version=$(python3 -c "
import json
try:
    data = json.load(open('$STATUS_FILE'))
    print(data.get('latestVersion', ''))
except: print('')
" 2>/dev/null || echo "")
    if [ -n "$new_version" ]; then
        echo "$new_version" > "$VERSION_FILE"
        log "  Version updated to $new_version"
    fi

    # Clean up staging
    rm -rf "$STAGING_DIR"/*
    log "Updates applied successfully."
}

# ---- Main ----

case "${1:-}" in
    --daemon)
        log "Starting daemon mode (check every $((CHECK_INTERVAL_SECONDS / 3600))h)..."
        # Run an initial check shortly after startup, then loop.
        sleep 30
        while true; do
            do_check || true
            sleep "$CHECK_INTERVAL_SECONDS"
        done
        ;;
    --check)
        do_check
        ;;
    --apply)
        do_apply
        ;;
    *)
        echo "Usage: auto_update.sh [--daemon|--check|--apply]"
        echo "  --daemon   Background periodic checker (every 3 days)"
        echo "  --check    One-shot check + download (manual trigger)"
        echo "  --apply    Apply staged updates (entrypoint startup)"
        exit 1
        ;;
esac
