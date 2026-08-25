// ============================================================
// Domain D: AXI-lite style Bridge
// Clock: clk_bridge (100MHz master) + TWO generated clocks:
//        gen_clk_50 (divided /2), gen_clk_33 (divided /3)
// Function: Bridges fast-side requests to a slow-side interface
//           via an async FIFO (genuine wide-data CDC crossing)
// ============================================================
module domain_d_axi_bridge (
    input  wire        clk_bridge,
    input  wire        rst_n,

    input  wire        fast_valid,
    output wire        fast_ready,
    input  wire [7:0]  fast_addr,
    input  wire [23:0] fast_data,

    output wire        slow_valid,
    input  wire        slow_ready,
    output wire [7:0]  slow_addr,
    output wire [23:0] slow_data,
    output wire         slow_clk
);

    wire clk_50;
    clk_divider #(.DIV_RATIO(2)) u_div50 (
        .clk_in  (clk_bridge),
        .rst_n   (rst_n),
        .clk_out (clk_50)
    );

    wire clk_33;
    clk_divider #(.DIV_RATIO(3)) u_div33 (
        .clk_in  (clk_bridge),
        .rst_n   (rst_n),
        .clk_out (clk_33)
    );

    wire rst_n_bridge;
    reset_sync u_rst_bridge (
        .clk         (clk_bridge),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_bridge)
    );

    wire rst_n_50;
    reset_sync u_rst_50 (
        .clk         (clk_50),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_50)
    );

    wire [31:0] fifo_wr_data = {fast_addr, fast_data};
    wire        fifo_full;
    wire        fifo_wr_en  = fast_valid && !fifo_full;

    assign fast_ready = !fifo_full;

    wire [31:0] fifo_rd_data;
    wire        fifo_empty;
    wire        fifo_rd_en = slow_ready && !fifo_empty;

    async_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(4)) u_bridge_fifo (
        .wr_clk   (clk_bridge),
        .wr_rst_n (rst_n_bridge),
        .wr_en    (fifo_wr_en),
        .wr_data  (fifo_wr_data),
        .full     (fifo_full),

        .rd_clk   (clk_50),
        .rd_rst_n (rst_n_50),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .empty    (fifo_empty)
    );

    assign slow_valid = !fifo_empty;
    assign slow_addr  = fifo_rd_data[31:24];
    assign slow_data  = fifo_rd_data[23:0];
    assign slow_clk = clk_50;

    wire fifo_wr_en_sync;
    sync_2ff #(.WIDTH(1)) u_sync_wr_en (
        .clk      (clk_33),
        .rst_n    (rst_n),
        .async_in (fifo_wr_en),
        .sync_out (fifo_wr_en_sync)
    );

    (* keep = "true" *) reg [15:0] transfer_counter;
    always @(posedge clk_33 or negedge rst_n) begin
        if (!rst_n)
            transfer_counter <= 16'd0;
        else if (fifo_wr_en_sync)
            transfer_counter <= transfer_counter + 16'd1;
    end

endmodule