# 32-bit Non-Restoring Square Root on FPGA (Gate Level, VHDL)

Gate-level VHDL implementation of the modified non-restoring square root
algorithm from Tole Sutikno, *"An Efficient Implementation of the Non Restoring
Square Root Algorithm in Gate Level"*, IJCTE Vol. 3 No. 1, Feb 2011.

Takes an unsigned **32-bit radicand** `P`, produces a **16-bit root** `Q` and a
**17-bit remainder** `R`, such that `Q = floor(sqrt(P))` and `R = P - Q*Q`.

Built from a single reusable cell -- the **Controlled Subtract-Multiplex (CSM)** --
arranged as a 16-row triangular array. No adders, no multipliers, no restore step.

Verified against ~30,000 vectors in GHDL. Synthesises in Xilinx Vivado.

---

## Repository layout

| File | Description |
|---|---|
| `csm.vhd` | The CSM cell, gate level |
| `csm_cells.vhd` | Modules A-F: constant-folded CSM variants |
| `sqrt32.vhd` | **Top level** -- combinational 16-row CSM array, generic width |
| `sqrt32_opt.vhd` | Same array built from the minimised cells |
| `sqrt32_pipelined.vhd` | One register per row: 1 result/clock, 17-clock latency |
| `sqrt32_behavioral.vhd` | Behavioural reference model of the same algorithm |
| `tb_sqrt32.vhd` | Self-checking testbench (combinational) |
| `tb_sqrt32_pipelined.vhd` | Streaming testbench (pipelined) |
| `sqrt32_pipelined.xdc` | Timing constraints for the pipelined core |
| `synth_sqrt32.tcl` | Non-project Vivado batch synthesis + reports |

---

## Algorithm

```
Rm = 0 ; Q = 0
for k = 1 .. 16:
    x = (Rm << 2) | next pair of P bits      -- minuend
    y = (Q  << 2) | 1                        -- subtrahend ("append 01")
    if x >= y:  Q = (Q<<1)|1 ;  Rm = x - y
    else:       Q = (Q<<1)|0 ;  Rm = x       -- not restored, just not taken
```

`x >= y` is detected for free: it is borrow-out = 0, so the root bit is
`q = not bo`. Because `bo` never depends on the mux control `u`, the borrow
chain settles first and the multiplexers never sit in the critical carry path.

Row `k` handles a `k+2`-bit minuend and therefore contains `k+2` CSM cells.
Total for 32 bits: **168 cells** (120 full CSM + 16 each of the E/F/B minimised
types).

---

## Source

### `csm.vhd`

```vhdl
--------------------------------------------------------------------------------
-- csm.vhd : Controlled Subtract-Multiplex cell
-- Gate-level model, after Fig. 5 / Fig. 15 of
--   T. Sutikno, "An Efficient Implementation of the Non Restoring Square Root
--   Algorithm in Gate Level", IJCTE Vol.3 No.1, Feb 2011.
--
-- Function:  bo = borrow-out of the 1-bit full subtractor (x - y - b)
--            d  = (x xor y xor b)  when u = '1'   (keep the subtraction)
--                 x                when u = '0'   (discard it -> "non restoring")
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity csm is
  port (
    x  : in  std_logic;  -- minuend bit   (current partial remainder)
    y  : in  std_logic;  -- subtrahend bit (partial root with "01" appended)
    b  : in  std_logic;  -- borrow in  (from the cell on the right)
    u  : in  std_logic;  -- control = root bit produced by this row
    d  : out std_logic;  -- result bit -> next row's partial remainder
    bo : out std_logic   -- borrow out (to the cell on the left)
  );
end entity csm;

architecture gate_level of csm is
  -- one product term per input combination x y b that must assert an output
  signal t011, t111, t010, t001, t100 : std_logic;
  signal td : std_logic;
begin
  t011 <= (not x) and      y  and      b;   -- x=0 y=1 b=1
  t111 <=      x  and      y  and      b;   -- x=1 y=1 b=1
  t010 <= (not x) and      y  and (not b);  -- x=0 y=1 b=0
  t001 <= (not x) and (not y) and      b;   -- x=0 y=0 b=1
  t100 <=      x  and (not y) and (not b);  -- x=1 y=0 b=0

  bo <= t011 or t111 or t010 or t001;       -- bo = x'y + yb + x'b
  td <= t100 or t001 or t010 or t111;       -- td = x xor y xor b
  d  <= td when u = '1' else x;             -- the "multiplex" half of the cell
end architecture gate_level;
```

