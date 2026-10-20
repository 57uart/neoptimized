#!/bin/sh
# Add or remove the Santa silent-block rules listed in santa-rules.txt.
# Usage: sudo ./santa-rules.sh apply|remove
set -u
cd "$(dirname "$0")"
action="${1:-}"
santactl=/usr/local/bin/santactl
[ -x "$santactl" ] || santactl=/Applications/Santa.app/Contents/MacOS/santactl

grep -vE '^\s*(#|$)' santa-rules.txt | while read -r id; do
  case "$action" in
    apply)  "$santactl" rule --silent-block --signingid --identifier "$id" --comment neoptimized ;;
    remove) "$santactl" rule --remove --signingid --identifier "$id" ;;
    *) echo "usage: $0 apply|remove" >&2; exit 1 ;;
  esac
done
