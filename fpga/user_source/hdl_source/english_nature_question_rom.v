`timescale 1ns/1ps

// Question metadata for exercise images 3..11.  Visible question and option
// text is already rendered into the BMP; tokens remain useful to diagnostics.
module english_nature_question_rom (
    input  wire [3:0] image_index,
    output reg        question_valid,
    output reg  [1:0] question_group,
    output reg  [7:0] prompt_token,
    output reg  [7:0] option_a_token,
    output reg  [7:0] option_b_token,
    output reg  [7:0] option_c_token,
    output reg  [7:0] option_d_token,
    output reg  [1:0] correct_answer,
    output reg  [1:0] difficulty
);

always @* begin
    question_valid = 1'b1;
    question_group = 2'd0;
    prompt_token = 8'h00;
    option_a_token = 8'h00;
    option_b_token = 8'h00;
    option_c_token = 8'h00;
    option_d_token = 8'h00;
    correct_answer = 2'd0;
    difficulty = 2'd1;

    case (image_index)
        4'd3: begin question_group=2'd0; prompt_token=8'h40; option_a_token=8'h41; option_b_token=8'h42; option_c_token=8'h43; option_d_token=8'h44; correct_answer=2'd2; difficulty=2'd1; end
        4'd4: begin question_group=2'd0; prompt_token=8'h45; option_a_token=8'h46; option_b_token=8'h47; option_c_token=8'h48; option_d_token=8'h49; correct_answer=2'd1; difficulty=2'd1; end
        4'd5: begin question_group=2'd0; prompt_token=8'h4A; option_a_token=8'h4B; option_b_token=8'h4C; option_c_token=8'h4D; option_d_token=8'h4E; correct_answer=2'd3; difficulty=2'd1; end
        4'd6: begin question_group=2'd1; prompt_token=8'h50; option_a_token=8'h51; option_b_token=8'h52; option_c_token=8'h53; option_d_token=8'h54; correct_answer=2'd1; difficulty=2'd2; end
        4'd7: begin question_group=2'd1; prompt_token=8'h55; option_a_token=8'h56; option_b_token=8'h57; option_c_token=8'h58; option_d_token=8'h59; correct_answer=2'd0; difficulty=2'd2; end
        4'd8: begin question_group=2'd1; prompt_token=8'h5A; option_a_token=8'h5B; option_b_token=8'h5C; option_c_token=8'h5D; option_d_token=8'h5E; correct_answer=2'd2; difficulty=2'd2; end
        4'd9: begin question_group=2'd2; prompt_token=8'h60; option_a_token=8'h61; option_b_token=8'h62; option_c_token=8'h63; option_d_token=8'h64; correct_answer=2'd0; difficulty=2'd2; end
        4'd10: begin question_group=2'd2; prompt_token=8'h65; option_a_token=8'h66; option_b_token=8'h67; option_c_token=8'h68; option_d_token=8'h69; correct_answer=2'd2; difficulty=2'd2; end
        4'd11: begin question_group=2'd2; prompt_token=8'h6A; option_a_token=8'h6B; option_b_token=8'h6C; option_c_token=8'h6D; option_d_token=8'h6E; correct_answer=2'd3; difficulty=2'd2; end
        default: begin
            question_valid = 1'b0;
            question_group = 2'd0;
            prompt_token = 8'h00;
            option_a_token = 8'h00;
            option_b_token = 8'h00;
            option_c_token = 8'h00;
            option_d_token = 8'h00;
            correct_answer = 2'd0;
            difficulty = 2'd0;
        end
    endcase
end

endmodule
