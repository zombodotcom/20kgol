# Game of life on Tang Nano 20K
_Exported on 2/6/2026 at 08:33:56 CST from Cursor (2.4.28)_

---

**User**

# Game of Life on Tang Nano 20K — Project Brief

The Tang Nano 20K is a massive upgrade from what you were working with before. You've got **20,736 LUTs** and **15,552 DFFs** instead of the ~6,693 DFF limit you were fighting. Plus it has **HDMI out natively** via the onboard connector, same Gowin toolchain, and plenty of BRAM/PSRAM.

Here's the plan:

---

## The Vision

A **256×256 toroidal Game of Life** with 7 species (colors), running at ~30+ FPS, output over HDMI at 1080p (or 720p). The grid is rendered as scaled pixels so each cell is visible. The Tang Nano 20K makes this much more comfortable — no more agonizing over every DFF.

## Architecture Overview

**Three main modules:**

**`gol_engine.v`** — The update FSM. Iterates through all 65,536 cells each generation, reads 8 neighbors from RAM (toroidal wrap), applies Conway rules, writes the result to the opposite buffer. Double-buffered so display never sees partial updates.

**`video_source_gol.v`** — Maps HDMI pixel coordinates to grid coordinates, reads the display buffer, and outputs RGB based on species (0=dead/black, 1–7 = distinct colors). Handles layout: top info bar, grid area, bottom bar.

**`svo_hdmi.v`** (or equivalent top-level) — Generates HDMI timing signals (1080p or 720p), drives the TMDS output on the Tang Nano 20K's HDMI connector, manages clock domains (pixel clock from on-chip PLL), and triggers generation updates via `video_sof` (start-of-frame).

## Key Constraints (still apply)

- **Grid RAM in separate modules** (`gol_ram.v`): `reg [3:0] mem [0:65535]`, synchronous read/write, so Gowin infers PSRAM/BRAM — not DFFs. Never put large arrays in the FSM module.
- **Double buffering**: `ram_select` flips which bank is read (display) vs written (update). Swap ONLY on `video_sof`. Never write to the display bank.
- **1-cycle RAM read latency**: Address on cycle N → data on cycle N+1. The FSM must pipeline accordingly. Don't use "current cycle" read data for current cycle decisions.
- **Toroidal wrap**: x and y wrap with 8-bit unsigned arithmetic (256×256 grid, so `x-1` when x=0 becomes 255 automatically).
- **Address**: `addr = {y[7:0], x[7:0]}` — 16-bit, simply concatenate.

## What's Different on the 20K

- **DFF budget is ~15,552** instead of 6,693. Still keep RAM in dedicated modules, but the FSM can be a bit more comfortable — small counters, state registers, etc. are fine.
- **HDMI connector is onboard** — use Gowin's OSER10/ELVDS primitives or an open-source HDMI module (like the `svo_hdmi` approach from the previous project, or the HDMI examples from sipeed/TangNano-20K-example).
- **27 MHz crystal** on board; use the Gowin rPLL to generate pixel clock (74.25 MHz for 720p, 148.5 MHz for 1080p). 720p is the safer bet for timing closure.
- **PSRAM**: The 20K has 2× HyperRAM chips (64Mbit total), but for this project on-chip BRAM (41× B-SRAM blocks of 18Kbit each) is simpler and sufficient for 2× 64K×4-bit buffers.

## FSM Design (gol_engine)

States for processing each cell:
1. **READ_CENTER** — Read current cell from source bank. Set up first neighbor address.
2. **READ_NEIGHBORS** (8 cycles) — Pipeline: each cycle sets the next neighbor address while accumulating the count from the previous cycle's read. Use `same_species_count` and `any_alive_count` as needed for your species rules.
3. **APPLY_RULES** — Standard Conway: alive + (2 or 3 neighbors) → survive; dead + (exactly 3) → birth (inherit majority species or pick one). Write result to dest bank.
4. **ADVANCE** — Move to next cell. After all 65,536: signal done, wait for next SOF swap.

**Optimizations** (safe):
- Early exit: if neighbor count ≥ 4 during accumulation, skip remaining neighbors (cell dies regardless).
- Skip write: if new state == old state, don't write (dest bank retains previous gen's value since it was the display bank last frame — only valid with double buffering).

## Species / Color Rules

