#!/usr/bin/env bash
# disk-cleanup.sh - Clean up temp + find duplicates (full protection)
# Portable: Linux & macOS

set -uo pipefail

# --- Defaults ---
SCAN_PATHS=("$HOME/Downloads" "$HOME/Documents")
REMOVE=0
MAX_DUPLICATES=500
MIN_SIZE_KB=10

QUARANTINE="$HOME/_Duplicates_Quarantine"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$QUARANTINE/cleanup_$TS.log"
MAP_FILE="$QUARANTINE/undo_map_$TS.csv"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove) REMOVE=1; shift ;;
    --max) MAX_DUPLICATES="$2"; shift 2 ;;
    --min-kb) MIN_SIZE_KB="$2"; shift 2 ;;
    --paths) shift; SCAN_PATHS=(); while [[ $# -gt 0 && "$1" != --* ]]; do SCAN_PATHS+=("$1"); shift; done ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# === PROTECTION 1: Locked folders (prefixes) ===
PROTECTED=(
  "/bin" "/sbin" "/usr" "/etc" "/var" "/lib" "/lib64" "/boot" "/proc" "/sys" "/dev"
  "/System" "/Library" "/Applications" "/private"
  "$HOME/OneDrive" "$HOME/Dropbox" "$HOME/Library"
)
# === PROTECTION: locked folder names anywhere in path ===
LOCKED_NAMES=(".git" ".svn" "node_modules" ".Trash")
# === PROTECTION 2: locked extensions ===
LOCKED_EXT=("so" "dylib" "ko" "sys" "app" "kext" "sh" "bash" "ps1" "exe" "dll")

# --- Cross-platform helpers ---
file_size() { # bytes
  if stat --version >/dev/null 2>&1; then stat -c%s "$1"; else stat -f%z "$1"; fi
}
file_mtime() { # epoch seconds
  if stat --version >/dev/null 2>&1; then stat -c%Y "$1"; else stat -f%m "$1"; fi
}
file_hash() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else echo ""; fi
}
log() { echo "$(date +%H:%M:%S)  $1" >> "$LOG_FILE"; }

is_protected() {
  local p; p="$(cd "$1" 2>/dev/null && pwd || echo "$1")"
  local low; low="$(echo "$p" | tr '[:upper:]' '[:lower:]')"
  local g
  for g in "${PROTECTED[@]}"; do
    local gl; gl="$(echo "$g" | tr '[:upper:]' '[:lower:]')"
    [[ "$low" == "$gl" || "$low" == "$gl/"* ]] && return 0
  done
  local n
  for n in "${LOCKED_NAMES[@]}"; do
    case "/$p/" in */"$n"/*) return 0 ;; esac
  done
  return 1
}

ext_locked() {
  local e; e="$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')"
  [[ "$1" != *.* ]] && return 1
  local x
  for x in "${LOCKED_EXT[@]}"; do [[ "$e" == "$x" ]] && return 0; done
  return 1
}

echo "=== Disk Cleanup (full protection) ==="
mkdir -p "$QUARANTINE"
log "=== Cleanup started ==="

# --- Validate paths ---
VALID=()
for path in "${SCAN_PATHS[@]}"; do
  if is_protected "$path"; then
    echo "BLOCKED (protected): $path"; log "BLOCKED: $path"
  elif [[ ! -d "$path" ]]; then
    echo "Not found: $path"
  else
    VALID+=("$path")
  fi
done
[[ ${#VALID[@]} -eq 0 ]] && { echo "No valid paths. Aborting."; exit 1; }

# --- Whitelist confirmation ---
echo; echo "The following folders will be scanned:"
printf '    %s\n' "${VALID[@]}"
read -rp $'\nScan these folders? (yes/no) ' ok
[[ "$ok" != "yes" ]] && { echo "Aborted."; log "Aborted by user."; exit 0; }

# --- 1. Clean temp ---
echo; echo "[1] Cleaning temp files older than 1 day..."
find "${TMPDIR:-/tmp}" -type f -mtime +0 -delete 2>/dev/null || true
echo "Temp cleaned"; log "Temp cleaned"

# --- 2. Find duplicates ---
echo "[2] Searching for duplicates..."
MIN_BYTES=$((MIN_SIZE_KB * 1024))

# Collect eligible files (size<TAB>path), skipping symlinks via -type f
declare -a FILES=()
for path in "${VALID[@]}"; do
  while IFS= read -r -d '' f; do
    is_protected "$(dirname "$f")" && continue
    ext_locked "$f" && continue
    sz="$(file_size "$f")"
    [[ -z "$sz" || "$sz" -lt "$MIN_BYTES" ]] && continue
    FILES+=("$sz"$'\t'"$f")
  done < <(find "$path" -type f -print0 2>/dev/null)
done

# Group by size first (only hash files sharing a size)
declare -A SIZE_COUNT
for entry in "${FILES[@]}"; do
  sz="${entry%%$'\t'*}"
  SIZE_COUNT["$sz"]=$(( ${SIZE_COUNT["$sz"]:-0} + 1 ))
done

# Hash candidates, group by hash
declare -A HASH_FILES   # hash -> newline-separated paths
for entry in "${FILES[@]}"; do
  sz="${entry%%$'\t'*}"; f="${entry#*$'\t'}"
  [[ "${SIZE_COUNT[$sz]}" -lt 2 ]] && continue
  h="$(file_hash "$f")"
  [[ -z "$h" ]] && continue
  HASH_FILES["$h"]+="$f"$'\n'
done

# --- 3. Report ---
echo; echo "[3] Duplicates found:"
DUP_COUNT=0
SAVED_BYTES=0
DUP_GROUPS=()   # store hashes that have >1 file
for h in "${!HASH_FILES[@]}"; do
  mapfile -t group < <(printf '%s' "${HASH_FILES[$h]}" | sed '/^$/d')
  [[ ${#group[@]} -lt 2 ]] && continue
  DUP_GROUPS+=("$h")
  # sort by mtime ascending -> oldest is keeper
  sorted=$(for g in "${group[@]}"; do echo "$(file_mtime "$g")"$'\t'"$g"; done | sort -n | cut -f2-)
  mapfile -t sgroup <<< "$sorted"
  keeper="${sgroup[0]}"
  ksize="$(file_size "$keeper")"
  echo; printf '  Group (%d KB):\n' $((ksize/1024))
  echo "    KEEP:      $keeper"
  for ((i=1; i<${#sgroup[@]}; i++)); do
    echo "    DUPLICATE: ${sgroup[$i]}"
    DUP_COUNT=$((DUP_COUNT+1))
    SAVED_BYTES=$((SAVED_BYTES + ksize))
  done
done

echo; echo "Duplicates: $DUP_COUNT | Recoverable: ~$((SAVED_BYTES/1024/1024)) MB"
log "Found: $DUP_COUNT duplicates (~$((SAVED_BYTES/1024/1024)) MB)"
[[ $DUP_COUNT -eq 0 ]] && { echo "No duplicates."; exit 0; }

# === PROTECTION: count limit ===
if [[ $DUP_COUNT -gt $MAX_DUPLICATES ]]; then
  echo "STOP: $DUP_COUNT duplicates exceed limit ($MAX_DUPLICATES)."
  echo "Check scan paths or raise --max deliberately."
  log "ABORT: limit exceeded ($DUP_COUNT > $MAX_DUPLICATES)"
  exit 1
fi

# --- 4. Remove ---
if [[ $REMOVE -eq 0 ]]; then
  echo "Report only. To move: $0 --remove"
  exit 0
fi

read -rp "Move $DUP_COUNT duplicates to quarantine? (yes/no) " ans
[[ "$ans" != "yes" ]] && { echo "Aborted."; log "Move aborted."; exit 0; }

echo "Quarantine;Original" > "$MAP_FILE"
for h in "${DUP_GROUPS[@]}"; do
  mapfile -t group < <(printf '%s' "${HASH_FILES[$h]}" | sed '/^$/d')
  sorted=$(for g in "${group[@]}"; do echo "$(file_mtime "$g")"$'\t'"$g"; done | sort -n | cut -f2-)
  mapfile -t sgroup <<< "$sorted"
  keeper="${sgroup[0]}"; khash="$(file_hash "$keeper")"
  for ((i=1; i<${#sgroup[@]}; i++)); do
    f="${sgroup[$i]}"
    is_protected "$(dirname "$f")" && continue
    ext_locked "$f" && continue
    # HASH RE-CHECK: skip if changed since scan, or keeper changed
    [[ "$(file_hash "$f")" != "$h" ]] && { echo "SKIPPED (changed): $f"; log "SKIPPED (hash mismatch): $f"; continue; }
    [[ "$(file_hash "$keeper")" != "$khash" ]] && { echo "SKIPPED (keeper changed): $keeper"; log "SKIPPED (keeper changed): $keeper"; continue; }
    dest="$QUARANTINE/${RANDOM}_$(basename "$f")"
    if mv "$f" "$dest" 2>/dev/null; then
      echo "$dest;$f" >> "$MAP_FILE"
      log "MOVED: $f  ->  $dest"
    fi
  done
done

echo; echo "Done. Moved to: $QUARANTINE"
echo "Log:  $LOG_FILE"
echo "Undo: ./disk-undo.sh \"$MAP_FILE\""
log "=== Cleanup finished ==="
