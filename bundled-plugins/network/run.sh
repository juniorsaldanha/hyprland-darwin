#!/bin/sh
iface="$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/ { print $2; exit }')"
wifi_iface="$(/usr/sbin/networksetup -listallhardwareports | /usr/bin/awk '/Wi-Fi/ { getline; print $2; exit }')"
ip="$([ -n "$iface" ] && /usr/sbin/ipconfig getifaddr "$iface")"
if [ -z "$ip" ]; then printf '{"icon":"\\uDB81\\uDDAA","label":"offline"}\n'
elif [ "$iface" = "$wifi_iface" ]; then printf '{"icon":"\\uDB81\\uDDA9","label":"%s"}\n' "$ip"
else printf '{"icon":"\\uDB80\\uDE00","label":"%s"}\n' "$ip"
fi
