#!/bin/sh
# Exercise the installed command with the PATH used by the scheduled tool check.
set -eu
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
PATH="$root:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH
annotate --help >/dev/null
# A tiny PPM fixture uses no external image library to create the input.
printf 'P3\n200 100\n255\n' > "$tmp/input.ppm"
awk 'BEGIN { for (i=0; i<20000; i++) print "255 255 255" }' >> "$tmp/input.ppm"
annotate "$tmp/input.ppm" --box 10,10,50,40 --label 70,20:Test -o "$tmp/output.png"
[ "$(annotate "$tmp/output.png" --info)" = '200x100' ]
printf 'annotate: ok\n'
