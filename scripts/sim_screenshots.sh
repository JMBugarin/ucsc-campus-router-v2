#!/bin/sh
# Watches a directory for ".want-<name>" files that the integration tests create, takes a
# screenshot of the booted simulator for each, and removes the request.
# usage: scripts/sim_screenshots.sh docs/screenshots
dir="${1:?directory}"
mkdir -p "$dir"
while true; do
  for req in "$dir"/.want-*; do
    [ -e "$req" ] || continue
    name="${req##*/.want-}"
    xcrun simctl io booted screenshot "$dir/$name.png" >/dev/null 2>&1
    rm -f "$req"
  done
  sleep 0.2
done
