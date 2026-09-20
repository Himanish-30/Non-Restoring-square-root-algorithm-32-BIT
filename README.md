# 32-bit Non-Restoring Square Root: Gate-Level VHDL

A gate-level VHDL implementation of the modified non-restoring square root algorithm. It takes an unsigned 32-bit number and returns its integer square root and remainder, using **one reusable cell** arranged in a triangular array, with **no adders, no multipliers and no restore step**.

Based on: T. Sutikno, *"An Efficient Implementation of the Non Restoring Square Root Algorithm in Gate Level"*, IJCTE Vol. 3 No. 1, Feb 2011.

**At a glance**

| | |
|---|---|
| Input | unsigned 32-bit radicand `P` |
| Output | 16-bit root `Q = floor(sqrt(P))`, 17-bit remainder `R = P - Q*Q` |
| Language | VHDL (design files are VHDL-93 clean, testbenches use VHDL-2008) |
| Structure | 16-row triangular array of one Controlled Subtract-Multiplex (CSM) cell, 168 cells in total |
| Variants | combinational, minimised-cell, and pipelined (1 result per clock, 17-clock latency) |
| Verification | self-checking testbenches, about 30,000 vectors, simulated in GHDL |
| Tools | GHDL, Xilinx Vivado (xsim and synthesis) |

---

## What this project demonstrates

| Skill | Where to look |
|-------|---------------|
| **Turning a paper into hardware** | Algorithm from a published paper, implemented at gate level and checked against a behavioural model |
| **Datapath design** | Single reusable CSM cell, triangular array, borrow chain kept out of the multiplexer path (`csm.vhd`, `sqrt32.vhd`) |
| **Logic minimisation** | Constant-folded cell variants (modules A-F) that shrink the array (`csm_cells.vhd`, `sqrt32_opt.vhd`) |
| **Pipelining** | One register per row for 1 result per clock (`sqrt32_pipelined.vhd`) with timing constraints (`.xdc`) |
| **Parameterised design** | Generic width `N`; change one generic to get other sizes |
| **Verification discipline** | Property-based checking (`Q*Q <= P < (Q+1)*(Q+1)`), exhaustive plus random plus corner cases, streaming testbench for the pipeline |
| **Tool flow** | GHDL and Vivado xsim scripts, non-project Vivado batch synthesis with reports |

---

## How it works

The algorithm computes one root bit per iteration:

```
Rm = 0 ; Q = 0
for k = 1 .. 16:
    x = (Rm << 2) | next pair of P bits      -- minuend
    y = (Q  << 2) | 1                        -- subtrahend ("append 01")
    if x >= y:  Q = (Q<<1)|1 ;  Rm = x - y
    else:       Q = (Q<<1)|0 ;  Rm = x       -- not restored, just not taken
```

**The CSM cell** (`csm.vhd`) is a 1-bit full subtractor plus a multiplexer:

- `bo` is the borrow out of `x - y - b`
- `d` is the difference bit when the control `u = 1` (keep the subtraction), otherwise it passes `x` through (discard it)

**The array.** Row `k` handles a `(k+2)`-bit minuend, so it contains `k+2` cells. Sixteen rows give 168 cells for 32 bits (120 full CSM cells plus 16 each of the E, F and B minimised types).

```
row 1   [CSM][CSM][CSM]                       -> q15
row 2   [CSM][CSM][CSM][CSM]                  -> q14
  ...
row 16  [CSM] x 18                            -> q0

each row: ripple-borrow chain of CSM cells
          root bit = NOT (final borrow-out)
          partial remainder feeds the next row
```

**Design point worth noting.** The test `x >= y` comes for free as the borrow out (`q = not bo`). Because `bo` never depends on the mux control `u`, the borrow chain settles first and the multiplexers never sit in the critical carry path.

---

## Repository layout

| File | Description |
|------|-------------|
| `csm.vhd` | The CSM cell, gate level |
| `csm_cells.vhd` | Modules A-F: constant-folded CSM variants |
| `sqrt32.vhd` | Top level: combinational 16-row CSM array, generic width |
| `sqrt32_opt.vhd` | Same array built from the minimised cells |
| `sqrt32_pipelined.vhd` | One register per row: 1 result per clock, 17-clock latency |
| `sqrt32_behavioral.vhd` | Behavioural reference model of the same algorithm |
| `tb_sqrt32.vhd` | Self-checking testbench (combinational) |
| `tb_sqrt32_pipelined.vhd` | Streaming testbench (pipelined) |
| `sqrt32_pipelined.xdc` | Timing constraints for the pipelined core |
| `synth_sqrt32.tcl` | Non-project Vivado batch synthesis and reports |

---

## Verification

| Test | Vectors | Result |
|------|---------|--------|
| `tb_sqrt32`: asserts `Q*Q <= P < (Q+1)*(Q+1)` and `R = P - Q*Q` | 4096 exhaustive, perfect squares +/-1, 20,000 pseudorandom, corners including 0 and `0xFFFFFFFF` | PASS |
| `sqrt32` vs `sqrt32_behavioral` | 30,001 | identical Q, R |
| `sqrt32_opt` (both generic settings) vs `sqrt32` | 30,001 | identical |
| `tb_sqrt32_pipelined`: 1 radicand per clock | 20,000 | PASS, latency 17 clocks |

---

## Run it

**GHDL**
```
ghdl -a --std=08 csm.vhd csm_cells.vhd sqrt32.vhd sqrt32_opt.vhd \
                 sqrt32_behavioral.vhd sqrt32_pipelined.vhd tb_sqrt32.vhd
ghdl -e --std=08 tb_sqrt32
ghdl -r --std=08 tb_sqrt32
```
Expected: `ALL TESTS PASSED`

**Vivado xsim (command line)**
```
xvhdl -2008 csm.vhd sqrt32.vhd tb_sqrt32.vhd
xelab -debug typical tb_sqrt32 -s tb_sim
xsim tb_sim -runall
```

**Vivado GUI:** create an RTL project (any 7-series part, e.g. `xc7a35tcpg236-1`), add `csm.vhd` and `sqrt32.vhd` as design sources with `sqrt32` as top, add `tb_sqrt32.vhd` as a simulation source and set its file type to VHDL 2008, then run behavioural simulation and type `run all` in the Tcl console.

**Synthesis**
```
vivado -mode batch -source synth_sqrt32.tcl -tclargs sqrt32
vivado -mode batch -source synth_sqrt32.tcl -tclargs sqrt32_pipelined
```
Reports are written to `./reports/`. Valid tops: `sqrt32`, `sqrt32_opt`, `sqrt32_behavioral`, `sqrt32_pipelined`. The core has 32 input and 33 output data ports, so wrap it (for example counter plus seven-segment, or an ILA) before implementing with real I/O constraints.

**Other widths:** change the generic only (`N` must be even):
```
dut : entity work.sqrt32 generic map (N => 64)
  port map (P => p64, Q => q32, R => r33);
```
A width-`N` core has `N/2` rows and `(N/2)*(N/2+5)/2` cells in total.

<!-- Add here once you have them from the Vivado reports:
| Metric | sqrt32 | sqrt32_pipelined |
|--------|--------|------------------|
| LUTs   |        |                  |
| Max frequency |  |                 |
-->

---

## About the author

**Himanish**, final-year B.Tech, Electronics and Communication Engineering, NIT Rourkela (graduating May 2027). Looking for entry-level **ASIC / RTL design** roles.

GitHub: [Himanish-30](https://github.com/Himanish-30)
<!-- Add: email and LinkedIn -->
