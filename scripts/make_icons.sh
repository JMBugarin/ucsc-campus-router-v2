#!/bin/sh
# Redraws the app icon and launch image (UCSC blue and gold) into the iOS and Android projects.
# usage: scripts/make_icons.sh   (macOS: needs swift and sips)
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swift "$root/scripts/make_icon.swift" "$tmp/icon.png" "$tmp/launch.png"

resize() { sips -z "$2" "$2" "$1" --out "$3" >/dev/null; }

icons="$root/app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for spec in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 29x29@3x:87 40x40@1x:40 40x40@2x:80 \
            40x40@3x:120 60x60@2x:120 60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 1024x1024@1x:1024; do
  resize "$tmp/icon.png" "${spec##*:}" "$icons/Icon-App-${spec%%:*}.png"
done

launch="$root/app/ios/Runner/Assets.xcassets/LaunchImage.imageset"
resize "$tmp/launch.png" 160 "$launch/LaunchImage.png"
resize "$tmp/launch.png" 320 "$launch/LaunchImage@2x.png"
resize "$tmp/launch.png" 480 "$launch/LaunchImage@3x.png"

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  resize "$tmp/icon.png" "${spec##*:}" "$root/app/android/app/src/main/res/mipmap-${spec%%:*}/ic_launcher.png"
done
echo "icons written"
