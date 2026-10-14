# physx5-zluda — resume notes (checkpoint 2026-10-14 ~11:25)

Goal: NVIDIA PhysX SDK 5 (GitHub NVIDIA-Omniverse/PhysX, commit 6dc53585d7db07346f53d0598a5fd3bfdce47d8d,
version 5.11.0) built with its GPU kernels and running them on the RX 9070 XT through ZLUDA
(zluda-preview-bin 7.preview.13). Packaged locally into /opt/physx5 (PKGBUILD in this dir).

## STATUS

DONE
- Prebuilt PhysXGpu: NOT available in this tree (dependencies.xml has no GPU binary package) -> compiled from source.
- CUDA toolkit WITHOUT installing nvidia-*/cuda: NVIDIA redist tarballs extracted into a private prefix.
  * cuda-local/   = CUDA 12.9 (nvcc 12.9.86) -> FAILS on this glibc (cospi/sinpi/rsqrt noexcept clash). Unused.
  * cuda13-local/ = CUDA 13.4.92 (cuda_nvcc + cuda_cudart + cuda_crt + cccl + libnvvm) + `lib64 -> lib` symlink. WORKS.
  * Host compiler: extra `gcc14` package (g++-14) installed via pacman (nvcc 13.4 rejects gcc 16).
  * pacman -Qo /usr/lib/libcuda.so.1 -> zluda-preview-bin (verified; nothing NVIDIA installed system-wide).
- dev/ = patched source tree, configured in dev/build (Ninja, build type `checked`), fully built (~10 min),
  PTX-only GPU library: dev/bin/linux.x86_64/checked/libPhysXGpu_64.so (61 PTX modules, 0 cubins).
- Patches (physx5-zluda.patch, 3 files):
  1. source/compiler/cmakegpu/CMakeLists.txt: GENERATE_ARCH_CODE_LIST(PTX "75") only (CUDA 13 dropped sm_70,
     ZLUDA needs PTX) + `--compress-mode=none` (uncompressed fatbin so the shim can rewrite PTX text).
  2. source/cudamanager/src/CudaContextManager.cpp: cuCtxCreate 4-arg form under CUDA_VERSION >= 13000.
  3. snippets/compiler/cmake/CMakeLists.txt: drop SnippetMultiPruners (upstream link error with shared libs).
  Plus cmake args: -DCMAKE_CUDA_ARCHITECTURES=75-virtual, compilers gcc-14/g++-14, CUDAToolkit_ROOT=cuda13-local.
- physx5-gputest.cpp: headless functional test. RESULT on ZLUDA: **GPU PhysX ENGAGED** — device
  "AMD Radeon RX 9070 XT [ZLUDA]", broadphase eGPU, gpuMemHeap 64 MiB, 220 boxes + ball simulate correctly,
  CUDA last error 0. No ZLUDA_CC needed (ZLUDA reports CC 8.5; PTX-only so no cubin selection trap).
- zluda-physx-shim.c -> libzluda-physx-shim.so (LD_PRELOAD):
  * cuMemcpy3DAsync -> 801 on ZLUDA -> fallback to sync cuMemcpy3D (SDF textures).
  * cuMemcpyPeerAsync -> 801 -> cuMemcpyDtoDAsync when same context.
  * ZLUDA drops every kernel containing `red.<space>.add.f32` (cuModuleGetFunction -> 500). Shim rewrites
    PTX text in cuModuleLoadData(Ex): `red.X.f32 [a], v;` -> `atom.X.f32 %zlred, [a], v;` (+ `.reg .f32 %zlred;`).
    Recovers 8 kernels (iso_* isosurface, computeArtiCOM). 476/488 kernels now resolve.
  * REMAINING ZLUDA GAP (unfixable here): 12 kernels using indirect calls (`prototype_N`/call via pointer):
    convexCore*Nphase_Kernel* (PxConvexCoreGeometry collision, 5) and ps_* (particle system collision, 7).
- physx5-zluda-run (wrapper) written. Scratch probes in
  /tmp/claude-1000/-home-user/a5463c93-0c4a-4761-b055-a545017926a9/scratchpad/physx5/probe (loadfn.c = per-kernel resolver).

