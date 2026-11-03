`timescale 1ns/1ps

module video_effects_osd #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer SCROLL_FRAME_DIV = 1,
    parameter integer ENABLE_AMBIENT_OSD = 0
) (
    input  wire              pixel_clk,
    input  wire              pixel_rst,
    input  wire              frame_boundary,
    input  wire              in_hs,
    input  wire              in_vs,
    input  wire              in_de,
    input  wire [23:0]       in_rgb,
    input  wire signed [2:0] source_brightness,
    input  wire [1:0]        source_contrast,
    input  wire              source_osd_enable,
    input  wire              source_subtitle_enable,
    input  wire              source_control_toggle,
    input  wire              source_ambient_enable,
    input  wire              source_ambient_ready,
    input  wire [2:0]        source_zoom_preview_level,
    input  wire [3:0]        display_image_idx,
    input  wire              display_valid,
    input  wire              transition_active,
    input  wire [2:0]        display_zoom_level,
    input  wire [3:0]        source_state_code,
    // Stable payload published with source_state_toggle, not a live bus.
    input  wire [2:0]        source_wrong_bitmap,
    input  wire [3:0]        source_target_image_idx,
    input  wire              source_state_toggle,
    output wire              state_ack_toggle,
    input  wire              source_auto_play,
    input  wire [2:0]        source_volume_level,
    input  wire              source_volume_toggle,
    input  wire [1:0]        source_speed_level,
    input  wire              source_speed_toggle,
    // Already in pixel_clk; produced by the existing consumed-PCM mailbox.
    input  wire [8:0]        voice_progress,
    input  wire [1:0]        voice_clip,
    input  wire              voice_valid,
    input  wire              source_eye_comfort_enable,
    output wire              eye_filter_enable,
    input  wire              source_lesson_subtitle_active,
    input  wire [1:0]        source_lesson_subtitle_clip,
    input  wire [4:0]        source_lesson_subtitle_cue,
    input  wire              source_lesson_subtitle_toggle,
    output reg               out_hs,
    output reg               out_vs,
    output reg               out_de,
    output reg [23:0]        out_rgb
);

reg [2:0] control_toggle_sync /* fehdl keep="true" */;
reg signed [2:0] brightness_meta /* fehdl keep="true" */;
reg signed [2:0] brightness_sync /* fehdl keep="true" */;
reg [1:0] contrast_meta /* fehdl keep="true" */;
reg [1:0] contrast_sync /* fehdl keep="true" */;
reg osd_meta /* fehdl keep="true" */;
reg osd_sync /* fehdl keep="true" */;
reg subtitle_meta /* fehdl keep="true" */;
reg subtitle_sync /* fehdl keep="true" */;
reg [2:0] zoom_preview_level_meta /* fehdl keep="true" */;
reg [2:0] zoom_preview_level_sync /* fehdl keep="true" */;
reg control_seen;
reg ambient_enable_meta /* fehdl keep="true" */;
reg ambient_enable_sync /* fehdl keep="true" */;
reg ambient_ready_meta /* fehdl keep="true" */;
reg ambient_ready_sync /* fehdl keep="true" */;
reg ambient_enable_active, ambient_ready_active;

reg signed [2:0] brightness_active;
reg [1:0] contrast_active;
reg osd_active;
reg subtitle_active;
reg [2:0] zoom_preview_level_active;
reg signed [2:0] brightness_pending;
reg [1:0] contrast_pending;
reg osd_pending;
reg subtitle_pending;
reg [2:0] zoom_preview_level_pending;
reg control_pending_valid;

reg [2:0] state_toggle_sync /* fehdl keep="true" */;
reg [10:0] state_mailbox_meta /* fehdl keep="true" */;
reg [10:0] state_mailbox_sync /* fehdl keep="true" */;
reg       state_seen;
// ACK only after the stable payload has been captured into state_pending.
// The source synchronizes this toggle before reusing the mailbox.
assign state_ack_toggle = state_seen;
reg [10:0] state_pending;
reg [3:0] state_active;
reg [2:0] wrong_active;
reg [3:0] target_image_active;
reg [3:0] banner_image;
reg [8:0] banner_frames;
reg banner_seen;
reg auto_meta;
reg auto_sync;
reg [2:0] volume_meta /* fehdl keep="true" */;
reg [2:0] volume_sync /* fehdl keep="true" */;
reg [2:0] volume_toggle_sync /* fehdl keep="true" */;
reg volume_seen;
reg [2:0] volume_pending;
reg [2:0] volume_active;
reg [1:0] speed_meta /* fehdl keep="true" */;
reg [1:0] speed_sync /* fehdl keep="true" */;
reg [2:0] speed_toggle_sync /* fehdl keep="true" */;
reg speed_seen;
reg [1:0] speed_pending;
reg [1:0] speed_active;
reg [6:0] progress_active;
reg [3:0] progress_image;
wire [8:0] bounded_progress = voice_progress > 9'd256 ? 9'd256 : voice_progress;
// 100/256 = 25/64, implemented with shifts and adds, without a divider/DSP.
wire [13:0] progress_scaled = {bounded_progress,4'b0} +
    {bounded_progress,3'b0} + {5'b0,bounded_progress};
wire [6:0] progress_percent = progress_scaled[12:6];
wire [6:0] display_percent = progress_image == display_image_idx ? progress_active : 7'd0;
// An independent, persistent single-bit preference needs no multi-bit mailbox.
reg eye_meta /* fehdl keep="true" */;
reg eye_sync /* fehdl keep="true" */;
reg eye_active;
assign eye_filter_enable = eye_active &&
    ((state_active == 4'd1) || (state_active == 4'd2) || (state_active == 4'd3) ||
     (state_active == 4'd4) || (state_active == 4'd5) ||
     (state_active == 4'd7) || (state_active == 4'd8));

reg [2:0] lesson_subtitle_toggle_sync /* fehdl keep="true" */;
reg       lesson_subtitle_active_meta /* fehdl keep="true" */;
reg       lesson_subtitle_active_sync /* fehdl keep="true" */;
reg [1:0] lesson_subtitle_clip_meta /* fehdl keep="true" */;
reg [1:0] lesson_subtitle_clip_sync /* fehdl keep="true" */;
reg [4:0] lesson_subtitle_cue_meta /* fehdl keep="true" */;
reg [4:0] lesson_subtitle_cue_sync /* fehdl keep="true" */;
reg       lesson_subtitle_seen;
reg       lesson_subtitle_pending_valid;
reg       lesson_subtitle_active_pending;
reg [1:0] lesson_subtitle_clip_pending;
reg [4:0] lesson_subtitle_cue_pending;
reg       lesson_subtitle_active;
reg [1:0] lesson_subtitle_clip;
reg [4:0] lesson_subtitle_cue;

reg [9:0] pixel_x;
reg [9:0] pixel_y;
reg de_d;
reg [9:0] scroll_position;
reg [7:0] scroll_frame_count;
reg stage_hs;
reg stage_vs;
reg stage_de;
reg [23:0] stage_adjusted_rgb;
reg stage_status_region;
reg [7:0] stage_status_code;
reg [3:0] stage_status_row;
reg [3:0] stage_status_col;
reg stage_lesson_subtitle_region;
reg [7:0] stage_lesson_subtitle_code;
reg [3:0] stage_lesson_subtitle_row;
reg [3:0] stage_lesson_subtitle_col;
reg stage_subtitle_region;
reg [7:0] stage_subtitle_code;
reg [3:0] stage_subtitle_row;
reg [3:0] stage_subtitle_col;

wire [15:0] stage_status_font_row;
wire [15:0] stage_lesson_subtitle_font_row;
wire [15:0] stage_subtitle_font_row;

wire [7:0] adjusted_r;
wire [7:0] adjusted_g;
wire [7:0] adjusted_b;
wire [23:0] adjusted_rgb = {adjusted_r, adjusted_g, adjusted_b};
wire [2:0] status_zoom_level = (state_active == 4'd7) ?
                               zoom_preview_level_active : display_zoom_level;

wire banner_eligible = display_valid && !transition_active &&
    (state_active == 4'd3 || state_active == 4'd5) &&
    (display_image_idx >= 4'd3) && (display_image_idx <= 4'd11) &&
    (display_image_idx == target_image_active);
// Append 17 cells to the existing 23-cell parameter strip, without a gap.
wire banner_region = osd_active && banner_eligible && banner_seen &&
    (banner_frames < 9'd300) && (pixel_y < 10'd16) &&
    (pixel_x >= 10'd368) && (pixel_x < 10'd640);
wire status_region = banner_region || (osd_active &&
    ((pixel_y < 10'd16) &&
      (pixel_x < ((state_active == 4'd2) ? 10'd640 :
                   (state_active == 4'd7) ?
                   (ENABLE_AMBIENT_OSD ? 10'd544 : 10'd432) : 10'd368))));
wire [5:0] status_index = pixel_x[9:4];
wire [3:0] status_col = pixel_x[3:0];
wire [3:0] status_row = pixel_y[3:0];
wire [7:0] status_code;
// Exercise pools contain three interchangeable cards per logical page.
// Derive the label from the committed picture, so loading a new card cannot
// advance the displayed page before the actual frame-buffer switch.
reg [3:0] status_image_idx;
always @* begin
    status_image_idx = display_image_idx;
    if ((state_active == 4'd3) || (state_active == 4'd4) ||
        (state_active == 4'd5)) begin
        case (display_image_idx)
            4'd3, 4'd4, 4'd5: status_image_idx = 4'd3;
            4'd6, 4'd7, 4'd8: status_image_idx = 4'd4;
            4'd9, 4'd10, 4'd11: status_image_idx = 4'd5;
            default: status_image_idx = display_image_idx;
        endcase
    end
end
wire [15:0] status_font_row;
wire status_pixel;

wire [10:0] subtitle_virtual =
    {1'b0, pixel_x} + {1'b0, scroll_position};
wire subtitle_region = subtitle_active &&
                       (pixel_y >= FRAME_HEIGHT - 16) &&
                       (pixel_y < FRAME_HEIGHT) &&
                       (subtitle_virtual >= FRAME_WIDTH) &&
                       (subtitle_virtual < FRAME_WIDTH + 256);
wire [8:0] subtitle_pixel_x = subtitle_virtual - FRAME_WIDTH;
wire [3:0] subtitle_pixel_y = pixel_y - (FRAME_HEIGHT - 16);
// Center each short message inside the existing 16-cell scrolling strip.
reg [7:0] subtitle_left_padding;
always @* begin
    case (state_active)
        4'd0: subtitle_left_padding = 8'd80; // 6 characters
        4'd1: subtitle_left_padding = 8'd88; // 5 characters
        4'd2: subtitle_left_padding = 8'd64; // 8 characters
        4'd3: subtitle_left_padding = 8'd88; // 5 characters
        4'd4: subtitle_left_padding = 8'd56; // 9 cells, including a gap
        4'd5: subtitle_left_padding = 8'd72; // 7 characters
        4'd6: subtitle_left_padding = 8'd40; // 11 cells, including a gap
        4'd7: subtitle_left_padding = 8'd64; // 8 characters
        4'd8: subtitle_left_padding = (wrong_active != 0) ? 8'd8 : 8'd48;
        default: subtitle_left_padding = 8'd80; // 6 characters
    endcase
end
wire [8:0] subtitle_text_x = subtitle_pixel_x - {1'b0, subtitle_left_padding};
wire [3:0] subtitle_char_index = subtitle_text_x[7:4];
wire [3:0] subtitle_col = subtitle_text_x[3:0];
wire [3:0] subtitle_row = subtitle_pixel_y[3:0];
wire [7:0] subtitle_code;
wire [15:0] subtitle_font_row;
wire subtitle_pixel;

wire lesson_subtitle_region = subtitle_active &&
                              lesson_subtitle_active &&
                              (pixel_y >= FRAME_HEIGHT - 16) &&
                              (pixel_y < FRAME_HEIGHT);
wire [5:0] lesson_subtitle_index = pixel_x[9:4];
wire [3:0] lesson_subtitle_col = pixel_x[3:0];
wire [3:0] lesson_subtitle_row = pixel_y - (FRAME_HEIGHT - 16);
wire [7:0] lesson_subtitle_code;
wire [15:0] lesson_subtitle_font_row;
wire lesson_subtitle_pixel =
    lesson_subtitle_font_row[15 - lesson_subtitle_col];

function [7:0] adjust_channel;
    input [7:0] channel;
    input signed [2:0] brightness;
    input [1:0] contrast;
    integer centered;
    integer scaled;
    integer value;
    begin
        centered = channel - 128;
        case (contrast)
            2'd0: scaled = centered - (centered >>> 2);
            2'd1: scaled = centered;
            2'd2: scaled = centered + (centered >>> 2);
            default: scaled = centered + (centered >>> 1);
        endcase
        value = 128 + scaled + (brightness <<< 4);
        if (value < 0)
            adjust_channel = 8'd0;
        else if (value > 255)
            adjust_channel = 8'd255;
        else
            adjust_channel = value[7:0];
    end
endfunction

function [7:0] hex_char;
    input [3:0] value;
    begin
        if (value < 10)
            hex_char = 8'h30 + value;
        else
            hex_char = 8'h41 + (value - 10);
    end
endfunction

function [7:0] banner_char;
    input [4:0] index;
    input [3:0] image_index;
    begin
        case (index)
            5'd0: banner_char = image_index < 4'd6 ? "1" : " ";
            5'd1: banner_char = image_index < 4'd6 ? "2" :
                                  image_index < 4'd9 ? "8" : "3";
            5'd2: banner_char = image_index < 4'd6 ? "8" :
                                  image_index < 4'd9 ? "0" : "2";
            5'd3: banner_char = "0";
            5'd4: banner_char = "*";
            5'd5: banner_char = image_index < 4'd6 ? "9" :
                                  image_index < 4'd9 ? "6" : "2";
            5'd6: banner_char = image_index < 4'd6 ? "6" :
                                  image_index < 4'd9 ? "0" : "4";
            5'd7: banner_char = "0";
            5'd8: banner_char = "-";
            5'd9: banner_char = ">";
            5'd10: banner_char = "6";
            5'd11: banner_char = "4";
            5'd12: banner_char = "0";
            5'd13: banner_char = "*";
            5'd14: banner_char = "4";
            5'd15: banner_char = "8";
            default: banner_char = "0";
        endcase
    end
endfunction

function [7:0] status_char;
    input [4:0] index;
    input [3:0] image_index;
    input auto_play;
    input signed [2:0] brightness;
    input [1:0] contrast;
    input [2:0] zoom_level;
    input eye_enabled;
    reg [2:0] brightness_abs;
    reg [7:0] zoom_hundreds;
    reg [7:0] zoom_tens;
    reg [7:0] zoom_ones;
    begin
        brightness_abs = brightness[2] ? -brightness : brightness;
        case (zoom_level)
            3'd0: begin zoom_hundreds = " "; zoom_tens = "5"; zoom_ones = "0"; end
            3'd1: begin zoom_hundreds = " "; zoom_tens = "7"; zoom_ones = "5"; end
            3'd2: begin zoom_hundreds = "1"; zoom_tens = "0"; zoom_ones = "0"; end
            3'd3: begin zoom_hundreds = "1"; zoom_tens = "2"; zoom_ones = "5"; end
            default: begin zoom_hundreds = "1"; zoom_tens = "5"; zoom_ones = "0"; end
        endcase
        case (index)
            0: status_char = 8'h80;  // 图
            1: status_char = 8'h81;  // 像
            2: status_char = ":";
            3: status_char = hex_char(image_index + 4'd1);
            4: status_char = " ";
            5: status_char = 8'h86; // 亮
            6: status_char = 8'h87; // 度
            7: status_char = ":";
            8: status_char = brightness[2] ? "-" : "+";
            9: status_char = "0" + brightness_abs;
            10: status_char = " ";
            11: status_char = 8'h88; // 对
            12: status_char = 8'h89; // 比
            13: status_char = ":";
            14: status_char = "0" + contrast;
            15: status_char = " ";
            16: status_char = 8'hC0; // 缩
            17: status_char = 8'hC1; // 放
            18: status_char = ":";
            19: status_char = zoom_hundreds;
            20: status_char = zoom_tens;
            21: status_char = zoom_ones;
            22: status_char = "%";
            // These cells are visible only in the extended SETTINGS region.
            23: status_char = 8'hC2; // 护
            24: status_char = 8'hC3; // 眼
            25: status_char = ":";
            26: status_char = eye_enabled ? 8'h84 : 8'h85;
            default: status_char = " ";
        endcase
    end
endfunction

function [7:0] learning_audio_char;
    input [3:0] index;
    input [2:0] volume;
    input [6:0] percent;
    reg [6:0] remainder;
    begin
        remainder = percent == 100 ? 0 : percent;
        case (index)
            0: learning_audio_char = " ";
            1: learning_audio_char = 8'hC4; // 音
            2: learning_audio_char = 8'hC5; // 量
            3: learning_audio_char = ":";
            4: learning_audio_char = "0" + volume;
            5: learning_audio_char = 8'hC6; // 进
            6: learning_audio_char = 8'h87; // 度
            7: learning_audio_char = ":";
            8: learning_audio_char = percent == 100 ? "1" : " ";
            9: learning_audio_char = percent >= 10 ? "0" + (remainder / 10) : " ";
            10: learning_audio_char = "0" + (remainder % 10);
            11: learning_audio_char = "%";
            default: learning_audio_char = " ";
        endcase
    end
endfunction

function [7:0] learning_speed_char;
    input [2:0] index;
    input [1:0] speed;
    begin
        case (index)
            3'd0: learning_speed_char = speed == 2'd0 ? "0" : "1";
            3'd1: learning_speed_char = ".";
            3'd2: learning_speed_char = speed == 2'd0 ? "7" :
                                        speed == 2'd2 ? "2" : "0";
            3'd3: learning_speed_char = speed == 2'd1 ? "0" : "5";
            default: learning_speed_char = "X";
        endcase
    end
endfunction

function [7:0] subtitle_char;
    input [3:0] index;
    input [3:0] state_code;
    begin
        subtitle_char = " ";
        case (state_code)
            4'd0: begin // 正在开机自检
                case (index)
                    0: subtitle_char = 8'h8C;
                    1: subtitle_char = 8'h8D;
                    2: subtitle_char = 8'h84;
                    3: subtitle_char = 8'h8E;
                    4: subtitle_char = 8'h82;
                    5: subtitle_char = 8'h8F;
                endcase
            end
            4'd1: begin // 请选择功能
                case (index)
                    0: subtitle_char = 8'h90;
                    1: subtitle_char = 8'h91;
                    2: subtitle_char = 8'h92;
                    3: subtitle_char = 8'h93;
                    4: subtitle_char = 8'h94;
                endcase
            end
            4'd2: begin // 按键切换学习图片
                case (index)
                    0: subtitle_char = 8'h95;
                    1: subtitle_char = 8'h96;
                    2: subtitle_char = 8'h97;
                    3: subtitle_char = 8'h98;
                    4: subtitle_char = 8'h99;
                    5: subtitle_char = 8'h9A;
                    6: subtitle_char = 8'h80;
                    7: subtitle_char = 8'h9B;
                endcase
            end
            4'd3: begin // 请输入答案
                case (index)
                    0: subtitle_char = 8'h90;
                    1: subtitle_char = 8'h9C;
                    2: subtitle_char = 8'h9D;
                    3: subtitle_char = 8'h9E;
                    4: subtitle_char = 8'h9F;
                endcase
            end
            4'd4: begin // 查看结果 按键继续
                case (index)
                    0: subtitle_char = 8'hA0;
                    1: subtitle_char = 8'hA1;
                    2: subtitle_char = 8'hA2;
                    3: subtitle_char = 8'hA3;
                    5: subtitle_char = 8'h95;
                    6: subtitle_char = 8'h96;
                    7: subtitle_char = 8'hA4;
                    8: subtitle_char = 8'hA5;
                endcase
            end
            4'd5: begin // 请重新回答错题
                case (index)
                    0: subtitle_char = 8'h90;
                    1: subtitle_char = 8'hA6;
                    2: subtitle_char = 8'hA7;
                    3: subtitle_char = 8'hA8;
                    4: subtitle_char = 8'h9E;
                    5: subtitle_char = 8'hA9;
                    6: subtitle_char = 8'hAA;
                endcase
            end
            4'd6: begin // 调节声音 进入听音挑战
                case (index)
                    0: subtitle_char = 8'hAB;
                    1: subtitle_char = 8'hAC;
                    2: subtitle_char = 8'hAD;
                    3: subtitle_char = 8'hAE;
                    5: subtitle_char = 8'hAF;
                    6: subtitle_char = 8'h9D;
                    7: subtitle_char = 8'hB0;
                    8: subtitle_char = 8'hAE;
                    9: subtitle_char = 8'hB1;
                    10: subtitle_char = 8'hB2;
                endcase
            end
            4'd7: begin // 选择要修改的参数
                case (index)
                    0: subtitle_char = 8'h91;
                    1: subtitle_char = 8'h92;
                    2: subtitle_char = 8'hB3;
                    3: subtitle_char = 8'hB4;
                    4: subtitle_char = 8'hB5;
                    5: subtitle_char = 8'hB6;
                    6: subtitle_char = 8'hB7;
                    7: subtitle_char = 8'hB8;
                endcase
            end
            4'd8: begin // 错题:4 5 6 进入错题回顾 / 无错题 按键返回首页
                if (wrong_active != 3'd0) begin
                case (index)
                    0: subtitle_char = 8'hA9;
                    1: subtitle_char = 8'hAA;
                    2: subtitle_char = ":";
                    3: subtitle_char = wrong_active[0] ? "4" : " ";
                    5: subtitle_char = wrong_active[1] ? "5" : " ";
                    7: subtitle_char = wrong_active[2] ? "6" : " ";
                    9: subtitle_char = 8'hAF;
                    10: subtitle_char = 8'h9D;
                    11: subtitle_char = 8'hA9;
                    12: subtitle_char = 8'hAA;
                    13: subtitle_char = 8'hA8;
                    14: subtitle_char = 8'hC7;
                endcase
                end else begin
                case (index)
                    0: subtitle_char = 8'hC8;
                    1: subtitle_char = 8'hA9;
                    2: subtitle_char = 8'hAA;
                    4: subtitle_char = 8'h95;
                    5: subtitle_char = 8'h96;
                    6: subtitle_char = 8'hCB;
                    7: subtitle_char = 8'hA8;
                    8: subtitle_char = 8'hC9;
                    9: subtitle_char = 8'hCA;
                endcase
                end
            end
            default: begin // 系统状态异常
                case (index)
                    0: subtitle_char = 8'hBC;
                    1: subtitle_char = 8'hBD;
                    2: subtitle_char = 8'h8A;
                    3: subtitle_char = 8'h8B;
                    4: subtitle_char = 8'hBE;
                    5: subtitle_char = 8'hBF;
                endcase
            end
        endcase
    end
endfunction

function [15:0] double_bits;
    input [7:0] bits;
    begin
        double_bits = {{2{bits[7]}}, {2{bits[6]}},
                       {2{bits[5]}}, {2{bits[4]}},
                       {2{bits[3]}}, {2{bits[2]}},
                       {2{bits[1]}}, {2{bits[0]}}};
    end
endfunction

function [15:0] font_row;
    input [7:0] char_code;
    input [3:0] row;
    reg [255:0] glyph;
    reg [63:0] ascii_glyph;
    begin
        glyph = 256'd0;
        ascii_glyph = 64'd0;
        case (char_code)
            8'h80: glyph = 256'h00007FFC200C220C27CC2E4C2B8C23CC2D3C218C220C218C200C7FFC60000000; // 图
            8'h81: glyph = 256'h198013F036203FF8724853F8518016D81170167015A8162434C0008000000000; // 像
            8'h82: glyph = 256'h020002003FF8101810181FF8101810181FF8101810181FF83018000000000000; // 自
            8'h83: glyph = 256'h002000207E2001FC00247E2410241064224422447FC400840118000000000000; // 动
            8'h84: glyph = 256'h000020083FF804600460046004607FFC046004600C6008601860706000000000; // 开
            8'h85: glyph = 256'h0860044004403FF80100010001007FFC0180028006601838701C000000000000; // 关
            8'h86: glyph = 256'h01007FFC00001FF018301FF000007FFC400407C004400C44387C200000000000; // 亮
            8'h87: glyph = 256'h01803FF8200022202FF8222023E020002FF02220214040804F7C100400000000; // 度
            8'h88: glyph = 256'h001800107E1005FC04102410159018900CD01410321062104030000000000000; // 对
            8'h89: glyph = 256'h0000208020802080209C20B03EC020802080208022802C84708C20F800000000; // 比
            8'h8A: glyph = 256'h08400858484868402BFC08401860186028A048B0099009080E0C000000000000; // 状
            8'h8B: glyph = 256'h030002007FFC06C004400A20311C600001002498240C443447E0000000000000; // 态
            8'h8C: glyph = 256'h000000003FF8010001000100110011F8110011001100110011007FFC00000000; // 正
            8'h8D: glyph = 256'h030002007FFC040004401840184033F8704050401040104017FC100000000000; // 在
            8'h8E: glyph = 256'h0000100011F011107D10111031103D1035105110511011101214161C00000000; // 机
            8'h8F: glyph = 256'h104010C010A07D1013EC37E438007E48535851701110102017FC000000000000; // 检
            8'h90: glyph = 256'h204033FC184003F8004077FC33F8320833F832083BF832080218000000000000; // 请
            8'h91: glyph = 256'h0240224013F80440004077FC10A011A01120132416383C0043FC000000000000; // 选
            8'h92: glyph = 256'h13F8111810907CE010E0131C384073F81040104017FC10407040004000000000; // 择
            8'h93: glyph = 256'h004000407C4011FC10441044104C104C10881E88618803080638000000000000; // 功
            8'h94: glyph = 256'h1840105826706F40504400783E4022483E7822403E402244267C000000000000; // 能
            8'h95: glyph = 256'h1040106013FC7A04124410C01BFC3098511013B0106010F8770C000000000000; // 按
            8'h96: glyph = 256'h302027F87A2842FC0A283778252079F8252026FC2A20332024FC000000000000; // 键
            8'h97: glyph = 256'h0000100013FC104410443C447044104C10CC14881C8831080308063800000000; // 切
            8'h98: glyph = 256'h1080110011F07A2017F812481A48324857FC106010A01118760C000000000000; // 换
            8'h99: glyph = 256'h0310313010207FFC400440041FE000C001007FFC010001000700020000000000; // 学
            8'h9A: glyph = 256'h00001FF8000808080E1803180018005801D80E181818001000F0000000000000; // 习
            8'h9B: glyph = 256'h10401040104010401FFC100010001FE010201020302020206020000000000000; // 片
            8'h9C: glyph = 256'h30C020A0793023FC260453CC7A5853D812581BD87258127812D8100000000000; // 输
            8'h9D: glyph = 256'h04000600030001000180028002C006400C6008301018600C4000000000000000; // 入
            8'h9E: glyph = 256'h10403F7C28904508030004C0187077DC40001FF018301FF01830000000000000; // 答
            8'h9F: glyph = 256'h01003FF8220804003FF80C4003E03E1801003FFC05401930610C000000000000; // 案
            8'hA0: glyph = 256'h0000010001007FFC05400930311C5FF410101FF010101FF000007FFC00000000; // 查
            8'hA1: glyph = 256'h03F83F001FF802007FFC04000FF818183FF848180FF808180FF8081800000000; // 看
            8'hA2: glyph = 256'h1020102023FC6420782059FC100021F87D08010801087DF80108000000000000; // 结
            8'hA3: glyph = 256'h00001FF0111011101FF011101FF001007FFC07400D601930710C010000000000; // 果
            8'hA4: glyph = 256'h0000002032A422AC4AE87A2052FC322022787A6802A402A07A0003FC00000000; // 继
            8'hA5: glyph = 256'h106033FC20406BFC480C71A810A02320792003FC004078D8070C000000000000; // 续
            8'hA6: glyph = 256'h000000303FC001007FFC01001FF011101FF01FF001003FF801007FFC00000000; // 重
            8'hA7: glyph = 256'h083C7F4000402640047C7F4808487F4808483A486AC848881988000800000000; // 新
            8'hA8: glyph = 256'h00003FF82008200827C824482448244827C8200820083FF82008000000000000; // 回
            8'hA9: glyph = 256'h109030903BFC609040903BFC10007DF8110811F81D08190811F8000000000000; // 错
            8'hAA: glyph = 256'h00007DFC24203C2024F824887CA87EA808A868A84E5068D8588047FC00000000; // 题
            8'hAB: glyph = 256'h0000000013FC126402F47244124412F4120412F41A9412F404040C1C00100000; // 调
            8'hAC: glyph = 256'h044004407FFC044004407FF80208020802080208027802000200000000000000; // 节
            8'hAD: glyph = 256'h01007FFC01003FF800001FF81108110811083FF8200020006000000000000000; // 声
            8'hAE: glyph = 256'h01003FF800000C6004407FFC00001FF010101FF0101010101FF0000000000000; // 音
            8'hAF: glyph = 256'h2120212017FC01200120712017FC1120112012201620780047FC000000000000; // 进
            8'hB0: glyph = 256'h00187DE045004500450045FC451045107D104510421006100410000000000000; // 听
            8'hB1: glyph = 256'h10A010A014AC7AA812B810A018B073B814A8112011241324763C000000000000; // 挑
            8'hB2: glyph = 256'h1080109010901E8C11F812807C584450447044607C6445B4031C000000000000; // 战
            8'hB3: glyph = 256'h00007FFC044004403FF824483FF802000200FFFC08400F8003F07C1C00000000; // 要
            8'hB4: glyph = 256'h108010F831902B50686069DC2B2428C029182860299C207023C0020000000000; // 修
            8'hB5: glyph = 256'h00407CC0048004FC051005103C902090206020602C607198670C040400000000; // 改
            8'hB6: glyph = 256'h0840104010FC7EFC6284630462447E44626C620862087E086238000000000000; // 的
            8'hB7: glyph = 256'h0300064008201FF002007FFC08A033184CEC03901E7001C03E00000000000000; // 参
            8'hB8: glyph = 256'h000008602A4008407F7C18886A8841487F50125022301E200B58718C01000000; // 数
            8'hB9: glyph = 256'h00B0009800803FFC208020C83E5822502270226026646DB4431C000000000000; // 成
            8'hBA: glyph = 256'h304023FC20404BF8784017FC20007BF86348034878404098070C040000000000; // 绩
            8'hBB: glyph = 256'h0C000FF810007FF018101FF0181007E00FF01C20364001807E7C000000000000; // 复
            8'hBC: glyph = 256'h00783F80030004701FC0030004303FFC018401801998218C4300000000000000; // 系
            8'hBD: glyph = 256'h1040104023FC6CC07880111813FC23A07CA000A005A07924423C000000000000; // 统
            8'hBE: glyph = 256'h00001FF0101010101FF0100C1FF8000004207FFC042008201820702000000000; // 异
            8'hBF: glyph = 256'h111009207FFC40045FF4101010101FF001003FF8210821082130010000000000; // 常
            8'hC0: glyph = 256'h106023FC22044B80597C73102720275C7B44037C03447B44037C034400000000; // 缩
            8'hC1: glyph = 256'h1060184000407EFC108811881E58125032502230222066584D8C000000000000; // 放
            8'hC2: glyph = 256'h10401020102011FEFD021102110215FE19023100D10011001200120054002800; // 护
            8'hC3: glyph = 256'h03F87A084A084BF87A084A084BF87A444A484A304A207A104A88030602000000; // 眼
            8'hC4: glyph = 256'h000001807FFC08100420FFFE00003FF8200820083FF8200820083FF820080000; // 音
            8'hC5: glyph = 256'h00001FF810081FF810081FF800007FFE10881FF810883FFC00807FFE00000000; // 量
            8'hC6: glyph = 256'h41102110311017FC01100110E1102FFE21102110231022106410D0008FFE0000; // 进
            8'hC7: glyph = 256'h7EFE402040405EFC5284529452945A945494509452A454305848508483020000; // 顾
            8'hC8: glyph = 256'h3FF002000200020002007FFC0480048004800880088010842084407C80000000; // 无
            8'hC9: glyph = 256'h10100820FFFE020004003FF8200820083FF8200820083FF8200820083FF82008; // 首
            8'hCA: glyph = 256'h7FFC020004001FF0101011101110111011101110129002400420181060080000; // 页
            8'hCB: glyph = 256'h0008203C13C01200020003FCF204128812501220125014881504280047FE0000; // 返
            default: glyph = 256'd0;
        endcase

        case (char_code)
            "0": ascii_glyph = 64'h3C666E7666663C00;
            "1": ascii_glyph = 64'h1838181818187E00;
            "2": ascii_glyph = 64'h3C66060C30607E00;
            "3": ascii_glyph = 64'h3C66061C06663C00;
            "4": ascii_glyph = 64'h0C1C3C6C7E0C0C00;
            "5": ascii_glyph = 64'h7E607C0606663C00;
            "6": ascii_glyph = 64'h1C30607C66663C00;
            "7": ascii_glyph = 64'h7E66060C18181800;
            "8": ascii_glyph = 64'h3C66663C66663C00;
            "9": ascii_glyph = 64'h3C66663E060C3800;
            "A": ascii_glyph = 64'h183C66667E666600;
            "M": ascii_glyph = 64'h63777F6B63636300;
            "B": ascii_glyph = 64'h7C66667C66667C00;
            "C": ascii_glyph = 64'h3C66606060663C00;
            "D": ascii_glyph = 64'h786C6666666C7800;
            "E": ascii_glyph = 64'h7E60607C60607E00;
            "F": ascii_glyph = 64'h7E60607C60606000;
            ":": ascii_glyph = 64'h0018180018180000;
            "+": ascii_glyph = 64'h0018187E18180000;
            "-": ascii_glyph = 64'h0000007E00000000;
            "%": ascii_glyph = 64'h62640C1830264600;
            ".": ascii_glyph = 64'h0000000000001818;
            "*": ascii_glyph = 64'h00663CFF3C660000;
            "X": ascii_glyph = 64'h66663C183C666600;
            ">": ascii_glyph = 64'h6030180C18306000;
            default: ascii_glyph = 64'd0;
        endcase

        case (row)
            4'd0: font_row = char_code[7] ? glyph[255:240] :
                    double_bits(ascii_glyph[63:56]);
            4'd1: font_row = char_code[7] ? glyph[239:224] :
                    double_bits(ascii_glyph[63:56]);
            4'd2: font_row = char_code[7] ? glyph[223:208] :
                    double_bits(ascii_glyph[55:48]);
            4'd3: font_row = char_code[7] ? glyph[207:192] :
                    double_bits(ascii_glyph[55:48]);
            4'd4: font_row = char_code[7] ? glyph[191:176] :
                    double_bits(ascii_glyph[47:40]);
            4'd5: font_row = char_code[7] ? glyph[175:160] :
                    double_bits(ascii_glyph[47:40]);
            4'd6: font_row = char_code[7] ? glyph[159:144] :
                    double_bits(ascii_glyph[39:32]);
            4'd7: font_row = char_code[7] ? glyph[143:128] :
                    double_bits(ascii_glyph[39:32]);
            4'd8: font_row = char_code[7] ? glyph[127:112] :
                    double_bits(ascii_glyph[31:24]);
            4'd9: font_row = char_code[7] ? glyph[111:96] :
                    double_bits(ascii_glyph[31:24]);
            4'd10: font_row = char_code[7] ? glyph[95:80] :
                     double_bits(ascii_glyph[23:16]);
            4'd11: font_row = char_code[7] ? glyph[79:64] :
                     double_bits(ascii_glyph[23:16]);
            4'd12: font_row = char_code[7] ? glyph[63:48] :
                     double_bits(ascii_glyph[15:8]);
            4'd13: font_row = char_code[7] ? glyph[47:32] :
                     double_bits(ascii_glyph[15:8]);
            4'd14: font_row = char_code[7] ? glyph[31:16] :
                     double_bits(ascii_glyph[7:0]);
            default: font_row = char_code[7] ? glyph[15:0] :
                         double_bits(ascii_glyph[7:0]);
        endcase
    end
endfunction

assign adjusted_r = adjust_channel(
    in_rgb[23:16], brightness_active, contrast_active);
assign adjusted_g = adjust_channel(
    in_rgb[15:8], brightness_active, contrast_active);
assign adjusted_b = adjust_channel(
    in_rgb[7:0], brightness_active, contrast_active);
assign status_code =
    banner_region ? banner_char(status_index[4:0] - 5'd23, display_image_idx) :
    (ENABLE_AMBIENT_OSD && state_active == 4'd7 && status_index >= 27) ?
    ((status_index == 28) ? 8'h82 : // 自
     (status_index == 29) ? 8'h83 : // 动
     (status_index == 30) ? 8'h86 : // 亮
     (status_index == 31) ? 8'h87 : // 度
     (status_index == 32) ? ":" :
     (status_index == 33) ? (ambient_enable_active ? 8'h84 : 8'h85) : " ") :
    (state_active == 4'd2 && status_index >= 35) ?
    learning_speed_char(status_index - 6'd35, speed_active) :
    (state_active == 4'd2 && status_index >= 23) ?
    learning_audio_char(status_index - 6'd23, volume_active, display_percent) :
    status_char(status_index[4:0], status_image_idx, auto_sync, brightness_active,
                contrast_active, status_zoom_level, eye_active);
assign status_font_row = font_row(status_code, status_row);
assign status_pixel = status_font_row[15 - status_col];
assign subtitle_code = subtitle_pixel_x >= {1'b0, subtitle_left_padding} ?
    subtitle_char(subtitle_char_index, state_active) : 8'h20;
assign subtitle_font_row = font_row(subtitle_code, subtitle_row);
assign subtitle_pixel = subtitle_font_row[15 - subtitle_col];

// Both read ports use the pre-stage coordinates. The native synchronous ROM
// therefore replaces the old stage combinational lookup without adding a
// pixel of latency to RGB/HS/VS/DE. font_row stays as the golden data source.
video_status_font u_status_font (
    .enable_a(status_region), .enable_b(subtitle_region),
    .clk(pixel_clk), .code_a(status_code), .row_a(status_row),
    .code_b(subtitle_code), .row_b(subtitle_row),
    .data_a(stage_status_font_row), .data_b(stage_subtitle_font_row)
);

lesson_subtitle_rom u_lesson_subtitle_rom (
    .clip_index (lesson_subtitle_clip),
    .cue_index  (lesson_subtitle_cue),
    .char_index (lesson_subtitle_index),
    .row_index  (lesson_subtitle_row),
    .char_code  (lesson_subtitle_code),
    .font_row   (lesson_subtitle_font_row)
);

// BRAM read runs in parallel with the existing OSD first pipeline stage.
lesson_subtitle_font_bram u_stage_lesson_font (
    .clk(pixel_clk),
    .char_code(lesson_subtitle_code),
    .row_index(lesson_subtitle_row),
    .font_row(stage_lesson_subtitle_font_row)
);

// The application keeps its volume payload stable between key events. Two
// payload stages and a three-stage token capture it before the frame commit.
always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        volume_meta <= 3'd4;
        volume_sync <= 3'd4;
        volume_toggle_sync <= 0;
        volume_seen <= 0;
        volume_pending <= 3'd4;
        volume_active <= 3'd4;
        speed_meta <= 2'd2;
        speed_sync <= 2'd2;
        speed_toggle_sync <= 0;
        speed_seen <= 0;
        speed_pending <= 2'd2;
        speed_active <= 2'd2;
        progress_active <= 0;
        progress_image <= 0;
    end else begin
        volume_meta <= source_volume_level;
        volume_sync <= volume_meta;
        volume_toggle_sync <= {volume_toggle_sync[1:0],source_volume_toggle};
        speed_meta <= source_speed_level;
        speed_sync <= speed_meta;
        speed_toggle_sync <= {speed_toggle_sync[1:0],source_speed_toggle};
        if (volume_toggle_sync[2] != volume_seen) begin
            volume_seen <= volume_toggle_sync[2];
            volume_pending <= volume_sync <= 4 ? volume_sync : 3'd0;
        end
        if (speed_toggle_sync[2] != speed_seen) begin
            speed_seen <= speed_toggle_sync[2];
            speed_pending <= speed_sync <= 2'd2 ? speed_sync : 2'd1;
        end
        if (frame_boundary) begin
            volume_active <= volume_toggle_sync[2] != volume_seen ?
                (volume_sync <= 4 ? volume_sync : 3'd0) : volume_pending;
            speed_active <= speed_toggle_sync[2] != speed_seen ?
                (speed_sync <= 2'd2 ? speed_sync : 2'd1) : speed_pending;
            progress_image <= display_image_idx;
            progress_active <= voice_valid && display_image_idx < 3 &&
                voice_clip == display_image_idx[1:0] ? progress_percent : 7'd0;
        end
    end
end

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        control_toggle_sync <= 3'b000;
        brightness_meta <= 3'sd0;
        brightness_sync <= 3'sd0;
        contrast_meta <= 2'd1;
        contrast_sync <= 2'd1;
        osd_meta <= 1'b1;
        osd_sync <= 1'b1;
        subtitle_meta <= 1'b1;
        subtitle_sync <= 1'b1;
        zoom_preview_level_meta <= 3'd2;
        zoom_preview_level_sync <= 3'd2;
        control_seen <= 1'b0;
        ambient_enable_meta<=0; ambient_enable_sync<=0; ambient_enable_active<=0;
        ambient_ready_meta<=0; ambient_ready_sync<=0; ambient_ready_active<=0;
        brightness_active <= 3'sd0;
        contrast_active <= 2'd1;
        osd_active <= 1'b1;
        subtitle_active <= 1'b1;
        zoom_preview_level_active <= 3'd2;
        brightness_pending <= 3'sd0;
        contrast_pending <= 2'd1;
        osd_pending <= 1'b1;
        subtitle_pending <= 1'b1;
        zoom_preview_level_pending <= 3'd2;
        control_pending_valid <= 1'b0;
        state_toggle_sync <= 3'b000;
        state_mailbox_meta <= 11'd0;
        state_mailbox_sync <= 11'd0;
        state_seen <= 1'b0;
        state_pending <= 11'd0;
        auto_meta <= 1'b0;
        auto_sync <= 1'b0;
        eye_meta <= 1'b0;
        eye_sync <= 1'b0;
        eye_active <= 1'b0;
        lesson_subtitle_toggle_sync <= 3'b000;
        lesson_subtitle_active_meta <= 1'b0;
        lesson_subtitle_active_sync <= 1'b0;
        lesson_subtitle_clip_meta <= 2'd0;
        lesson_subtitle_clip_sync <= 2'd0;
        lesson_subtitle_cue_meta <= 5'd0;
        lesson_subtitle_cue_sync <= 5'd0;
        lesson_subtitle_seen <= 1'b0;
        lesson_subtitle_pending_valid <= 1'b0;
        lesson_subtitle_active_pending <= 1'b0;
        lesson_subtitle_clip_pending <= 2'd0;
        lesson_subtitle_cue_pending <= 5'd0;
        lesson_subtitle_active <= 1'b0;
        lesson_subtitle_clip <= 2'd0;
        lesson_subtitle_cue <= 5'd0;
    end else begin
        control_toggle_sync <=
            {control_toggle_sync[1:0], source_control_toggle};
        brightness_meta <= source_brightness;
        ambient_enable_meta<=source_ambient_enable;
        ambient_enable_sync<=ambient_enable_meta;
        ambient_ready_meta<=source_ambient_ready;
        ambient_ready_sync<=ambient_ready_meta;
        if (frame_boundary) begin
            ambient_enable_active<=ambient_enable_sync;
            ambient_ready_active<=ambient_ready_sync;
        end
        brightness_sync <= brightness_meta;
        contrast_meta <= source_contrast;
        contrast_sync <= contrast_meta;
        osd_meta <= source_osd_enable;
        osd_sync <= osd_meta;
        subtitle_meta <= source_subtitle_enable;
        subtitle_sync <= subtitle_meta;
        zoom_preview_level_meta <= source_zoom_preview_level;
        zoom_preview_level_sync <= zoom_preview_level_meta;
        state_toggle_sync <=
            {state_toggle_sync[1:0], source_state_toggle};
        state_mailbox_meta <= {source_target_image_idx, source_wrong_bitmap,
                               source_state_code};
        state_mailbox_sync <= state_mailbox_meta;
        auto_meta <= source_auto_play;
        auto_sync <= auto_meta;
        eye_meta <= source_eye_comfort_enable;
        eye_sync <= eye_meta;
        if (frame_boundary)
            eye_active <= eye_sync;
        lesson_subtitle_toggle_sync <=
            {lesson_subtitle_toggle_sync[1:0],
             source_lesson_subtitle_toggle};
        lesson_subtitle_active_meta <= source_lesson_subtitle_active;
        lesson_subtitle_active_sync <= lesson_subtitle_active_meta;
        lesson_subtitle_clip_meta <= source_lesson_subtitle_clip;
        lesson_subtitle_clip_sync <= lesson_subtitle_clip_meta;
        lesson_subtitle_cue_meta <= source_lesson_subtitle_cue;
        lesson_subtitle_cue_sync <= lesson_subtitle_cue_meta;

        if (control_toggle_sync[2] != control_seen) begin
            control_seen <= control_toggle_sync[2];
            brightness_pending <= brightness_sync;
            contrast_pending <= contrast_sync;
            osd_pending <= osd_sync;
            subtitle_pending <= subtitle_sync;
            zoom_preview_level_pending <= zoom_preview_level_sync;
            control_pending_valid <= 1'b1;
        end

        // Keep every visible control field stable for a complete frame.  If a
        // new mailbox event arrives on the boundary itself, commit that newest
        // synchronized payload directly and do not leave a stale event queued.
        if (frame_boundary) begin
            if (control_toggle_sync[2] != control_seen) begin
                brightness_active <= brightness_sync;
                contrast_active <= contrast_sync;
                osd_active <= osd_sync;
                subtitle_active <= subtitle_sync;
                zoom_preview_level_active <= zoom_preview_level_sync;
                control_pending_valid <= 1'b0;
            end else if (control_pending_valid) begin
                brightness_active <= brightness_pending;
                contrast_active <= contrast_pending;
                osd_active <= osd_pending;
                subtitle_active <= subtitle_pending;
                zoom_preview_level_active <= zoom_preview_level_pending;
                control_pending_valid <= 1'b0;
            end
        end

        if (state_toggle_sync[2] != state_seen) begin
            state_seen <= state_toggle_sync[2];
            state_pending <= state_mailbox_sync;
        end

        if (lesson_subtitle_toggle_sync[2] != lesson_subtitle_seen) begin
            lesson_subtitle_seen <= lesson_subtitle_toggle_sync[2];
            lesson_subtitle_active_pending <= lesson_subtitle_active_sync;
            lesson_subtitle_clip_pending <= lesson_subtitle_clip_sync;
            lesson_subtitle_cue_pending <= lesson_subtitle_cue_sync;
            lesson_subtitle_pending_valid <= 1'b1;
        end

        // Subtitle text switches only on a complete-frame boundary.  If the
        // synchronized event arrives on the boundary, commit the newest stable
        // payload directly rather than showing the preceding cue for a frame.
        if (frame_boundary) begin
            if (lesson_subtitle_toggle_sync[2] != lesson_subtitle_seen) begin
                lesson_subtitle_active <= lesson_subtitle_active_sync;
                lesson_subtitle_clip <= lesson_subtitle_clip_sync;
                lesson_subtitle_cue <= lesson_subtitle_cue_sync;
                lesson_subtitle_pending_valid <= 1'b0;
            end else if (lesson_subtitle_pending_valid) begin
                lesson_subtitle_active <= lesson_subtitle_active_pending;
                lesson_subtitle_clip <= lesson_subtitle_clip_pending;
                lesson_subtitle_cue <= lesson_subtitle_cue_pending;
                lesson_subtitle_pending_valid <= 1'b0;
            end
        end
    end
end

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        pixel_x <= 10'd0;
        pixel_y <= 10'd0;
        de_d <= 1'b0;
        scroll_position <= 10'd0;
        scroll_frame_count <= 8'd0;
        state_active <= 4'd0;
        wrong_active <= 3'd0;
        target_image_active <= 4'd0;
        banner_image <= 4'd0;
        banner_frames <= 9'd0;
        banner_seen <= 1'b0;
        stage_hs <= 1'b0;
        stage_vs <= 1'b0;
        stage_de <= 1'b0;
        stage_adjusted_rgb <= 24'd0;
        stage_status_region <= 1'b0;
        stage_status_code <= 8'd0;
        stage_status_row <= 4'd0;
        stage_status_col <= 4'd0;
        stage_lesson_subtitle_region <= 1'b0;
        stage_lesson_subtitle_code <= 8'd0;
        stage_lesson_subtitle_row <= 4'd0;
        stage_lesson_subtitle_col <= 4'd0;
        stage_subtitle_region <= 1'b0;
        stage_subtitle_code <= 8'd0;
        stage_subtitle_row <= 4'd0;
        stage_subtitle_col <= 4'd0;
        out_hs <= 1'b0;
        out_vs <= 1'b0;
        out_de <= 1'b0;
        out_rgb <= 24'd0;
    end else begin
        stage_hs <= in_hs;
        stage_vs <= in_vs;
        stage_de <= in_de;
        stage_adjusted_rgb <= adjusted_rgb;
        stage_status_region <= status_region;
        stage_status_code <= status_code;
        stage_status_row <= status_row;
        stage_status_col <= status_col;
        stage_lesson_subtitle_region <= lesson_subtitle_region;
        stage_lesson_subtitle_code <= lesson_subtitle_code;
        stage_lesson_subtitle_row <= lesson_subtitle_row;
        stage_lesson_subtitle_col <= lesson_subtitle_col;
        stage_subtitle_region <= subtitle_region;
        stage_subtitle_code <= subtitle_code;
        stage_subtitle_row <= subtitle_row;
        stage_subtitle_col <= subtitle_col;
        out_hs <= stage_hs;
        out_vs <= stage_vs;
        out_de <= stage_de;
        de_d <= in_de;

        if (stage_de) begin
            if (stage_status_region)
                out_rgb <= stage_status_font_row[15 - stage_status_col] ? 24'hFFFFFF :
                           {2'b00, stage_adjusted_rgb[23:18],
                            2'b00, stage_adjusted_rgb[15:10],
                            2'b00, stage_adjusted_rgb[7:2]};
            else if (stage_lesson_subtitle_region)
                out_rgb <= stage_lesson_subtitle_font_row[15 - stage_lesson_subtitle_col] ? 24'hFFFFFF :
                           {2'b00, stage_adjusted_rgb[23:18],
                            2'b00, stage_adjusted_rgb[15:10],
                            2'b00, stage_adjusted_rgb[7:2]};
            else if (stage_subtitle_region)
                out_rgb <= stage_subtitle_font_row[15 - stage_subtitle_col] ? 24'hFFD54A :
                           {1'b0, stage_adjusted_rgb[23:17],
                            1'b0, stage_adjusted_rgb[15:9],
                            1'b0, stage_adjusted_rgb[7:1]};
            else
                out_rgb <= stage_adjusted_rgb;
        end else begin
            out_rgb <= 24'd0;
        end

        if (in_de) begin
            pixel_x <= pixel_x + 1'b1;
        end else begin
            pixel_x <= 10'd0;
            if (de_d && (pixel_y < FRAME_HEIGHT - 1))
                pixel_y <= pixel_y + 1'b1;
        end

        if (frame_boundary) begin
            pixel_x <= 10'd0;
            pixel_y <= 10'd0;
            if ({target_image_active,wrong_active,state_active} != state_pending) begin
                state_active <= state_pending[3:0];
                wrong_active <= state_pending[6:4];
                target_image_active <= state_pending[10:7];
                scroll_position <= 10'd0;
                scroll_frame_count <= 8'd0;
            end else if (subtitle_active && !lesson_subtitle_active) begin
                if (scroll_frame_count == SCROLL_FRAME_DIV - 1) begin
                    scroll_frame_count <= 8'd0;
                    if (scroll_position == FRAME_WIDTH + 255)
                        scroll_position <= 10'd0;
                    else
                        scroll_position <= scroll_position + 1'b1;
                end else begin
                    scroll_frame_count <= scroll_frame_count + 1'b1;
                end
            end
            if (!banner_eligible) begin
                banner_seen <= 1'b0;
                banner_frames <= 9'd0;
            end else if (!banner_seen || (banner_image != display_image_idx)) begin
                banner_seen <= 1'b1;
                banner_image <= display_image_idx;
                banner_frames <= 9'd0;
            end else if (banner_frames < 9'd300) begin
                banner_frames <= banner_frames + 1'b1;
            end
        end
    end
end

endmodule
