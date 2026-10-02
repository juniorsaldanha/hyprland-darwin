#!/bin/sh
# HYPR_PMSET_OUTPUT: test hook, replaces `pmset -g batt`
batt="${HYPR_PMSET_OUTPUT:-$(pmset -g batt)}"
pct="$(printf '%s' "$batt" | grep -o '[0-9]\{1,3\}%' | head -1 | tr -d '%')"
if [ -z "$pct" ]; then
    echo '{"hidden":true}' # no battery (desktop Mac)
    exit 0
fi
if [ "$pct" -ge 90 ]; then icon='\uF240'; color=0xff40a02b
elif [ "$pct" -ge 60 ]; then icon='\uF241'; color=0xff179299
elif [ "$pct" -ge 30 ]; then icon='\uF242'; color=0xfffe640b
elif [ "$pct" -ge 10 ]; then icon='\uF243'; color=0xffdf8e1d
else icon='\uF244'; color=0xffd20f39
fi
case "$batt" in *"AC Power"*) icon='\uDB80\uDC84' ;; esac
printf '{"hidden":false,"icon":"%s","icon_color":"%s","label":"%s%%"}\n' "$icon" "$color" "$pct"
