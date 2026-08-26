// ============================================================
// Domain C: DSP Pipeline - 16-tap FIR Filter
// Clock: clk_dsp (250MHz master) + gen_clk_50 (divided /5)
// Function: Direct-form FIR filter, 24-bit signed samples
//
// INTENTIONAL DESIGN NOTE: the multiply-accumulate stage below is
// built as a SINGLE combinational block (all 16 taps computed in
// one cycle). This is realistic but timing-unfriendly - exactly
// the kind of critical path a GenAI optimization engine should
// identify and fix via pipelining. Do not "pre-optimize" this.
// ============================================================
module domain_c_dsp_fir (
    input  wire                  clk_dsp,
    input  wire                  rst_n,

    input  wire signed [23:0]    sample_in,
    input  wire                  sample_valid,

    output reg  signed [23:0]    result_out,
    output reg                   result_valid
);

    wire clk_50;
    clk_divider #(.DIV_RATIO(5)) u_div50 (
        .clk_in  (clk_dsp),
        .rst_n   (rst_n),
        .clk_out (clk_50)
    );

    wire rst_n_dsp;
    reset_sync u_rst_dsp (
        .clk         (clk_dsp),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_dsp)
    );

    localparam signed [15:0] TAP0  = 16'sd128;
    localparam signed [15:0] TAP1  = 16'sd256;
    localparam signed [15:0] TAP2  = 16'sd384;
    localparam signed [15:0] TAP3  = 16'sd512;
    localparam signed [15:0] TAP4  = 16'sd640;
    localparam signed [15:0] TAP5  = 16'sd768;
    localparam signed [15:0] TAP6  = 16'sd896;
    localparam signed [15:0] TAP7  = 16'sd1024;
    localparam signed [15:0] TAP8  = 16'sd1024;
    localparam signed [15:0] TAP9  = 16'sd896;
    localparam signed [15:0] TAP10 = 16'sd768;
    localparam signed [15:0] TAP11 = 16'sd640;
    localparam signed [15:0] TAP12 = 16'sd512;
    localparam signed [15:0] TAP13 = 16'sd384;
    localparam signed [15:0] TAP14 = 16'sd256;
    localparam signed [15:0] TAP15 = 16'sd128;

    reg signed [23:0] delay [0:15];
    integer i;

    always @(posedge clk_dsp or negedge rst_n_dsp) begin
        if (!rst_n_dsp) begin
            for (i = 0; i < 16; i = i + 1)
                delay[i] <= 24'sd0;
        end else if (sample_valid) begin
            delay[0] <= sample_in;
            for (i = 1; i < 16; i = i + 1)
                delay[i] <= delay[i-1];
        end
    end

    wire signed [47:0] mac_sum;
    assign mac_sum = (delay[0]  * TAP0)  + (delay[1]  * TAP1)  +
                      (delay[2]  * TAP2)  + (delay[3]  * TAP3)  +
                      (delay[4]  * TAP4)  + (delay[5]  * TAP5)  +
                      (delay[6]  * TAP6)  + (delay[7]  * TAP7)  +
                      (delay[8]  * TAP8)  + (delay[9]  * TAP9)  +
                      (delay[10] * TAP10) + (delay[11] * TAP11) +
                      (delay[12] * TAP12) + (delay[13] * TAP13) +
                      (delay[14] * TAP14) + (delay[15] * TAP15);

    always @(posedge clk_dsp or negedge rst_n_dsp) begin
        if (!rst_n_dsp) begin
            result_out   <= 24'sd0;
            result_valid <= 1'b0;
        end else begin
            result_out   <= mac_sum[39:16];
            result_valid <= sample_valid;
        end
    end

    wire sample_valid_sync;
    sync_2ff #(.WIDTH(1)) u_sync_sample_valid (
        .clk      (clk_50),
        .rst_n    (rst_n),
        .async_in (sample_valid),
        .sync_out (sample_valid_sync)
    );

    (* keep = "true" *) reg [15:0] sample_counter;
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n)
            sample_counter <= 16'd0;
        else if (sample_valid_sync)
            sample_counter <= sample_counter + 16'd1;
    end

endmodule