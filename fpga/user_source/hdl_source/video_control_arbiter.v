// Merge the UART control mailbox and the two-key SETTINGS controls in the
// 50 MHz reference domain.  UART has priority on a same-cycle collision;
// otherwise the last accepted writer becomes the visible control value.
module video_control_arbiter #(
    parameter integer ZOOM_APPLY_DELAY_CYCLES = 1_000_000,
    parameter integer ZOOM_APPLY_COUNTER_WIDTH = 24,
    parameter integer ENABLE_AMBIENT = 0
) (
    input  wire              clk,
    input  wire              rst,

    input  wire signed [2:0] uart_brightness,
    input  wire        [1:0] uart_contrast,
    input  wire              uart_osd_enable,
    input  wire              uart_subtitle_enable,
    input  wire              uart_control_toggle,

    input  wire              settings_active,
    input  wire        [1:0] select_parameter_async,
    input  wire              zoom_next_pulse,
    input  wire              zoom_prev_pulse,
    input  wire              decrement_pulse,
    input  wire              increment_pulse,
    input  wire              auto_selector_async,
    input  wire signed [2:0] ambient_level,
    input  wire              ambient_valid,
    output reg               auto_brightness_enable,

    output reg  signed [2:0] brightness,
    output reg         [1:0] contrast,
    output reg               osd_enable,
    output reg               subtitle_enable,
    output reg               control_toggle,
    output reg         [2:0] zoom_level,
    output reg         [1:0] zoom_image_index,
    input  wire        [1:0] zoom_lookup_index,
    output wire        [2:0] zoom_lookup_level,
    output reg               zoom_request_toggle,
    output reg         [1:0] editing_parameter,
    output reg               eye_comfort_enable
);

reg uart_toggle_seen;
reg auto_selector_meta, auto_selector_sync;
reg signed [2:0] manual_brightness;
wire signed [2:0] selected_brightness =
    (ENABLE_AMBIENT && auto_brightness_enable && ambient_valid) ?
    ambient_level : manual_brightness;
reg [1:0] select_parameter_sync1;
reg [1:0] select_parameter_sync2;
reg       zoom_mode_active;
reg [2:0] zoom_level0;
reg [2:0] zoom_level1;
reg [2:0] zoom_level2;
reg       zoom_apply_pending;
reg [ZOOM_APPLY_COUNTER_WIDTH-1:0] zoom_apply_count;

localparam [ZOOM_APPLY_COUNTER_WIDTH-1:0] ZOOM_APPLY_DELAY_LIMIT =
    ZOOM_APPLY_DELAY_CYCLES - 1;

function [2:0] zoom_level_lut;
    input [1:0] image_index;
    begin
        case (image_index)
            2'd0: zoom_level_lut = zoom_level0;
            2'd1: zoom_level_lut = zoom_level1;
            2'd2: zoom_level_lut = zoom_level2;
            default: zoom_level_lut = zoom_level0;
        endcase
    end
endfunction

