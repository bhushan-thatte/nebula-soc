module sync_2ff #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] async_in,
    output reg  [WIDTH-1:0] sync_out
);
    reg [WIDTH-1:0] stage1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1   <= {WIDTH{1'b0}};
            sync_out <= {WIDTH{1'b0}};
        end else begin
            stage1   <= async_in;
            sync_out <= stage1;
        end
    end
endmodule
