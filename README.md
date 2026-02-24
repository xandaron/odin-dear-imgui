# odin-dear-imgui

Odin bindings for [Dear ImGui](https://github.com/ocornut/imgui) **v1.92.6-docking**, generated via [odin-c-bindgen](https://github.com/karl-zylinski/odin-c-bindgen) on top of [Dear Bindings](https://github.com/dearimgui/dear_bindings) — a C header generator that wraps the Dear ImGui C++ API into a clean C API (`dcimgui.h` / `dcimgui_internal.h`).

The generated Odin package lives in `imgui/` under the package name `ImGui`.

---

## Features

- Full bindings for the public Dear ImGui API (`dcimgui.h`) and internal API (`dcimgui_internal.h`)
- Docking branch support (`IMGUI_HAS_DOCK`)
- Backend bindings for **GLFW** (platform) and **Vulkan** (renderer)
- Cross-platform: Windows, Linux, macOS, WASM
- Idiomatic Odin: `Im`/`ImGui` prefixes stripped, flag enums converted to `bit_set`, and many types remapped to native Odin equivalents including generic types such as `Vector`, `Span`, `Pool`, `ChunkStream`, and `StableVector`

---

## Prerequisites

### Odin

A recent [Odin nightly](https://odin-lang.org/docs/install/) is recommended.

### STB vendor libraries

The package links against several STB libraries that ship with Odin but must be compiled before first use:

```sh
make -C "<ODIN_ROOT>/vendor/stb/src"
```

This produces `stb_truetype`, `stb_rect_pack`, and `stb_sprintf` — all required by Dear ImGui.

### Pre-compiled Dear ImGui static library

A compiled Dear ImGui static library must be present in the `imgui/` folder. The expected file names are:

| OS      | Architecture | File name                  |
|---------|--------------|----------------------------|
| Windows | x64          | `imgui_windows_x64.lib`    |
| Windows | arm64        | `imgui_windows_arm64.lib`  |
| Linux   | x64          | `imgui_linux_x64.a`        |
| Linux   | arm64        | `imgui_linux_arm64.a`      |
| macOS   | x64          | `imgui_darwin_x64.a`       |
| macOS   | arm64        | `imgui_darwin_arm64.a`     |

A pre-built `imgui_windows_x64.lib` is included. For other platforms you will need to compile Dear ImGui yourself and place the resulting library in `imgui/`.

> ⚠️ **`imconfig.h` must match — see the [Compiling the ImGui library](#compiling-the-imgui-library) section below.**

---

## Usage

Import the `imgui/` directory as a package in your project:

```odin
import imgui "path/to/imgui"
```

### Backends

Backend bindings live in sub-packages:

| Backend | Sub-package path |
|---------|-----------------|
| GLFW    | `imgui/glfw`    |
| Vulkan  | `imgui/vulkan`  |

ImGui provides more example backends that haven't been included here. If you would like to rewrite one of these backends into Odin and add it to this binding feel free to create a PR.

---

## Compiling the ImGui library

When compiling Dear ImGui into a static library, you **must** compile it with the same `imconfig.h` that lives in `headers/imconfig.h`. This file controls compile-time options that affect data structure layouts and ABI. If the library is compiled with different settings than those used when the bindings were generated, you could get silent memory corruption or crashes at runtime.

The active non-default settings in `headers/imconfig.h` that are particularly important are:

| Define | Effect |
|---|---|
| `IMGUI_DISABLE_OBSOLETE_FUNCTIONS` | Removes deprecated API — affects available symbols |
| `IMGUI_DISABLE_DEFAULT_ALLOCATORS` | Removes default `malloc`/`free` — you must call `ImGui.SetAllocatorFunctions()` |
| `IMGUI_USE_STB_SPRINTF` | Switches the internal formatter to `stb_sprintf` |
| `IMGUI_DISABLE_STB_TRUETYPE_IMPLEMENTATION` | Uses the external STB truetype library instead of the embedded copy |
| `IMGUI_DISABLE_STB_RECT_PACK_IMPLEMENTATION` | Uses the external STB rect_pack library instead of the embedded copy |
| `IMGUI_DISABLE_STB_SPRINTF_IMPLEMENTATION` | Uses the external STB sprintf library instead of the embedded copy |
| `IMGUI_ENABLE_WIN32_DEFAULT_IME_FUNCTIONS` | Links against `imm32` on Windows for IME support |

---

## Regenerating / Updating the Bindings

The Odin bindings are generated from the C headers in `headers/` using odin-c-bindgen, configured by the two SJSON files at the project root.

| Config file              | Input header                 | Output                        |
|--------------------------|------------------------------|-------------------------------|
| `dcimgui.sjson`          | `headers/dcimgui.h`          | `imgui/dcimgui.odin`          |
| `dcimgui_internal.sjson` | `headers/dcimgui_internal.h` | `imgui/dcimgui_internal.odin` |

### Steps to update to a new ImGui version

1. Download the latest docking-branch C headers from the [Dear Bindings releases page](https://github.com/dearimgui/dear_bindings/releases) — grab the `AllBindingFiles.zip` for the `docking` variant.
2. Replace `headers/dcimgui.h` and `headers/dcimgui_internal.h` with the new files.
3. Review any changes to `imconfig.h` in the new Dear ImGui release. If you need to update `headers/imconfig.h`, you must also recompile the Dear ImGui static library (see [Compiling the ImGui library](#compiling-the-imgui-library)).
4. Recompile the Dear ImGui static library using the updated sources and the `headers/imconfig.h` from this repo, then place the result in `imgui/`.
5. Re-run odin-c-bindgen with `dcimgui.sjson` and `dcimgui_internal.sjson`.
6. Review any new types, functions, or flags that may need to be added to the SJSON configs.

> ⚠️ **Important — check the include in `dcimgui_internal.h`**
>
> After replacing `headers/dcimgui_internal.h` with a freshly downloaded file, open it and check whether it contains:
>
> ```c
> #include "imgui.h"
> ```
>
> If it does, **replace it** with:
>
> ```c
> #include "dcimgui.h"
> ```
>
> The bindgen tool parses the C API headers, not the original C++ ones. Without this fix, parsing `dcimgui_internal.h` will produce errors.

---

## License

- Dear ImGui — MIT license (see `backends/LICENSE.txt`)
- Dear Bindings — MIT license (see `headers/LICENSE.txt`)