assign zoom_lookup_level = zoom_level_lut(zoom_lookup_index);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        select_parameter_sync1 <= 2'b00;
        select_parameter_sync2 <= 2'b00;
        auto_selector_meta <= 0;
        auto_selector_sync <= 0;
    end else begin
        select_parameter_sync1 <= select_parameter_async;
        select_parameter_sync2 <= select_parameter_sync1;
        auto_selector_meta <= auto_selector_async;
        auto_selector_sync <= auto_selector_meta;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        brightness       <= 3'sd0;
        manual_brightness <= 3'sd0;
        auto_brightness_enable <= 1'b0;
        contrast         <= 2'd1;
        osd_enable       <= 1'b1;
        subtitle_enable  <= 1'b1;
        control_toggle   <= 1'b0;
        zoom_level       <= 3'd2;
        zoom_image_index <= 2'd0;
        zoom_request_toggle <= 1'b0;
        editing_parameter <= 2'b00;
        eye_comfort_enable <= 1'b1;
        uart_toggle_seen <= 1'b0;
        zoom_mode_active <= 1'b0;
        zoom_level0 <= 3'd2;
        zoom_level1 <= 3'd2;
        zoom_level2 <= 3'd2;
        zoom_apply_pending <= 1'b0;
        zoom_apply_count <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
    end else begin
        editing_parameter <= select_parameter_sync2;
        if (ENABLE_AMBIENT && brightness != selected_brightness) begin
            brightness <= selected_brightness;
            control_toggle <= ~control_toggle;
        end

        // A zoom key changes the visible requested value immediately, but a
        // TF reread is expensive. Wait for a short quiet interval so several
        // quick key presses collapse into one complete frame conversion.
        if (zoom_apply_pending) begin
            if ((ZOOM_APPLY_DELAY_CYCLES <= 1) ||
                (zoom_apply_count >= ZOOM_APPLY_DELAY_LIMIT)) begin
                zoom_apply_pending <= 1'b0;
                zoom_apply_count <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
                zoom_request_toggle <= ~zoom_request_toggle;
            end else begin
                zoom_apply_count <= zoom_apply_count + 1'b1;
            end
        end

        if (!(settings_active && (select_parameter_sync2 == 2'b10)) &&
            zoom_mode_active) begin
            zoom_mode_active <= 1'b0;

            // Do not lose the final stored value if the operator leaves the
            // zoom selector before the quiet interval expires.
            if (zoom_apply_pending) begin
                zoom_apply_pending <= 1'b0;
                zoom_apply_count <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
                zoom_request_toggle <= ~zoom_request_toggle;
            end
        end

        // The UART producer already holds all data stable around its toggle.
        // Copy the complete mailbox atomically and acknowledge it locally.
        if (uart_control_toggle != uart_toggle_seen) begin
            uart_toggle_seen <= uart_control_toggle;
            brightness      <= uart_brightness;
            manual_brightness <= uart_brightness;
            auto_brightness_enable <= 0;
            contrast        <= uart_contrast;
            osd_enable      <= uart_osd_enable;
            subtitle_enable <= uart_subtitle_enable;
            control_toggle  <= ~control_toggle;
        end else if (settings_active &&
                     (select_parameter_sync2 == 2'b10) &&
                     !zoom_mode_active) begin
            // Reopen the selected image with its retained zoom value.
            zoom_mode_active       <= 1'b1;
            zoom_level             <= zoom_level_lut(zoom_image_index);
            zoom_apply_pending     <= 1'b1;
            zoom_apply_count       <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
            control_toggle         <= ~control_toggle;
        end else if (settings_active && zoom_mode_active &&
                     (select_parameter_sync2 == 2'b10) &&
                     (zoom_next_pulse ^ zoom_prev_pulse)) begin
            if (zoom_next_pulse && (zoom_image_index < 2'd2)) begin
                zoom_image_index   <= zoom_image_index + 1'b1;
                zoom_level         <= zoom_level_lut(zoom_image_index + 1'b1);
                zoom_apply_pending <= 1'b1;
                zoom_apply_count   <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
                control_toggle     <= ~control_toggle;
            end else if (zoom_prev_pulse && (zoom_image_index != 2'd0)) begin
                zoom_image_index   <= zoom_image_index - 1'b1;
                zoom_level         <= zoom_level_lut(zoom_image_index - 1'b1);
                zoom_apply_pending <= 1'b1;
                zoom_apply_count   <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
                control_toggle     <= ~control_toggle;
            end
        end else if (settings_active &&
                     (decrement_pulse ^ increment_pulse)) begin
            case (select_parameter_sync2)
            2'b01: begin
                if (decrement_pulse && (contrast != 2'd0)) begin
                    contrast       <= contrast - 2'd1;
                    control_toggle <= ~control_toggle;
                end else if (increment_pulse && (contrast != 2'd3)) begin
                    contrast       <= contrast + 2'd1;
                    control_toggle <= ~control_toggle;
                end
            end
            2'b00: begin
                if (ENABLE_AMBIENT && auto_selector_sync) begin
                    auto_brightness_enable <= increment_pulse;
                end else if (decrement_pulse && (brightness != -3'sd2)) begin
                    brightness     <= brightness - 3'sd1;
                    manual_brightness <= brightness - 3'sd1;
                    auto_brightness_enable <= 0;
                    control_toggle <= ~control_toggle;
                end else if (increment_pulse && (brightness != 3'sd2)) begin
                    brightness     <= brightness + 3'sd1;
                    manual_brightness <= brightness + 3'sd1;
                    auto_brightness_enable <= 0;
                    control_toggle <= ~control_toggle;
                end else if (ENABLE_AMBIENT) begin
                    // Manual override also works at the saturated end stops.
                    manual_brightness <= brightness;
                    auto_brightness_enable <= 0;
                end
            end
            2'b10: begin
                if (decrement_pulse && (zoom_level != 3'd0)) begin
                    zoom_level          <= zoom_level - 3'd1;
                    case (zoom_image_index)
                        2'd0: zoom_level0 <= zoom_level - 3'd1;
                        2'd1: zoom_level1 <= zoom_level - 3'd1;
                        2'd2: zoom_level2 <= zoom_level - 3'd1;
                        default: ;
                    endcase
                    zoom_apply_pending <= 1'b1;
                    zoom_apply_count <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
                    control_toggle <= ~control_toggle;
                end else if (increment_pulse && (zoom_level != 3'd4)) begin
                    zoom_level          <= zoom_level + 3'd1;
                    case (zoom_image_index)
                        2'd0: zoom_level0 <= zoom_level + 3'd1;
                        2'd1: zoom_level1 <= zoom_level + 3'd1;
                        2'd2: zoom_level2 <= zoom_level + 3'd1;
                        default: ;
                    endcase
                    zoom_apply_pending <= 1'b1;
                    zoom_apply_count <= {ZOOM_APPLY_COUNTER_WIDTH{1'b0}};
                    control_toggle <= ~control_toggle;
                end
            end
            2'b11: begin
                // Explicit ON/OFF is idempotent; simultaneous keys are
                // rejected by the common XOR guard above. No SD reread.
                eye_comfort_enable <= increment_pulse;
            end
            endcase
        end
    end
end

endmodule
