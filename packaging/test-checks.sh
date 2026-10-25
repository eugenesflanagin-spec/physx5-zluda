#!/bin/bash
# SPDX-License-Identifier: MIT  (Copyright (c) 2026 Eugene Flanagin; see LICENSE)
# Runs INSIDE the test container (see test-in-container.sh).  Fails on the first broken check.
set -euo pipefail
ver=$1
fail() { echo "FAIL: $*" >&2; exit 1; }
pacman -Syu --noconfirm >/dev/null
# zluda is an AUR package (it provides libcuda.so.1 at run time): pretend it is installed
pacman -U --noconfirm --assume-installed zluda /tmp/p.pkg.tar.zst >/dev/null
pacman -S --noconfirm --needed cmake ninja patchelf desktop-file-utils libarchive binutils >/dev/null

[[ $(pacman -Q physx5-zluda) == "physx5-zluda $ver" ]] || fail "installed version is not $ver"
pacman -Qkk physx5-zluda
# (outputs captured first: "cmd | grep -q" can SIGPIPE cmd and trip pipefail)
help=$(physx5-zluda-run --help); grep -q '^usage: physx5-zluda-run' <<<"$help" || fail "--help"
list=$(physx5-zluda-run --list); grep -q '^gputest' <<<"$list" || fail "--list has no gputest"
grep -q 'HelloGRB' <<<"$list" || fail "--list has no HelloGRB"
rc=0; physx5-zluda-run NoSuchThing 2>/dev/null || rc=$?; [[ $rc -eq 2 ]] || fail "unknown target exit $rc, expected 2"

cd /opt/physx5
n=$(ls bin/Snippet*_64 | wc -l); echo "snippets: $n"; [[ $n -ge 60 ]] || fail "only $n snippets"
for f in bin/physx5-gputest lib/libPhysXGpu_64.so lib/libzluda-physx-shim.so lib/libcudart.so.13 \
         lib/cmake/PhysX/PhysXConfig.cmake include/PxPhysicsAPI.h; do [[ -e $f ]] || fail "missing $f"; done
# every library must resolve, except libcuda.so.1, which ZLUDA provides on a real system
bad=$(for f in lib/*.so* bin/*; do ldd "$f" 2>/dev/null | grep 'not found' || true; done | grep -v 'libcuda\.so\.1 ' || true)
[[ -z $bad ]] || fail "unresolved libraries: $bad"
grep -q 'libcudart.so.13 => /opt/physx5/lib/' <<<"$(ldd lib/libPhysXGpu_64.so)" || fail "libcudart not resolved"
[[ $(patchelf --print-rpath bin/SnippetHelloGRB_64) == '$ORIGIN/../lib' ]] || fail "snippet RPATH"
! grep -rIl '/work/src\|/build/' lib/cmake /usr/bin/physx5-zluda-run /usr/share/applications | grep . || fail "build paths in text files"
desktop-file-validate /usr/share/applications/physx5-*.desktop
for l in LICENSE LICENSE.CUDA-EULA LICENSE.PhysX.md; do [[ -s /usr/share/licenses/physx5-zluda/$l ]] || fail "licence $l"; done
grep -q 'End User License Agreement' /usr/share/licenses/physx5-zluda/LICENSE.CUDA-EULA || fail "CUDA EULA is not the EULA"
# generic x86-64: no AVX/AVX-512 code from host-specific flags
for f in lib/libPhysX_64.so lib/libPhysXGpu_64.so lib/libzluda-physx-shim.so; do
  [[ $(objdump -d "$f" | grep -cE 'ymm|zmm' || true) -eq 0 ]] || fail "$f contains AVX code"
done

# Link tests: libPhysXGpu_64.so needs libcuda.so.1's symbols at link time.  ZLUDA provides it on a
# real system; here (test container only, never shipped) NVIDIA's link stub from the cudart
# redistributable stands in.  Nothing is executed.
url=$(sed -n 's/^_redist=//p' /src/PKGBUILD)/cuda_cudart/linux-x86_64/cuda_cudart-linux-x86_64-13.4.92-archive.tar.xz
curl -fsSL -o /tmp/cudart.tar.xz "$url"
grep -q "$(sha256sum /tmp/cudart.tar.xz | cut -d' ' -f1)" /src/PKGBUILD || fail "cudart checksum"
bsdtar -xOf /tmp/cudart.tar.xz cuda_cudart-linux-x86_64-13.4.92-archive/lib/stubs/libcuda.so > /usr/lib/libcuda.so.1
mkdir -p /tmp/c && cat > /tmp/c/hello.cpp <<'CPP'
#include <PxPhysicsAPI.h>
using namespace physx;
static PxDefaultAllocator a; static PxDefaultErrorCallback e;
int main() { PxFoundation* f = PxCreateFoundation(PX_PHYSICS_VERSION, a, e);
  return (f && PxCreatePhysics(PX_PHYSICS_VERSION, *f, PxTolerancesScale())) ? 0 : 1; }
CPP
printf 'cmake_minimum_required(VERSION 3.20)\nproject(c CXX)\nfind_package(PhysX REQUIRED CONFIG)\nadd_executable(hello hello.cpp)\ntarget_link_libraries(hello PRIVATE PhysX::physx_lib)\n' > /tmp/c/CMakeLists.txt
cmake -S /tmp/c -B /tmp/c/b -G Ninja -DCMAKE_PREFIX_PATH=/opt/physx5 >/dev/null && ninja -C /tmp/c/b >/dev/null || fail "CMake consumer build"
g++ -std=c++17 /tmp/c/hello.cpp -I/opt/physx5/include -L/opt/physx5/lib -Wl,-rpath,/opt/physx5/lib \
  -lPhysX_64 -lPhysXCommon_64 -lPhysXFoundation_64 /opt/physx5/lib/libPhysXExtensions_static_64.a \
  /opt/physx5/lib/libPhysXPvdSDK_static_64.a -lpthread -ldl -o /tmp/mysim || fail "g++ build from the user guide"
echo "ALL CHECKS PASSED ($ver)"