DONE (11:35) — package built and installed
- physx5-zluda-5.11.0-1-x86_64.pkg.tar.zst installed with `sudo pacman -U`; /usr/lib/libcuda.so.1 still zluda-preview-bin.
- `physx5-zluda-run gputest` -> "RESULT: GPU PhysX ENGAGED", exit 0 (release build, 61 PTX / 0 ELF in /opt/physx5/lib/libPhysXGpu_64.so).
- Menu: Education & Science / Physics & Electronics (after `menu-resort`), both .desktop files validate.
- CPU reference (`physx5-zluda-run --cpu-only gputest --cpu`) completes; trajectories agree qualitatively (chaotic stack).
- Git: local repo, commit e3c9682 (+ follow-up). Publish is the USER's call: `gh repo create physx5-zluda --public --source=. --push`.

## Dev-tree commands (if the package build needs iterating)
cmake configure used for dev/ (replace `checked` with `release` for the package):
  P=~/pkgbuilds/physx5-zluda; T13=$P/cuda13-local
  cmake -S $P/dev -B $P/dev/build -G Ninja --no-warn-unused-cli -DCMAKE_BUILD_TYPE=checked \
    -DTARGET_BUILD_PLATFORM=linux -DPX_OUTPUT_ARCH=x86 -DPHYSX_ROOT_DIR=$P/dev -DPX_OUTPUT_LIB_DIR=$P/dev -DPX_OUTPUT_BIN_DIR=$P/dev \
    -DCMAKE_C_COMPILER=gcc-14 -DCMAKE_CXX_COMPILER=g++-14 -DCMAKE_CUDA_COMPILER=$T13/bin/nvcc -DCMAKE_CUDA_HOST_COMPILER=g++-14 \
    -DCUDAToolkit_ROOT=$T13 -DCMAKE_CUDA_ARCHITECTURES=75-virtual -DPX_GENERATE_GPU_PROJECTS=ON -DPX_GENERATE_STATIC_LIBRARIES=OFF \
    -DPX_GENERATE_GPU_STATIC_LIBRARIES=OFF -DPX_BUILDSNIPPETS=ON -DPX_BUILDPVDRUNTIME=OFF -DPX_GENERATE_GPU_REDUCED_ARCHITECTURES=ON \
    -DCMAKE_INSTALL_PREFIX=/opt/physx5
  ninja -C $P/dev/build -j10
Test from the dev tree:
  cd $P/dev && LD_PRELOAD=$P/libzluda-physx-shim.so LD_LIBRARY_PATH=$PWD/bin/linux.x86_64/checked:$T13/lib timeout 60 ./physx5-gputest --steps 120

## Memory notes for the caller (not written to memory by this agent)
- ZLUDA 7.p13 reports CC 8.5 now (memory says 8.8). cuDriverGetVersion 13000.
- ZLUDA gaps found: cuMemcpy3DAsync 801 (sync cuMemcpy3D OK), cuMemcpyPeerAsync 801, `red.*.add.f32` PTX kills the
  kernel (atom form OK), indirect calls (callprototype) unsupported. cuEventQuery/cuStreamQuery return 600 legitimately
  until synced, then 0.
- CUDA 12.9 headers clash with glibc 2.42 (cospi/sinpi/rsqrt noexcept); CUDA 13.4 redist works with g++-14 (gcc14 pkg).
- CUDA 13 dropped compute_70; nvcc 13 compresses fatbins with zstd by default (`--compress-mode=none` to keep PTX text).
- CUDA 13 headers map cuCtxCreate -> cuCtxCreate_v4 (4 args); PhysX 5.11 needs the 1-line patch.
- NVIDIA redist tarballs (developer.download.nvidia.com/compute/cuda/redist/) are the way to get nvcc without pacman cuda.

## Repo hygiene
.gitignore excludes cuda-local/, cuda13-local/, src/, pkg/, dev/, *.pkg.tar.*, *.tar.xz, *.tar.gz (NVIDIA binaries and
the toolkit must never be committed to the public repo; the PKGBUILD downloads them by URL + sha256).