- Dead = 0, species 1–7.
- Birth: exactly 3 alive neighbors → new cell takes the majority species among those 3 (or any tiebreak rule you like).
- Survival: 2 or 3 alive neighbors → keep current species.
- Death: otherwise → 0.

## Video Output

- 720p (1280×720) is recommended. Each grid cell = 2×2 pixels gives a 512×512 pixel game area, centered with bars.
- Color palette: 8 entries (index 0 = black, 1–7 = distinct colors). Simple LUT, no computation.
- `gol_x = (pixel_x - GRID_OFFSET_X) >> 1`, same for y. Out-of-bounds pixels → black.

## File Structure

```
src/
  top.v              — Pin assignments, PLL, instantiate svo_hdmi
  svo_hdmi.v         — HDMI timing + TMDS encoding, update_interval, video_sof
  video_source_gol.v — Pixel-to-grid mapping, color LUT, layout
  gol_engine.v       — GoL FSM, double-buffer control
  gol_ram.v          — Simple synchronous 64K×4 RAM module (instantiate 2×)
  tmds_encoder.v     — TMDS 8b/10b (unless using Gowin primitives)
constraints.cst      — Pin constraints for Tang Nano 20K HDMI + clock
```

## Init / Seed

On reset, write a seed pattern (R-pentomino, acorn, or random via LFSR) into both RAM banks. An LFSR-based random fill with ~25% density makes for a great demo. Seed can be baked into the FSM's init state.

## Summary for the AI doing the implementation

> You're building Conway's Game of Life on a **Gowin GW2A-LV18PG256C8/I7** (Tang Nano 20K). 256×256 toroidal grid, 7 species, double-buffered in on-chip BRAM, HDMI 720p output. Read the DEV_GUIDE.md for pitfalls — especially: RAM in separate modules, 1-cycle read latency pipelining, swap on SOF only, no large arrays in the FSM. You have more DFFs than the old board but the same architectural rules apply. Start with `gol_ram.v`, then `gol_engine.v`, then video/HDMI integration. Test synthesis after each module to verify BRAM inference and DFF count.


---

**Cursor**


Exploring the codebase and any existing docs or modules to draft an implementation plan.



Checking for Tang Nano 20K pin/HDMI references and Gowin BRAM inference patterns:



Creating the implementation plan:


---

**User**

we should be doing this in segments and tdd ion parts to confirm what is working 

---

**Cursor**


Updating the plan to build in segments with verification (simulation/synthesis) at each step so we confirm each part works before moving on.



Adding a segment-based structure with explicit verification (simulation + synthesis) at each step.



Summary of what’s in the plan:

**1. Segment-based build**
- **Segment 1 — RAM**: `DEV_GUIDE.md`, `gol_ram.v`, minimal top with 2× RAM, testbench.
- **Segment 2 — Engine**: `gol_engine.v`, testbench, top with 2× RAM + engine.
- **Segment 3 — Video + HDMI**: `tmds_encoder.v`, `svo_hdmi.v`, `video_source_gol.v` (with sim/synth where useful).
- **Segment 4 — Integration**: full `top.v`, `constraints.cst`, timing closure, on-board check.

**2. TDD-style verification**
For each segment the plan defines what must pass before moving on:

- **Segment 1**: Sim — write/read several addresses, assert 1-cycle read latency and correct data. Synth — BRAM/BSRAM for 2× 64K×4, no large DFF in RAM.
- **Segment 2**: Sim — reset → init writes both banks; fixed SOF; a few cells and one known cell (e.g. R-pentomino) correct; buffer swap only on SOF. Synth — DFF count reasonable, no BRAM in FSM.
- **Segment 3**: Sim (where useful) — timing counts, pixel→grid, color LUT. Synth — each block builds without inference surprises.
- **Segment 4**: Full synth and timing at 74.25 MHz; on-board HDMI shows grid / running GoL (or test pattern).

**3. Testbenches**
- **sim/tb_gol_ram.v** — Segment 1.
- **sim/tb_gol_engine.v** — Segment 2.
- DEV_GUIDE (or README) documents how to run sims (e.g. `iverilog` or Gowin).

**4. Todos**
The plan’s todo list is updated to these four segments so you can track and complete them one by one.

So the plan is now: implement in segments and confirm each part with simulation and synthesis before moving to the next. If you want, we can add a fifth segment (e.g. “HDMI test pattern only”) or more detail for any segment’s tests.

