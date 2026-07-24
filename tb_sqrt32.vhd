--------------------------------------------------------------------------------
-- tb_sqrt32.vhd : self-checking testbench for the combinational 32-bit
--                 non-restoring square root array.
--
-- The check is the definition of the integer square root:
--        Q*Q <= P < (Q+1)*(Q+1)      and      R = P - Q*Q
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sqrt32 is
end entity tb_sqrt32;

architecture sim of tb_sqrt32 is

  signal P : std_logic_vector(31 downto 0) := (others => '0');
  signal Q : std_logic_vector(15 downto 0);
  signal R : std_logic_vector(16 downto 0);

  signal errors : integer := 0;

  -- pseudo random generator (32-bit xorshift) so we can sweep a lot of values
  function xorshift (s : unsigned(31 downto 0)) return unsigned is
    variable v : unsigned(31 downto 0) := s;
  begin
    v := v xor (v sll 13);
    v := v xor (v srl 17);
    v := v xor (v sll  5);
    return v;
  end function;

begin

  dut : entity work.sqrt32(csm_array)
    generic map (N => 32)
    port map (P => P, Q => Q, R => R);

  stimulus : process
    variable pv    : unsigned(31 downto 0);
    variable qv    : unsigned(15 downto 0);
    variable rv    : unsigned(16 downto 0);
    variable q2    : unsigned(33 downto 0);
    variable q1sq  : unsigned(33 downto 0);
    variable qp1   : unsigned(16 downto 0);
    variable rnd   : unsigned(31 downto 0) := x"12345678";
    variable nerr  : integer := 0;

    procedure check (val : in unsigned(31 downto 0)) is
    begin
      P <= std_logic_vector(val);
      wait for 10 ns;                       -- let the combinational array settle
      qv := unsigned(Q);
      rv := unsigned(R);
      qp1  := resize(qv, 17) + 1;
      q2   := resize(qv, 17) * resize(qv, 17);
      q1sq := qp1 * qp1;
      if not (q2 <= resize(val, 34) and resize(val, 34) < q1sq) then
        report "SQRT ERROR: P=" & integer'image(to_integer(val(30 downto 0))) &
               " Q=" & integer'image(to_integer(qv)) severity error;
        nerr := nerr + 1;
      elsif resize(rv, 34) /= resize(val, 34) - q2 then
        report "REMAINDER ERROR: P=" & integer'image(to_integer(val(30 downto 0))) &
               " R=" & integer'image(to_integer(rv)) severity error;
        nerr := nerr + 1;
      end if;
    end procedure;

  begin
    -- ---------------------------------------------------------------- corners
    check(to_unsigned(0, 32));
    check(to_unsigned(1, 32));
    check(to_unsigned(2, 32));
    check(to_unsigned(3, 32));
    check(to_unsigned(4, 32));
    check(to_unsigned(27, 32));
    check(to_unsigned(93, 32));            -- the example used in the paper
    check(to_unsigned(16384, 32));         -- Fig.18 of the paper -> 128
    check(to_unsigned(65535, 32));
    check(to_unsigned(65536, 32));
    check(x"FFFFFFFF");
    check(x"FFFFFFFE");

    -- --------------------------------------------------- exhaustive small end
    for i in 0 to 4095 loop
      check(to_unsigned(i, 32));
    end loop;

    -- ----------------------------------------------- perfect squares + / - 1
    for i in 1 to 2000 loop
      check(to_unsigned(i*i, 32));
      check(to_unsigned(i*i - 1, 32));
      check(to_unsigned(i*i + 1, 32));
    end loop;

    -- ------------------------------------------------------------- random set
    for i in 1 to 20000 loop
      rnd := xorshift(rnd);
      check(rnd);
    end loop;

    errors <= nerr;
    if nerr = 0 then
      report "ALL TESTS PASSED" severity note;
    else
      report integer'image(nerr) & " FAILURES" severity failure;
    end if;
    wait;
  end process stimulus;

end architecture sim;
