--------------------------------------------------------------------------------
-- tb_sqrt32_pipelined.vhd : streams one radicand per clock into the pipelined
-- array and checks every result that comes out 17 clocks later.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sqrt32_pipelined is
end entity tb_sqrt32_pipelined;

architecture sim of tb_sqrt32_pipelined is

  constant TCLK  : time    := 10 ns;
  constant NVEC  : integer := 20000;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal start  : std_logic := '0';
  signal P      : std_logic_vector(31 downto 0) := (others => '0');
  signal Q      : std_logic_vector(15 downto 0);
  signal R      : std_logic_vector(16 downto 0);
  signal dvalid : std_logic;
  signal done   : boolean := false;

  type vec_t is array (0 to NVEC-1) of unsigned(31 downto 0);
  signal vectors : vec_t;

  function xorshift (s : unsigned(31 downto 0)) return unsigned is
    variable v : unsigned(31 downto 0) := s;
  begin
    v := v xor (v sll 13);
    v := v xor (v srl 17);
    v := v xor (v sll  5);
    return v;
  end function;

begin

  clk <= not clk after TCLK/2 when not done else '0';

  dut : entity work.sqrt32_pipelined(csm_pipe)
    generic map (N => 32)
    port map (clk => clk, rst => rst, start => start,
              P => P, Q => Q, R => R, dvalid => dvalid);

  ------------------------------------------------------------------ stimulus
  drive : process
    variable rnd : unsigned(31 downto 0) := x"9E3779B9";
    variable v   : vec_t;
  begin
    for i in 0 to NVEC-1 loop
      if i < 1000 then
        v(i) := to_unsigned(i, 32);          -- small values first
      else
        rnd  := xorshift(rnd);
        v(i) := rnd;
      end if;
    end loop;
    vectors <= v;

    wait for 5*TCLK;
    rst <= '0';
    wait until rising_edge(clk);

    for i in 0 to NVEC-1 loop
      P     <= std_logic_vector(v(i));
      start <= '1';
      wait until rising_edge(clk);
    end loop;
    start <= '0';
    wait;
  end process drive;

  ------------------------------------------------------------------- checker
  check : process
    variable idx  : integer := 0;
    variable qv   : unsigned(15 downto 0);
    variable rv   : unsigned(16 downto 0);
    variable qp1  : unsigned(16 downto 0);
    variable q2   : unsigned(33 downto 0);
    variable q1sq : unsigned(33 downto 0);
    variable pv   : unsigned(31 downto 0);
    variable nerr : integer := 0;
  begin
    loop
      wait until rising_edge(clk);
      if dvalid = '1' then
        pv   := vectors(idx);
        qv   := unsigned(Q);
        rv   := unsigned(R);
        qp1  := resize(qv, 17) + 1;
        q2   := resize(qv, 17) * resize(qv, 17);
        q1sq := qp1 * qp1;
        if not (q2 <= resize(pv, 34) and resize(pv, 34) < q1sq) then
          report "ERROR at vector " & integer'image(idx) severity error;
          nerr := nerr + 1;
        elsif resize(rv, 34) /= resize(pv, 34) - q2 then
          report "REMAINDER ERROR at vector " & integer'image(idx) severity error;
          nerr := nerr + 1;
        end if;
        idx := idx + 1;
        if idx = NVEC then
          if nerr = 0 then
            report "PIPELINED: ALL " & integer'image(NVEC) &
                   " RESULTS CORRECT" severity note;
          else
            report integer'image(nerr) & " FAILURES" severity failure;
          end if;
          done <= true;
          wait;
        end if;
      end if;
    end loop;
  end process check;

end architecture sim;
