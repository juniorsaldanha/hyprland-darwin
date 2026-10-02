#!/bin/sh
# The volume event carries the level; otherwise (first run, hourly refresh) ask macOS
level="$(printf '%s' "$HYPR_EVENT_JSON" | sed -n 's/.*"level":\([0-9]*\).*/\1/p')"
[ -z "$level" ] && level="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
case "$level" in '' | *[!0-9]*) level=0 ;; esac
if [ "$level" -ge 60 ]; then icon='\uDB81\uDD7E'
elif [ "$level" -ge 30 ]; then icon='\uDB81\uDD80'
elif [ "$level" -ge 1 ]; then icon='\uDB81\uDD7F'
else icon='\uDB81\uDD81'
fi
printf '{"icon":"%s","label":"%s%%"}\n' "$icon" "$level"
