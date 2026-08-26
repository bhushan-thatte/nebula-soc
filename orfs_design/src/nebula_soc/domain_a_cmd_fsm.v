// ============================================================
// Domain A: Command FSM
// Clock: clk_core (300MHz master) + gen_clk_150 (divided /2)
// Function: Issues commands to Domain B (Memory Controller)
// ============================================================
module domain_a_cmd_fsm (
    input  wire        clk_core,
    input  wire        rst_n,

    output wire        cmd_valid,
    output wire [7:0]  cmd_data,
    input  wire        cmd_ack,

    output wire [1:0]  fsm_state
);

    wire clk_150;
    clk_divider #(.DIV_RATIO(2)) u_div150 (
        .clk_in  (clk_core),
        .rst_n   (rst_n),
        .clk_out (clk_150)
    );

    wire rst_n_core;
    reset_sync u_rst_core (
        .clk         (clk_core),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_core)
    );

    localparam S_IDLE     = 2'b00;
    localparam S_ISSUE    = 2'b01;
    localparam S_WAIT_ACK = 2'b10;
    localparam S_DONE     = 2'b11;

    reg [1:0] state, next_state;
    reg [7:0] cmd_counter;
    reg [7:0] cmd_data_r;
    reg       cmd_valid_r;

    assign fsm_state = state;
    assign cmd_valid = cmd_valid_r;
    assign cmd_data  = cmd_data_r;

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:     next_state = S_ISSUE;
            S_ISSUE:    next_state = S_WAIT_ACK;
            S_WAIT_ACK: next_state = cmd_ack ? S_DONE : S_WAIT_ACK;
            S_DONE:     next_state = S_IDLE;
            default:    next_state = S_IDLE;
        endcase
    end

    always @(posedge clk_core or negedge rst_n_core) begin
        if (!rst_n_core)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(posedge clk_core or negedge rst_n_core) begin
        if (!rst_n_core) begin
            cmd_counter <= 8'd0;
            cmd_data_r  <= 8'd0;
            cmd_valid_r <= 1'b0;
        end else begin
            case (state)
                S_ISSUE: begin
                    cmd_valid_r <= 1'b1;
                    cmd_data_r  <= cmd_counter + 8'd1;
                    cmd_counter <= cmd_counter + 8'd1;
                end
                S_WAIT_ACK: begin
                    cmd_valid_r <= 1'b0;
                end
                default: begin
                    cmd_valid_r <= 1'b0;
                end
            endcase
        end
    end
// Housekeeping counter on generated clk_150 to keep the clock active
    (* keep = "true" *) reg [7:0] heartbeat_counter;

    always @(posedge clk_150 or negedge rst_n) begin
        if (!rst_n) begin
            heartbeat_counter <= 8'd0;
        end else begin
            heartbeat_counter <= heartbeat_counter + 8'd1;
        end
    end
endmodule