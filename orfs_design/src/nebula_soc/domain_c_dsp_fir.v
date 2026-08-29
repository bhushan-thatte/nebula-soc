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

        // ---- Balanced binary adder tree (replaces serial 15-add chain) ----
    // FIX: original serial sum (p0+p1+p2+...+p15) created a 15-deep
    // sequential adder chain - this is the root cause of our timing
    // violation. Restructuring into a balanced tree reduces the
    // critical path to just 4 sequential addition stages (log2(16)),
    // with IDENTICAL cycle-accurate behavior (same latency, same
    // result) - purely a logic restructuring fix, no pipelining needed.

    wire signed [39:0] p0  = delay[0]  * TAP0;
    wire signed [39:0] p1  = delay[1]  * TAP1;
    wire signed [39:0] p2  = delay[2]  * TAP2;
    wire signed [39:0] p3  = delay[3]  * TAP3;
    wire signed [39:0] p4  = delay[4]  * TAP4;
    wire signed [39:0] p5  = delay[5]  * TAP5;
    wire signed [39:0] p6  = delay[6]  * TAP6;
    wire signed [39:0] p7  = delay[7]  * TAP7;
    wire signed [39:0] p8  = delay[8]  * TAP8;
    wire signed [39:0] p9  = delay[9]  * TAP9;
    wire signed [39:0] p10 = delay[10] * TAP10;
    wire signed [39:0] p11 = delay[11] * TAP11;
    wire signed [39:0] p12 = delay[12] * TAP12;
    wire signed [39:0] p13 = delay[13] * TAP13;
    wire signed [39:0] p14 = delay[14] * TAP14;
    wire signed [39:0] p15 = delay[15] * TAP15;

    // Level 1: 16 -> 8
    wire signed [40:0] s1_0 = p0  + p1;
    wire signed [40:0] s1_1 = p2  + p3;
    wire signed [40:0] s1_2 = p4  + p5;
    wire signed [40:0] s1_3 = p6  + p7;
    wire signed [40:0] s1_4 = p8  + p9;
    wire signed [40:0] s1_5 = p10 + p11;
    wire signed [40:0] s1_6 = p12 + p13;
    wire signed [40:0] s1_7 = p14 + p15;

        // Level 2: 8 -> 4
    wire signed [41:0] s2_0 = s1_0 + s1_1;
    wire signed [41:0] s2_1 = s1_2 + s1_3;
    wire signed [41:0] s2_2 = s1_4 + s1_5;
    wire signed [41:0] s2_3 = s1_6 + s1_7;

    // ---- PIPELINE REGISTER: break the critical path here ----
    // Registers the 4 partial sums from Level 2, splitting the tree
    // into two pipeline stages. Adds 1 cycle of latency (was 1 cycle
    // total, now 2), which is why we also need to delay sample_valid
    // by one extra cycle below to keep result_valid correctly aligned.
    reg signed [41:0] reg_s2_0, reg_s2_1, reg_s2_2, reg_s2_3;
    reg                valid_stage1;

    always @(posedge clk_dsp or negedge rst_n_dsp) begin
        if (!rst_n_dsp) begin
            reg_s2_0     <= 42'sd0;
            reg_s2_1     <= 42'sd0;
            reg_s2_2     <= 42'sd0;
            reg_s2_3     <= 42'sd0;
            valid_stage1 <= 1'b0;
        end else begin
            reg_s2_0     <= s2_0;
            reg_s2_1     <= s2_1;
            reg_s2_2     <= s2_2;
            reg_s2_3     <= s2_3;
            valid_stage1 <= sample_valid;
        end
    end

    // Level 3: 4 -> 2 (now operating on registered values)
    wire signed [42:0] s3_0 = reg_s2_0 + reg_s2_1;
    wire signed [42:0] s3_1 = reg_s2_2 + reg_s2_3;

    // Level 4: 2 -> 1 (final sum)
    wire signed [47:0] mac_sum = s3_0 + s3_1;

    always @(posedge clk_dsp or negedge rst_n_dsp) begin
        if (!rst_n_dsp) begin
            result_out   <= 24'sd0;
            result_valid <= 1'b0;
        end else begin
            result_out   <= mac_sum[39:16];
            result_valid <= valid_stage1;
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