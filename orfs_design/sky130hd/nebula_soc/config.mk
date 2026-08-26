export DESIGN_NAME = nebula_soc_top
export PLATFORM    = sky130hd

export VERILOG_FILES = \
    $(DESIGN_HOME)/src/nebula_soc/clk_divider.v \
    $(DESIGN_HOME)/src/nebula_soc/reset_sync.v \
    $(DESIGN_HOME)/src/nebula_soc/sync_2ff.v \
    $(DESIGN_HOME)/src/nebula_soc/async_fifo.v \
    $(DESIGN_HOME)/src/nebula_soc/domain_a_cmd_fsm.v \
    $(DESIGN_HOME)/src/nebula_soc/domain_b_mem_ctrl.v \
    $(DESIGN_HOME)/src/nebula_soc/domain_c_dsp_fir.v \
    $(DESIGN_HOME)/src/nebula_soc/domain_d_axi_bridge.v \
    $(DESIGN_HOME)/src/nebula_soc/domain_e_uart_spi.v \
    $(DESIGN_HOME)/src/nebula_soc/nebula_soc_top.v

export SDC_FILE = $(DESIGN_HOME)/sky130hd/nebula_soc/constraint.sdc

export CORE_UTILIZATION = 30
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.50
