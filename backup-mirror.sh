#!/usr/bin/env bash
# backup-mirror.sh - Mirror folders to a backup destination (rsync)
# Portable: Linux & macOS (rsync ships with both)
set -uo pipefail

SOURCES=("$HOME/Documents" "$HOME/Pictures")
DESTINATION=""
MIRROR=0
RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DESTINATION="$2"; shift 2 ;;
    --mirror) MIRROR=1; shift ;;
    --run) RUN=1; shift ;;
    --sources) shift; SOURCES=(); while [[ $# -gt 0 && "$1" != --* ]]; do SOURCES+=("$1"); shift; done ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ -z "$DESTINATION" ]] && { echo "Usage: $0 --dest <path> [--sources ...] [--mirror] [--run]"; exit 1; }

LOG_DIR="$HOME/_BackupLogs"
LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

echo "=== Backup Mirror ==="
if [[ ! -d "$DESTINATION" ]]; then
  echo "Destination not found: $DESTINATION"
  read -rp "Create it? (yes/no) " m
  [[ "$m" == "yes" ]] && mkdir -p "$DESTINATION" || { echo "Aborted."; exit 0; }
fi

VALID=()
for s in "${SOURCES[@]}"; do [[ -d "$s" ]] && VALID+=("$s"); done
[[ ${#VALID[@]} -eq 0 ]] && { echo "No valid source folders."; exit 1; }

echo "Sources:"; printf '    %s\n' "${VALID[@]}"
echo "Destination: $DESTINATION"
echo "Mode: $([[ $MIRROR -eq 1 ]] && echo 'MIRROR (deletes extras in dest)' || echo 'COPY (adds/updates only)')"
echo "Run:  $([[ $RUN -eq 1 ]] && echo 'LIVE' || echo 'DRY-RUN (nothing written)')"
echo

# rsync flags:
#  -a archive (perms, times, symlinks), -h human, --stats summary
#  -n dry-run, --delete = mirror, --log-file logging
RSYNC_OPTS=(-a -h --stats --log-file="$LOG_FILE")
[[ $RUN -eq 0 ]] && RSYNC_OPTS+=(-n)
[[ $MIRROR -eq 1 ]] && RSYNC_OPTS+=(--delete)

if [[ $MIRROR -eq 1 && $RUN -eq 1 ]]; then
  echo "WARNING: Mirror mode DELETES files in the destination not present in source."
  read -rp "Type 'MIRROR' to confirm: " c
  [[ "$c" != "MIRROR" ]] && { echo "Aborted."; exit 0; }
fi

for src in "${VALID[@]}"; do
  leaf="$(basename "$src")"
  dest="$DESTINATION/$leaf"
  mkdir -p "$dest"
  echo "--- $src/  ->  $dest/ ---"
  # trailing slash on source = copy contents into dest
  rsync "${RSYNC_OPTS[@]}" "$src/" "$dest/"
done

echo
echo "Done. Log: $LOG_FILE"
[[ $RUN -eq 0 ]] && echo "This was a DRY-RUN. Add --run to copy for real."
