`timescale 1ns/1ps

module tb_lesson_auto_advance;

    localparam [3:0] ST_HOME  = 4'd1;
    localparam [3:0] ST_LEARN = 4'd2;
    localparam [3:0] ST_QUIZ  = 4'd3;
    localparam [3:0] ST_FEEDBACK = 4'd4;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [3:0] app_state = ST_HOME;
    reg [2:0] page_index = 3'd0;
    reg voice_active_async = 1'b0;
    reg voice_complete_async = 1'b0;
    wire auto_next_pulse;

    integer pulse_count = 0;

    always #5 clk = ~clk;

    lesson_auto_advance dut (
        .clk               (clk),
        .rst               (rst),
        .app_state         (app_state),
        .page_index        (page_index),
        .voice_active_async(voice_active_async),
        .voice_complete_async(voice_complete_async),
        .auto_next_pulse   (auto_next_pulse)
    );

    always @(posedge clk) begin
        if (auto_next_pulse)
            pulse_count <= pulse_count + 1;
    end

    task wait_clocks(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
        end
    endtask

    task finish_narration_and_expect_pulse(
        input [2:0] expected_page,
        input integer expected_total
    );
        integer timeout;
        begin
            if (page_index != expected_page)
                $fatal(1, "unexpected page before narration completion");
            voice_active_async = 1'b1;
            voice_complete_async = 1'b0;
            wait_clocks(5);
            if (auto_next_pulse)
                $fatal(2, "page advanced before narration finished");
            voice_complete_async = 1'b1;
            wait_clocks(3);
            voice_active_async = 1'b0;
            timeout = 0;
            while (!auto_next_pulse && (timeout < 10)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!auto_next_pulse)
                $fatal(3, "narration completion did not request next page");
            @(posedge clk);
            #1;
            if (pulse_count != expected_total)
                $fatal(4, "completion pulse count mismatch");
            if (auto_next_pulse)
                $fatal(5, "completion pulse lasted more than one clock");
        end
    endtask

    initial begin
        wait_clocks(3);
        rst = 1'b0;
        app_state = ST_LEARN;

        // First English lesson completes and requests page two.
        page_index = 3'd0;
        finish_narration_and_expect_pulse(3'd0, 1);

        // A normally entered second lesson completes and requests page three.
        page_index = 3'd1;
        finish_narration_and_expect_pulse(3'd1, 2);

        // A manual switch during page two narration invalidates the old page
        // tag. Its later falling edge must not skip past the final lesson.
        page_index = 3'd1;
        voice_complete_async = 1'b0;
        voice_active_async = 1'b1;
        wait_clocks(5);
        page_index = 3'd2;
        wait_clocks(2);
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(6, "manual page switch caused a second automatic advance");

        // The third and final lesson remains on screen after narration so
        // KEY4, rather than an automatic event, starts the exercise.
        page_index = 3'd2;
        voice_active_async = 1'b1;
        wait_clocks(5);
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(7, "final learning page unexpectedly advanced");

        // Narration completion outside LEARN is also a bounded no-op.
        app_state = ST_HOME;
        page_index = 3'd0;
        voice_active_async = 1'b1;
        wait_clocks(5);
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(8, "non-learning narration changed the course page");

        app_state = ST_QUIZ;
        voice_active_async = 1'b1;
        wait_clocks(5);
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(9, "quiz narration triggered automatic page advance");

        app_state = ST_FEEDBACK;
        voice_active_async = 1'b1;
        wait_clocks(5);
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(10, "practice feedback triggered automatic page advance");

        // A quiz entry can coincide with the falling edge of the previous
        // lesson narration.  That stale completion must not become a quiz
        // page advance on the transition edge or on the following cycle.
        app_state = ST_LEARN;
        page_index = 3'd0;
        voice_active_async = 1'b1;
        wait_clocks(5);
        app_state = ST_QUIZ;
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(11, "narration edge during quiz entry caused a stale advance");

        // Malformed media ends audio but must not mark the lesson complete.
        app_state = ST_LEARN;
        page_index = 3'd0;
        voice_complete_async = 1'b0;
        voice_active_async = 1'b1;
        wait_clocks(5);
        wait_clocks(5);
        voice_active_async = 1'b0;
        wait_clocks(6);
        if (pulse_count != 2 || auto_next_pulse)
            $fatal(12, "bad audio caused automatic page advance");

        $display("TEST_PASS tb_lesson_auto_advance");
        $finish;
    end

endmodule
