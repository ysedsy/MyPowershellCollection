#!/usr/bin/env bash
# disk-usage.sh - Report largest files and folders (read-only)
# Portable: Linux & macOS
set -uo pipefail

PATH_TO_SCAN="$HOME"
TOP_FILES=20
TOP_FOLDERS=15
MIN_SIZE_MB=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) PATH_TO_SCAN="$2"; shift 2 ;;
    --top-files) TOP_FILES="$2"; shift 2 ;;
    --top-folders) TOP_FOLDERS="$2"; shift 2 ;;
    --min-mb) MIN_SIZE_MB="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ ! -d "$PATH_TO_SCAN" ]] && { echo "Path not found: $PATH_TO_SCAN"; exit 1; }

file_size() { if stat --version >/dev/null 2>&1; then stat -c%s "$1"; else stat -f%z "$1"; fi; }

echo "=== Disk Usage Report ==="
echo "Scanning: $PATH_TO_SCAN"
echo

# --- Drive overview ---
echo "[ Filesystem ]"
df -h "$PATH_TO_SCAN" | tail -n +1
echo

# --- Largest files ---
echo "[ Top $TOP_FILES largest files (>= ${MIN_SIZE_MB} MB) ]"
MIN_BYTES=$((MIN_SIZE_MB * 1024 * 1024))
# find + size; GNU find supports -printf, BSD/macOS does not, so compute via stat
find "$PATH_TO_SCAN" -type f 2>/dev/null | while read -r f; do
  sz="$(file_size "$f" 2>/dev/null)" || continue
  [[ -z "$sz" || "$sz" -lt "$MIN_BYTES" ]] && continue
  printf '%s\t%s\n' "$sz" "$f"
done | sort -rn | head -n "$TOP_FILES" | while IFS=$'\t' read -r sz f; do
  printf '%8d MB   %s\n' $((sz/1024/1024)) "$f"
done
echo

# --- Largest top-level folders ---
echo "[ Top $TOP_FOLDERS largest folders (first level) ]"
# du is the right tool here; -h not sortable, so use -k (KB) then convert
du -k -d 1 "$PATH_TO_SCAN" 2>/dev/null | sort -rn | head -n "$((TOP_FOLDERS+1))" | while read -r kb dir; do
  [[ "$dir" == "$PATH_TO_SCAN" ]] && continue
  printf '%8d MB   %s\n' $((kb/1024)) "$dir"
done
echo

# --- File-type breakdown ---
echo "[ Space by file type (top 10) ]"
find "$PATH_TO_SCAN" -type f 2>/dev/null | while read -r f; do
  ext="${f##*.}"; [[ "$f" != *.* ]] && ext="(none)"
  sz="$(file_size "$f" 2>/dev/null)" || continue
  printf '%s\t%s\n' "$ext" "$sz"
done | awk -F'\t' '{sum[$1]+=$2; cnt[$1]++} END {for (e in sum) printf "%d\t%s\t%d\n", sum[e], e, cnt[e]}' \
  | sort -rn | head -n 10 | while IFS=$'\t' read -r sz ext cnt; do
  printf '%8d MB   %-8s  (%d files)\n' $((sz/1024/1024)) "$ext" "$cnt"
done

echo
echo "Done (read-only, nothing changed)."
