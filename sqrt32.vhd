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
