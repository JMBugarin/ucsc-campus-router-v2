#!/bin/sh
# Copies the campus data the app ships from data/ into app/assets/data/. Run after changing data/.
set -e
cd "$(dirname "$0")/.."
for f in buildings.json rooms.json search_aliases.json holidays.json; do
  cp "data/$f" "app/assets/data/$f"
done
