#!/bin/sh
# "Device Utilization %" from IOKit (Activity Monitor's GPU History source)
pct="$(/usr/sbin/ioreg -r -d 1 -c IOAccelerator | /usr/bin/awk -F'"Device Utilization %"=' 'NF > 1 { split($2, a, /[^0-9]/); print a[1]; exit }')"
case "$pct" in '' | *[!0-9]*) pct=0 ;; esac
printf '{"icon":"\\uDB82\\uDCAE","label":"%s%%"}\n' "$pct"
