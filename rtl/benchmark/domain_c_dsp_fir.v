// ============================================================
// Domain C: DSP Pipeline - 16-tap FIR Filter
// Clock: clk_dsp (250MHz master) + gen_clk_50 (divided /5)
// Function: Direct-form FIR filter, 24-bit signed samples
//
// PIPELINE HISTORY (GenAI-assisted timing closure iterations):
//   v1: serial 15-add chain (WNS -3.85ns, TNS -49.59ns)
//   v2: balanced binary adder tree, unpipelined (WNS -3.14ns, TNS -43.95ns)
//   v3: added pipeline register after Level 2 (WNS -0.64ns, TNS -4.58ns)
//   v4 (this version): added a SECOND pipeline register after Level 1,
//       splitting Level 1 and Level 2 addition across a clock edge.
//       GenAI engine (qwen2.5-coder:7b) identified ha_1/fa_1 ripple-carry
//       cells as the dominant delay source across all 16 remaining
//       violations and recommended ADD_PIPELINE_STAGE (11/16 votes).
//       This adds 1 more cycle of latency (2 -> 3 cycles total,
//       sample_valid to result_valid) -- requires updated formal
//       equivalence checking (latency-aware) in Week 3.
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

    // ---- Balanced binary adder tree ----
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

    // ---- NEW PIPELINE REGISTER (v4): break the critical path after
    // Level 1, so multiply+add1 and add2 no longer share a combinational
    // path. This is the GenAI-recommended fix for the ha_1/fa_1
    // ripple-carry delay identified in all 16 remaining violations. ----
    reg signed [40:0] reg_s1_0, reg_s1_1, reg_s1_2, reg_s1_3;
    reg signed [40:0] reg_s1_4, reg_s1_5, reg_s1_6, reg_s1_7;
    reg                valid_stage0;

    always @(posedge clk_dsp or negedge rst_n_dsp) begin
        if (!rst_n_dsp) begin
            reg_s1_0     <= 41'sd0;
            reg_s1_1     <= 41'sd0;
            reg_s1_2     <= 41'sd0;
            reg_s1_3     <= 41'sd0;
            reg_s1_4     <= 41'sd0;
            reg_s1_5     <= 41'sd0;
            reg_s1_6     <= 41'sd0;
            reg_s1_7     <= 41'sd0;
            valid_stage0 <= 1'b0;
        end else begin
            reg_s1_0     <= s1_0;
            reg_s1_1     <= s1_1;
            reg_s1_2     <= s1_2;
            reg_s1_3     <= s1_3;
            reg_s1_4     <= s1_4;
            reg_s1_5     <= s1_5;
            reg_s1_6     <= s1_6;
            reg_s1_7     <= s1_7;
            valid_stage0 <= sample_valid;
        end
    end

    // Level 2: 8 -> 4 (now operating on registered Level-1 values)
    wire signed [41:0] s2_0 = reg_s1_0 + reg_s1_1;
    wire signed [41:0] s2_1 = reg_s1_2 + reg_s1_3;
    wire signed [41:0] s2_2 = reg_s1_4 + reg_s1_5;
    wire signed [41:0] s2_3 = reg_s1_6 + reg_s1_7;

    // ---- EXISTING PIPELINE REGISTER (v3): unchanged from prior
    // milestone -- registers the 4 partial sums from Level 2. ----
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
            valid_stage1 <= valid_stage0;   // CHANGED: was <= sample_valid
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
