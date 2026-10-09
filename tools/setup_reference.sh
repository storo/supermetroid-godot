#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
reference_dir="$project_dir/tools/reference_disassembly"
revision=7af131ebc328359e852e923603163a329c7aa7af
if [ ! -d "$reference_dir/.git" ]; then
  git clone --no-checkout --filter=blob:none https://github.com/InsaneFirebat/sm_disassembly.git "$reference_dir"
fi
if [ "$(git -C "$reference_dir" rev-parse HEAD 2>/dev/null || true)" != "$revision" ]; then
  git -C "$reference_dir" fetch --depth 1 origin "$revision"
  git -C "$reference_dir" checkout --detach "$revision"
fi
