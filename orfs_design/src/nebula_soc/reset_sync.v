module reset_sync (
    input  wire clk,
    input  wire async_rst_n,
    output reg  sync_rst_n
);
    reg rst_ff1;
    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rst_ff1    <= 1'b0;
            sync_rst_n <= 1'b0;
        end else begin
            rst_ff1    <= 1'b1;
            sync_rst_n <= rst_ff1;
        end
    end
endmodule
