# physx5-zluda developer notes

How this package was made to work, and what was found along the way. Useful if you want to
reproduce the build by hand, port it to another distribution, or re-check it against a newer
ZLUDA. The user-facing summary is in the [README](../README.md).

Reference setup: PhysX 5.11.0 (NVIDIA-Omniverse/PhysX commit `6dc53585d7db07346f53d0598a5fd3bfdce47d8d`),
AMD Radeon RX 9070 XT (RDNA 4, gfx1201), ROCm 10, `zluda-preview-bin` 7.preview.13, glibc 2.42.

## 1. No prebuilt GPU library

The 5.11 source tree does not ship a prebuilt `libPhysXGpu_64.so` (its `dependencies.xml` has no
GPU binary package), so the GPU library is compiled from source. That needs a CUDA compiler.

## 2. CUDA toolkit without installing NVIDIA packages

Installing Arch's `cuda` or `nvidia-utils` would replace ZLUDA's `libcuda.so.1`, so the toolkit
comes from NVIDIA's redistributable tarballs instead
(`https://developer.download.nvidia.com/compute/cuda/redist/`):
`cuda_nvcc`, `cuda_cudart`, `cuda_crt`, `cccl` and `libnvvm`. The PKGBUILD extracts them into a
private prefix inside `$srcdir` and adds a `lib64 -> lib` symlink (nvcc looks for `lib64/`).
Only `libcudart.so.13`, which the CUDA EULA lists as redistributable, is installed.

Version choice:

- **CUDA 12.9 does not work on glibc 2.42.** Its math headers declare `cospi`, `sinpi` and
  `rsqrt` with exception specifications that clash with glibc's new declarations, so every
  `.cu` file fails to compile.
- **CUDA 13.4 works**, with one PhysX patch (below).
- **Host compiler: GCC 14** (Arch package `gcc14`, binaries `gcc-14` / `g++-14`). nvcc 13.4
  refuses newer GCC releases.

Check that nothing NVIDIA is installed system-wide: `pacman -Qo /usr/lib/libcuda.so.1` should
name your ZLUDA package.

## 3. The patch (`physx5-zluda.patch`, three files)

1. `source/compiler/cmakegpu/CMakeLists.txt`
   - Generate **PTX only, for `compute_75`**. ZLUDA executes PTX and cannot use SASS cubins,
     and CUDA 13 dropped `compute_70`. Together with `-DCMAKE_CUDA_ARCHITECTURES=75-virtual`
     the resulting `libPhysXGpu_64.so` holds 61 PTX modules and no cubins.
   - Add `--compress-mode=none`. nvcc 13 compresses fatbins with zstd by default; uncompressed
     fatbins keep the PTX as plain text, which the shim needs to patch (section 4).
2. `source/cudamanager/src/CudaContextManager.cpp`: CUDA 13 headers map `cuCtxCreate` to
   `cuCtxCreate_v4`, which takes four arguments. The patch uses that form when
   `CUDA_VERSION >= 13000`.
3. `snippets/compiler/cmake/CMakeLists.txt`: drop `SnippetMultiPruners`, which fails to link
   upstream when PhysX is built as shared libraries.

No `ZLUDA_CC` override is needed: ZLUDA 7.preview.13 reports compute capability 8.5, and
PTX for `compute_75` runs on any capability at or above 7.5.

## 4. ZLUDA gaps and the shim (`zluda-physx-shim.c`)

`libzluda-physx-shim.so` is loaded with `LD_PRELOAD` by `physx5-zluda-run`. It wraps a few
CUDA driver API calls and only acts when ZLUDA fails, so it is inert on a real NVIDIA driver.

| ZLUDA 7.preview.13 behaviour | what PhysX uses it for | shim workaround |
|---|---|---|
| `cuMemcpy3DAsync` returns `CUDA_ERROR_NOT_SUPPORTED` (801) | SDF collision textures | synchronise the stream, then do the same copy with `cuMemcpy3D` |
| `cuMemcpyPeerAsync` returns 801 | device-to-device copies | `cuMemcpyDtoDAsync` when source and destination are the same context |
| Any kernel containing a `red.<space>.add.f32` instruction is silently dropped (`cuModuleGetFunction` returns 500) | float `atomicAdd` whose result is unused | rewrite the PTX text passed to `cuModuleLoadData(Ex)`: `red.X.f32 [a], v;` becomes `atom.X.f32 %zlred, [a], v;` with a `.reg .f32 %zlred;` declaration added |

