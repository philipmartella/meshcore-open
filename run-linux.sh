#!/usr/bin/env bash
#
# Launch the meshcore-open Linux desktop build with the two things WSL2 needs:
#
#   1. A real locale  — WSL defaults to C.UTF-8, which Flutter localization
#      treats as unknown and falls back to Bulgarian. en_US.utf8 -> English.
#   2. GPU rendering   — without GALLIUM_DRIVER=d3d12, Mesa falls back to the
#      llvmpipe software rasterizer. On this box d3d12 routes GL through the
#      RTX 5060 via /dev/dxg (verify with: GALLIUM_DRIVER=d3d12 glxinfo -B).
#
# Vector-tile rendering is CPU-heavy on the Canvas (Skia) path, so the GPU
# flag matters for smooth pan/zoom. Falls back cleanly to llvmpipe if d3d12
# isn't present, so this is safe to run anywhere.
#
# Usage:  ./run-linux.sh            # runs the release bundle
#         ./run-linux.sh --debug    # runs `flutter run -d linux` instead
set -euo pipefail

cd "$(dirname "$0")"

export LANG=en_US.utf8
export LC_ALL=en_US.utf8
export GALLIUM_DRIVER=d3d12

if [[ "${1:-}" == "--debug" ]]; then
  exec ~/flutter/bin/flutter run -d linux
fi

BUNDLE=build/linux/x64/release/bundle/meshcore_open
if [[ ! -x "$BUNDLE" ]]; then
  echo "Release bundle not found at $BUNDLE" >&2
  echo "Build it first:  ~/flutter/bin/flutter build linux --release" >&2
  exit 1
fi

exec "$BUNDLE"
