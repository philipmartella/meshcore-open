#!/usr/bin/env bash
#
# Launch the meshcore-open Linux desktop build with the two things WSL2 needs:
#
#   1. A real locale  — WSL defaults to C.UTF-8, which Flutter localization
#      treats as unknown and falls back to Bulgarian. en_US.utf8 -> English.
#   2. GPU rendering   — OPT-IN, see below.
#
# GPU (--gpu): GALLIUM_DRIVER=d3d12 routes GL through the RTX 5060 via WSL's
# /dev/dxg passthrough, instead of Mesa's llvmpipe software rasterizer. It is
# noticeably smoother for vector tiles, which rasterize on the CPU otherwise.
#
# It is NOT the default because that passthrough is unreliable under sustained
# load. Observed: panning a map with a route drawn produced
#     misc dxg: dxgk: dxgkio_escape: Ioctl failed: -75
# in dmesg, after which the GL context was gone — the window vanished while the
# process lingered, with no crash, no OOM and a clean exit. A slower map beats
# one that disappears, so software rendering is the default and the GPU is
# something you ask for.
#
# Usage:  ./run-linux.sh            # software rendering (stable)
#         ./run-linux.sh --gpu      # d3d12 via /dev/dxg (faster, can drop out)
#         ./run-linux.sh --debug    # `flutter run -d linux`
set -euo pipefail

cd "$(dirname "$0")"

export LANG=en_US.utf8
export LC_ALL=en_US.utf8

if [[ "${1:-}" == "--gpu" ]]; then
  export GALLIUM_DRIVER=d3d12
  echo "GPU rendering via d3d12 — if the window disappears, check:" >&2
  echo "  dmesg | grep 'misc dxg'" >&2
  shift
fi

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
