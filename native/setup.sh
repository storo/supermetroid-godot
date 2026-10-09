#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sh "$project_dir/tools/native_probe/setup.sh"
bindings_dir="$project_dir/third_party/godot-cpp"
revision=e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
if [ ! -d "$bindings_dir/.git" ]; then
  mkdir -p "$project_dir/third_party"
  git clone --no-checkout --filter=blob:none https://github.com/godotengine/godot-cpp.git "$bindings_dir"
fi
if [ "$(git -C "$bindings_dir" rev-parse HEAD 2>/dev/null || true)" != "$revision" ]; then
  git -C "$bindings_dir" fetch --depth 1 origin "$revision"
  git -C "$bindings_dir" checkout --detach "$revision"
fi
cmake -S "$project_dir/native" -B "$project_dir/native/build" -DCMAKE_BUILD_TYPE=Release
printf '%s\n' '*' > "$project_dir/native/build/.gdignore"
cmake --build "$project_dir/native/build" --parallel 4
