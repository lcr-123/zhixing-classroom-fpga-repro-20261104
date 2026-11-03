`timescale 1ns/1ps

// Deterministic answer selector for the learning quiz.
//
// With all four answer switches down, the established KEY2 interaction remains:
// every short release cycles A -> B -> C -> D -> A.  With exactly one switch
// raised, SW1/SW2/SW3/SW4 directly selects A/B/C/D.  Two or more raised switches
// are rejected so an ambiguous physical setting can never submit a hidden
// answer.  The asynchronous switches are synchronized before application use.
// Leaving an answer page, or raising any switch, restores the key-cycled value
// to A so stale choices cannot leak into a later question.
module learning_answer_input (
    input  wire       clk,
    input  wire       rst,
    input  wire       answer_page_active,
    input  wire       cycle_pulse,
    input  wire [3:0] switch_async,
    output reg  [1:0] selected_answer,
    output reg        switch_selection_active,
    output reg        selection_valid
);

reg [3:0] switch_meta /* fehdl keep="true" */;
reg [3:0] switch_sync /* fehdl keep="true" */;
reg [1:0] key_answer  /* fehdl keep="true" */;

always @(posedge clk) begin
    if (rst) begin
        switch_meta <= 4'b0000;
        switch_sync <= 4'b0000;
    end else begin
        switch_meta <= switch_async;
        switch_sync <= switch_meta;
    end
end

always @(posedge clk) begin
    if (rst) begin
        key_answer <= 2'd0;
    end else if (!answer_page_active || (|switch_sync)) begin
        key_answer <= 2'd0;
    end else if (cycle_pulse) begin
        key_answer <= key_answer + 2'd1;
    end
end

always @* begin
    selected_answer = key_answer;
    switch_selection_active = 1'b0;
    selection_valid = 1'b1;

    case (switch_sync)
        4'b0000: begin
            selected_answer = key_answer;
        end
        4'b0001: begin
            selected_answer = 2'd0;
            switch_selection_active = 1'b1;
        end
        4'b0010: begin
            selected_answer = 2'd1;
            switch_selection_active = 1'b1;
        end
        4'b0100: begin
            selected_answer = 2'd2;
            switch_selection_active = 1'b1;
        end
        4'b1000: begin
            selected_answer = 2'd3;
            switch_selection_active = 1'b1;
        end
        default: begin
            selected_answer = 2'd0;
            switch_selection_active = 1'b1;
            selection_valid = 1'b0;
        end
    endcase
end

endmodule
