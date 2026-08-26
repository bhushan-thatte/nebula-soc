// ============================================================
// Nebula SoC Top-Level Integration
// Wires all 5 clock domains together via CDC-safe bridges.
// Data flow: A -> B -> C -> D -> E, plus direct A -> E trigger link
// ============================================================
module nebula_soc_top (
    input wire clk_core,    // 300MHz - Domain A master
    input wire clk_mem,     // 200MHz - Domain B master
    input wire clk_dsp,     // 250MHz - Domain C master
    input wire clk_bridge,  // 100MHz - Domain D master
    input wire clk_periph,  //  50MHz - Domain E master
    input wire rst_n,

    output wire [1:0] debug_fsm_state,
    output wire        debug_tx_serial,
    output wire [7:0]  debug_rx_data,
    output wire        debug_rx_valid
);

    // ---- Domain A: Command FSM ----
    wire       a_cmd_valid;
    wire [7:0] a_cmd_data;
    wire       a_cmd_ack;

    domain_a_cmd_fsm u_domain_a (
        .clk_core  (clk_core),
        .rst_n     (rst_n),
        .cmd_valid (a_cmd_valid),
        .cmd_data  (a_cmd_data),
        .cmd_ack   (a_cmd_ack),
        .fsm_state (debug_fsm_state)
    );

    // ---- CDC Bridge 1: A (clk_core) -> B (clk_mem) ----
    wire        fifo1_full, fifo1_empty;
    wire [7:0]  fifo1_rd_data;
    wire        b_req0_grant;

    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) u_fifo_a_to_b (
        .wr_clk   (clk_core),
        .wr_rst_n (rst_n),
        .wr_en    (a_cmd_valid && !fifo1_full),
        .wr_data  (a_cmd_data),
        .full     (fifo1_full),

        .rd_clk   (clk_mem),
        .rd_rst_n (rst_n),
        .rd_en    (!fifo1_empty && b_req0_grant),
        .rd_data  (fifo1_rd_data),
        .empty    (fifo1_empty)
    );

    assign a_cmd_ack = !fifo1_full;

    // ---- Domain B: Memory Controller ----
    wire [7:0] b_req0_rdata;

    domain_b_mem_ctrl u_domain_b (
        .clk_mem     (clk_mem),
        .rst_n       (rst_n),

        .req0_valid  (!fifo1_empty),
        .req0_grant  (b_req0_grant),
        .req0_addr   (6'h00),
        .req0_wdata  (fifo1_rd_data),
        .req0_we     (1'b1),
        .req0_rdata  (b_req0_rdata),

        .req1_valid  (1'b0),
        .req1_grant  (),
        .req1_addr   (6'h00),
        .req1_wdata  (8'h00),
        .req1_we     (1'b0),
        .req1_rdata  (),

        .req2_valid  (1'b0),
        .req2_grant  (),
        .req2_addr   (6'h00),
        .req2_wdata  (8'h00),
        .req2_we     (1'b0),
        .req2_rdata  ()
    );

    // ---- CDC Bridge 2: B (clk_mem) -> C (clk_dsp) ----
    wire        fifo2_full, fifo2_empty;
    wire [7:0]  fifo2_rd_data;

    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) u_fifo_b_to_c (
        .wr_clk   (clk_mem),
        .wr_rst_n (rst_n),
        .wr_en    (b_req0_grant && !fifo2_full),
        .wr_data  (b_req0_rdata),
        .full     (fifo2_full),

        .rd_clk   (clk_dsp),
        .rd_rst_n (rst_n),
        .rd_en    (!fifo2_empty),
        .rd_data  (fifo2_rd_data),
        .empty    (fifo2_empty)
    );

    // ---- Domain C: DSP FIR Filter ----
    wire signed [23:0] c_result_out;
    wire                c_result_valid;

    domain_c_dsp_fir u_domain_c (
        .clk_dsp      (clk_dsp),
        .rst_n        (rst_n),
        .sample_in    ({{16{fifo2_rd_data[7]}}, fifo2_rd_data}),
        .sample_valid (!fifo2_empty),
        .result_out   (c_result_out),
        .result_valid (c_result_valid)
    );

    // ---- CDC Bridge 3: C (clk_dsp) -> D fast side (clk_bridge) ----
    wire        fifo3_full, fifo3_empty;
    wire [23:0] fifo3_rd_data;
    wire        d_fast_ready;

    async_fifo #(.DATA_WIDTH(24), .ADDR_WIDTH(4)) u_fifo_c_to_d (
        .wr_clk   (clk_dsp),
        .wr_rst_n (rst_n),
        .wr_en    (c_result_valid && !fifo3_full),
        .wr_data  (c_result_out),
        .full     (fifo3_full),

        .rd_clk   (clk_bridge),
        .rd_rst_n (rst_n),
        .rd_en    (d_fast_ready && !fifo3_empty),
        .rd_data  (fifo3_rd_data),
        .empty    (fifo3_empty)
    );

    // ---- Domain D: AXI-lite Bridge ----
    wire        d_slow_valid;
    wire [7:0]  d_slow_addr;
    wire [23:0] d_slow_data;
    wire        d_slow_clk;
    wire        d_slow_ready;

    domain_d_axi_bridge u_domain_d (
        .clk_bridge (clk_bridge),
        .rst_n      (rst_n),

        .fast_valid (!fifo3_empty),
        .fast_ready (d_fast_ready),
        .fast_addr  (8'h00),
        .fast_data  (fifo3_rd_data),

        .slow_valid (d_slow_valid),
        .slow_ready (d_slow_ready),
        .slow_addr  (d_slow_addr),
        .slow_data  (d_slow_data),
        .slow_clk   (d_slow_clk)
    );

    // ---- CDC Bridge 4: D slow side (d_slow_clk) -> E (clk_periph) ----
    wire        fifo4_full, fifo4_empty;
    wire [7:0]  fifo4_rd_data;
    wire        e_tx_busy;

    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(4)) u_fifo_d_to_e (
        .wr_clk   (d_slow_clk),
        .wr_rst_n (rst_n),
        .wr_en    (d_slow_valid && !fifo4_full),
        .wr_data  (d_slow_data[7:0]),
        .full     (fifo4_full),

        .rd_clk   (clk_periph),
        .rd_rst_n (rst_n),
        .rd_en    (!e_tx_busy && !fifo4_empty),
        .rd_data  (fifo4_rd_data),
        .empty    (fifo4_empty)
    );

    assign d_slow_ready = !fifo4_full;

    // ---- Domain E: UART/SPI Peripheral ----
    // Loopback tx_serial->rx_serial for self-test.
    // ext_trigger driven by A's raw cmd_valid (E syncs internally).
    wire e_tx_serial;

    domain_e_uart_spi u_domain_e (
        .clk_periph  (clk_periph),
        .rst_n       (rst_n),

        .tx_start    (!fifo4_empty && !e_tx_busy),
        .tx_data     (fifo4_rd_data),
        .tx_busy     (e_tx_busy),
        .tx_serial   (e_tx_serial),

        .rx_serial   (e_tx_serial),
        .rx_data     (debug_rx_data),
        .rx_valid    (debug_rx_valid),

        .ext_trigger (a_cmd_valid)
    );

    assign debug_tx_serial = e_tx_serial;

endmodule