`timescale 1ns/1ps

module tb_seg_scan;
    localparam [3:0] ST_BOOT_SELFTEST = 4'd0;
    localparam [3:0] ST_HOME          = 4'd1;
    localparam [3:0] ST_LEARN         = 4'd2;
    localparam [3:0] ST_QUIZ          = 4'd3;
    localparam [3:0] ST_FEEDBACK      = 4'd4;
    localparam [3:0] ST_WRONG_REVIEW  = 4'd5;
    localparam [3:0] ST_SOUND_LAB     = 4'd6;
    localparam [3:0] ST_SETTINGS      = 4'd7;
    localparam [3:0] ST_SUMMARY       = 4'd8;

    localparam [7:0] X = 8'b1_1111111;
    localparam [7:0] DASH = 8'b1_0111111;
    localparam [7:0] N1 = 8'b1_1111001;
    localparam [7:0] N2 = 8'b1_0100100;
    localparam [7:0] N3 = 8'b1_0110000;
    localparam [7:0] N4 = 8'b1_0011001;
    localparam [7:0] A = 8'b1_0001000;
    localparam [7:0] B = 8'b1_0000011;
    localparam [7:0] C = 8'b1_1000110;
    localparam [7:0] D = 8'b1_0100001;
    localparam [7:0] E = 8'b1_0000110;
    localparam [7:0] H = 8'b1_0001001;
    localparam [7:0] L = 8'b1_1000111;
    localparam [7:0] O = 8'b1_1000000;
    localparam [7:0] R = 8'b1_0101111;
    localparam [7:0] S = 8'b1_0010010;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire [7:0] normal_sel;
    wire [7:0] normal_data;
    wire [7:0] diag_sel;
    wire [7:0] diag_data;
    integer digit;

    reg [3:0] app_state = ST_BOOT_SELFTEST;
    reg [2:0] question_index = 3'd0;
    reg [3:0] boot_state_code = 4'd0;
    reg [1:0] settings_index = 2'd0;
    reg answer_selection_valid = 1'b1;
    reg [1:0] answer_choice = 2'd0;
    reg answer_correct = 1'b0;
    reg sound_quiz_active = 1'b0;
    reg sound_quiz_feedback = 1'b0;
    reg sound_quiz_complete = 1'b0;
    reg sound_quiz_answer_correct = 1'b0;
    wire [63:0] status_segments;

    always #10 clk = ~clk;

    seg_scan #(.SEG_DIAG_MODE(1'b0)) dut_normal (
        .clk(clk), .rst_n(rst_n),
        .seg_sel(normal_sel), .seg_data(normal_data),
        .seg_data_0(8'hA0), .seg_data_1(8'hA1),
        .seg_data_2(8'hA2), .seg_data_3(8'hA3),
        .seg_data_4(8'hA4), .seg_data_5(8'hA5),
        .seg_data_6(8'hA6), .seg_data_7(8'hA7)
    );

    seg_scan #(.SEG_DIAG_MODE(1'b1)) dut_diag (
        .clk(clk), .rst_n(rst_n),
        .seg_sel(diag_sel), .seg_data(diag_data),
        .seg_data_0(8'hFF), .seg_data_1(8'hFF),
        .seg_data_2(8'hFF), .seg_data_3(8'hFF),
        .seg_data_4(8'hFF), .seg_data_5(8'hFF),
        .seg_data_6(8'hFF), .seg_data_7(8'hFF)
    );

    learning_seg_status dut_status (
        .app_state(app_state), .question_index(question_index),
        .boot_state_code(boot_state_code),
        .settings_index(settings_index),
        .answer_selection_valid(answer_selection_valid),
        .answer_choice(answer_choice), .answer_correct(answer_correct),
        .sound_quiz_active(sound_quiz_active),
        .sound_quiz_feedback(sound_quiz_feedback),
        .sound_quiz_complete(sound_quiz_complete),
        .sound_quiz_answer_correct(sound_quiz_answer_correct),
        .segments(status_segments)
    );

    task automatic check_scan_digit(input integer index);
        reg [7:0] expected_sel;
        reg [7:0] expected_data;
        begin
            expected_sel = ~(8'b0000_0001 << index);
            expected_data = 8'hA0 + index;
            wait (normal_sel == expected_sel);
            #1;
            if (normal_data !== expected_data)
                $fatal(1, "production scan mismatch at digit %0d", index);
            if (diag_sel !== expected_sel || diag_data !== 8'h00)
                $fatal(2, "diagnostic 88888888 mismatch at digit %0d", index);
        end
    endtask

    task automatic expect_segments(input [63:0] expected, input integer code);
        begin
            #1;
            if (status_segments !== expected)
                $fatal(code, "status word mismatch: got=%h expected=%h",
                       status_segments, expected);
        end
    endtask

    task automatic set_state(input [3:0] next_state);
        begin
            @(negedge clk);
            app_state = next_state;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        if (normal_sel !== 8'hFF || normal_data !== 8'hFF)
            $fatal(3, "reset must disable every digit and segment");

        @(negedge clk);
        rst_n = 1'b1;

        for (digit = 0; digit < 8; digit = digit + 1)
            check_scan_digit(digit);

        expect_segments({X, X, DASH, DASH, DASH, X, X, X}, 10);
        boot_state_code = 4'he;
        expect_segments({X, X, X, E, X, X, X, X}, 11);
        boot_state_code = 4'd4;

        set_state(ST_HOME);
        expect_segments({X, H, E, L, L, O, X, X}, 12);

        set_state(ST_LEARN);
        expect_segments({L, X, X, X, X, X, X, N1}, 13);
        question_index = 3'd2;
        expect_segments({L, X, X, X, X, X, X, N3}, 14);
        question_index = 3'd7;
        expect_segments({L, X, X, X, X, X, X, E}, 15);
        question_index = 3'd0;

        set_state(ST_QUIZ);
        expect_segments({E, X, X, X, X, X, X, A}, 16);
        answer_choice = 2'd1;
        expect_segments({E, X, X, X, X, X, X, B}, 17);
        answer_selection_valid = 1'b0;
        expect_segments({E, X, X, X, X, X, X, E}, 18);
        answer_selection_valid = 1'b1;
        answer_choice = 2'd3;
        expect_segments({E, X, X, X, X, X, X, D}, 19);

        answer_correct = 1'b1;
        set_state(ST_FEEDBACK);
        expect_segments({E, X, X, X, X, X, X, C}, 20);
        answer_correct = 1'b0;
        expect_segments({E, X, X, X, X, X, X, E}, 21);

        set_state(ST_WRONG_REVIEW);
        expect_segments({E, X, X, X, X, X, X, D}, 22);

        set_state(ST_SOUND_LAB);
        expect_segments({A, X, X, X, X, X, X, X}, 23);
        sound_quiz_active = 1'b1;
        expect_segments({E, X, X, X, X, X, X, D}, 24);
        sound_quiz_feedback = 1'b1;
        sound_quiz_answer_correct = 1'b1;
        expect_segments({E, X, X, X, X, X, X, C}, 25);
        sound_quiz_answer_correct = 1'b0;
        expect_segments({E, X, X, X, X, X, X, E}, 26);
        sound_quiz_feedback = 1'b0;
        sound_quiz_complete = 1'b1;
        expect_segments({R, X, X, X, X, X, X, X}, 27);
        sound_quiz_active = 1'b0;
        sound_quiz_complete = 1'b0;

        set_state(ST_SETTINGS);
        expect_segments({S, X, X, X, X, X, X, N1}, 28);
        settings_index = 2'd1;
        expect_segments({S, X, X, X, X, X, X, N2}, 29);
        settings_index = 2'd2;
        expect_segments({S, X, X, X, X, X, X, N3}, 30);
        settings_index = 2'd3;
        // SW2/SW1=11 selects the fourth setting (eye comfort), not an error.
        expect_segments({S, X, X, X, X, X, X, N4}, 31);
        set_state(ST_SUMMARY);
        expect_segments({R, X, X, X, X, X, X, X}, 32);
        set_state(4'hf);
        expect_segments({X, X, X, E, X, X, X, X}, 33);

        $display("TEST_PASS tb_seg_scan");
        $finish;
    end

    initial begin
        #6_000_000;
        $fatal(34, "timeout waiting for all eight scan positions");
    end
endmodule
