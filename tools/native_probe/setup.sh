#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
reference_dir="$project_dir/tools/reference_native"
revision=578f90b3cc49557bb70060ad033bb90b8cf8ac50
if [ ! -d "$reference_dir/.git" ]; then
  git clone --no-checkout --filter=blob:none https://github.com/snesrev/sm.git "$reference_dir"
fi
if [ "$(git -C "$reference_dir" rev-parse HEAD 2>/dev/null || true)" != "$revision" ]; then
  git -C "$reference_dir" fetch --depth 1 origin "$revision"
  git -C "$reference_dir" checkout --detach "$revision"
fi
printf '%s\n' '*' > "$reference_dir/.gdignore"
