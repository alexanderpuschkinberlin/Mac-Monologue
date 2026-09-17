#!/usr/bin/env bash
# Render the static design concepts. Requires Chromium; no application or camera access.
set -euo pipefail
plan_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
render_profile="$(mktemp -d /tmp/monologue-render.XXXXXX)"
trap 'rm -rf -- "$render_profile"' EXIT
mkdir -p "$plan_dir/screenshots"
for entry in 'ready 01' 'recording 02' 'paused 03' 'finished 04'; do
  read -r state number <<< "$entry"
  chromium --headless --disable-gpu --hide-scrollbars \
    --user-data-dir="$render_profile" --window-size=1040,830 \
    --screenshot="$plan_dir/screenshots/$number-$state.png" \
    "file://$plan_dir/mockups.html?state=$state"
done
