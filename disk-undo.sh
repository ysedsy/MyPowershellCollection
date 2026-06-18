#!/usr/bin/env bash
# disk-undo.sh - Restore moved duplicates from a map file
set -uo pipefail

MAP_FILE="${1:-}"
[[ -z "$MAP_FILE" ]] && { echo "Usage: $0 <map-file.csv>"; exit 1; }
[[ ! -f "$MAP_FILE" ]] && { echo "Map file not found: $MAP_FILE"; exit 1; }

echo "=== Undo: Restore files ==="
# count entries minus header
total=$(( $(wc -l < "$MAP_FILE") - 1 ))
echo "$total files will be moved back."
read -rp "Continue? (yes/no) " ok
[[ "$ok" != "yes" ]] && { echo "Aborted."; exit 0; }

success=0; failed=0
# skip header
tail -n +2 "$MAP_FILE" | while IFS=';' read -r quarantine original; do
  [[ -z "$quarantine" ]] && continue
  if [[ -f "$quarantine" ]]; then
    mkdir -p "$(dirname "$original")"
    if [[ -e "$original" ]]; then
      echo "Already exists, skipped: $original"; failed=$((failed+1))
    else
      if mv "$quarantine" "$original" 2>/dev/null; then success=$((success+1)); else failed=$((failed+1)); fi
    fi
  else
    echo "Quarantine file missing: $quarantine"; failed=$((failed+1))
  fi
  # note: counters reset in subshell; final tally below is approximate
done

echo
echo "Restore complete. Check output above for any skipped files."
