---
title: "Adding DFRobot UniHiker K10 support to MicroPythonOS"
description: "Walking through the hardware bring-up work to add the DFRobot UniHiker K10 (ESP32-S3) to MicroPythonOS: USB identity issues, a 1GB memory allocation bug, cold-boot DMA exhaustion, and why the fix ultimately required freezing the board module into firmware."
pubDate: 2026-06-16
tags: ["embedded", "MicroPython", "ESP32", "hardware", "open-source"]
---

I've been using the DFRobot UniHiker K10 as a touchscreen interface for Home Assistant —
buttons, display, a proper enclosure. At some point I wanted to run
[MicroPythonOS](https://github.com/MicroPythonOS/MicroPythonOS) on it, which is an
Android/iOS-inspired launcher for ESP32 devices built on top of LVGL and MicroPython.

The K10 wasn't in the supported board list. So I added it.

This is the story of what that took — not a tutorial, just an honest account of the
problems I ran into and how I solved them. The upstream PR is
[#165](https://github.com/MicroPythonOS/MicroPythonOS/pull/165).

---

## The hardware

The K10 is an ESP32-S3 with a 240×320 ILI9341 display over SPI, an XL9535 I2C GPIO
expander, two physical buttons (A and B), a camera, microphone, and speaker. The display
SPI runs on host 1 (FSPI/SPI2) with CLK on GPIO12 — that pin is on the IO_MUX fast path,
which matters at 40 MHz. The backlight isn't a GPIO; it's behind the XL9535 expander at
I2C address 0x20, pin P0.0.

None of this is exotic. The ESP32-S3 is well-supported in MicroPython. The ILI9341 driver
exists. The XL9535 is straightforward. The question was whether these pieces would compose
correctly in MicroPythonOS's initialization sequence.

They didn't, out of the box.

---

## Problem 1: USB identity

The K10 ships with `303a:1001` — USB-Serial-JTAG. MicroPythonOS builds firmware with
`303a:4001` — USB CDC OTG. Different USB interface entirely.

This matters because `mpremote`, the standard MicroPython tooling, tries to toggle DTR/RTS
control lines to enter raw REPL mode. On a USB CDC device, `TIOCMBIC` rejects those
ioctl calls. `mpremote` either hangs or errors out depending on how it handles the failure.

The fix is to stop using `mpremote` for raw REPL entry and talk to the device directly via
pyserial with flow control disabled, using paste mode (Ctrl+E / Ctrl+D) instead of raw
mode (Ctrl+A). This works reliably and is actually how several ESP32 flashing tools handle
CDC devices anyway. Once I understood what was happening at the USB layer, this took about
twenty minutes to sort out. The two-hour rabbit hole happened before I understood it.

---

## Problem 2: The 1GB memory allocation

The first time I called `ILI9341.init()` with no arguments, I got a `MemoryError`
originating from `lv.display_create(240, 320)`.

On an ESP32-S3 with a few hundred KB of internal SRAM, a `MemoryError` during display
initialization is easy to misread as "not enough RAM for LVGL." That's not what was
happening.

`ILI9341.init()` with no argument passes `type=0`. The LVGL display driver reads an
internal initialization table indexed by that type value. At `type=0`, it reads an
uninitialized entry in that table and uses whatever value is there as the frame buffer
size. In this case, that value was something in the neighborhood of 1GB.

The fix is to call `init(2)` explicitly — which selects the correct initialization path
for the ILI9341. One character difference in the call. About two hours to find it, because
the stack trace pointed at `lv.display_create` and I spent a long time looking at LVGL
internals before tracing backward into the driver's init table.

This is the kind of bug that's embarrassing in retrospect and completely opaque in the
moment.

---

## Problem 3: Cold-boot DMA exhaustion

After fixing the init call, everything worked correctly from a warm REPL session — one
where I'd already imported the mpos modules interactively. The display came up. LVGL
initialized. The board detection ran correctly.

Cold boot was a different story. The firmware would panic during display initialization
before completing the boot sequence.

The issue is SRAM pressure during cold boot. When MicroPythonOS imports its modules
from the filesystem during startup, those imports consume internal SRAM before the display
driver even runs. The ILI9341 frame buffer allocation requests `MEMORY_INTERNAL | MEMORY_DMA`
— it has to be internal SRAM for DMA to work. By the time the display init runs at cold
boot, the DMA-capable region is exhausted.

The solution is to freeze the board module into the firmware rather than deploying it as
a `.py` file. Frozen modules live in flash and their bytecode is executed in-place, so they
don't consume internal SRAM for the module object the way filesystem modules do. This
reclaims enough internal SRAM that the frame buffer allocation succeeds at cold boot.

This is why the build step isn't optional. You can't deploy the `unihiker_k10.py` board
file and expect a cold boot to work. It has to be compiled into the firmware.

---

## CI instead of a 45-minute local build

The MicroPythonOS firmware build is not quick. Submodule initialization, CMake, a full
LVGL compile — end-to-end it takes over 45 minutes on my workstation and longer on slower
machines. Doing this in a tight feedback loop while debugging cold-boot panics wasn't viable.

The project has GitHub Actions CI. I pushed my branch, triggered the workflow, and waited
17 minutes for the build artifact. Downloaded it, flashed it. The GitHub Actions runner is
faster than my local build setup for this particular workload because the runner has better
I/O and the submodule cache is warmer.

This is mundane in most software contexts. For embedded firmware, having a working CI
pipeline that produces flashable artifacts is genuinely valuable and not always a given.

---

## Board detection

MicroPythonOS detects hardware by checking the device's WiFi MAC address prefix. It's a
clean approach — no I2C probing, no GPIO sniffing, no fragile string matching in
`sys.platform`. The MAC prefix is stable and unique to each hardware variant.

The K10's prefix is `b'\x1c\xdb\xd4'`. Four lines in `main.py`:

```python
elif mac[:3] == b'\x1c\xdb\xd4':
    board_name = "unihiker_k10"
```

The board module itself is `board/unihiker_k10.py` — 186 lines that wire up the SPI
display, configure the XL9535 backlight and button inputs (BTN_A on P1.4, BTN_B on P0.2 of
the expander), and register a keypad indev with LVGL.

---

## The result

Serial REPL after a clean cold boot on MicroPythonOS 0.12.3 built from the branch:

```
detect_board(): 'unihiker_k10'
lv.is_initialized(): True
mpos.ui.main_display: <ILI9341 object at 3c367a60>
display resolution: 240 x 320
XL9535 backlight ON: True
BTN_A pressed: False / BTN_B pressed: False
```

Screen lights up. MicroPythonOS UI loads. Buttons navigate the launcher.

---

## The PR

Two files changed in [PR #165](https://github.com/MicroPythonOS/MicroPythonOS/pull/165):
4 lines in `main.py` for MAC-based detection and 186 lines for `board/unihiker_k10.py`.

Worth noting: I've been using and following open source projects for years but this is my
first time actually contributing back to one at this scale. The MicroPythonOS codebase has
a clean, consistent pattern for board modules — it was readable enough that a first-time
contributor could follow it, understand the conventions, and add something without breaking
the existing architecture. That's a sign of a well-maintained project.

Whether the PR merges upstream is up to the maintainers. Either way, the work is done, it's
documented, and the branch builds a flashable artifact.

The K10 is a capable piece of hardware at a reasonable price point. If you're building
anything that needs a small touchscreen, physical buttons, and a real MicroPython OS on
top — this is a solid option.
