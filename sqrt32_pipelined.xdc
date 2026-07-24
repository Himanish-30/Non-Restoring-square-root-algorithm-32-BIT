#-------------------------------------------------------------------------------
# sqrt32_pipelined.xdc
#
# Timing constraints only -- no pin assignments, because the core has 32 input
# and 33 output data ports and will not pin out directly on a small board.
# Wrap it (counter + seven-segment, or an ILA) before adding I/O constraints.
#
# Usage: add as a constraints source when top = sqrt32_pipelined.
#-------------------------------------------------------------------------------

# 200 MHz target. Relax to 6.000 / 8.000 if WNS comes out negative, or tighten
# it to find the real Fmax by bisection.
create_clock -period 5.000 -name clk [get_ports clk]

# The data ports are driven/sampled by a testbench, not by real I/O, so tell
# the tools not to bother trying to close timing on them. Remove these three
# lines once you wrap the core in a real design with real I/O timing.
set_false_path -from [get_ports {P[*]}]
set_false_path -from [get_ports {rst start}]
set_false_path -to   [get_ports {Q[*] R[*] dvalid}]
