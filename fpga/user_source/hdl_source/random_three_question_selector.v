`timescale 1ns/1ps

// Latches one exercise image from each fixed three-question pool.  The LFSR
// runs continuously; an external free-running counter is mixed in only at the
// session boundary.  Selection is stable until the next session_start pulse.
module random_three_question_selector (
    input  wire        clk,
    input  wire        rst,
    input  wire        session_start,
    input  wire [15:0] entropy_counter,
    input  wire [1:0]  vocabulary_count,
    input  wire [1:0]  sentence_count,
    input  wire [1:0]  question_count,
    output reg         selection_valid,
    output reg         selection_fault,
    output reg  [3:0]  question_image0,
    output reg  [3:0]  question_image1,
    output reg  [3:0]  question_image2
);

reg [15:0] lfsr;
wire lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
wire [15:0] mixed_seed = lfsr ^ entropy_counter;

function [1:0] bounded_pick;
    input [3:0] value;
    input [1:0] count;
    begin
        case (count)
            2'd0, 2'd1: bounded_pick = 2'd0;
            2'd2: bounded_pick = {1'b0, value[0]};
            default: begin
                case (value)
                    4'd0, 4'd3, 4'd6, 4'd9, 4'd12, 4'd15: bounded_pick = 2'd0;
                    4'd1, 4'd4, 4'd7, 4'd10, 4'd13: bounded_pick = 2'd1;
                    default: bounded_pick = 2'd2;
                endcase
            end
        endcase
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        lfsr            <= 16'h1ACE;
        selection_valid <= 1'b0;
        selection_fault <= 1'b0;
        question_image0 <= 4'd3;
        question_image1 <= 4'd6;
        question_image2 <= 4'd9;
    end else begin
        lfsr <= {lfsr[14:0], lfsr_feedback};
        if (session_start) begin
            selection_fault <= (vocabulary_count == 2'd0) ||
                               (sentence_count == 2'd0) ||
                               (question_count == 2'd0);
            selection_valid <= (vocabulary_count != 2'd0) &&
                               (sentence_count != 2'd0) &&
                               (question_count != 2'd0);
            question_image0 <= 4'd3 + bounded_pick(mixed_seed[3:0], vocabulary_count);
            question_image1 <= 4'd6 + bounded_pick(mixed_seed[8:5], sentence_count);
            question_image2 <= 4'd9 + bounded_pick(mixed_seed[13:10], question_count);
        end
    end
end

endmodule
