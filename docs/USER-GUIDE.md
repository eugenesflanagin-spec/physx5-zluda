# physx5-zluda — User Guide

NVIDIA PhysX SDK 5 GPU physics, running on an AMD Radeon GPU under Linux through ZLUDA.

This guide is for people installing the package, from first-time AUR users to developers who
want to link their own programs against it. It starts in plain words, then gives the detail,
then every option. A glossary is at the end.

---

## 1. In plain words

**PhysX** is NVIDIA's physics engine: falling boxes, ragdolls, vehicles, cloth, soft bodies.
Its SDK (version 5) is open source. Part of it can run on the **graphics card** instead of the
CPU, which makes very large scenes possible. That GPU part is written in **CUDA**, NVIDIA's GPU
language, so normally it only runs on NVIDIA cards.

**ZLUDA** is a project that lets CUDA programs run on AMD GPUs. It pretends to be NVIDIA's CUDA
driver (`libcuda.so`) and translates the GPU code for the AMD card.

**physx5-zluda** builds the PhysX 5 SDK, *including* its GPU kernels, in a form ZLUDA can run.
It then adds a small fix-up library for three ZLUDA gaps and installs everything into
`/opt/physx5`. You get:

- the PhysX 5 libraries and headers, for your own programs;
- about 70 official PhysX demo programs ("snippets"), several of which use the GPU;
- a one-command self-test that tells you whether GPU PhysX really engaged on your AMD card.

### Who it is for

- AMD GPU owners curious to see PhysX GPU simulation running on their card.
- Developers who want to build or test PhysX 5 GPU code on an AMD machine.
- ZLUDA testers looking for a large, real-world CUDA workload.

### What it is not

