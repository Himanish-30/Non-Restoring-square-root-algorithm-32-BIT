--------------------------------------------------------------------------------
-- sqrt32_pipelined.vhd : the same CSM array with a register between every row.
--
-- 16 pipeline stages, throughput = 1 result / clock, latency = 17 clocks
-- (1 input register + 16 row registers).  This is the "fully pipelined
-- architecture" the paper argues is free on an FPGA, because each row already
-- ends in a LUT output that feeds the flip-flop sitting in the same slice.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity sqrt32_pipelined is
  generic (
    N : integer := 32
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                       -- synchronous, active high
    start  : in  std_logic;                       -- P is valid this cycle
    P      : in  std_logic_vector(N-1 downto 0);
    Q      : out std_logic_vector(N/2-1 downto 0);
    R      : out std_logic_vector(N/2 downto 0);
    dvalid : out std_logic
  );
end entity sqrt32_pipelined;

architecture csm_pipe of sqrt32_pipelined is

  constant M : integer := N/2;
  constant W : integer := M + 2;

  type mat_t is array (0 to M) of std_logic_vector(W-1 downto 0);
  type brw_t is array (0 to M) of std_logic_vector(W   downto 0);
  type prg_t is array (0 to M) of std_logic_vector(N-1 downto 0);
  type qrg_t is array (0 to M) of std_logic_vector(M-1 downto 0);
  type rrg_t is array (0 to M) of std_logic_vector(M   downto 0);

  signal xr : mat_t := (others => (others => '0'));
  signal yr : mat_t := (others => (others => '0'));
  signal dr : mat_t := (others => (others => '0'));
  signal br : brw_t := (others => (others => '0'));

  signal p_reg : prg_t := (others => (others => '0'));
  signal q_reg : qrg_t := (others => (others => '0'));
  signal r_reg : rrg_t := (others => (others => '0'));
  signal v_reg : std_logic_vector(0 to M) := (others => '0');
  signal qbit  : std_logic_vector(1 to M);

begin

  ------------------------------------------------------------------ input reg
  stage0 : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        v_reg(0) <= '0';
      else
        p_reg(0) <= P;
        r_reg(0) <= (others => '0');
        q_reg(0) <= (others => '0');
        v_reg(0) <= start;
      end if;
    end if;
  end process stage0;

  ------------------------------------------------------------- 16 array stages
  rows : for k in 1 to M generate
  begin
    xr(k)(1 downto 0)   <= p_reg(k-1)(N-1 downto N-2);  -- next pair, always at top
    xr(k)(k+1 downto 2) <= r_reg(k-1)(k-1 downto 0);

    yr(k)(0)   <= '1';
    yr(k)(1)   <= '0';
    yr(k)(k+1) <= '0';
    root_so_far : if k > 1 generate
      yr(k)(k downto 2) <= q_reg(k-1)(M-1 downto M-k+1);
    end generate root_so_far;

    br(k)(0) <= '0';

    cells : for j in 0 to k+1 generate
      cell_j : entity work.csm(gate_level)
        port map (x  => xr(k)(j),
                  y  => yr(k)(j),
                  b  => br(k)(j),
                  u  => qbit(k),
                  d  => dr(k)(j),
                  bo => br(k)(j+1));
    end generate cells;

    qbit(k) <= not br(k)(k+2);

    stage_reg : process (clk)
    begin
      if rising_edge(clk) then
        if rst = '1' then
          v_reg(k) <= '0';
        else
          r_reg(k)             <= (others => '0');
          r_reg(k)(k downto 0) <= dr(k)(k downto 0);
          q_reg(k)             <= q_reg(k-1);
          q_reg(k)(M-k)        <= qbit(k);
          p_reg(k)             <= p_reg(k-1)(N-3 downto 0) & "00";
          v_reg(k)             <= v_reg(k-1);
        end if;
      end if;
    end process stage_reg;
  end generate rows;

  Q      <= q_reg(M);
  R      <= r_reg(M);
  dvalid <= v_reg(M);

end architecture csm_pipe;
