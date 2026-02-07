# Game of Life on Tang Nano 20K — Developer Guide

## Key constraints (pitfalls to avoid)

1. **Grid RAM in separate modules only**  
   Use `gol_ram.v` with `reg [3:0] mem [0:65535]` so Gowin infers BRAM/BSRAM — not DFFs. Never put large arrays inside the FSM module (`gol_engine.v`).

2. **1-cycle RAM read latency**  
   Address on cycle N → data on cycle N+1. The FSM must pipeline: never use "this cycle's" read data for "this cycle's" write or state transition. Same for video: present address one cycle before using species for color.

3. **Buffer swap only on SOF**  
   Flip `ram_select` (which bank is display vs update) only on `video_sof` (start of frame). Never write to the display bank.

4. **No large arrays in the FSM**  
   Keep only small counters, state registers, and pipeline registers in `gol_engine.v`. All grid storage stays in `gol_ram.v` instances.

## Build order (segments)

Work in segments; verify each before moving on:

1. **Segment 1 — RAM**: `DEV_GUIDE.md`, `gol_ram.v`, minimal top with 2× RAM, testbench. Sim: write/read, 1-cycle latency. Synth: BRAM/BSRAM for 2× 64K×4.
2. **Segment 2 — Engine**: `gol_engine.v`, testbench, top with 2× RAM + engine. Sim: init, one-cell update, SOF swap. Synth: DFF count reasonable, no BRAM in FSM.
3. **Segment 3 — Video + HDMI**: `tmds_encoder.v`, `svo_hdmi.v`, `video_source_gol.v`. Sim where useful; synth per block.
4. **Segment 4 — Integration**: `top.v`, `constraints.cst`. Full synth, timing closure, on-board check.

## Running simulation

- Testbenches live in `sim/` (e.g. `tb_gol_ram.v`, `tb_gol_engine.v`).
- With **Icarus Verilog** (install from http://iverilog.icarus.com/ or package manager):
  ```bash
  iverilog -o sim/gol_ram.vvp sim/tb_gol_ram.v src/gol_ram.v
  vvp sim/gol_ram.vvp
  ```
  Expected: `PASS: write/read and 1-cycle read latency`
- With **Gowin IDE**: add the testbench and RTL to the project, run simulation from the GUI.
- **Segment 1 synthesis**: Use `top_ram.v` as top with `src/gol_ram.v`; check resource report for BRAM/BSRAM (2× 64K×4), no large DFF in RAM.
- Run sims after each segment to confirm behavior before synthesis.

## Tang Nano 20K HDMI (Sipeed example)

- **Submodule**: `TangNano-20K-example/` — run `git submodule update --init --recursive` to clone. The HDMI example is in **TangNano-20K-example/hdmi/**:
  - **hdmi/src/gowin_rpll/TMDS_rPLL.v** — PLL: 27 MHz → 371.25 MHz serial clock; use with CLKDIV/5 for 74.25 MHz pixel clock.
  - **hdmi/src/dvi_tx/** — DVI_TX_Top (encoder + OSER10 + ELVDS) and supporting files.
  - **hdmi/src/hdmi.cst** — pin constraints; **video_top.v** — 720p timing, testpattern, PLL + DVI_TX wiring.
- **This project**: `constraints.cst` is adapted from Sipeed's `hdmi.cst`. For a working HDMI bitstream, add the PLL and DVI_TX from the submodule (e.g. copy or reference `TangNano-20K-example/hdmi/src/gowin_rpll/` and `dvi_tx/`) and wire them in `top.v` instead of the placeholder.
