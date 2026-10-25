#!/bin/bash
# SPDX-License-Identifier: MIT  (Copyright (c) 2026 Eugene Flanagin; see LICENSE)
# Runs INSIDE a fresh archlinux:base-devel container as root (see packaging/build.sh).
# Builds the package from /src (a read-only copy of this repository) with Arch's stock,
# generic x86-64 makepkg.conf, and writes the .pkg.tar.zst to /out.
set -euo pipefail

# gcc14 (the CUDA 13.4 nvcc refuses GCC 15+) is not in the Arch repositories; arch4edu builds it.
# Its signing key is checked against the full fingerprint before it is trusted.
A4E_KEY=CCED9BE21E1173C61DC1C9407931B6D628C8D3BA
pacman-key --init >/dev/null
pacman-key --populate archlinux >/dev/null
for i in 1 2 3; do pacman-key --keyserver hkps://keyserver.ubuntu.com --recv-keys "$A4E_KEY" && break; sleep 10; done
pacman-key --lsign-key "$A4E_KEY" >/dev/null
printf '\n[arch4edu]\nServer = https://repository.arch4edu.org/$arch\n' >> /etc/pacman.conf

# make- and run-time dependencies, except zluda (AUR only, needed at run time only)
pacman -Syu --noconfirm --needed git cmake ninja gcc14 python patchelf rapidjson \
  gcc-libs glibc freeglut glu libxmu libx11 libxi >/dev/null

# smaller download than the stock zstd level
echo "COMPRESSZST=(zstd -c -T0 --ultra -20 -)" >> /etc/makepkg.conf

useradd -m builder
install -d -o builder /work /out
cp -a /src/. /work/
chown -R builder: /work
# -d: skip the dependency check (zluda is not installable here; everything else is installed above)
su builder -c 'cd /work && makepkg -f --noconfirm -d'
cp /work/*.pkg.tar.zst /out/
ls -l /out
