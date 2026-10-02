#!/bin/sh
# Two `top` samples 1 s apart; the first has no delta, so take the last. user + sys, 0-100.
line="$(top -l 2 -n 0 -s 1 2>/dev/null | awk '/CPU usage/ { l = $0 } END { print l }')"
pct="$(printf '%s' "$line" | awk -F'[% ,]+' '/CPU usage/ { v = $3 + $5; if (v < 0) v = 0; if (v > 100) v = 100; printf "%.0f", v }')"
case "$pct" in '' | *[!0-9]*) pct=0 ;; esac
printf '{"icon":"\\uF4BC","label":"%s%%"}\n' "$pct"
