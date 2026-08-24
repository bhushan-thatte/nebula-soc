// ============================================================
// Domain B: Memory Controller with Round-Robin Arbitration
// Clock: clk_mem (200MHz master) + gen_clk_50 (divided /4)
// Function: Arbitrates 3 requesters accessing shared memory
// ============================================================
module domain_b_mem_ctrl (
    input  wire        clk_mem,
    input  wire        rst_n,

    input  wire        req0_valid,
    output wire        req0_grant,
    input  wire [7:0]  req0_addr,
    input  wire [7:0]  req0_wdata,
    input  wire        req0_we,
    output wire [7:0]  req0_rdata,

    input  wire        req1_valid,
    output wire        req1_grant,
    input  wire [7:0]  req1_addr,
    input  wire [7:0]  req1_wdata,
    input  wire        req1_we,
    output wire [7:0]  req1_rdata,

    input  wire        req2_valid,
    output wire        req2_grant,
    input  wire [7:0]  req2_addr,
    input  wire [7:0]  req2_wdata,
    input  wire        req2_we,
    output wire [7:0]  req2_rdata
);

    wire clk_50;
    clk_divider #(.DIV_RATIO(4)) u_div50 (
        .clk_in  (clk_mem),
        .rst_n   (rst_n),
        .clk_out (clk_50)
    );

    wire rst_n_mem;
    reset_sync u_rst_mem (
        .clk         (clk_mem),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_mem)
    );

    reg [1:0] last_grant;
    wire grant0, grant1, grant2;

    reg g0, g1, g2;
    always @(*) begin
        g0 = 1'b0; g1 = 1'b0; g2 = 1'b0;
        case (last_grant)
            2'd0: begin
                if      (req1_valid) g1 = 1'b1;
                else if (req2_valid) g2 = 1'b1;
                else if (req0_valid) g0 = 1'b1;
            end
            2'd1: begin
                if      (req2_valid) g2 = 1'b1;
                else if (req0_valid) g0 = 1'b1;
                else if (req1_valid) g1 = 1'b1;
            end
            default: begin
                if      (req0_valid) g0 = 1'b1;
                else if (req1_valid) g1 = 1'b1;
                else if (req2_valid) g2 = 1'b1;
            end
        endcase
    end

    assign grant0 = g0;
    assign grant1 = g1;
    assign grant2 = g2;
    assign req0_grant = grant0;
    assign req1_grant = grant1;
    assign req2_grant = grant2;

    always @(posedge clk_mem or negedge rst_n_mem) begin
        if (!rst_n_mem) begin
            last_grant <= 2'd2;
        end else begin
            if (grant0)      last_grant <= 2'd0;
            else if (grant1) last_grant <= 2'd1;
            else if (grant2) last_grant <= 2'd2;
        end
    end

    reg [7:0] mem [0:255];

    wire [7:0] mux_addr  = grant0 ? req0_addr  : grant1 ? req1_addr  : req2_addr;
    wire [7:0] mux_wdata = grant0 ? req0_wdata : grant1 ? req1_wdata : req2_wdata;
    wire       mux_we    = grant0 ? req0_we    : grant1 ? req1_we    : req2_we;
    wire       mux_valid = grant0 | grant1 | grant2;

    reg [7:0] rdata_r;
    reg [1:0] last_grant_d;

    always @(posedge clk_mem or negedge rst_n_mem) begin
        if (!rst_n_mem) begin
            rdata_r      <= 8'd0;
            last_grant_d <= 2'd0;
        end else begin
            if (mux_valid) begin
                if (mux_we)
                    mem[mux_addr] <= mux_wdata;
                rdata_r      <= mem[mux_addr];
                last_grant_d <= grant0 ? 2'd0 : grant1 ? 2'd1 : 2'd2;
            end
        end
    end

    assign req0_rdata = (last_grant_d == 2'd0) ? rdata_r : 8'd0;
    assign req1_rdata = (last_grant_d == 2'd1) ? rdata_r : 8'd0;
    assign req2_rdata = (last_grant_d == 2'd2) ? rdata_r : 8'd0;

    // NOTE: mux_valid lives in the clk_mem domain. We must synchronize it
    // into the clk_50 domain before use - this is a genuine CDC crossing,
    // handled via our sync_2ff module (edge-detected pulse sync).
    wire mux_valid_sync;
    sync_2ff #(.WIDTH(1)) u_sync_mux_valid (
        .clk      (clk_50),
        .rst_n    (rst_n),
        .async_in (mux_valid),
        .sync_out (mux_valid_sync)
    );

    (* keep = "true" *) reg [15:0] access_counter;
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n)
            access_counter <= 16'd0;
        else if (mux_valid_sync)
            access_counter <= access_counter + 16'd1;
    end

endmodule