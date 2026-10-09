#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")" && pwd)"
godot_bin="/Applications/Godot.app/Contents/MacOS/Godot"
if [[ ! -x "$godot_bin" ]]; then
  print "No se encontró Godot en /Applications/Godot.app. Abre project.godot desde Godot 4.5 o posterior."
  exit 1
fi
exec "$godot_bin" --path "$project_dir"