### `sqrt32.vhd`

```vhdl
--------------------------------------------------------------------------------
-- sqrt32.vhd : unsigned 32-bit radicand -> 16-bit root, 17-bit remainder
-- Purely combinational CSM array (the unrolled version of Fig. 6 / Fig. 8).
--
--   Q = floor(sqrt(P))            R = P - Q*Q
--
-- Row k (k = 1 .. 16) performs one iteration:
--      x_k = rem(k-1) & P(33-2k downto 32-2k)      (shift 2 bits in)
--      y_k = 0 & q(15 downto 16-k+1) & "01"        (append 01 to the root)
--      q_k = not borrow_out(x_k - y_k)             (root bit of this row)
--      rem(k) = (q_k = '1') ? x_k - y_k : x_k      (never restore, just select)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity sqrt32 is
  generic (
    N : integer := 32                       -- radicand width, must be even
  );
  port (
    P : in  std_logic_vector(N-1 downto 0); -- radicand
    Q : out std_logic_vector(N/2-1 downto 0);   -- square root
    R : out std_logic_vector(N/2 downto 0)      -- remainder P - Q*Q
  );
end entity sqrt32;

architecture csm_array of sqrt32 is

  constant M : integer := N/2;      -- 16 root bits  = 16 rows
  constant W : integer := M + 2;    -- 18 = width of the widest (last) row

  -- One fixed-width slot per row; only the low (k+2) bits of row k are wired.
  type mat_t is array (0 to M) of std_logic_vector(W-1 downto 0);
  type brw_t is array (0 to M) of std_logic_vector(W   downto 0);

  signal xr : mat_t := (others => (others => '0'));  -- minuend of each row
  signal yr : mat_t := (others => (others => '0'));  -- subtrahend of each row
  signal dr : mat_t := (others => (others => '0'));  -- CSM result bits
  signal rr : mat_t := (others => (others => '0'));  -- partial remainder chain
  signal br : brw_t := (others => (others => '0'));  -- borrow chain of each row
  signal qi : std_logic_vector(M-1 downto 0);        -- root bits

begin

  ------------------------------------------------------------------------------
  -- rr(0) is the "remainder before the first row" : a single zero bit.
  ------------------------------------------------------------------------------
  rr(0) <= (others => '0');

  rows : for k in 1 to M generate
  begin
    ----------------------------------------------------------------------------
    -- minuend : previous remainder shifted left 2, next radicand pair appended
    ----------------------------------------------------------------------------
    xr(k)(1 downto 0)   <= P(N-2*k+1 downto N-2*k);
    xr(k)(k+1 downto 2) <= rr(k-1)(k-1 downto 0);

    ----------------------------------------------------------------------------
    -- subtrahend : root found so far, with "01" appended, zero extended by 1
    ----------------------------------------------------------------------------
    yr(k)(0)   <= '1';
    yr(k)(1)   <= '0';
    yr(k)(k+1) <= '0';
    root_so_far : if k > 1 generate
      yr(k)(k downto 2) <= qi(M-1 downto M-k+1);
    end generate root_so_far;

    ----------------------------------------------------------------------------
    -- the ripple-borrow row of CSM cells : k+2 cells, LSB first
    ----------------------------------------------------------------------------
    br(k)(0) <= '0';                       -- no borrow into the LSB cell

    cells : for j in 0 to k+1 generate
      cell_j : entity work.csm(gate_level)
        port map (
          x  => xr(k)(j),
          y  => yr(k)(j),
          b  => br(k)(j),
          u  => qi(M-k),                   -- broadcast root bit of this row
          d  => dr(k)(j),
          bo => br(k)(j+1)
        );
    end generate cells;

    ----------------------------------------------------------------------------
    -- root bit = complement of the final borrow-out (subtraction succeeded)
    ----------------------------------------------------------------------------
    qi(M-k) <= not br(k)(k+2);

    ----------------------------------------------------------------------------
    -- remainder passed to the next row : k+1 bits, MSB of the row is dropped
    ----------------------------------------------------------------------------
    rr(k)(k downto 0) <= dr(k)(k downto 0);
  end generate rows;

  Q <= qi;
  R <= rr(M)(M downto 0);

end architecture csm_array;
```

