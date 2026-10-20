#!/bin/sh
# Disable or re-enable the Apple services listed in services.txt.
# Usage: sudo ./services.sh disable|enable|status   (disable/enable need SIP off to persist)
set -u
cd "$(dirname "$0")"
action="${1:-status}"
uid="${SUDO_UID:-$(id -u)}"

grep -vE '^\s*(#|$)' services.txt | while IFS="$(printf '\t')" read -r domain label; do
  case "$domain" in
    gui|user) target="$domain/$uid" ;;
    *) target="system" ;;
  esac
  case "$action" in
    disable)
      launchctl disable "$target/$label"
      launchctl bootout "$target/$label" 2>/dev/null
      echo "disabled $target/$label" ;;
    enable)
      launchctl enable "$target/$label"
      echo "enabled  $target/$label (takes effect after reboot)" ;;
    status)
      state=$(launchctl print-disabled "$target" | awk -v l="\"$label\"" '$1==l{print $3}')
      if launchctl print "$target/$label" >/dev/null 2>&1; then loaded=loaded; else loaded=-; fi
      printf '%-9s %-7s %s/%s\n' "${state:-enabled}" "$loaded" "$target" "$label" ;;
    *) echo "usage: $0 disable|enable|status" >&2; exit 1 ;;
  esac
done
