# Game of Life on Tang Nano 20K

256×256 toroidal Conway's Game of Life with 7 species (colors), double-buffered in on-chip BRAM, 720p HDMI output. Target: Gowin GW2AR-18 / GW2A-LV18 (Tang Nano 20K).

## Structure

- **src/gol_ram.v** — 64K×4 sync RAM (BRAM inference).
- **src/gol_engine.v** — Update FSM: INIT, READ_CENTER, READ_NEIGHBORS (8), APPLY_RULES, ADVANCE; swap on SOF.
- **src/video_source_gol.v** — Pixel→grid (2×2), 8-color LUT, display-bank read.
- **src/tmds_encoder.v** — 8b/10b TMDS per channel.
- **src/svo_hdmi.v** — 720p60 timing, video_sof, video_source_gol, 3× TMDS encoder.
- **src/pll/TMDS_rPLL.v** — PLL 27→371.25 MHz (in-repo; no submodule needed for PLL).
- **src/top.v** — PLL + CLKDIV + 2× RAM + engine + svo_hdmi + DVI_TX_Top.
- **gol_20k.gprj** — Gowin FPGA project file (same format as antigravityGoL’s `hdmi.gprj`); lists all RTL and constraints so you can open the project directly in Gowin IDE.
- **constraints.cst** — Pin constraints: which FPGA pin is clk, rst, HDMI TMDS, etc. The FPGA has hundreds of pins; without this file the tool would assign signals to arbitrary pins and the board wouldn’t work (e.g. HDMI wouldn’t be on the HDMI connector). Board-specific; from [Sipeed Tang Nano 20K HDMI](https://github.com/sipeed/TangNano-20K-example/tree/main/hdmi).

## You do NOT need RISC-V, Sparrow, LiteX, or any other TangNano-20K-example project

This design is **only** Game of Life + HDMI. The Sipeed repo has RISC-V, Sparrow, LiteX, NES, etc. — **ignore all of them**. You need exactly **one file** from the submodule: Gowin DVI_TX IP (`dvi_tx.v`), which we can’t copy (encrypted). The PLL is in this repo (`src/pll/TMDS_rPLL.v`).

## Build

1. Clone with submodule: `git submodule update --init --recursive` (so `TangNano-20K-example/hdmi/src/dvi_tx/dvi_tx.v` exists).
2. Open **gol_20k.gprj** in Gowin IDE (File → Open Project). The project file already lists all sources and constraints; top module is `top`.
3. Run synthesis and place-and-route; generate bitstream.

If you create a new Gowin project by hand instead: add all `src/*.v`, `src/pll/TMDS_rPLL.v`, and `TangNano-20K-example/hdmi/src/dvi_tx/dvi_tx.v`; add `constraints.cst`; set top to `top`. Do **not** add anything else from the submodule (no RISC-V, LiteX, etc.).

**Current top (`top.v`)** is the full Game of Life (256×256, 7 species, double-buffered). To run the Sipeed test pattern instead, enable `TangNano-20K-example/hdmi/src/video_top.v` and `key_led_ctrl.v`/`testpattern.v`, add a wrapper top that instantiates `video_top`, and set that as top.

**If you get a black screen:** Try a **direct monitor** first — some HDMI recorders or capture devices show black even when the signal is fine; a normal monitor usually works. Then: (1) Press and release the reset button (pin 88) after power-on. (2) To confirm the board, build and program the Sipeed HDMI example (`TangNano-20K-example/hdmi/hdmi.gprj`); if that’s also black on the same display, check cable and power.

## Simulation

See **DEV_GUIDE.md** for segment order and how to run sims (e.g. Icarus Verilog).

```bash
iverilog -o sim/gol_ram.vvp sim/tb_gol_ram.v src/gol_ram.v
vvp sim/gol_ram.vvp
```

## References

- **DEV_GUIDE.md** — Pitfalls, segment order, Tang Nano 20K HDMI notes.
