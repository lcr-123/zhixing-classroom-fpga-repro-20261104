`timescale 1ns/1ps

module frame_fifo_read_dual #(
    parameter ADDR_BITS = 21,
    parameter BURST_BITS = 9,
    parameter FIFO_DEPTH = 512,
    parameter BURST_SIZE = 128
) (
    input  wire                   rst,
    input  wire                   mem_clk,
    input  wire                   Sdr_init_done,
    input  wire                   Sdr_init_ref_vld,
    input  wire                   Sdr_busy,
    input  wire                   App_wr_busy,
    output wire                   O_rd_busy,
    output reg                    App_rd_en,
    output reg  [ADDR_BITS-1:0]   App_rd_addr,
    input  wire                   read_req,
    output reg                    read_req_ack,
    output wire                   read_finish,
    input  wire [ADDR_BITS-1:0]   read_addr_0,
    input  wire [ADDR_BITS-1:0]   read_addr_1,
    input  wire [ADDR_BITS-1:0]   read_addr_2,
    input  wire [ADDR_BITS-1:0]   read_addr_3,
    input  wire [1:0]             read_addr_index_a,
    input  wire [1:0]             read_addr_index_b,
    input  wire                   dual_read,
    input  wire [ADDR_BITS-1:0]   read_len,
    output reg                    fifo_aclr,
    input  wire [BURST_BITS-1:0]  wrusedw_a,
    input  wire [BURST_BITS-1:0]  wrusedw_b,
    output reg                    read_target
);

localparam [2:0] S_IDLE  = 3'd0;
localparam [2:0] S_ACK   = 3'd1;
localparam [2:0] S_CHECK = 3'd2;
localparam [2:0] S_READ  = 3'd3;
localparam [2:0] S_DRAIN = 3'd4;
localparam [2:0] S_END   = 3'd5;
localparam [2:0] S_EVAL  = 3'd6;

reg [2:0] state;
reg [2:0] read_req_sync /* fehdl keep="true" */;
reg [1:0] index_a_meta /* fehdl keep="true" */;
reg [1:0] index_a_sync /* fehdl keep="true" */;
reg [1:0] index_b_meta /* fehdl keep="true" */;
reg [1:0] index_b_sync /* fehdl keep="true" */;
reg dual_meta /* fehdl keep="true" */;
reg dual_sync /* fehdl keep="true" */;
reg [ADDR_BITS-1:0] length_meta /* fehdl keep="true" */;
reg [ADDR_BITS-1:0] length_sync /* fehdl keep="true" */;

reg [ADDR_BITS-1:0] length_latched;
reg [ADDR_BITS-1:0] next_addr_a;
reg [ADDR_BITS-1:0] next_addr_b;
// The last full burst may round a non-aligned length up to 2**ADDR_BITS.
// Keep that carry so the terminal comparison cannot wrap back to pending.
reg [ADDR_BITS:0] count_a;
reg [ADDR_BITS:0] count_b;
reg a_pending;
reg b_count_pending;
reg dual_latched;
reg last_target;
reg [BURST_BITS:0] issue_count;
reg [3:0] drain_count;

wire request_active = read_req_sync[2];
wire b_pending = dual_latched && b_count_pending;
wire a_space = wrusedw_a < (FIFO_DEPTH - BURST_SIZE);
wire b_space = wrusedw_b < (FIFO_DEPTH - BURST_SIZE);
wire can_start = Sdr_init_done && !Sdr_init_ref_vld &&
                 !Sdr_busy && !App_wr_busy;

assign O_rd_busy = (state == S_READ) || (state == S_DRAIN);
assign read_finish = (state == S_END);

function [ADDR_BITS-1:0] selected_address;
    input [1:0] index;
    begin
        case (index)
            2'd0: selected_address = read_addr_0;
            2'd1: selected_address = read_addr_1;
            2'd2: selected_address = read_addr_2;
            default: selected_address = read_addr_3;
        endcase
    end
endfunction

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        a_pending <= 1'b0;
        b_count_pending <= 1'b0;
    end else if (state == S_EVAL) begin
        // Counts and length are stable on entry. Separate the wide compares
        // from FIFO arbitration, and avoid evaluating them on every read beat.
        a_pending <= count_a < {1'b0, length_latched};
        b_count_pending <= count_b < {1'b0, length_latched};
    end
end

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        read_req_sync <= 3'b000;
        index_a_meta <= 2'd0;
        index_a_sync <= 2'd0;
        index_b_meta <= 2'd0;
        index_b_sync <= 2'd0;
        dual_meta <= 1'b0;
        dual_sync <= 1'b0;
        length_meta <= {ADDR_BITS{1'b0}};
        length_sync <= {ADDR_BITS{1'b0}};
    end else begin
        read_req_sync <= {read_req_sync[1:0], read_req};
        index_a_meta <= read_addr_index_a;
        index_a_sync <= index_a_meta;
        index_b_meta <= read_addr_index_b;
        index_b_sync <= index_b_meta;
        dual_meta <= dual_read;
        dual_sync <= dual_meta;
        length_meta <= read_len;
        length_sync <= length_meta;
    end
end

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        read_req_ack <= 1'b0;
        fifo_aclr <= 1'b0;
        App_rd_en <= 1'b0;
        App_rd_addr <= {ADDR_BITS{1'b0}};
        length_latched <= {ADDR_BITS{1'b0}};
        next_addr_a <= {ADDR_BITS{1'b0}};
        next_addr_b <= {ADDR_BITS{1'b0}};
        count_a <= {(ADDR_BITS+1){1'b0}};
        count_b <= {(ADDR_BITS+1){1'b0}};
        dual_latched <= 1'b0;
        last_target <= 1'b1;
        read_target <= 1'b0;
        issue_count <= {(BURST_BITS+1){1'b0}};
        drain_count <= 4'd0;
    end else begin
        App_rd_en <= 1'b0;

        case (state)
            S_IDLE: begin
                read_req_ack <= 1'b0;
                fifo_aclr <= 1'b0;
                if (request_active && Sdr_init_done)
                    state <= S_ACK;
            end

            S_ACK: begin
                read_req_ack <= 1'b1;
                fifo_aclr <= 1'b1;
                length_latched <= length_sync;
                next_addr_a <= selected_address(index_a_sync);
                next_addr_b <= selected_address(index_b_sync);
                count_a <= {(ADDR_BITS+1){1'b0}};
                count_b <= {(ADDR_BITS+1){1'b0}};
                dual_latched <= dual_sync;
                // Fill the displayed-frame FIFO first on every new frame.
                last_target <= 1'b1;
                if (!request_active) begin
                    read_req_ack <= 1'b0;
                    fifo_aclr <= 1'b0;
                    state <= S_EVAL;
                end
            end

            S_EVAL: begin
                if (request_active)
                    state <= S_ACK;
                else
                    state <= S_CHECK;
            end

            S_CHECK: begin
                if (request_active) begin
                    state <= S_ACK;
                end else if (!a_pending && !b_pending) begin
                    state <= S_END;
                end else if (can_start) begin
                    if (a_pending && a_space &&
                        (!b_pending || !b_space || last_target)) begin
                        read_target <= 1'b0;
                        last_target <= 1'b0;
                        issue_count <= {(BURST_BITS+1){1'b0}};
                        state <= S_READ;
                    end else if (b_pending && b_space) begin
                        read_target <= 1'b1;
                        last_target <= 1'b1;
                        issue_count <= {(BURST_BITS+1){1'b0}};
                        state <= S_READ;
                    end
                end
            end

            S_READ: begin
                if (issue_count < BURST_SIZE) begin
                    App_rd_en <= 1'b1;
                    if (read_target)
                        App_rd_addr <= next_addr_b + issue_count;
                    else
                        App_rd_addr <= next_addr_a + issue_count;
                    issue_count <= issue_count + 1'b1;
                end else begin
                    drain_count <= 4'd0;
                    state <= S_DRAIN;
                end
            end

            S_DRAIN: begin
                if (drain_count == 4'd10) begin
                    if (read_target) begin
                        next_addr_b <= next_addr_b + BURST_SIZE;
                        count_b <= count_b + BURST_SIZE;
                    end else begin
                        next_addr_a <= next_addr_a + BURST_SIZE;
                        count_a <= count_a + BURST_SIZE;
                    end
                    state <= S_EVAL;
                end else begin
                    drain_count <= drain_count + 1'b1;
                end
            end

            S_END: state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end
end

endmodule
