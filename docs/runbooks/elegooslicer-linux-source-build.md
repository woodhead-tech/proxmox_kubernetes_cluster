# ElegooSlicer Linux Source Build & Reinstall Runbook

**Date:** 2026-11-20
**Severity:** low
**Affected:** Ubuntu 26.04.1 LTS (`resolute`, x86_64) workstation — `elegooofficial/ElegooSlicer` (tested on `main` @ `2d507e39`, v1.5.3.5 / engine 2.4.2)

## Summary

End-to-end procedure for cloning, patching, compiling, packaging, and verifying `elegooofficial/ElegooSlicer` natively from source on Ubuntu 26.04, including fixes for five issues encountered during the initial build:

1. Host RAM guard (`<= 10 GiB` available) aborts `build_linux.sh` without `-r`.
2. `dep_OpenVDB` fails to link against `libtbb.a` under `ld.lld` because `oneTBB 2021.5.0` emits GCC `.gnu.lto_*` bitcode (and fails with `-Werror=stringop-overflow=` on GCC 13 once `-flto` is disabled).
3. Direct execution of `build/package/bin/elegoo-slicer` fails to load `libaosl.so` (must launch via the top-level `build/package/elegoo-slicer` wrapper).
4. Upstream null-pointer dereference (`SIGSEGV` at `0x7`) in `Plater::priv::on_select_preset()` when selecting a printer preset without a matching system model.
5. ElegooLink Device UI fails if web assets (`lan_service_web`, `cloud_service_web`) are not downloaded via `-w` / `scripts/download_web_dep.sh`.