The remaining sources (`csm_cells.vhd`, `sqrt32_opt.vhd`,
`sqrt32_pipelined.vhd`, `sqrt32_behavioral.vhd` and the two testbenches) are in
the repository root.

---

## Simulation

### GHDL

```bash
ghdl -a --std=08 csm.vhd csm_cells.vhd sqrt32.vhd sqrt32_opt.vhd \
                 sqrt32_behavioral.vhd sqrt32_pipelined.vhd tb_sqrt32.vhd
ghdl -e --std=08 tb_sqrt32
ghdl -r --std=08 tb_sqrt32
```

Expected output:

```
tb_sqrt32.vhd:104:7:@301080ns:(report note): ALL TESTS PASSED
```

### Vivado XSim (command line)

```bash
xvhdl -2008 csm.vhd sqrt32.vhd tb_sqrt32.vhd
xelab -debug typical tb_sqrt32 -s tb_sim
xsim tb_sim -runall
```

### Vivado GUI

1. RTL project, part `xc7a35tcpg236-1` (any 7-series works).
2. Add `csm.vhd` + `sqrt32.vhd` as design sources; set `sqrt32` as top.
3. Add `tb_sqrt32.vhd` as a simulation source, then right-click it ->
   **Set File Type -> VHDL 2008** (the testbench uses `sll`/`srl` on `unsigned`;
   the design files are VHDL-93 clean).
4. Run Behavioral Simulation, then type `run all` in the Tcl console -- the
   default 1000 ns runtime stops before the testbench finishes.

---

## Synthesis

```bash
vivado -mode batch -source synth_sqrt32.tcl -tclargs sqrt32
vivado -mode batch -source synth_sqrt32.tcl -tclargs sqrt32_pipelined
```

Reports land in `./reports/`. Valid tops: `sqrt32`, `sqrt32_opt`,
`sqrt32_behavioral`, `sqrt32_pipelined`.

The core has 32 input + 33 output data ports, so it will not pin out directly on
a small dev board. Wrap it (counter + seven-segment, or an ILA) before running
implementation with real I/O constraints.

---

## Verification

| Test | Vectors | Result |
|---|---|---|
| `tb_sqrt32` -- asserts `Q*Q <= P < (Q+1)*(Q+1)` and `R = P - Q*Q` | 4096 exhaustive + perfect squares +/-1 + 20,000 pseudorandom + corners incl. `0` and `0xFFFFFFFF` | PASS |
| `sqrt32` vs `sqrt32_behavioral` | 30,001 | identical `Q`, `R` |
| `sqrt32_opt` (both generic settings) vs `sqrt32` | 30,001 | identical |
| `tb_sqrt32_pipelined` -- 1 radicand/clock | 20,000 | PASS, latency 17 clocks |

---

## Other widths

Change the generic only. `N` must be even.

```vhdl
dut : entity work.sqrt32 generic map (N => 64)
  port map (P => p64, Q => q32, R => r33);
```

`M = N/2` rows, bottom row `N/2 + 2` cells, total `(N/2)*(N/2+5)/2` cells.

---



