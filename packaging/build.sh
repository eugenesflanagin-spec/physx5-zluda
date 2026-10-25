#!/bin/bash
# SPDX-License-Identifier: MIT  (Copyright (c) 2026 Eugene Flanagin; see LICENSE)
# Build the package in a fresh Arch Linux container, so the result does not depend on this
# PC's compiler flags and runs on any x86-64 Arch system.
#   usage: packaging/build.sh OUTDIR        (CONTAINER=podman to use podman instead of docker)
set -euo pipefail
out=$(realpath -m "${1:?usage: packaging/build.sh OUTDIR}")
repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
"${CONTAINER:-docker}" run --rm -v "$repo:/src:ro" -v "$out:/out" \
  docker.io/library/archlinux:base-devel bash /src/packaging/build-in-container.sh
