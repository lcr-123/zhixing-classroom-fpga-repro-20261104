`timescale 1ns/1ps

// Convert asynchronous, active-low keys into debounced events in one clock
// domain. A short-press event is emitted on release. A long-press event is
// emitted once while the key remains held, and suppresses the short event.
module learning_keypad #(
    parameter integer KEY_COUNT = 7,
    parameter integer COUNTER_WIDTH = 26,
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer LONG_PRESS_CYCLES = 50000000,
    parameter integer NAV_LONG_PRESS_CYCLES = LONG_PRESS_CYCLES
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire [KEY_COUNT-1:0] key_n_async,
    input  wire [KEY_COUNT-1:0] nav_long_mode,
    output reg  [KEY_COUNT-1:0] pressed,
    output reg  [KEY_COUNT-1:0] short_press_pulse,
    output reg  [KEY_COUNT-1:0] long_press_pulse
);

// Keep the threshold in the same unsigned width as the physical counter.
// This avoids relying on a mixed-width comparison between a generated
// counter and a 32-bit signed integer parameter in synthesis.
localparam [COUNTER_WIDTH-1:0] LONG_PRESS_LIMIT = LONG_PRESS_CYCLES - 1;
localparam [COUNTER_WIDTH-1:0] NAV_LONG_PRESS_LIMIT = NAV_LONG_PRESS_CYCLES - 1;

reg [KEY_COUNT-1:0] key_meta /* fehdl keep="true" */;
reg [KEY_COUNT-1:0] key_sync /* fehdl keep="true" */;

always @(posedge clk) begin
    if (rst) begin
        key_meta <= {KEY_COUNT{1'b1}};
        key_sync <= {KEY_COUNT{1'b1}};
    end else begin
        key_meta <= key_n_async;
        key_sync <= key_meta;
    end
end

genvar key_index;
generate
    for (key_index = 0; key_index < KEY_COUNT; key_index = key_index + 1) begin : g_key
        reg [COUNTER_WIDTH-1:0] debounce_count;
        reg [COUNTER_WIDTH-1:0] hold_count;
        reg long_reported;
        reg nav_mode_latched;
        wire sampled_pressed = ~key_sync[key_index];

        always @(posedge clk) begin
            short_press_pulse[key_index] <= 1'b0;
            long_press_pulse[key_index] <= 1'b0;

            if (rst) begin
                pressed[key_index] <= 1'b0;
                debounce_count <= {COUNTER_WIDTH{1'b0}};
                hold_count <= {COUNTER_WIDTH{1'b0}};
                long_reported <= 1'b0;
                nav_mode_latched <= 1'b0;
            end else if (sampled_pressed != pressed[key_index]) begin
                hold_count <= hold_count;
                if ((DEBOUNCE_CYCLES <= 1) ||
                    (debounce_count == DEBOUNCE_CYCLES - 1)) begin
                    pressed[key_index] <= sampled_pressed;
                    debounce_count <= {COUNTER_WIDTH{1'b0}};

                    if (sampled_pressed) begin
                        hold_count <= {COUNTER_WIDTH{1'b0}};
                        long_reported <= 1'b0;
                        nav_mode_latched <= nav_long_mode[key_index];
                    end else begin
                        if (!long_reported)
                            short_press_pulse[key_index] <= 1'b1;
                        hold_count <= {COUNTER_WIDTH{1'b0}};
                        long_reported <= 1'b0;
                    end
                end else begin
                    debounce_count <= debounce_count + 1'b1;
                end
            end else begin
                debounce_count <= {COUNTER_WIDTH{1'b0}};

                if (pressed[key_index] && !long_reported) begin
                    if ((nav_mode_latched &&
                         ((NAV_LONG_PRESS_CYCLES <= 1) ||
                          (hold_count >= NAV_LONG_PRESS_LIMIT))) ||
                        (!nav_mode_latched &&
                         ((LONG_PRESS_CYCLES <= 1) ||
                          (hold_count >= LONG_PRESS_LIMIT)))) begin
                        long_press_pulse[key_index] <= 1'b1;
                        long_reported <= 1'b1;
                    end else begin
                        hold_count <= hold_count + 1'b1;
                    end
                end else if (!pressed[key_index]) begin
                    hold_count <= {COUNTER_WIDTH{1'b0}};
                end
            end
        end
    end
endgenerate

endmodule
