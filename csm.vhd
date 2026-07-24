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
