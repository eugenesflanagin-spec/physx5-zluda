#!/bin/bash
# SPDX-License-Identifier: MIT  (Copyright (c) 2026 Eugene Flanagin; see LICENSE)
# Install the built package into a FRESH Arch container and check everything that does not
# need a GPU: files, launcher, library resolution, RPATHs, menu entries, licences, and that a
# CMake and a plain g++ program build against /opt/physx5.  No GPU code is run.
#   usage: packaging/test-in-container.sh PKGDIR VERSION     (VERSION like 5.11.0-3)
set -euo pipefail
pkgdir=$(realpath "${1:?usage: test-in-container.sh PKGDIR VERSION}"); ver=${2:?VERSION}
repo=$(cd "$(dirname "$0")/.." && pwd)
pkg="$pkgdir/physx5-zluda-$ver-x86_64.pkg.tar.zst"
[[ -f $pkg ]] || { echo "missing $pkg" >&2; exit 1; }
"${CONTAINER:-docker}" run --rm -v "$pkg:/tmp/p.pkg.tar.zst:ro" -v "$repo:/src:ro" \
  docker.io/library/archlinux:base-devel bash /src/packaging/test-checks.sh "$ver"
