#!/usr/bin/env bash
# disk-usage-gui.sh - List largest files, select to delete, send to Trash
# Recoverable: files go to Trash, not permanent rm
# GUI picker via zenity (Linux) / osascript (macOS); falls back to terminal.
set -uo pipefail

PATH_TO_SCAN="$HOME"
TOP_FILES=100
MIN_SIZE_MB=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) PATH_TO_SCAN="$2"; shift 2 ;;
    --top-files) TOP_FILES="$2"; shift 2 ;;
    --min-mb) MIN_SIZE_MB="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ ! -d "$PATH_TO_SCAN" ]] && { echo "Path not found: $PATH_TO_SCAN"; exit 1; }

file_size() { if stat --version >/dev/null 2>&1; then stat -c%s "$1"; else stat -f%z "$1"; fi; }

OS="$(uname -s)"

# --- Send a file to Trash (recoverable), platform-aware ---
trash_file() {
  local f="$1"
  if command -v trash-put >/dev/null 2>&1; then         # Linux: trash-cli
    trash-put "$f"
  elif command -v gio >/dev/null 2>&1; then              # Linux: GNOME gio
    gio trash "$f"
  elif [[ "$OS" == "Darwin" ]]; then                     # macOS: AppleScript -> Trash
    osascript -e "tell application \"Finder\" to delete POSIX file \"$f\"" >/dev/null
  else
    return 1
  fi
}

echo "Scanning $PATH_TO_SCAN ..."
MIN_BYTES=$((MIN_SIZE_MB * 1024 * 1024))

# Build list: "<MB> MB\t<path>"
TMP="$(mktemp)"
find "$PATH_TO_SCAN" -type f 2>/dev/null | while read -r f; do
  sz="$(file_size "$f" 2>/dev/null)" || continue
  [[ -z "$sz" || "$sz" -lt "$MIN_BYTES" ]] && continue
  printf '%s\t%s\n' "$sz" "$f"
done | sort -rn | head -n "$TOP_FILES" | while IFS=$'\t' read -r sz f; do
  printf '%d MB\t%s\n' $((sz/1024/1024)) "$f"
done > "$TMP"

if [[ ! -s "$TMP" ]]; then
  echo "No files >= ${MIN_SIZE_MB} MB found under $PATH_TO_SCAN."
  rm -f "$TMP"; exit 0
fi

SELECTED=()

# --- GUI path: zenity checklist (Linux) ---
if command -v zenity >/dev/null 2>&1; then
  while true; do
    args=()
    while IFS=$'\t' read -r size path; do
      args+=(FALSE "$size" "$path")
    done < "$TMP"
    chosen="$(zenity --list --checklist \
      --title="Disk Usage - check files to delete (Trash)" \
      --text="Tick files to delete. Or tick ONE and choose Preview to open it first." \
      --column="Sel" --column="Size" --column="Path" \
      --width=900 --height=600 --separator=$'\n' \
      --ok-label="Delete selected" --extra-button="Preview selected" \
      "${args[@]}" 2>/dev/null)"
    rc=$?
    # rc=0 -> Delete pressed; chosen holds ticked rows
    # "Preview selected" comes back as the literal button text on stdout
    if [[ "$chosen" == "Preview selected" ]]; then
      # zenity quirk: extra-button text replaces the row output, so ask which to open
      preview="$(zenity --list --title="Preview" --text="Pick one file to open" \
        --column="Path" $(cut -f2 "$TMP") --width=900 --height=500 2>/dev/null)"
      [[ -n "$preview" ]] && xdg-open "$preview" >/dev/null 2>&1 &
      continue   # reshow the checklist after previewing
    fi
    [[ $rc -ne 0 ]] && { rm -f "$TMP"; exit 0; }   # cancelled
    [[ -n "$chosen" ]] && mapfile -t SELECTED <<< "$chosen"
    break
  done
# --- Terminal fallback: numbered multi-select ---
else
  echo
  echo "No GUI picker found (install 'zenity' on Linux for a dialog). Terminal mode:"
  echo
  mapfile -t ROWS < "$TMP"
  for i in "${!ROWS[@]}"; do
    printf '  [%d] %s\n' "$((i+1))" "${ROWS[$i]}"
  done
  echo
  echo "Enter numbers to delete, space-separated (e.g. 1 3 5), or blank to cancel:"
  read -r picks
  for n in $picks; do
    idx=$((n-1))
    [[ $idx -ge 0 && $idx -lt ${#ROWS[@]} ]] && SELECTED+=("$(echo "${ROWS[$idx]}" | cut -f2)")
  done
fi

rm -f "$TMP"

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "Nothing selected."; exit 0
fi

echo
echo "${#SELECTED[@]} file(s) selected:"
printf '    %s\n' "${SELECTED[@]}"
read -rp "Send these to Trash? (yes/no) " ok
[[ "$ok" != "yes" ]] && { echo "Aborted."; exit 0; }

done_count=0
for f in "${SELECTED[@]}"; do
  [[ -z "$f" || ! -e "$f" ]] && continue
  if trash_file "$f"; then
    done_count=$((done_count+1))
  else
    echo "Failed (no trash tool available): $f"
  fi
done

echo "Sent $done_count file(s) to Trash."
