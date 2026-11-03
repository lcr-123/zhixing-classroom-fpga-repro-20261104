`timescale 1ns/1ps

// Four-question wrong-answer bitmap for the learning machine.
// Set/clear requests are single-cycle events in the learning control clock
// domain. The lowest-numbered pending question is exposed for review.
module wrong_question_queue #(
    parameter integer QUESTION_COUNT = 4
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear_all,
    input  wire                         set_wrong,
    input  wire                         clear_wrong,
    input  wire [2:0]                   question_index,
    output wire [QUESTION_COUNT-1:0]    wrong_bitmap,
    output reg  [3:0]                   wrong_count,
    output reg                          wrong_available,
    output reg  [2:0]                   first_wrong_question
);

    reg [QUESTION_COUNT-1:0] wrong_bitmap_reg;
    integer i;
    reg found_first;

    assign wrong_bitmap = wrong_bitmap_reg;

    always @(posedge clk) begin
        if (rst || clear_all) begin
            wrong_bitmap_reg <= {QUESTION_COUNT{1'b0}};
        end else if (clear_wrong && (question_index < QUESTION_COUNT)) begin
            // Correcting a question wins if contradictory set/clear events
            // arrive together; this keeps review completion monotonic.
            wrong_bitmap_reg[question_index] <= 1'b0;
        end else if (set_wrong && (question_index < QUESTION_COUNT)) begin
            wrong_bitmap_reg[question_index] <= 1'b1;
        end
    end

    always @* begin
        wrong_count = 4'd0;
        wrong_available = 1'b0;
        first_wrong_question = 3'd0;
        found_first = 1'b0;
        for (i = 0; i < QUESTION_COUNT; i = i + 1) begin
            if (wrong_bitmap_reg[i]) begin
                wrong_count = wrong_count + 4'd1;
                wrong_available = 1'b1;
                if (!found_first) begin
                    first_wrong_question = i[2:0];
                    found_first = 1'b1;
                end
            end
        end
    end

endmodule