- **Not** a way to turn on "GPU PhysX" in old Windows games (those use PhysX 2.x/3.x through
  NVIDIA's Windows driver). This is the PhysX **5 SDK** for Linux programs.
- **Not** an NVIDIA driver. Nothing from NVIDIA's driver is installed.

---

## 2. Requirements

| need | detail |
|---|---|
| OS | Arch Linux or an Arch-based distribution (CachyOS, EndeavourOS, Manjaro…). |
| GPU | An AMD Radeon GPU that ZLUDA and ROCm support. **Verified:** Radeon RX 9070 XT (RDNA 4, gfx1201). Other RDNA 2/3/4 cards should work if ZLUDA does; they are untested. |
| ROCm | ROCm runtime pulled in by ZLUDA (`hip-runtime-amd`, `rocblas`, `miopen-hip`, `hipblaslt`, `rocm-smi-lib`). Verified with ROCm 10. |
| ZLUDA | Any package that provides `zluda`. **Recommended: `zluda-preview-bin`.** Verified with 7.preview.13; the AUR now has 7.preview.18, which should work but has not been re-verified. The older `zluda` (version 6) package is untested. |
| Build tools | `base-devel`, `cmake`, `ninja`, `gcc14` (GCC 14 — the CUDA 13.4 compiler refuses newer GCC), `python`, `patchelf`, `rapidjson`. Pulled in automatically as make-dependencies. |
| Runtime libraries | `freeglut`, `glu`, `libxmu`, `libx11`, `libxi` (for the demo windows). |
| Optional | `konsole` (the two menu entries open in it). |
| Build resources | A few GB of free disk space in the build directory, a working internet connection (about 100 MB of downloads), and plenty of RAM: the CUDA compiler is memory-hungry, so the build caps itself at 10 parallel jobs. Expect 10–30 minutes. |
| Installed size | About 110 MiB in `/opt/physx5`. |

> **Never install `nvidia-utils` or `cuda` on the same machine.** They provide their own
> `libcuda.so` and conflict with ZLUDA. The package manager will remove ZLUDA, and GPU PhysX
> stops working. This package needs neither: it downloads only the pieces of the CUDA toolkit it
> needs to **compile**, keeps them inside the build folder, and installs just one
> redistributable runtime library (`libcudart.so.13`) into `/opt/physx5/lib`.

---

## 3. Install

### 3a. From the AUR (recommended)

```sh
yay -S physx5-zluda          # or paru -S physx5-zluda
```

If you don't have a ZLUDA package yet, install one first, so the helper doesn't pick a provider
for you:

```sh
yay -S zluda-preview-bin
```

### 3b. By hand with makepkg

```sh
git clone https://aur.archlinux.org/physx5-zluda.git      # or the GitHub repository
cd physx5-zluda
makepkg -si
```

### What the build does

1. Downloads PhysX 5.11.0 (commit `6dc53585`) from NVIDIA-Omniverse/PhysX on GitHub, and five
   CUDA 13.4 redistributable archives (`cuda_nvcc`, `cuda_cudart`, `cuda_crt`, `cccl`,
   `libnvvm`) from NVIDIA's download server. All are checked against SHA-256 sums.
2. Unpacks the CUDA pieces into a private folder **inside the build directory**. They are never
   installed.
3. Applies `physx5-zluda.patch`:
   - GPU code is built as **PTX only** (`compute_75`), with no NVIDIA machine code (SASS);
   - fat binaries are left **uncompressed**, so the shim can edit the PTX text;
   - a one-line fix for the CUDA 13 `cuCtxCreate` signature;
   - one snippet that doesn't build here (`MultiPruners`) is dropped.
4. Builds PhysX with GCC 14, the shim, and the self-test.
5. Installs to `/opt/physx5` and fixes the snippets' library search path to `/opt/physx5/lib`.

### What gets installed

| path | contents |
|---|---|
| `/opt/physx5/lib/` | `libPhysX_64.so`, `libPhysXCommon_64.so`, `libPhysXFoundation_64.so`, `libPhysXCooking_64.so`, **`libPhysXGpu_64.so`** (61 PTX modules), static extension/vehicle/character/PVD libraries, `libcudart.so.13`, **`libzluda-physx-shim.so`**, `cmake/PhysX` |
| `/opt/physx5/include/` | PhysX headers |
| `/opt/physx5/bin/` | `Snippet*_64` demo programs and `physx5-gputest` |
| `/opt/physx5/share/doc/` | this project's README, the shim and test sources, PhysX's README and CHANGELOG |
| `/usr/bin/physx5-zluda-run` | the launcher |
| `/usr/share/applications/` | "PhysX 5 GPU Demo (ZLUDA)" and "PhysX 5 GPU Test (ZLUDA)" menu entries |
| `/usr/share/licenses/physx5-zluda/` | PhysX licence and the CUDA EULA |

---

## 4. Check that it works

```sh
physx5-zluda-run gputest
```

The first run is **slow** (up to a few minutes): ZLUDA compiles every PTX module for your GPU
and caches the result in `~/.cache/zluda`. Later runs start quickly.

Good result (RX 9070 XT):

```
PhysX 5.11.0 GPU functional test (GPU pipeline requested)
CUDA device      : AMD Radeon RX 9070 XT [ZLUDA]
broadphase type  : eGPU
stats            : activeDynamic=217 pairs=27 gpuMemHeap=65536 KiB (BP 9043, NP 357, solver 23997, sim 136)
RESULT: GPU PhysX ENGAGED  (bp=GPU, gpuHeap=yes, cudaErr=0, physxErrors=0, warnings=0, kernelsUnavailable=12)
note: 12 kernels could not be compiled by ZLUDA (indirect calls); ...
```

What the test does: it builds a small scene (4 stacks of 55 boxes, 220 bodies, plus a heavy
ball fired at them). It asks for the **GPU** broadphase and GPU dynamics, simulates 300 steps
at 60 Hz, and checks four things: the broadphase really is on the GPU, GPU memory was used,
the CUDA error state is clean, and PhysX reported no errors. It is a short functional check,
not a benchmark.

| exit code | meaning |
|---|---|
| `0` | GPU PhysX engaged with no errors (or, with `--cpu`, the CPU run completed) |
| `1` | GPU not available, scene creation failed, GPU fell back, or PhysX reported errors |
| `2` | bad command-line option |

`kernelsUnavailable=12` is **expected** (section 7).

You can also start the test from the menu: **PhysX 5 GPU Test (ZLUDA)** opens it in Konsole and
keeps the window open.

---

## 5. Everyday use

```sh
physx5-zluda-run --list                  # list the installed snippets
physx5-zluda-run HelloGRB                # 8,400 rigid bodies on the GPU, in a window
physx5-zluda-run SnippetHelloGRB         # same; the Snippet prefix and _64 suffix are optional
physx5-zluda-run --debug SDF             # log every shim fallback and PTX rewrite
physx5-zluda-run gputest --steps 600 --stacks 8    # bigger self-test scene
physx5-zluda-run gputest --cpu           # same scene on the CPU pipeline, for comparison
physx5-zluda-run --cpu-only gputest      # same, and also without the shim or a GPU device
physx5-zluda-run ./my_physx_program      # run your own program with the right environment
```

In the snippet windows, the usual PhysX snippet controls apply: mouse to look, `W A S D` to
move. Most snippets also use the space bar (for example to shoot a ball). The terminal shows
any key help the snippet prints.

### Snippets that exercise the GPU

| snippet | shows |
|---|---|
| `HelloGRB` | GPU rigid bodies (the menu demo) |
| `RBDirectGPUAPI`, `DirectGPUAPIArticulation` | PhysX's direct-GPU data API |
| `SDF` | signed-distance-field mesh collision (uses a shim fallback) |
| `DeformableVolume*`, `DeformableSurface*` | soft bodies and cloth |
| `Isosurface`, `PBF`, `PBFMultiMat` | particle systems. **Expected to fail or show errors** (section 7) |

The other snippets (joints, vehicles, queries, serialization…) run on the CPU and work as in
stock PhysX.

### Using the SDK in your own program

```sh
g++ -std=c++17 mysim.cpp -I/opt/physx5/include -L/opt/physx5/lib \
    -Wl,-rpath,/opt/physx5/lib \
    -lPhysX_64 -lPhysXCommon_64 -lPhysXFoundation_64 \
    /opt/physx5/lib/libPhysXExtensions_static_64.a /opt/physx5/lib/libPhysXPvdSDK_static_64.a \
    -lpthread -ldl -o mysim
physx5-zluda-run ./mysim
```

CMake users can point `CMAKE_PREFIX_PATH` at `/opt/physx5` (`lib/cmake/PhysX`). Always run
through `physx5-zluda-run`, or set the same three variables yourself (section 6).
`libPhysXGpu_64.so` is loaded at runtime **by bare name**, so `/opt/physx5/lib` must be on
`LD_LIBRARY_PATH` for the GPU part to be found.

---

## 6. Reference: every option and variable

### `physx5-zluda-run`

```
physx5-zluda-run [--cpu-only] [--debug] [--list] <SnippetName|gputest|/path/to/exe> [args...]
```

| option | meaning |
|---|---|
| `--list` | Print `gputest` and the installed snippet names, then exit. |
| `--debug` | Set `PHYSX_SHIM_DEBUG=1` (shim logs every fallback and rewrite to stderr). |
| `--cpu-only` | Don't preload the shim and set `PHYSX_GPU_DEVICE=-1` (no GPU device for PhysX). With `gputest` it also passes the test's own `--cpu` flag, so `physx5-zluda-run --cpu-only gputest` runs the CPU reference. |
| `-h`, `--help` | Show the built-in help. |
| `gputest` | Run `/opt/physx5/bin/physx5-gputest`. |
| `SnippetName` | `HelloGRB`, `SnippetHelloGRB` or `SnippetHelloGRB_64`; case doesn't matter. |
| `/path/to/exe` | Any executable, run with the PhysX/ZLUDA environment. |
| `[args...]` | Passed to the program unchanged. |

Exit status 2 means usage error or unknown snippet. Otherwise the program's own status is
returned.

### What the launcher sets

| variable | value |
|---|---|
| `LD_LIBRARY_PATH` | `/opt/physx5/lib` in front of yours |
| `LD_PRELOAD` | `/opt/physx5/lib/libzluda-physx-shim.so` in front of yours (not with `--cpu-only`) |
| `PHYSX_GPU_DEVICE` | `0` unless you already set it (`-1` with `--cpu-only`). The CUDA device number PhysX uses. On a machine whose CPU has integrated graphics, ZLUDA may list it as a second device; if PhysX picks the wrong GPU, try `PHYSX_GPU_DEVICE=1`. |

`ZLUDA_CC` (a ZLUDA override for the reported compute capability) is **not** needed. The GPU
code is PTX for `compute_75`, which any capability ZLUDA reports can run.

### Shim variables (`libzluda-physx-shim.so`)

| variable | meaning |
|---|---|
| `PHYSX_SHIM_DEBUG` | Any value: log each `cuMemcpy3DAsync` / `cuMemcpyPeerAsync` fallback and each PTX rewrite to stderr, prefixed `[physx-shim]`. |
| `PHYSX_SHIM_DUMP=<dir>` | Also write every PTX module the shim sees into `<dir>` (for debugging ZLUDA). |
| `PHYSX_SHIM_NO_REWRITE` | Any value: don't rewrite `red.*.add.f32` instructions. Useful to check whether a newer ZLUDA has fixed that gap: run `gputest` and compare the kernel count. |

### `physx5-gputest`

| option | default | meaning |
|---|---|---|
| `--cpu` | off | Use the CPU pipeline (no CUDA context). |
| `--steps N` | 300 | Simulation steps (at 1/60 s each). |
| `--stacks N` | 4 | Number of 55-box pyramids. |

### What the shim fixes

ZLUDA 7.preview.13 has three gaps that PhysX runs into. The shim sits between PhysX and ZLUDA
and only acts when ZLUDA fails. On a real NVIDIA driver it never steps in.

1. **`cuMemcpy3DAsync` → "not supported"** (used for SDF collision textures). The shim waits
   for the stream, then does the same copy with the synchronous `cuMemcpy3D`.
2. **`cuMemcpyPeerAsync` → error 801.** For copies inside one context, it uses
   `cuMemcpyDtoDAsync`.
3. **Kernels with a `red.<space>.add.f32` instruction are silently dropped by ZLUDA.** The
   compiler emits `red` when the result of a float `atomicAdd` isn't used. The shim rewrites
   it to the equivalent `atom...add.f32` form in the PTX text before ZLUDA compiles it. This
   recovers 8 kernels.

---

## 7. Known limits

- **12 of PhysX's 488 GPU kernels can't run.** They use indirect calls through function
  pointers (`.callprototype`), which ZLUDA can't compile:
  - the five `convexCore*Nphase_Kernel*` (collision for the new `PxConvexCoreGeometry`
    cylinders and cones);
  - the seven `ps_*` particle-system collision kernels.

  PhysX prints `Could not find CUDA module containing function '...'` for each one at start-up.
  **Unaffected:** rigid bodies, joints, articulations, deformable volumes and surfaces, SDF
  meshes, the direct-GPU API. **Affected:** particle systems (PBF, isosurface) and ConvexCore
  scenes, which report errors.
- **First start is slow** while ZLUDA compiles and caches the PTX. Deleting `~/.cache/zluda`
  makes the next start slow again.
- **ZLUDA is pre-release software.** A new ZLUDA version can fix gaps (some shim steps then
  become unnecessary) or introduce new ones.
- **Performance is not tuned.** The goal is correctness. No benchmark numbers are claimed.
- **Linux only, x86-64 only.**

---

## 8. Troubleshooting

| symptom | cause and fix |
|---|---|
| `RESULT: no usable CUDA context manager` | ZLUDA isn't installed or can't see the GPU. Check `pacman -Qo /usr/lib/libcuda.so.1` (should be your ZLUDA package), and check that ROCm sees the card (`rocminfo` / `rocm-smi` if installed). Your user must be in the `render` and `video` groups on some setups. |
| `CUDA device` shows the integrated GPU ("Raphael [ZLUDA]" etc.) | Set `PHYSX_GPU_DEVICE=1` (or the right number). |
| `RESULT: GPU PhysX NOT engaged` with `cudaErr` ≠ 0 | A ZLUDA error. Run with `--debug` and look at the first errors. Try deleting `~/.cache/zluda` once. |
| Many more than 12 `Could not find CUDA module containing function` lines | The shim isn't loaded (you ran the program directly, or with `--cpu-only`). Use `physx5-zluda-run`. |
| `error while loading shared libraries: libPhysX_64.so` | You ran a program outside the launcher. Use `physx5-zluda-run`, or set `LD_LIBRARY_PATH=/opt/physx5/lib`. |
| Snippet window doesn't open | No X11/XWayland display, or freeglut is missing. Run from a desktop session. |
| Build fails: `unsupported GNU version` | `gcc14` is missing, or the build picked the system GCC. Install `gcc14` and rebuild cleanly (`makepkg -Cf`). |
| Build killed / machine freezes during build | Out of memory in `cudafe++`/`ptxas`. Close other programs, add swap, or build with fewer jobs. |
| Download of a `cuda_*` archive fails or the checksum doesn't match | NVIDIA's server was unreachable, or the file changed. Retry later; report it if the sum differs. |
| ZLUDA disappeared after a system update | Something pulled in `nvidia-utils` or `cuda` (some AI tools depend on them). Remove that package and reinstall ZLUDA. |
| Monitoring tools show extra "NVIDIA" or "[ZLUDA]" GPUs with no sensors | Side effect of ZLUDA, not of this package: ZLUDA installs `libnvidia-ml.so`, and tools that query NVIDIA's NVML (e.g. CoolerControl) find "GPUs" that have no sensors. Configure the tool not to use NVML (CoolerControl: start the daemon with `--nvidia-cli`). Don't delete ZLUDA's library; other CUDA programs need it. |

---

## 9. Updating

```sh
yay -Syu            # picks up new physx5-zluda releases
```

After a **ZLUDA** update, run `physx5-zluda-run gputest` once. ZLUDA recompiles the kernels
(slow first start), and the result line tells you whether everything still engages.

## 10. Uninstall

```sh
sudo pacman -R physx5-zluda
rm -rf ~/.cache/zluda      # optional: ZLUDA's compiled-kernel cache (shared with other ZLUDA programs)
```

ZLUDA itself stays installed. Remove it separately if nothing else needs it.

---

## 11. FAQ

**Does this need an NVIDIA card or driver?** No. That's the point.

**Is any NVIDIA software installed?** Only `libcudart.so.13`, NVIDIA's redistributable CUDA
runtime library (allowed by the CUDA EULA), inside `/opt/physx5/lib`. The compiler and headers
are used only during the build and deleted with the build folder.

**Why PTX only?** ZLUDA translates PTX (CUDA's portable assembly). It can't use the
NVIDIA-specific machine code (SASS cubins) that PhysX normally ships.

**Why CUDA 13.4 when PhysX targets 12.8?** CUDA 12.9's headers don't compile against glibc 2.42
(the `cospi`/`sinpi`/`rsqrt` declarations clash). CUDA 13.4 works with one small PhysX patch.

**Will games use this?** Only Linux-native programs built against the PhysX 5 SDK. Windows
games under Proton use their own Windows PhysX builds.

**Is it fast?** It works. Speed depends on ZLUDA's code generation. No claims are made.

---

## 12. Glossary

- **PhysX SDK** — NVIDIA's open-source physics engine library.
- **Snippet** — a small official PhysX demo program showing one feature.
- **GPU dynamics / GPU broadphase** — running the physics solver and the "which objects might
  touch" pass on the graphics card.
- **CUDA** — NVIDIA's GPU programming platform. **CUDA driver API** (`libcuda.so`) is the
  low-level interface, which ZLUDA implements.
- **ZLUDA** — a drop-in CUDA implementation for AMD GPUs, built on ROCm/HIP.
- **ROCm / HIP** — AMD's GPU compute stack and its CUDA-like runtime.
- **comgr** — ROCm's code-object manager, which ZLUDA uses to compile kernels.
- **PTX** — CUDA's portable intermediate GPU assembly. **SASS / cubin** — NVIDIA's
  hardware-specific machine code.
- **Fatbin** — the bundle of GPU code embedded in a CUDA library.
- **Kernel** — one GPU function.
- **Shim / LD_PRELOAD** — a small library loaded first so it can intercept function calls.
- **`red` / `atom`** — PTX reduction and atomic instructions. `red` doesn't return a value;
  `atom` does.
- **Indirect call / `.callprototype`** — calling a GPU function through a pointer. ZLUDA can't
  compile these yet.
- **SDF** — signed distance field, a shape representation used for detailed mesh collision.
- **PBF** — position-based fluids (PhysX particle systems).
- **Compute capability (CC)** — NVIDIA's version number for GPU features. `compute_75` = the
  PTX feature level used here.

---

## 13. Credits and licence

- **PhysX SDK 5** © NVIDIA Corporation, Apache License 2.0 (the `LICENSE.md` of PhysX 5.11.0,
  [NVIDIA-Omniverse/PhysX](https://github.com/NVIDIA-Omniverse/PhysX)). The licence is
  installed as `/usr/share/licenses/physx5-zluda/LICENSE.PhysX.md`. Older PhysX 5 releases
  were BSD-3-Clause.
- **CUDA toolkit components** © NVIDIA Corporation, downloaded at build time under the NVIDIA
  CUDA EULA (installed as `LICENSE.CUDA-EULA`). Only the redistributable `libcudart.so.13` ends
  up in the package. Nothing from the toolkit is stored in this repository.
- **ZLUDA** by Andrzej Janik (vosen) and contributors ([vosen/ZLUDA](https://github.com/vosen/ZLUDA)).
- **ROCm** © Advanced Micro Devices, Inc.
- Packaging, the ZLUDA shim, the self-test, the launcher, the menu entries and this guide:
  Eugene Flanagin, MIT licence (`LICENSE` in the repository). `physx5-zluda.patch` is a
  modification of PhysX files and stays under PhysX's Apache-2.0.
- Full list of sources and licences: `CREDITS.md` in the
  [repository](https://github.com/eugenesflanagin-spec/physx5-zluda/blob/master/CREDITS.md).

NVIDIA, PhysX and CUDA are trademarks of NVIDIA Corporation. AMD, Radeon and ROCm are
trademarks of Advanced Micro Devices, Inc. This project is not affiliated with, endorsed by,
or supported by NVIDIA, AMD or the ZLUDA project.
