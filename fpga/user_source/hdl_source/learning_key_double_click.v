`timescale 1ns/1ps

// Resolve a debounced short release into one click or a double click. The
// first click is held until the window expires, so it cannot trigger the
// single-click action before a possible second click arrives. At 50 MHz,
// allow 500 ms between short releases, including the second press duration.
module learning_key_double_click #(
    parameter integer WINDOW_CYCLES = 25_000_000,
    parameter integer COUNTER_WIDTH = 25
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       active,
    input  wire [3:0] context_id,
    input  wire       short_pulse,
    input  wire       long_pulse,
    output reg        single_pulse,
    output reg        double_pulse
);

localparam [COUNTER_WIDTH-1:0] WINDOW_LIMIT = WINDOW_CYCLES - 1;

reg pending;
reg [3:0] pending_context;
reg [COUNTER_WIDTH-1:0] window_count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending         <= 1'b0;
        pending_context <= 4'd0;
        window_count    <= {COUNTER_WIDTH{1'b0}};
        single_pulse    <= 1'b0;
        double_pulse    <= 1'b0;
    end else begin
        single_pulse <= 1'b0;
        double_pulse <= 1'b0;

        if (!active || long_pulse ||
            (pending && (context_id != pending_context))) begin
            pending      <= 1'b0;
            window_count <= {COUNTER_WIDTH{1'b0}};
        end else if (short_pulse) begin
            if (pending) begin
                pending      <= 1'b0;
                window_count <= {COUNTER_WIDTH{1'b0}};
                double_pulse <= 1'b1;
            end else begin
                pending         <= 1'b1;
                pending_context <= context_id;
                window_count    <= {COUNTER_WIDTH{1'b0}};
            end
        end else if (pending) begin
            if ((WINDOW_CYCLES <= 1) ||
                (window_count >= WINDOW_LIMIT)) begin
                pending      <= 1'b0;
                window_count <= {COUNTER_WIDTH{1'b0}};
                single_pulse <= 1'b1;
            end else begin
                window_count <= window_count + 1'b1;
            end
        end
    end
end

endmodule
