// ============================================================
// Domain E: UART/SPI-style Serial Peripheral
// Clock: clk_periph (50MHz master) + gen_clk_25 (divided /2)
// Function: UART-style TX (parallel->serial) + RX (serial->parallel)
//           shift registers, driven by the generated bit clock.
//           Also demonstrates a genuine cross-master CDC input
//           (ext_trigger, arriving from an unrelated clock domain).
// ============================================================
module domain_e_uart_spi (
    input  wire        clk_periph,
    input  wire        rst_n,

    input  wire        tx_start,
    input  wire [7:0]  tx_data,
    output wire        tx_busy,
    output reg         tx_serial,

    input  wire        rx_serial,
    output reg  [7:0]  rx_data,
    output reg          rx_valid,

    input  wire        ext_trigger
);

    wire clk_25;
    clk_divider #(.DIV_RATIO(2)) u_div25 (
        .clk_in  (clk_periph),
        .rst_n   (rst_n),
        .clk_out (clk_25)
    );

    wire rst_n_periph;
    reset_sync u_rst_periph (
        .clk         (clk_periph),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_periph)
    );

    wire rst_n_25;
    reset_sync u_rst_25 (
        .clk         (clk_25),
        .async_rst_n (rst_n),
        .sync_rst_n  (rst_n_25)
    );

    wire ext_trigger_sync;
    sync_2ff #(.WIDTH(1)) u_sync_trigger (
        .clk      (clk_periph),
        .rst_n    (rst_n_periph),
        .async_in (ext_trigger),
        .sync_out (ext_trigger_sync)
    );

    reg [3:0]  tx_bit_cnt;
    reg [9:0]  tx_shift;
    reg        tx_active;

    assign tx_busy = tx_active;

    always @(posedge clk_25 or negedge rst_n_25) begin
        if (!rst_n_25) begin
            tx_active  <= 1'b0;
            tx_bit_cnt <= 4'd0;
            tx_shift   <= 10'b1111111111;
            tx_serial  <= 1'b1;
        end else begin
            if (!tx_active && (tx_start || ext_trigger_sync)) begin
                tx_active  <= 1'b1;
                tx_bit_cnt <= 4'd0;
                tx_shift   <= {1'b1, tx_data, 1'b0};
            end else if (tx_active) begin
                tx_serial <= tx_shift[0];
                tx_shift  <= {1'b1, tx_shift[9:1]};
                tx_bit_cnt <= tx_bit_cnt + 4'd1;
                if (tx_bit_cnt == 4'd9)
                    tx_active <= 1'b0;
            end
        end
    end

    reg [3:0] rx_bit_cnt;
    reg [9:0] rx_shift;
    reg       rx_active;

    always @(posedge clk_25 or negedge rst_n_25) begin
        if (!rst_n_25) begin
            rx_active  <= 1'b0;
            rx_bit_cnt <= 4'd0;
            rx_shift   <= 10'd0;
            rx_data    <= 8'd0;
            rx_valid   <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            if (!rx_active && (rx_serial == 1'b0)) begin
                rx_active  <= 1'b1;
                rx_bit_cnt <= 4'd0;
            end else if (rx_active) begin
                rx_shift   <= {rx_serial, rx_shift[9:1]};
                rx_bit_cnt <= rx_bit_cnt + 4'd1;
                if (rx_bit_cnt == 4'd9) begin
                    rx_active <= 1'b0;
                    rx_data   <= rx_shift[8:1];
                    rx_valid  <= 1'b1;
                end
            end
        end
    end

endmodule