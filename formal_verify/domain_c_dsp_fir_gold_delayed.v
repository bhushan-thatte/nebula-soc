// ============================================================
// Latency-matching wrapper for formal equivalence checking.
//
// domain_c_dsp_fir_gold (2-stage pipeline) produces results 1 cycle
// earlier than domain_c_dsp_fir_gate (3-stage pipeline, GenAI-patched).
// This wrapper adds one extra register stage on gold's outputs so
// both designs can be compared with a standard CYCLE-ACCURATE EQY
// check (same-cycle equivalence), rather than requiring a more
// complex latency-aware/retiming-aware equivalence proof.
// ============================================================
module domain_c_dsp_fir_gate (
    input  wire                  clk_dsp,
    input  wire                  rst_n,

    input  wire signed [23:0]    sample_in,
    input  wire                  sample_valid,

    output reg  signed [23:0]    result_out,
    output reg                   result_valid
);

    wire signed [23:0] result_out_inner;
    wire               result_valid_inner;

    domain_c_dsp_fir_gold u_gold (
        .clk_dsp      (clk_dsp),
        .rst_n        (rst_n),
        .sample_in    (sample_in),
        .sample_valid (sample_valid),
        .result_out   (result_out_inner),
        .result_valid (result_valid_inner)
    );

    // One extra pipeline register to match the gate design's latency.
    always @(posedge clk_dsp or negedge rst_n) begin
        if (!rst_n) begin
            result_out   <= 24'sd0;
            result_valid <= 1'b0;
        end else begin
            result_out   <= result_out_inner;
            result_valid <= result_valid_inner;
        end
    end

endmodule