**Updated 2026-11-24** — also builds natively on **CachyOS** (same 12-core / 14 GiB laptop, reinstalled). See [CachyOS / Arch Build](#cachyos--arch-build) for the two extra issues (6, 7) and the toolchain pins.

---

## CachyOS / Arch Build

Tested 2026-11-24 on CachyOS (rolling, gcc 16.2.1, CMake 4.5.1 system), `main` @ `2d507e39`. Build time ~37 min for the final resume (deps + app), ~10 GB on disk (`build/` 3.2 GB, `deps/build/` 7.0 GB).

The repo ships `scripts/linux.d/cachyos`, so `build_linux.sh` detects the distro natively — no Docker needed. Two pins are required:

| Pin | Why |
|-----|-----|
| **gcc-14** (`cachyos/gcc14`, `/usr/bin/gcc-14`) | gcc-13 isn't packaged for CachyOS; system gcc 16 is too new for the vendored deps. gcc-14 is the closest available to CI's gcc-13. |
| **CMake 4.3.0** (venv) | System CMake 4.5.1 fails `dep_Boost` configure (Issue 6). 4.3.0 is what upstream CI uses (`ORCA_DOCKER_CMAKE_VERSION` default in `build_linux.sh`). |

```bash
# Toolchain + deps (scripts/linux.d/cachyos list, plus gcc14/ccache)
sudo pacman -S --needed gcc14 ccache cmake ninja curl dbus eglexternalplatform extra-cmake-modules \
  file gettext glew gst-plugins-good gstreamer gtk3 libmspack libsecret libspnav mesa openssl \
  texinfo wayland-protocols webkit2gtk-4.1 wget unzip

# CMake 4.3.0 in a private venv (leaves system cmake alone)
python3 -m venv ~/.local/share/cmake-4.3 && ~/.local/share/cmake-4.3/bin/pip install 'cmake==4.3.0'

# Apply the Plater.cpp patch (Step 3 below), then build.
# No -L: GNU ld avoids the TBB/ld.lld LTO issue (Issue 2) entirely.
cd ~/Workspace/ElegooSlicer
PATH=~/.local/share/cmake-4.3/bin:$PATH CC=/usr/bin/gcc-14 CXX=/usr/bin/g++-14 \
CMAKE_BUILD_PARALLEL_LEVEL=4 ./build_linux.sh -wdsr -j 4
# The first run stops at dep_elegoolink (Issue 7): apply the include fix, re-run the same command.
```

> If you switch CMake versions after a failed configure, `rm -rf deps/build` first — the ExternalProject caches record the CMake that generated them.

---

## Clean Reinstall Procedure

### 1. System Prerequisites

Ensure `gcc-13`/`g++-13`, `lld`, `ccache`, and all `scripts/linux.d/debian` development packages are installed:

```bash
sudo apt-get update && sudo apt-get install -y \
  autoconf build-essential ccache cmake eglexternalplatform-dev \
  extra-cmake-modules file g++ g++-13 gcc-13 gettext git gstreamer1.0-gtk3 \
  libcurl4-openssl-dev libdbus-1-dev libglew-dev libgstreamerd-3-dev \
  libgtk-3-dev libmspack-dev libsecret-1-dev libspnav-dev libssl-dev \
  libtool libudev-dev libwebkit2gtk-4.1-dev lld ninja-build texinfo wget unzip
```

**Resource requirements:**
- Disk: ~12 GB retained after build (~15–20 GB peak).
- Memory: Cap parallelism at `CMAKE_BUILD_PARALLEL_LEVEL=4` on 14 GiB RAM hosts (CGAL + PCH compilation peaks around ~9.5 GiB used at `-j 4`).
- Time: ~90 minutes cold build; incremental rebuilds take < 1 minute with `ccache` + `ld.lld`.

### 2. Clone Repository

```bash
git clone --depth 1 https://github.com/elegooofficial/ElegooSlicer.git ~/Workspace/ElegooSlicer
cd ~/Workspace/ElegooSlicer
```

### 3. Pre-Build Fix: Prevent `Plater::priv::on_select_preset()` Segfault

Check `src/slic3r/GUI/Plater.cpp` around line 9731. If `preset == nullptr` still lacks a `return;`, apply this patch:

```diff
diff --git a/src/slic3r/GUI/Plater.cpp b/src/slic3r/GUI/Plater.cpp
index 7a90f41a..2216be14 100644
--- a/src/slic3r/GUI/Plater.cpp
+++ b/src/slic3r/GUI/Plater.cpp
@@ -9731,8 +9731,9 @@ void Plater::priv::on_select_preset(wxCommandEvent &evt)
             if (combo->is_selected_printer_model()) {
                 auto preset = wxGetApp().preset_bundle->get_similar_printer_preset(preset_name, {});
                 if (preset == nullptr) {
-                    MessageDialog dlg(this->sidebar, "", "");
+                    MessageDialog dlg(this->sidebar, _L("Configuration incompatible"), _L("Warning"), wxICON_WARNING | wxOK);
                     dlg.ShowModal();
+                    return;
                 }
                 preset->is_visible = true; // force visible
                 preset_name = preset->name;
```

### 4. Build Dependencies, Web Assets, Application, and Package

Run with `-w` (download ElegooLink web UI assets), `-d` (vendored deps), `-s` (ElegooSlicer + profile validator + translations + `build/package/`), `-r` (skip RAM check), and `-L` (`ld.lld` linker):

```bash
cd ~/Workspace/ElegooSlicer
CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13 \
CMAKE_BUILD_PARALLEL_LEVEL=4 \
./build_linux.sh -wdsrL
```

> **Important (`dep_TBB` + `ld.lld`):** If `dep_OpenVDB` fails linking `vdb_print` with undefined `tbb::detail::r1::*` symbols, run the TBB fix in [Issue 2](#issue-2-dep_openvdb-fails-linking-libtbba-under-ldlld) below, then re-run the exact `./build_linux.sh -wdsrL` command above (Ninja resumes without rebuilding completed dependencies).
>
> **Alternative (no TBB LTO issue):** Omit `-L` to link with GNU `ld`, or use the upstream Ubuntu 24.04 container runner: `./build_linux.sh -g -wdsrL`.

---

## Known Issues, Root Causes, and Fixes

### Issue 1: `build_linux.sh` Exits With Code 2 on Memory Check

- **Symptom:** `ERROR: ElegooSlicer Builder requires at least 10G of 'available' mem (system has only 10G available)`.
- **Root Cause:** `build_linux.sh` checks `if [[ ${FREE_MEM_GB} -le 10 ]]`, which fails on a 14 GiB workstation with ~10 GiB available.
- **Fix:** Always pass `-r` and keep `CMAKE_BUILD_PARALLEL_LEVEL=4`.

### Issue 2: `dep_OpenVDB` Fails Linking `libtbb.a` Under `ld.lld`

- **Symptom:** `[29/29] Linking CXX executable openvdb/openvdb/cmd/vdb_print` fails with `ld.lld: error: undefined symbol: tbb::detail::r1::execution_slot(...)` (and thousands of `tbb::detail::r1::*` symbols), even though `libtbb.a` is on the link line.
- **Root Cause:** `oneTBB 2021.5.0` unconditionally enables `-flto` in `cmake/compilers/GNU.cmake` under GCC, producing `.gnu.lto_*` GIMPLE bitcode in `libtbb.a` and `libtbbmalloc.a`. `ld.lld` cannot read GCC LTO bitcode. Disabling `-flto` then exposes a GCC 13 `-Werror=stringop-overflow=` false positive because `TBB_STRICT` defaults to `ON`.
- **Diagnosis:**
  ```bash
  readelf -S ~/Workspace/ElegooSlicer/deps/build/ElegooSlicer_dep/usr/local/lib/libtbb.a | grep '\.gnu\.lto'
  ```
- **Fix:** Disable `TBB_IPO_*` in the extracted `dep_TBB` build copy, reconfigure with `-DTBB_STRICT=OFF`, rebuild/reinstall `dep_TBB`, and resume `build_linux.sh`:
  ```bash
  TBB_SRC=~/Workspace/ElegooSlicer/deps/build/dep_TBB-prefix/src/dep_TBB
  TBB_BUILD=~/Workspace/ElegooSlicer/deps/build/dep_TBB-prefix/src/dep_TBB-build

  sed -i 's/set(TBB_IPO_COMPILE_FLAGS.*/set(TBB_IPO_COMPILE_FLAGS "")/; s/set(TBB_IPO_LINK_FLAGS.*/set(TBB_IPO_LINK_FLAGS "")/' \
    "$TBB_SRC/cmake/compilers/GNU.cmake"

  cmake -DTBB_STRICT=OFF "$TBB_BUILD"
  cmake --build "$TBB_BUILD" --clean-first -j 4
  cmake --install "$TBB_BUILD"

  # Confirm zero .gnu.lto sections remain:
  readelf -S ~/Workspace/ElegooSlicer/deps/build/ElegooSlicer_dep/usr/local/lib/libtbb.a | grep '\.gnu\.lto' || echo "CLEAN"

  # Resume full build:
  cd ~/Workspace/ElegooSlicer && CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13 CMAKE_BUILD_PARALLEL_LEVEL=4 ./build_linux.sh -wdsrL
  ```

### Issue 3: `libaosl.so: cannot open shared object file`

- **Symptom:** Running `build/package/bin/elegoo-slicer` directly fails immediately with `error while loading shared libraries: libaosl.so`.
- **Root Cause:** Bundled Agora SDK libraries (`libaosl.so`, `libagora_rtm_sdk.so`) live in `build/package/bin/` and require `LD_LIBRARY_PATH` configured by `libexec/elegoo-slicer-env`.
- **Fix:** Always invoke the top-level wrapper script, never `bin/elegoo-slicer` directly:
  ```bash
  ~/Workspace/ElegooSlicer/build/package/elegoo-slicer
  ```

### Issue 4: `SIGSEGV` at `0x7` in `Plater::priv::on_select_preset()`

- **Symptom:** Crash (`segfault at 7 ... error 6 in elegoo-slicer`) when selecting a printer preset / closing a blank modal dialog.
- **Root Cause:** Upstream bug in `src/slic3r/GUI/Plater.cpp:9731-9739`: after checking `if (preset == nullptr)` and showing an empty `MessageDialog`, execution falls through without `return;` and executes `preset->is_visible = true;` (offset `0x7` -> `movb $0x1, 0x7(%rax)` with `%rax == 0`).
- **Diagnosis (reusable for future Release crashes):**
  ```bash
  # 1. Get file offset from kernel dmesg:
  sudo dmesg -T | grep -i elegoo | tail -n 5
  # Example: segfault at 7 ip 00005a949a214c84 ... in elegoo-slicer[35d3c84,5a9498879000+57a4000]

  # 2. Check ELF .text LOAD segment VirtAddr vs File Offset delta (here +0x1000 -> 0x35d4c84):
  readelf -l ~/Workspace/ElegooSlicer/build/package/bin/elegoo-slicer | grep LOAD

  # 3. Resolve symbol and disassembly:
  gdb -batch -ex "info symbol 0x35d4c84" -ex "x/15i 0x35d4c60" \
    ~/Workspace/ElegooSlicer/build/package/bin/elegoo-slicer
  ```
- **Fix:** Apply the `Plater.cpp` diff in Step 3 above and incrementally rebuild (see [Incremental Rebuild](#incremental-rebuild)).

### Issue 5: ElegooLink Device UI Missing / Blank

- **Symptom:** ElegooLink initializes, but Device tab web views fail to load and `resources/plugins/elegoolink/web/` does not exist.
- **Root Cause:** `src/slic3r/Utils/Elegoo/ElegooLink.cpp:257` sets `cfg.local.staticWebPath = webDir + "/plugins/elegoolink/web"`, which is populated only when `-w` (or `./scripts/download_web_dep.sh`) is run.
- **Fix:**
  ```bash
  cd ~/Workspace/ElegooSlicer
  ./scripts/download_web_dep.sh
  (cd build && ./src/build_linux_image.sh -R Release)
  ```

### Issue 6: `dep_Boost` Configure Fails Under CMake 4.5 (`source_group` prefix)

- **Symptom:** `FAILED: dep_Boost-configure` with
  ```
  CMake Error at libs/locale/CMakeLists.txt:231 (source_group):
    source_group ".../include/boost/locale" is not a prefix of file ".../include/boost/locale.hpp"
  ```
- **Root Cause:** CMake 4.5 (CachyOS system package) is stricter about `source_group(TREE ...)` prefixes than the vendored Boost's `libs/locale` CMakeLists expects. Upstream CI pins CMake 4.3.0.
- **Fix:** Use CMake 4.3.0 from a venv (see [CachyOS / Arch Build](#cachyos--arch-build)), `rm -rf deps/build`, and re-run. Confirm with `grep 'Build files have been written to.*dep_Boost-build' <log>`.

### Issue 7: `dep_elegoolink` Fails — `'find_if' is not a member of 'std'`

- **Symptom:** `FAILED: dep_elegoolink-build`, `event_system.h:94:28: error: 'find_if' is not a member of 'std'` (in `printer_manager.cpp`, `base_printer.cpp`, ...).
- **Root Cause:** ElegooLink uses `<algorithm>` functions without including the header; it relied on transitive includes that newer libstdc++ (gcc 14+) no longer provides.
- **Fix:** Add `#include <algorithm>` to the six affected files in the extracted dep source, then re-run `build_linux.sh` (Ninja resumes; completed deps aren't rebuilt):
  ```bash
  D=~/Workspace/ElegooSlicer/deps/build/dep_elegoolink-prefix/src/dep_elegoolink
  for f in include/events/event_system.h src/cloud/services/mqtt_service.cpp src/cloud/cloud_service.h \
           src/cloud/services/rtm_service.h src/cloud/cloud_service.cpp src/cloud/services/http_service.cpp; do
    grep -q '#include <algorithm>' "$D/$f" || sed -i '0,/^#include/s//#include <algorithm>\n#include/' "$D/$f"
  done
  ```
- **Caveat:** this edits the extracted copy under `deps/build/`, so it's lost on `rm -rf deps/build` or a re-download. To make it permanent, add it as a `PATCH_COMMAND` in ElegooSlicer's `deps/` ElegooLink CMake (or upstream it). Find affected files with:
  `grep -rln 'std::find_if\|std::remove_if\|std::sort\|std::find(' $D/{include,src} | xargs grep -L '#include <algorithm>'`

---

## Verification

Run after any fresh install or rebuild:

```bash
# 1. Verify top-level wrapper runs cleanly:
~/Workspace/ElegooSlicer/build/package/elegoo-slicer --help | head -n 10

# 2. Verify all shared libraries resolve under the packaged runtime env:
LD_LIBRARY_PATH=~/Workspace/ElegooSlicer/build/package/lib/orca-runtime:~/Workspace/ElegooSlicer/build/package/bin \
  ldd ~/Workspace/ElegooSlicer/build/package/bin/elegoo-slicer | grep "not found" && echo "MISSING LIBS" || echo "ALL LIBS RESOLVED"

# 3. Verify ElegooLink web bundles are staged in build/package:
ls -lh ~/Workspace/ElegooSlicer/build/package/resources/plugins/elegoolink/web/lan_service_web/index.html \
       ~/Workspace/ElegooSlicer/build/package/resources/plugins/elegoolink/web/cloud_service_web/index.html

# 4. Verify profile validator:
~/Workspace/ElegooSlicer/build/src/Release/ElegooSlicer_profile_validator --help

# 5. Runtime logs (after launching GUI):
tail -n 30 ~/.config/ElegooSlicer/log/elegoolink.log
tail -n 30 "$(ls -t ~/.config/ElegooSlicer/log/debug_*.log.0 | head -n 1)"
```

---

## Incremental Rebuild

After editing C++ sources in `src/` (takes ~30–60 seconds with `ccache` + `ld.lld`):

```bash
cd ~/Workspace/ElegooSlicer
cmake --build build --config Release --target ElegooSlicer -j 4
(cd build && ./src/build_linux_image.sh -R Release)
```

## Notes

- **Compiler pinning:** Ubuntu 26.04 defaults to `gcc-15`. Always pin `CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13` to match Ubuntu 24.04 CI and avoid GCC 15 breakage in vendored deps.
- **Config & logs:** Stored in `~/.config/ElegooSlicer/` (`ElegooSlicer.conf`, `log/debug_*.log.0`, `log/elegoolink.log`, `log/rtm.log`).
- **Local patch tracking:** Check `git -C ~/Workspace/ElegooSlicer diff` before pulling upstream updates; `version.inc` is also modified in place by `build_linux.sh`.
- **Docker fallback:** If a future Ubuntu upgrade breaks host headers/libraries, run `./build_linux.sh -g -wdsrL` to build inside the upstream `ubuntu:24.04` Docker runner image.
