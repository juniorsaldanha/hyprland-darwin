#!/bin/sh
# Free % of the Data volume (same as btop)
mount_point="/System/Volumes/Data"
[ -d "$mount_point" ] || mount_point="/"
pct="$(/bin/df -k "$mount_point" | /usr/bin/awk 'NR==2 && $2 > 0 { printf "%d", $4 * 100 / $2 + 0.5 }')"
case "$pct" in '' | *[!0-9]*) pct="?" ;; esac
printf '{"icon":"\\uDB80\\uDECA","label":"%s%%"}\n' "$pct"
