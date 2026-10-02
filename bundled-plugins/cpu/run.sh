#!/bin/sh
# user + sys over 1 s, from the second `iostat` sample (the first is the average since boot).
# ~1.0 s and almost no CPU; `top -l 2 -s 1` took ~1.7 s under load and hit the 2 s interval timeout.
pct="$(iostat -n 0 -w 1 -c 2 | awk 'END { v = $1 + $2; if (v < 0) v = 0; if (v > 100) v = 100; printf "%d", v }')"
case "$pct" in '' | *[!0-9]*) pct=0 ;; esac
printf '{"icon":"\\uF4BC","label":"%s%%"}\n' "$pct"
