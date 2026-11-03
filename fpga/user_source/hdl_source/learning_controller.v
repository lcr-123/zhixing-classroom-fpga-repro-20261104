`timescale 1ns/1ps

// Application-layer navigation state machine for the learning machine.
// All inputs are single-cycle events in clk domain; raw keys must pass through
// learning_keypad first. Course scoring and wrong-answer storage remain in
// their dedicated modules and report only status back here.
module learning_controller (
    input  wire       clk,
    input  wire       rst,
    input  wire       boot_done,
    input  wire       content_ready,
    input  wire       nav_next_pulse,
    input  wire       nav_prev_pulse,
    input  wire       nav_select_pulse,
    input  wire       nav_back_pulse,
    input  wire       home_long_pulse,
    input  wire       answer_valid,
    input  wire [1:0] answer_code,
    input  wire       feedback_ack_pressed,
    input  wire       feedback_done,
    input  wire       quiz_complete,
    input  wire       wrong_questions_available,
    input  wire [2:0] page_count,
    // Preserve the application state bank as 50 MHz control-domain storage.
    // Without this, TD can equivalence-merge a duplicated state bit into an
    // audio-domain register after small fanout changes, creating a false
    // stable_ready -> audio_mclk recovery path in the physical netlist.
    output reg  [3:0] state /* fehdl keep="true" */,
    output reg  [2:0] menu_index,
    output reg  [2:0] page_index,
    output reg  [1:0] selected_answer,
    output reg        answer_in_review,
    output reg        answer_submit_pulse,
    output reg        answer_reopen_pulse,
    output reg        session_clear_pulse,
    output reg        safe_recovery_pulse,
    // One-cycle events are emitted only after the state machine accepts a
    // real practice-page move. Boundary presses therefore stay silent.
    output reg        practice_prev_change_pulse,
    output reg        practice_next_change_pulse
);

localparam [3:0] ST_BOOT_SELFTEST = 4'd0;
localparam [3:0] ST_HOME          = 4'd1;
localparam [3:0] ST_LEARN         = 4'd2;
localparam [3:0] ST_QUIZ          = 4'd3;
localparam [3:0] ST_FEEDBACK      = 4'd4;
localparam [3:0] ST_WRONG_REVIEW  = 4'd5;
localparam [3:0] ST_SOUND_LAB     = 4'd6;
localparam [3:0] ST_SETTINGS      = 4'd7;
localparam [3:0] ST_SUMMARY       = 4'd8;

localparam [2:0] MENU_LEARN        = 3'd0;
localparam [2:0] MENU_WRONG_REVIEW = 3'd1;
localparam [2:0] MENU_SETTINGS     = 3'd2;
localparam [2:0] MENU_SUMMARY      = 3'd3;

reg feedback_returns_to_review;
reg feedback_ack_armed;
reg edit_return_valid;
reg edit_return_to_summary;
reg [2:0] edit_return_page;

always @(posedge clk) begin
    if (rst) begin
        state <= ST_BOOT_SELFTEST;
        menu_index <= MENU_LEARN;
        page_index <= 3'd0;
        selected_answer <= 2'd0;
        answer_in_review <= 1'b0;
        answer_submit_pulse <= 1'b0;
        answer_reopen_pulse <= 1'b0;
        session_clear_pulse <= 1'b0;
        safe_recovery_pulse <= 1'b0;
        practice_prev_change_pulse <= 1'b0;
        practice_next_change_pulse <= 1'b0;
        feedback_returns_to_review <= 1'b0;
        feedback_ack_armed <= 1'b0;
        edit_return_valid <= 1'b0;
        edit_return_to_summary <= 1'b0;
        edit_return_page <= 3'd0;
    end else begin
        answer_submit_pulse <= 1'b0;
        answer_reopen_pulse <= 1'b0;
        session_clear_pulse <= 1'b0;
        safe_recovery_pulse <= 1'b0;
        practice_prev_change_pulse <= 1'b0;
        practice_next_change_pulse <= 1'b0;

        if (state != ST_FEEDBACK)
            feedback_ack_armed <= 1'b0;
        else if (feedback_ack_pressed)
            feedback_ack_armed <= 1'b1;

        // A deliberate long press is the bounded escape path from every
        // application mode after self-test.
        if ((state != ST_BOOT_SELFTEST) && home_long_pulse) begin
            state <= ST_HOME;
            menu_index <= MENU_LEARN;
            edit_return_valid <= 1'b0;
            edit_return_to_summary <= 1'b0;
        end else begin
            case (state)
                ST_BOOT_SELFTEST: begin
                    if (boot_done) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                    end
                end

                ST_HOME: begin
                    if (nav_next_pulse) begin
                        if (menu_index == MENU_SUMMARY)
                            menu_index <= MENU_LEARN;
                        else
                            menu_index <= menu_index + 1'b1;
                    end else if (nav_select_pulse) begin
                        case (menu_index)
                            MENU_LEARN: begin
                                if (content_ready) begin
                                    state <= ST_LEARN;
                                    page_index <= 3'd0;
                                end else begin
                                    safe_recovery_pulse <= 1'b1;
                                end
                            end
                            MENU_WRONG_REVIEW: begin
                                if (wrong_questions_available)
                                    state <= ST_WRONG_REVIEW;
                                else
                                    state <= ST_SUMMARY;
                            end
                            MENU_SETTINGS: state <= ST_SETTINGS;
                            default: state <= ST_SUMMARY;
                        endcase
                    end
                end

                ST_LEARN: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                    end else if (nav_prev_pulse) begin
                        // Returning from the first lesson saturates at zero;
                        // it must never wrap to the final lesson.
                        if ((page_count == 3'd0) || (page_index == 3'd0))
                            page_index <= 3'd0;
                        else
                            page_index <= page_index - 1'b1;
                    end else if (nav_next_pulse) begin
                        if (page_count == 3'd0)
                            page_index <= 3'd0;
                        else if (page_index >= page_count - 1'b1)
                            page_index <= 3'd0;
                        else
                            page_index <= page_index + 1'b1;
                    end else if (nav_select_pulse) begin
                        if (content_ready) begin
                            state <= ST_QUIZ;
                            page_index <= 3'd0;
                            session_clear_pulse <= 1'b1;
                            edit_return_valid <= 1'b0;
                            edit_return_to_summary <= 1'b0;
                        end else begin
                            safe_recovery_pulse <= 1'b1;
                        end
                    end
                end

                ST_QUIZ: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                        edit_return_valid <= 1'b0;
                        edit_return_to_summary <= 1'b0;
                    end else if (nav_prev_pulse) begin
                        if (page_index != 3'd0) begin
                            // Multiple backward steps retain the original
                            // question as the post-edit resume point.
                            if (!edit_return_valid && !edit_return_to_summary) begin
                                edit_return_valid <= 1'b1;
                                edit_return_page <= page_index;
                            end
                            page_index <= page_index - 1'b1;
                            practice_prev_change_pulse <= 1'b1;
                        end
                    end else if (answer_valid) begin
                        selected_answer <= answer_code;
                        answer_in_review <= 1'b0;
                        answer_submit_pulse <= 1'b1;
                        feedback_returns_to_review <= 1'b0;
                        feedback_ack_armed <= 1'b0;
                        state <= ST_FEEDBACK;
                    end
                end

                ST_FEEDBACK: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                        edit_return_valid <= 1'b0;
                        edit_return_to_summary <= 1'b0;
                    end else if (nav_prev_pulse &&
                                 !feedback_returns_to_review &&
                                 (page_index != 3'd0)) begin
                        // Unlock the accepted answer and reopen the preceding
                        // primary-quiz question without touching its score.
                        if (!edit_return_valid && !edit_return_to_summary) begin
                            edit_return_valid <= 1'b1;
                            edit_return_page <= page_index;
                        end
                        page_index <= page_index - 1'b1;
                        answer_reopen_pulse <= 1'b1;
                        practice_prev_change_pulse <= 1'b1;
                        state <= ST_QUIZ;
                    end else if (feedback_done && feedback_ack_armed) begin
                        // Review feedback must resolve the wrong-question
                        // queue before consulting the already-latched primary
                        // quiz_complete flag. A retry stays in review, while
                        // the last correction returns HOME after this ACK.
                        if (feedback_returns_to_review) begin
                            if (wrong_questions_available)
                                state <= ST_WRONG_REVIEW;
                            else begin
                                state <= ST_HOME;
                                menu_index <= MENU_LEARN;
                                edit_return_valid <= 1'b0;
                                edit_return_to_summary <= 1'b0;
                            end
                        end else if (edit_return_to_summary) begin
                            state <= ST_SUMMARY;
                            edit_return_to_summary <= 1'b0;
                            edit_return_valid <= 1'b0;
                        end else if (edit_return_valid) begin
                            page_index <= edit_return_page;
                            state <= ST_QUIZ;
                            edit_return_valid <= 1'b0;
                            practice_next_change_pulse <= 1'b1;
                        end else if (quiz_complete) begin
                            state <= ST_SUMMARY;
                        end else begin
                            // Advance the primary quiz cursor only after the
                            // feedback acknowledgement. Review mode uses the
                            // wrong-question queue cursor instead.
                            if (page_count == 3'd0)
                                page_index <= 3'd0;
                            else if (page_index >= page_count - 1'b1)
                                page_index <= 3'd0;
                            else
                                page_index <= page_index + 1'b1;
                            if ((page_count != 3'd0) &&
                                (page_index < page_count - 1'b1))
                                practice_next_change_pulse <= 1'b1;
                            state <= ST_QUIZ;
                        end
                    end
                end

                ST_WRONG_REVIEW: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                    end else if (!wrong_questions_available) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                        edit_return_valid <= 1'b0;
                        edit_return_to_summary <= 1'b0;
                    end else if (answer_valid) begin
                        selected_answer <= answer_code;
                        answer_in_review <= 1'b1;
                        answer_submit_pulse <= 1'b1;
                        feedback_returns_to_review <= 1'b1;
                        feedback_ack_armed <= 1'b0;
                        state <= ST_FEEDBACK;
                    end
                end

                ST_SOUND_LAB: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                    end
                end

                ST_SETTINGS: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                    end
                end

                ST_SUMMARY: begin
                    if (nav_back_pulse) begin
                        state <= ST_HOME;
                        menu_index <= MENU_LEARN;
                    end else if (nav_prev_pulse) begin
                        // A completed quiz can be reopened from its final
                        // question and returns here after one replacement.
                        if (quiz_complete && (page_count != 3'd0)) begin
                            page_index <= page_count - 1'b1;
                            edit_return_to_summary <= 1'b1;
                            edit_return_valid <= 1'b0;
                            state <= ST_QUIZ;
                            practice_prev_change_pulse <= 1'b1;
                        end
                    end else if (nav_select_pulse) begin
                        edit_return_valid <= 1'b0;
                        edit_return_to_summary <= 1'b0;
                        if (wrong_questions_available)
                            state <= ST_WRONG_REVIEW;
                        else begin
                            state <= ST_HOME;
                            menu_index <= MENU_LEARN;
                        end
                    end
                end

                default: begin
                    state <= ST_HOME;
                    menu_index <= MENU_LEARN;
                    page_index <= 3'd0;
                    edit_return_valid <= 1'b0;
                    edit_return_to_summary <= 1'b0;
                    safe_recovery_pulse <= 1'b1;
                end
            endcase
        end
    end
end

endmodule
