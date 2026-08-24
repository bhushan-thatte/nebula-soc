// ============================================================
// Parameterizable clock divider
// Generates a divided clock from a master clock.
// DIV_RATIO=2 -> toggle every cycle (divide by 2)
// DIV_RATIO=N -> divide by N (even or odd supported)
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
        else if (DIV_RATIO % 2 == 0) begin : even_div
            // Even divide: simple toggle counter
            localparam CNT_W = $clog2(DIV_RATIO/2);
            reg [CNT_W-1:0] cnt;
            always @(posedge clk_in or negedge rst_n) begin
                if (!rst_n) begin
                    cnt     <= 0;
                    clk_out <= 1'b0;
                end else if (cnt == (DIV_RATIO/2 - 1)) begin
                    cnt     <= 0;
                    clk_out <= ~clk_out;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
        else begin : odd_div
            // Odd divide: dual-edge combine technique (50% duty cycle)
            localparam CNT_W = $clog2(DIV_RATIO);
            reg [CNT_W-1:0] cnt_pos;
            reg [CNT_W-1:0] cnt_neg;
            reg clk_pos, clk_neg;

            always @(posedge clk_in or negedge rst_n) begin
                if (!rst_n) begin
                    cnt_pos <= 0;
                    clk_pos <= 1'b0;
                end else if (cnt_pos == DIV_RATIO-1) begin
                    cnt_pos <= 0;
                    clk_pos <= ~clk_pos;
                end else begin
                    cnt_pos <= cnt_pos + 1'b1;
                end
            end

            always @(negedge clk_in or negedge rst_n) begin
                if (!rst_n) begin
                    cnt_neg <= 0;
                    clk_neg <= 1'b0;
                end else if (cnt_neg == DIV_RATIO-1) begin
                    cnt_neg <= 0;
                    clk_neg <= ~clk_neg;
                end else begin
                    cnt_neg <= cnt_neg + 1'b1;
                end
            end

            always @(*) clk_out = clk_pos ^ clk_neg;
        end
    endgenerate

endmodule
