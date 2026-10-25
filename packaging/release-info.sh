#!/bin/bash
# SPDX-License-Identifier: MIT  (Copyright (c) 2026 Eugene Flanagin; see LICENSE)
#   release-info.sh version        -> pkgver-pkgrel from PKGBUILD (e.g. 5.11.0-3)
#   release-info.sh check TAG      -> exit 1 unless TAG is exactly v<version>
#   release-info.sh notes TAG      -> release notes (docs/release-notes/TAG.md)
set -euo pipefail
cd "$(dirname "$0")/.."
ver=$(bash -c 'source PKGBUILD >/dev/null 2>&1; echo "$pkgver-$pkgrel"')
case ${1:-} in
  version) echo "$ver" ;;
  check) [[ ${2:-} == "v$ver" ]] || { echo "tag '${2:-}' does not match PKGBUILD version v$ver" >&2; exit 1; } ;;
  notes) f="docs/release-notes/${2:?TAG}.md"; [[ -s $f ]] || { echo "missing $f" >&2; exit 1; }; cat "$f" ;;
  *) echo "usage: $0 version | check TAG | notes TAG" >&2; exit 2 ;;
esac
