`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLK_FRE = 50,
    parameter integer BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] rx_data,
    output reg        rx_data_valid,
    input  wire       rx_data_ready,
    input  wire       rx_pin
);

localparam integer CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
localparam integer HALF_CYCLE = CYCLE / 2;
localparam [2:0] IDLE       = 3'd0;
localparam [2:0] START      = 3'd1;
localparam [2:0] DATA       = 3'd2;
localparam [2:0] STOP       = 3'd3;
localparam [2:0] DATA_VALID = 3'd4;

reg [2:0]  state;
reg [31:0] cycle_count;
reg [2:0]  bit_count;
reg [7:0]  rx_bits;
reg        rx_meta;
reg        rx_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        rx_meta <= rx_pin;
        rx_sync <= rx_meta;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= IDLE;
        cycle_count   <= 32'd0;
        bit_count     <= 3'd0;
        rx_bits       <= 8'd0;
        rx_data       <= 8'd0;
        rx_data_valid <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                cycle_count   <= 32'd0;
                bit_count     <= 3'd0;
                rx_data_valid <= 1'b0;
                if (!rx_sync)
                    state <= START;
            end

            START: begin
                if (cycle_count == HALF_CYCLE - 1) begin
                    cycle_count <= 32'd0;
                    if (!rx_sync)
                        state <= DATA;
                    else
                        state <= IDLE;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end

            DATA: begin
                if (cycle_count == CYCLE - 1) begin
                    cycle_count       <= 32'd0;
                    rx_bits[bit_count] <= rx_sync;
                    if (bit_count == 3'd7)
                        state <= STOP;
                    else
                        bit_count <= bit_count + 1'b1;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end

            STOP: begin
                if (cycle_count == CYCLE - 1) begin
                    cycle_count <= 32'd0;
                    if (rx_sync) begin
                        rx_data       <= rx_bits;
                        rx_data_valid <= 1'b1;
                        state         <= DATA_VALID;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end

            DATA_VALID: begin
                if (rx_data_ready) begin
                    rx_data_valid <= 1'b0;
                    state         <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
