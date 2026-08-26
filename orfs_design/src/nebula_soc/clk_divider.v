// ============================================================
// Parameterizable clock divider (single-edge, fully synchronous)
// Generates a divided clock from a master clock using an
// alternating-half-period toggle scheme. Works uniformly for
// both even and odd DIV_RATIO values, using ONLY posedge clk_in
// - no negedge logic, no combinational XOR-combine. This keeps
// clk_out as a clean, single DFF-driven net that survives
// synthesis/STA as a proper generated clock signal.
// ============================================================
module clk_divider #(
    parameter DIV_RATIO = 2
) (
    input  wire clk_in,
    input  wire rst_n,
    output reg  clk_out
);

    generate
        if (DIV_RATIO <= 1) begin : no_div
            always @(*) clk_out = clk_in;
        end
        else begin : div
            localparam HALF_A = (DIV_RATIO + 1) / 2;
            localparam HALF_B = DIV_RATIO / 2;
            localparam CNT_W  = $clog2(HALF_A + 1);

            reg [CNT_W-1:0] cnt;
            reg             half_sel;

            always @(posedge clk_in or negedge rst_n) begin
                if (!rst_n) begin
                    cnt      <= {CNT_W{1'b0}};
                    clk_out  <= 1'b0;
                    half_sel <= 1'b0;
                end else if ((half_sel == 1'b0 && cnt == HALF_A - 1) ||
                             (half_sel == 1'b1 && cnt == HALF_B - 1)) begin
                    cnt      <= {CNT_W{1'b0}};
                    clk_out  <= ~clk_out;
                    half_sel <= ~half_sel;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    endgenerate

endmodule