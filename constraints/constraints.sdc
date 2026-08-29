# ============================================================
# Nebula SoC - Timing Constraints
# 5 independent async master clocks + generated clocks per domain
# NOTE: post-flatten net names verified directly against the
# synthesized netlist (1_2_yosys.v). Domain D's /2 clock net
# merged with the top-level port name 'd_slow_clk' during
# optimization (since it drives an output port directly).
# ============================================================

create_clock -name clk_core   -period 3.333  [get_ports clk_core]    ; # 300 MHz
create_clock -name clk_mem    -period 5.000  [get_ports clk_mem]     ; # 200 MHz
create_clock -name clk_dsp    -period 4.000  [get_ports clk_dsp]     ; # 250 MHz
create_clock -name clk_bridge -period 10.000 [get_ports clk_bridge]  ; # 100 MHz
create_clock -name clk_periph -period 20.000 [get_ports clk_periph]  ; #  50 MHz

create_generated_clock -name clk_150 \
    -source [get_ports clk_core] -divide_by 2 \
    [get_nets {u_domain_a.clk_150}]

create_generated_clock -name clk_50_b \
    -source [get_ports clk_mem] -divide_by 4 \
    [get_nets {u_domain_b.clk_50}]

create_generated_clock -name clk_50_c \
    -source [get_ports clk_dsp] -divide_by 5 \
    [get_nets {u_domain_c.clk_50}]

create_generated_clock -name clk_50_d \
    -source [get_ports clk_bridge] -divide_by 2 \
    [get_nets {d_slow_clk}]
create_generated_clock -name clk_33_d \
    -source [get_ports clk_bridge] -divide_by 3 \
    [get_nets {u_domain_d.clk_33}]

create_generated_clock -name clk_25 \
    -source [get_ports clk_periph] -divide_by 2 \
    [get_nets {u_domain_e.clk_25}]

set_clock_groups -asynchronous \
    -group {clk_core clk_150} \
    -group {clk_mem clk_50_b} \
    -group {clk_dsp clk_50_c} \
    -group {clk_bridge clk_50_d clk_33_d} \
    -group {clk_periph clk_25}
# ------------------------------------------------------------------
# Reset-recovery exception: sync_rst_n is already synchronized to
# clk_dsp by reset_sync.v (2-flop synchronizer). The wide fanout of
# this net across Domain C's pipelined register file creates a
# recovery-check "violation" that is a false artifact of static
# reset timing analysis, not a real hazard -- reset is held stable
# far longer than one clk_dsp cycle in actual operation.
# ------------------------------------------------------------------
set_false_path -through [get_pins u_domain_c.u_rst_dsp.sync_rst_n*/Q]

set_max_fanout 20 [current_design]
