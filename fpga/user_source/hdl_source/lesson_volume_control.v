// Lesson narration controls in the 50 MHz application domain.
// SW4 selects volume; SW3 selects speed when SW4 is down.
module lesson_volume_control (
    input  wire       clk,
    input  wire       rst,
    input  wire       learning_active,
    input  wire       adjust_switch_async,
    input  wire       speed_switch_async,
    input  wire       decrement_pulse,
    input  wire       increment_pulse,
    output wire       adjust_mode_active,
    output wire       speed_adjust_active,
    output reg  [2:0] volume_level,
    output reg        control_toggle,
    output reg  [1:0] speed_level,
    output reg        speed_toggle
);

reg [1:0] adjust_switch_sync;
reg [1:0] speed_switch_sync;

assign adjust_mode_active = learning_active && adjust_switch_sync[1];
assign speed_adjust_active = learning_active && speed_switch_sync[1] &&
                             !adjust_switch_sync[1];

always @(posedge clk or posedge rst) begin
    if (rst)
        adjust_switch_sync <= 2'b00;
    else
        adjust_switch_sync <= {adjust_switch_sync[0], adjust_switch_async};
end

always @(posedge clk or posedge rst) begin
    if (rst)
        speed_switch_sync <= 2'b00;
    else
        speed_switch_sync <= {speed_switch_sync[0], speed_switch_async};
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        // Preserve the established narration loudness after reset.
        volume_level   <= 3'd4;
        control_toggle <= 1'b0;
        speed_level    <= 2'd2;
        speed_toggle   <= 1'b0;
    end else if (adjust_mode_active) begin
        // Conflicting simultaneous key events are ignored. At either limit,
        // the value and event token stay unchanged.
        if (decrement_pulse && !increment_pulse &&
            (volume_level != 3'd0)) begin
            volume_level   <= volume_level - 3'd1;
            control_toggle <= ~control_toggle;
        end else if (increment_pulse && !decrement_pulse &&
                     (volume_level != 3'd4)) begin
            volume_level   <= volume_level + 3'd1;
            control_toggle <= ~control_toggle;
        end
    end else if (speed_adjust_active) begin
        if (decrement_pulse && !increment_pulse && speed_level != 2'd0) begin
            speed_level  <= speed_level - 2'd1;
            speed_toggle <= ~speed_toggle;
        end else if (increment_pulse && !decrement_pulse &&
                     speed_level != 2'd2) begin
            speed_level  <= speed_level + 2'd1;
            speed_toggle <= ~speed_toggle;
        end
    end
end

endmodule
