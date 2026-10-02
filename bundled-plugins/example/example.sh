#!/bin/sh
# Reads one JSON event per line on stdin, writes widget updates as JSON lines on stdout.
# Exits when stdin closes (required for stream plugins).
echo '{"label":"ws ?"}'
while IFS= read -r event; do
    workspace=$(printf '%s' "$event" | sed -n 's/.*"focused":"\([^"]*\)".*/\1/p')
    [ -n "$workspace" ] && printf '{"label":"ws %s"}\n' "$workspace"
done
