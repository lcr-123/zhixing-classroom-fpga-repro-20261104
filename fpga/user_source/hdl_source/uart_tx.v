`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_FRE = 50,
    parameter integer BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_data_valid,
    output wire       tx_data_ready,
    output reg        tx_pin
);

localparam integer CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
localparam [1:0] IDLE  = 2'd0;
localparam [1:0] START = 2'd1;
localparam [1:0] DATA  = 2'd2;
localparam [1:0] STOP  = 2'd3;

reg [1:0]  state;
reg [31:0] cycle_count;
reg [2:0]  bit_count;
reg [7:0]  data_latch;

assign tx_data_ready = (state == IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        cycle_count <= 32'd0;
        bit_count   <= 3'd0;
        data_latch  <= 8'd0;
        tx_pin      <= 1'b1;
    end else begin
        case (state)
            IDLE: begin
                tx_pin      <= 1'b1;
                cycle_count <= 32'd0;
                bit_count   <= 3'd0;
                if (tx_data_valid) begin
                    data_latch <= tx_data;
                    tx_pin     <= 1'b0;
                    state      <= START;
                end
            end

            START: begin
                if (cycle_count == CYCLE - 1) begin
                    cycle_count <= 32'd0;
                    tx_pin      <= data_latch[0];
                    state       <= DATA;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end

            DATA: begin
                if (cycle_count == CYCLE - 1) begin
                    cycle_count <= 32'd0;
                    if (bit_count == 3'd7) begin
                        tx_pin <= 1'b1;
                        state  <= STOP;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        tx_pin    <= data_latch[bit_count + 1'b1];
                    end
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end

            STOP: begin
                if (cycle_count == CYCLE - 1) begin
                    cycle_count <= 32'd0;
                    state       <= IDLE;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
