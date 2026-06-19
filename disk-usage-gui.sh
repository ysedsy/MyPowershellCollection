#!/usr/bin/env bash
# disk-usage-gui.sh - Largest files, regex filter, delete to Trash, auto-rescan
# Recoverable: files go to Trash. GUI via zenity (Linux) / osascript (macOS), terminal fallback.
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
MIN_BYTES=$((MIN_SIZE_MB * 1024 * 1024))

trash_file() {
  local f="$1"
  if command -v trash-put >/dev/null 2>&1; then trash-put "$f"
  elif command -v gio >/dev/null 2>&1; then gio trash "$f"
  elif [[ "$OS" == "Darwin" ]]; then
    osascript -e "tell application \"Finder\" to delete POSIX file \"$f\"" >/dev/null
  else return 1; fi
}

# Build the size-sorted list into $TMP. Applies optional regex ($1) on
# either full path or basename (controlled by $MATCH_MODE: "path" | "name").
REGEX=".*"          # Default: match everything
MATCH_MODE="name"

build_list() {
  local tmp; tmp="$(mktemp)"
  find "$PATH_TO_SCAN" -type f 2>/dev/null | while read -r f; do
    sz="$(file_size "$f" 2>/dev/null)" || continue
    [[ -z "$sz" || "$sz" -lt "$MIN_BYTES" ]] && continue
    # regex filter
    # regex filter (skip entirely if default ".*" -> matches everything)
    if [[ -n "$REGEX" && "$REGEX" != ".*" ]]; then
      if [[ "$MATCH_MODE" == "name" ]]; then target="$(basename "$f")"; else target="$f"; fi
      echo "$target" | grep -Eq "$REGEX" || continue
    fi
    printf '%s\t%s\n' "$sz" "$f"
  done | sort -rn | head -n "$TOP_FILES" | while IFS=$'\t' read -r sz f; do
    printf '%d MB\t%s\n' $((sz/1024/1024)) "$f"
  done > "$tmp"
  echo "$tmp"
}

prompt_regex() {
  # Ask for regex + mode. Returns via globals REGEX / MATCH_MODE.
  if command -v zenity >/dev/null 2>&1; then
    local r
    r="$(zenity --entry --title="Regex filter" \
      --text="Regex (blank = all). Current mode: $MATCH_MODE" 2>/dev/null)" || return 1
    REGEX="$r"
    local m
    m="$(zenity --list --radiolist --title="Match mode" --text="Apply regex to:" \
      --column="" --column="Mode" TRUE name FALSE path 2>/dev/null)" || true
    [[ -n "$m" ]] && MATCH_MODE="$m"
  else
    read -rp "Regex (blank = all) [$REGEX]: " r; REGEX="${r:-$REGEX}"
    read -rp "Match on (name/path) [$MATCH_MODE]: " m; MATCH_MODE="${m:-$MATCH_MODE}"
  fi
}

echo "Disk Usage GUI - $PATH_TO_SCAN (files >= ${MIN_SIZE_MB} MB)"

# === MAIN LOOP: scan -> select -> delete -> rescan ===
while true; do
  TMP="$(build_list)"
  if [[ ! -s "$TMP" ]]; then
    echo "No matching files >= ${MIN_SIZE_MB} MB (regex='$REGEX', mode=$MATCH_MODE)."
    rm -f "$TMP"
    # offer to change the filter instead of just quitting
    read -rp "Change regex filter? (yes/no) " c
    [[ "$c" == "yes" ]] && { prompt_regex; continue; } || exit 0
  fi

  SELECTED=()

  if command -v zenity >/dev/null 2>&1; then
    args=()
    while IFS=$'\t' read -r size path; do args+=(FALSE "$size" "$path"); done < "$TMP"
    chosen="$(zenity --list --checklist \
      --title="Disk Usage - regex='$REGEX' mode=$MATCH_MODE" \
      --text="Tick files to delete (Trash). Buttons below to filter or preview." \
      --column="Sel" --column="Size" --column="Path" \
      --width=950 --height=600 --separator=$'\n' \
      --ok-label="Delete selected" \
      --extra-button="Set regex" --extra-button="Preview" \
      "${args[@]}" 2>/dev/null)"
    rc=$?
    rm -f "$TMP"
    case "$chosen" in
      "Set regex") prompt_regex; continue ;;
      "Preview")
        preview="$(zenity --list --title="Preview" --text="Pick one file to open" \
          --column="Path" $(build_list | tee /tmp/_dl.$$ >/dev/null; cut -f2 /tmp/_dl.$$; rm -f /tmp/_dl.$$) \
          --width=900 --height=500 2>/dev/null)"
        [[ -n "$preview" ]] && xdg-open "$preview" >/dev/null 2>&1 &
        continue ;;
    esac
    [[ $rc -ne 0 ]] && exit 0
    [[ -n "$chosen" ]] && mapfile -t SELECTED <<< "$chosen"

  elif [[ "$OS" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
    list_items="$(cut -f2 "$TMP" | sed 's/"/\\"/g' | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')"
    rm -f "$TMP"
    chosen="$(osascript -e "set theList to {$list_items}" \
      -e 'set picked to choose from list theList with title "Disk Usage" with prompt "Select files to send to Trash (Cancel to change filter)" with multiple selections allowed' \
      -e 'set AppleScript'"'"'s text item delimiters to linefeed' \
      -e 'if picked is false then return "__CANCEL__"' \
      -e 'picked as text' 2>/dev/null)"
    if [[ "$chosen" == "__CANCEL__" || -z "$chosen" ]]; then
      read -rp "Change regex filter? (yes/no) " c
      [[ "$c" == "yes" ]] && { prompt_regex; continue; } || exit 0
    fi
    mapfile -t SELECTED <<< "$chosen"

  else
    echo; echo "Terminal mode (regex='$REGEX', mode=$MATCH_MODE):"; echo
    mapfile -t ROWS < "$TMP"; rm -f "$TMP"
    for i in "${!ROWS[@]}"; do printf '  [%d] %s\n' "$((i+1))" "${ROWS[$i]}"; done
    echo; echo "Numbers to delete (e.g. 1 3 5), 'r' to set regex, blank to quit:"
    read -r picks
    if [[ "$picks" == "r" ]]; then prompt_regex; continue; fi
    [[ -z "$picks" ]] && exit 0
    for n in $picks; do
      idx=$((n-1))
      [[ $idx -ge 0 && $idx -lt ${#ROWS[@]} ]] && SELECTED+=("$(echo "${ROWS[$idx]}" | cut -f2)")
    done
  fi

  if [[ ${#SELECTED[@]} -eq 0 ]]; then
    echo "Nothing selected."; continue   # back to top -> rescan
  fi

  echo; echo "${#SELECTED[@]} file(s) selected:"; printf '    %s\n' "${SELECTED[@]}"
  read -rp "Send to Trash? (yes/no) " ok
  [[ "$ok" != "yes" ]] && continue

  done_count=0
  for f in "${SELECTED[@]}"; do
    [[ -z "$f" || ! -e "$f" ]] && continue
    if trash_file "$f"; then done_count=$((done_count+1)); else echo "Failed: $f"; fi
  done
  echo "Sent $done_count file(s) to Trash. Rescanning..."
  # loop continues -> full rescan picks up the next-largest files
done