The `red` rewrite recovers 8 kernels (the `iso_*` isosurface kernels and `computeArtiCOM`).
With the shim, **476 of PhysX's 488 GPU kernels resolve**.

`cuEventQuery` / `cuStreamQuery` returning 600 (`CUDA_ERROR_NOT_READY`) before a sync is
normal CUDA behaviour, not a ZLUDA gap.

### What cannot be fixed in the shim

The remaining **12 kernels use indirect calls** (calls through function pointers, emitted as
`.callprototype` in PTX), which ZLUDA cannot compile:

- the five `convexCore*Nphase_Kernel*` kernels: narrowphase collision for
  `PxConvexCoreGeometry` (cylinders, cones);
- the seven `ps_*` kernels: particle-system collision.

Rigid bodies, joints, articulations, deformable volumes and surfaces, SDF meshes and the
direct-GPU API do not use them. PhysX logs each one once at start-up as
`Could not find CUDA module containing function '...'`.

Shim environment variables, useful when re-checking a newer ZLUDA:

- `PHYSX_SHIM_DEBUG=1` logs every fallback and rewrite.
- `PHYSX_SHIM_DUMP=<dir>` writes every PTX module the shim sees into `<dir>`.
- `PHYSX_SHIM_NO_REWRITE=1` disables the `red` rewrite. If `gputest` still reports 12
  unavailable kernels with it set, that ZLUDA version has fixed the `red` gap.

## 5. Testing

`physx5-gputest.cpp` is a headless functional test: 4 stacks of 55 boxes plus a heavy ball,
300 steps at 60 Hz, GPU broadphase and GPU dynamics requested. It passes when the broadphase
is really `eGPU`, the GPU memory heap was used, the CUDA error state is clean and PhysX reported
no errors.

```sh
physx5-zluda-run gputest                 # GPU run; exit 0 and "RESULT: GPU PhysX ENGAGED"
physx5-zluda-run --cpu-only gputest      # CPU reference run of the same scene
physx5-zluda-run --debug gputest         # with shim logging
```

Expected GPU result on the reference setup: device `AMD Radeon RX 9070 XT [ZLUDA]`, broadphase
`eGPU`, 64 MiB GPU heap, CUDA last error 0, `kernelsUnavailable=12`. The CPU reference completes
and the trajectories agree qualitatively (a falling stack is chaotic, so they are not
bit-identical).

The first GPU run is slow: ZLUDA compiles each PTX module with ROCm's comgr and caches the
result in `~/.cache/zluda`.

## 6. Building outside makepkg

The PKGBUILD is the reference. In short: extract the five tarballs into one prefix, apply the
patch inside `physx/`, then configure with CMake/Ninja using the flags in `build()`
(`-DCMAKE_C_COMPILER=gcc-14 -DCMAKE_CXX_COMPILER=g++-14`,
`-DCMAKE_CUDA_COMPILER=<prefix>/bin/nvcc -DCMAKE_CUDA_HOST_COMPILER=g++-14`,
`-DCUDAToolkit_ROOT=<prefix> -DCMAKE_CUDA_ARCHITECTURES=75-virtual`,
`-DPX_GENERATE_GPU_PROJECTS=ON -DPX_GENERATE_GPU_REDUCED_ARCHITECTURES=ON`, shared libraries,
snippets on). Clear `CFLAGS`/`CXXFLAGS` for the SDK itself (PhysX sets its own `-Werror` set) and
do not use LTO (nvcc host objects do not mix with GCC LTO bytecode). `cudafe++` and `ptxas`
need a lot of memory per job; the PKGBUILD caps Ninja at 10 jobs.

To test a build tree without installing, preload the shim and put the build's library
directory and the toolkit's `lib/` on `LD_LIBRARY_PATH`, then run `physx5-gputest`.

## 7. Repository hygiene

Nothing from the CUDA toolkit or any NVIDIA binary is committed. `.gitignore` excludes the
extracted toolkit, makepkg work directories, tarballs and built packages; the PKGBUILD
downloads everything by URL and checks SHA-256 sums.
