
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [3:0]   SCAN_TARGET_COUNT = 4'd8,
    // Automatic image rotation is a legacy standalone-loader feature. The
    // learning application must advance practice cards only through its
    // application controller, so production instances keep this disabled.
    parameter         AUTO_PLAY_ENABLE  = 1'b0,
    parameter         PREFETCH_ENABLE   = 1'b0
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       home_request,
    input                       image_request,
    input  [3:0]                image_request_idx,
    input  [2:0]                image_request_zoom,
    input                       image_request_prev,
    input                       image_request_settings,
    input                       prefetch_enable,
    input  [3:0]                prefetch_image_idx,
    input                       zoom_request,
    input  [2:0]                zoom_level,
    input  [3:0]                zoom_image_idx,
    input                       narration_enable,
    input  [1:0]                voice_speed_level,
    input                       voice_speed_toggle,
    input                       voice_fifo_space_available,
    input                       voice_fifo_empty,
    output                      content_ready,
    output [3:0]                state_code,
    output [3:0]                display_image_idx,
    output reg                  display_page_right,
    output reg                  display_settings_entry,
    // Toggle-only diagnostics: scan, first, home, exact, zoom, next,
    // automatic load, frame write, and five SD fault sources.
    output reg [12:0]           debug_event_toggle,
    output                      auto_play_active,
    output reg [2:0]            display_zoom_level,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,
    output reg                  display_commit_toggle,
    input                       display_commit_ack_toggle,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      voice_fifo_write,
    output [9:0]                voice_fifo_data,
    output reg                  voice_start_toggle,
    output reg                  voice_end_toggle,
    output reg                  voice_stop_toggle,
    output [1:0]                voice_clip_index,
    output [31:0]               voice_sample_total,
    output                      narration_busy,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             fs_scan_busy;
wire             fs_scan_done;
wire [7:0]       fs_scan_error;
wire [7:0]       fs_sectors_per_cluster;
wire [2:0]       fs_sectors_per_cluster_shift;
wire [31:0]      fs_fat_start_lba;
wire [31:0]      fs_data_start_lba;
wire [31:0]      fs_max_cluster;
wire             fs_file_found_valid;
wire [3:0]       fs_file_found_index;
wire [31:0]      fs_file_found_cluster;
wire [31:0]      fs_file_found_size;
wire [11:0]      fs_file_found_mask;
wire             fs_scan_sd_read;
wire [31:0]      fs_scan_sd_read_addr;
wire             fs_scan_sd_recover_pulse;
wire             bridge_sd_read;
wire [31:0]      bridge_sd_read_addr;
wire             bridge_sd_recover_pulse;
wire [12:0]      bridge_metadata_mask;
wire [7:0]       virtual_sd_sec_read_data;
wire             virtual_sd_sec_read_data_valid;
wire             virtual_sd_sec_read_end;
wire             virtual_sd_sec_read_error;
reg  [7:0]       sd_sec_read_data_pipe;
reg              sd_sec_read_data_valid_pipe;
reg              sd_sec_read_owner_voice_pipe;
wire             bmp_sd_sec_read;
wire [31:0]      bmp_sd_sec_read_addr;
wire             bmp_sd_sec_read_data_valid;
wire             bmp_sd_sec_read_end;
wire             bmp_sd_sec_read_error;
wire             voice_sd_sec_read;
wire [31:0]      voice_sd_sec_read_addr;
wire             voice_sd_sec_read_data_valid;
wire             voice_sd_sec_read_end;
wire             voice_sd_sec_read_error;
wire             bmp_source_valid;
wire [23:0]      bmp_source_data;
wire [15:0]      bmp_source_width;
wire [15:0]      bmp_source_height;
wire [15:0]      bmp_source_first_row;
wire [15:0]      bmp_source_row_count;
wire             scaled_data_valid;
wire [23:0]      scaled_data;
wire             scaler_busy;
wire             scaler_done;
wire             scaler_overrun;
wire             scaler_source_start;
wire             sd_init_done;
wire             bmp_ready;
reg              scan_done;
wire [3:0]       bmp_state_code;
wire             bmp_load_error_pulse;
wire             bmp_sd_recover_pulse;
wire             voice_reader_ready;
wire             voice_reader_busy;
wire             voice_reader_start_pulse;
wire             voice_reader_end_pulse;
wire             voice_reader_error_pulse;
wire             voice_sd_recover_pulse;
wire [1:0]       voice_reader_page;
wire [31:0]      voice_reader_sample_total;
wire             voice_reader_data_valid;
wire [7:0]       voice_reader_data;
wire [1:0]       voice_reader_speed;

reg              scan_start_pulse;
reg              load_start_pulse;
wire [31:0]      load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              first_image_load_failed;
reg              home_image_failed;
wire [3:0]       home_image_idx =
    (bridge_metadata_mask[12] && !home_image_failed) ? 4'd12 : 4'd0;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [3:0]        img_found_count;
reg [3:0]        img_idx;              // 当前真正显示中的图片编号
reg [3:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [31:0]       img_sector4;
reg [31:0]       img_sector5;
reg [31:0]       img_sector6;
reg [31:0]       img_sector7;
reg [31:0]       img_sector8;
reg [31:0]       img_sector9;
reg [31:0]       img_sector10;
reg [31:0]       img_sector11;
reg [31:0]       voice_sector0;
reg [31:0]       voice_sector1;
reg [31:0]       voice_sector2;
reg [31:0]       voice_sector3;
reg [31:0]       voice_offset0;
reg [31:0]       voice_offset1;
reg [31:0]       voice_offset2;
reg [31:0]       voice_offset3;
reg [3:0]        voice_available;
reg              voice_req_pending;
reg [1:0]        selected_voice_idx;
reg              voice_start_pulse;
reg              voice_stop_pulse;
reg              next_req_pending;
reg              home_req_pending;
reg              image_req_pending;
reg [3:0]        selected_image_idx;
reg [2:0]        selected_image_zoom;
reg              selected_image_prev;
reg              selected_image_settings;
reg              load_page_right;
reg              load_settings_entry;
reg              zoom_req_pending;
reg [2:0]        selected_zoom_level;
reg [3:0]        selected_zoom_idx;
reg [2:0]        load_zoom_level;
reg [2:0]        image_zoom0;
reg [2:0]        image_zoom1;
reg [2:0]        image_zoom2;
reg [2:0]        image_zoom3;
reg [2:0]        image_zoom4;
reg [2:0]        image_zoom5;
reg [2:0]        image_zoom6;
reg [2:0]        image_zoom7;
reg [2:0]        image_zoom8;
reg [2:0]        image_zoom9;
reg [2:0]        image_zoom10;
reg [2:0]        image_zoom11;
reg              load_busy;
// Buffer 1 may hold the shared settings/first-lesson image while HOME uses 0.
// Buffer 2 remains reserved for a complete, normalized first-question cache.
// Video ACK still guards reuse of the question buffer through the transition.
reg              load_is_prefetch;
reg              load_is_entry_prefetch;
reg              entry_cache_valid;
reg [1:0]        entry_cache_buf_idx;
reg              prefetch_valid;
reg [3:0]        prefetch_idx;
reg              prefetch_failed;
reg [3:0]        prefetch_failed_idx;
reg              first_lesson_frame_ready;
// HOME first reserves an ordinary inactive buffer for settings/lesson zero.
// Once that card is ready, its cache can be displayed while buffer 2 is written.
wire [3:0] prefetch_target = ((prefetch_image_idx >= 4'd3) &&
    (prefetch_image_idx <= 4'd5) && (img_idx == 4'd12) &&
    !entry_cache_valid) ? 4'd0 : prefetch_image_idx;
wire entry_hit_while_prefetch = load_busy && load_is_prefetch &&
    !load_is_entry_prefetch && entry_cache_valid &&
    (selected_image_idx == 4'd0) && (selected_image_zoom == 3'd2);

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              scaler_started;
reg              scaler_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync /* fehdl keep="true" */;
wire             write_finish_pulse;

// 同步 mem_clk 域的写请求应答；请求保持到同步后的应答返回
reg [2:0]        write_req_ack_sync /* fehdl keep="true" */;
wire             write_req_ack_sd;
reg [2:0]        display_ack_sync /* fehdl keep="true" */;
reg              display_commit_pending;

wire auto_tick;
wire [3:0] next_from_current;
reg  scaler_start_pulse;
reg  frame_write_handshake_seen;

assign write_en   = scaled_data_valid;
assign write_data = {scaled_data[23:16], scaled_data[15:8], scaled_data[7:0], 8'b0};
assign display_image_idx = img_idx;
assign auto_play_active = auto_play_en;
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign write_req_ack_sd = write_req_ack_sync[2];
assign voice_fifo_write = voice_reader_data_valid;
assign voice_fifo_data = {voice_reader_speed,voice_reader_data};
assign voice_clip_index = voice_reader_page;
assign narration_busy = voice_req_pending || voice_reader_busy;
assign content_ready = scan_done &&
                       (SCAN_TARGET_COUNT != 4'd0) &&
                       (img_found_count >= SCAN_TARGET_COUNT) &&
                       ((bridge_metadata_mask &
                         (12'hfff >> (4'd12 - SCAN_TARGET_COUNT))) ==
                        (12'hfff >> (4'd12 - SCAN_TARGET_COUNT)));
assign state_code = fs_scan_busy ? 4'd2 :
                    ((!fs_scan_busy && (fs_scan_error != 8'd0)) ? 4'hE :
                     bmp_state_code);
assign sd_sec_read = fs_scan_busy ? fs_scan_sd_read : bridge_sd_read;
assign sd_sec_read_addr = fs_scan_busy ?
                          fs_scan_sd_read_addr : bridge_sd_read_addr;
assign bmp_sd_sec_read_data_valid =
    sd_sec_read_data_valid_pipe && !sd_sec_read_owner_voice_pipe;
assign bmp_sd_sec_read_end =
    virtual_sd_sec_read_end && !voice_reader_busy;
assign bmp_sd_sec_read_error =
    virtual_sd_sec_read_error && !voice_reader_busy;
assign voice_sd_sec_read_data_valid =
    sd_sec_read_data_valid_pipe && sd_sec_read_owner_voice_pipe;
assign voice_sd_sec_read_end =
    virtual_sd_sec_read_end && voice_reader_busy;
assign voice_sd_sec_read_error =
    virtual_sd_sec_read_error && voice_reader_busy;

// Break the SD controller's byte-data fanout away from the BMP parser and
// narration reader.  Data, valid and the selected consumer are registered as
// one aligned bundle.  Keep the one-cycle sector-end handshake direct: the SD
// controller returns to its request-wait state immediately after asserting
// end, so delaying end would leave the old read request high and launch the
// same sector a second time before the consumer can deassert it.
always @(posedge clk) begin
    if (rst) begin
        sd_sec_read_data_pipe <= 8'd0;
        sd_sec_read_data_valid_pipe <= 1'b0;
        sd_sec_read_owner_voice_pipe <= 1'b0;
    end else begin
        sd_sec_read_data_pipe <= virtual_sd_sec_read_data;
        sd_sec_read_data_valid_pipe <= virtual_sd_sec_read_data_valid;
        sd_sec_read_owner_voice_pipe <= voice_reader_busy;
    end
end

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [3:0] next_index_limited;
    input [3:0] cur;
    input [3:0] count;
    begin
        if (count <= 4'd1)
            next_index_limited = 4'd0;
        else if ((cur + 4'd1) >= count)
            next_index_limited = 4'd0;
        else
            next_index_limited = cur + 4'd1;
    end
endfunction

function [31:0] sector_lut;
    input [3:0] idx;
    begin
        case (idx)
            3'd0: sector_lut = img_sector0;
            3'd1: sector_lut = img_sector1;
            3'd2: sector_lut = img_sector2;
            3'd3: sector_lut = img_sector3;
            3'd4: sector_lut = img_sector4;
            3'd5: sector_lut = img_sector5;
            3'd6: sector_lut = img_sector6;
            4'd7: sector_lut = img_sector7;
            4'd8: sector_lut = img_sector8;
            4'd9: sector_lut = img_sector9;
            4'd10: sector_lut = img_sector10;
            4'd11: sector_lut = img_sector11;
            4'd12: sector_lut = {8'h80, 4'd12, 20'd0};
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

// load_idx is latched one SD clock before bmp_read observes load_start_pulse.
// Decode the sector from that stable index instead of writing a second 32-bit
// register through the controller's long request-priority chain.
assign load_sector = sector_lut(load_idx);

function [2:0] image_zoom_lut;
    input [3:0] idx;
    begin
        case (idx)
            3'd0: image_zoom_lut = image_zoom0;
            3'd1: image_zoom_lut = image_zoom1;
            3'd2: image_zoom_lut = image_zoom2;
            3'd3: image_zoom_lut = image_zoom3;
            3'd4: image_zoom_lut = image_zoom4;
            3'd5: image_zoom_lut = image_zoom5;
            3'd6: image_zoom_lut = image_zoom6;
            4'd7: image_zoom_lut = image_zoom7;
            4'd8: image_zoom_lut = image_zoom8;
            4'd9: image_zoom_lut = image_zoom9;
            4'd10: image_zoom_lut = image_zoom10;
            default: image_zoom_lut = image_zoom11;
        endcase
    end
endfunction

function [31:0] voice_sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: voice_sector_lut = voice_sector0;
            2'd1: voice_sector_lut = voice_sector1;
            2'd2: voice_sector_lut = voice_sector2;
            default: voice_sector_lut = voice_sector3;
        endcase
    end
endfunction

function [31:0] voice_offset_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: voice_offset_lut = voice_offset0;
            2'd1: voice_offset_lut = voice_offset1;
            2'd2: voice_offset_lut = voice_offset2;
            default: voice_offset_lut = voice_offset3;
        endcase
    end
endfunction

reg narration_enable_previous;
reg voice_stop_armed;
wire voice_cancel_request = home_request ||
    (image_request && !home_req_pending) ||
    (narration_enable_previous && !narration_enable);
wire voice_start_accepted = voice_reader_start_pulse && narration_enable &&
    !home_request && !image_request && !home_req_pending && !voice_stop_pulse;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        voice_start_toggle <= 1'b0;
        voice_end_toggle <= 1'b0;
        voice_stop_toggle <= 1'b0;
        narration_enable_previous <= 0;
        voice_stop_armed <= 1'b1;
    end else begin
        narration_enable_previous <= narration_enable;
        // Multiple navigation causes can arrive a few SD clocks apart, much
        // faster than mclk. Coalesce them until a validated new clip starts.
        if (voice_cancel_request && voice_stop_armed) begin
            voice_stop_toggle <= ~voice_stop_toggle;
            voice_stop_armed <= 1'b0;
        end
        if (voice_start_accepted) begin
            voice_start_toggle <= ~voice_start_toggle;
            voice_stop_armed <= 1'b1;
        end
        if (voice_reader_end_pulse)
            voice_end_toggle <= ~voice_end_toggle;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync     <= 3'b000;
        write_req_ack_sync <= 3'b000;
        display_ack_sync   <= 3'b000;
    end else begin
        wrfin_tgl_sync     <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        write_req_ack_sync <= {write_req_ack_sync[1:0], write_req_ack};
        display_ack_sync   <= {display_ack_sync[1:0], display_commit_ack_toggle};
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        scan_start_pulse      <= 1'b0;
        debug_event_toggle    <= 13'd0;
        scan_done             <= 1'b0;
        load_start_pulse      <= 1'b0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        first_image_load_failed <= 1'b0;
        home_image_failed     <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 4'd0;
        img_idx               <= 4'd0;
        load_idx              <= 4'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        img_sector4           <= 32'd0;
        img_sector5           <= 32'd0;
        img_sector6           <= 32'd0;
        img_sector7           <= 32'd0;
        img_sector8           <= 32'd0;
        img_sector9           <= 32'd0;
        img_sector10          <= 32'd0;
        img_sector11          <= 32'd0;
        voice_sector0         <= 32'd0;
        voice_sector1         <= 32'd0;
        voice_sector2         <= 32'd0;
        voice_sector3         <= 32'd0;
        voice_offset0         <= 32'd0;
        voice_offset1         <= 32'd0;
        voice_offset2         <= 32'd0;
        voice_offset3         <= 32'd0;
        voice_available       <= 4'b0000;
        voice_req_pending     <= 1'b0;
        selected_voice_idx    <= 2'd0;
        voice_start_pulse     <= 1'b0;
        voice_stop_pulse      <= 1'b0;
        next_req_pending      <= 1'b0;
        home_req_pending      <= 1'b0;
        image_req_pending     <= 1'b0;
        selected_image_idx    <= 4'd0;
        selected_image_zoom   <= 3'd2;
        selected_image_prev   <= 1'b0;
        selected_image_settings <= 1'b0;
        load_page_right       <= 1'b0;
        load_settings_entry   <= 1'b0;
        display_page_right    <= 1'b0;
        display_settings_entry <= 1'b0;
        zoom_req_pending      <= 1'b0;
        selected_zoom_level   <= 3'd2;
        selected_zoom_idx     <= 4'd0;
        load_zoom_level       <= 3'd2;
        image_zoom0           <= 3'd2;
        image_zoom1           <= 3'd2;
        image_zoom2           <= 3'd2;
        image_zoom3           <= 3'd2;
        image_zoom4           <= 3'd2;
        image_zoom5           <= 3'd2;
        image_zoom6           <= 3'd2;
        image_zoom7           <= 3'd2;
        image_zoom8           <= 3'd2;
        image_zoom9           <= 3'd2;
        image_zoom10          <= 3'd2;
        image_zoom11          <= 3'd2;
        load_busy             <= 1'b0;
        load_is_prefetch      <= 1'b0;
        load_is_entry_prefetch <= 1'b0;
        entry_cache_valid     <= 1'b0;
        entry_cache_buf_idx   <= 2'd1;
        prefetch_valid        <= 1'b0;
        prefetch_idx          <= 4'd0;
        prefetch_failed       <= 1'b0;
        prefetch_failed_idx   <= 4'd0;
        first_lesson_frame_ready <= 1'b0;
        source_done_seen      <= 1'b0;
        scaler_started        <= 1'b0;
        scaler_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
        display_commit_toggle <= 1'b0;
        display_commit_pending <= 1'b0;
        display_zoom_level    <= 3'd2;
        scaler_start_pulse    <= 1'b0;
        frame_write_handshake_seen <= 1'b0;
    end else begin
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        scaler_start_pulse <= 1'b0;
        voice_start_pulse <= 1'b0;
        voice_stop_pulse <= 1'b0;
        if (bmp_sd_recover_pulse)
            debug_event_toggle[8] <= ~debug_event_toggle[8];
        if (voice_sd_recover_pulse)
            debug_event_toggle[9] <= ~debug_event_toggle[9];
        if (fs_scan_sd_recover_pulse)
            debug_event_toggle[10] <= ~debug_event_toggle[10];
        if (bridge_sd_recover_pulse)
            debug_event_toggle[11] <= ~debug_event_toggle[11];
        if (virtual_sd_sec_read_error)
            debug_event_toggle[12] <= ~debug_event_toggle[12];

        // The SDRAM writer acknowledges while its FIFO is still held in reset.
        // Launch the scaler only after the synchronized acknowledge falls, then
        // let the scaler release bmp_read after any leading black border.
        if (write_req && write_req_ack_sd)
            frame_write_handshake_seen <= 1'b1;
        if (frame_write_handshake_seen && !write_req_ack_sd) begin
            scaler_start_pulse <= 1'b1;
            frame_write_handshake_seen <= 1'b0;
        end

        // SD recovery invalidates metadata and the in-flight writer, but the
        // last complete video frame and commit toggle remain owned by video.
        if (!sd_init_done) begin
            load_is_prefetch      <= 1'b0;
            load_is_entry_prefetch <= 1'b0;
            entry_cache_valid     <= 1'b0;
            prefetch_valid        <= 1'b0;
            prefetch_failed       <= 1'b0;
            first_lesson_frame_ready <= 1'b0;
            scan_kicked           <= 1'b0;
            scan_done             <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 4'd0;
            load_idx              <= 4'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            img_sector4           <= 32'd0;
            img_sector5           <= 32'd0;
            img_sector6           <= 32'd0;
            img_sector7           <= 32'd0;
            img_sector8           <= 32'd0;
            img_sector9           <= 32'd0;
            img_sector10          <= 32'd0;
            img_sector11          <= 32'd0;
            voice_sector0         <= 32'd0;
            voice_sector1         <= 32'd0;
            voice_sector2         <= 32'd0;
            voice_sector3         <= 32'd0;
            voice_offset0         <= 32'd0;
            voice_offset1         <= 32'd0;
            voice_offset2         <= 32'd0;
            voice_offset3         <= 32'd0;
            voice_available       <= 4'b0000;
            voice_req_pending     <= 1'b0;
            selected_voice_idx    <= 2'd0;
            voice_start_pulse     <= 1'b0;
            voice_stop_pulse      <= 1'b0;
            next_req_pending      <= 1'b0;
            if (home_request)
                home_req_pending  <= 1'b1;
            image_req_pending     <= 1'b0;
            selected_image_idx    <= 4'd0;
            selected_image_zoom   <= 3'd2;
            selected_image_prev   <= 1'b0;
            selected_image_settings <= 1'b0;
            load_page_right       <= 1'b0;
            load_settings_entry   <= 1'b0;
            zoom_req_pending      <= 1'b0;
            selected_zoom_level   <= 3'd2;
            load_zoom_level       <= 3'd2;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            scaler_started        <= 1'b0;
            scaler_done_seen      <= 1'b0;
            scaler_start_pulse    <= 1'b0;
            frame_write_handshake_seen <= 1'b0;
        end else begin
            if (fs_scan_done)
                scan_done <= (fs_scan_error == 8'd0);

            // Invalidate the shared entry frame before a foreground write
            // reuses its ordinary SDRAM buffer.
            if (load_busy && !load_is_prefetch && entry_cache_valid &&
                (pending_buf_idx == entry_cache_buf_idx))
                entry_cache_valid <= 1'b0;

            // FAT32 directory entries may arrive in any order. Cache each
            // exact 8.3 filename at a stable virtual-sector base.
            if (fs_file_found_valid) begin
                case (fs_file_found_index)
                    4'd0: img_sector0 <= {8'h80, 4'd0, 20'd0};
                    4'd1: img_sector1 <= {8'h80, 4'd1, 20'd0};
                    4'd2: img_sector2 <= {8'h80, 4'd2, 20'd0};
                    4'd3: img_sector3 <= {8'h80, 4'd3, 20'd0};
                    4'd4: img_sector4 <= {8'h80, 4'd4, 20'd0};
                    4'd5: img_sector5 <= {8'h80, 4'd5, 20'd0};
                    4'd6: img_sector6 <= {8'h80, 4'd6, 20'd0};
                    4'd7: img_sector7 <= {8'h80, 4'd7, 20'd0};
                    4'd8: img_sector8 <= {8'h80, 4'd8, 20'd0};
                    4'd9: img_sector9 <= {8'h80, 4'd9, 20'd0};
                    4'd10: img_sector10 <= {8'h80, 4'd10, 20'd0};
                    4'd11: img_sector11 <= {8'h80, 4'd11, 20'd0};
                    default: ;
                endcase

                if ((fs_file_found_index < 4'd12) && (img_found_count < 4'd12))
                    img_found_count <= img_found_count + 4'd1;

                // The validated English package embeds LMV1 immediately
                // after the fixed 640x480 pixel array in files 01..03.
                if ((fs_file_found_index < 4'd3) &&
                    (fs_file_found_size >= 32'd921670)) begin
                    case (fs_file_found_index[1:0])
                        2'd0: begin
                            voice_sector0 <= {8'h80, 4'd0, 20'd0};
                            voice_offset0 <= 32'd921654;
                        end
                        2'd1: begin
                            voice_sector1 <= {8'h80, 4'd1, 20'd0};
                            voice_offset1 <= 32'd921654;
                        end
                        2'd2: begin
                            voice_sector2 <= {8'h80, 4'd2, 20'd0};
                            voice_offset2 <= 32'd921654;
                        end
                        default: begin
                            voice_sector3 <= {8'h80, 4'd3, 20'd0};
                            voice_offset3 <= 32'd921654;
                        end
                    endcase
                    voice_available[fs_file_found_index[1:0]] <= 1'b1;
                end
            end

            if (scaler_start_pulse)
                scaler_started <= 1'b1;
            if (scaler_done)
                scaler_done_seen <= 1'b1;

            // A malformed header is rejected before bmp_read asks the SDRAM
            // writer to start. Drop only this transaction and preserve the
            // currently displayed buffer instead of remaining busy forever.
            if (bmp_load_error_pulse && load_busy) begin
                if (load_is_prefetch) begin
                    prefetch_failed <= 1'b1;
                    prefetch_failed_idx <= load_idx;
                end
                load_is_prefetch <= 1'b0;
                load_is_entry_prefetch <= 1'b0;
                load_busy                  <= 1'b0;
                source_done_seen           <= 1'b0;
                scaler_started             <= 1'b0;
                scaler_done_seen           <= 1'b0;
                frame_write_handshake_seen <= 1'b0;
                auto_cnt                   <= 32'd0;
                if (!display_valid && (load_idx == 4'd0))
                    first_image_load_failed <= 1'b1;
                // A rejected optional cover falls back once to course image 0.
                // Preserve the old displayed frame until the fallback commits.
                if (load_idx == 4'd12) begin
                    home_image_failed <= 1'b1;
                    home_req_pending <= display_valid;
                end
            end

            // 源 BMP 和缩放输出都完成后，继续等待 SDRAM 整帧写完。
            if (load_busy && bmp_ready &&
                ((!scaler_started) || scaler_done_seen))
                source_done_seen <= 1'b1;

            // 只有真正收到 write_finish_toggle 脉冲，才提交新图并切换显示缓冲区
            if (load_busy && source_done_seen && write_finish_pulse) begin
                debug_event_toggle[7] <= ~debug_event_toggle[7];
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                scaler_started        <= 1'b0;
                scaler_done_seen      <= 1'b0;
                load_is_prefetch      <= 1'b0;
                if (load_is_prefetch) begin
                    if (load_is_entry_prefetch) begin
                        entry_cache_valid <= 1'b1;
                        entry_cache_buf_idx <= pending_buf_idx;
                    end else begin
                        prefetch_valid <= 1'b1;
                        prefetch_idx <= load_idx;
                    end
                    load_is_entry_prefetch <= 1'b0;
                end else begin
                    if (first_image_committed && (load_idx < 4'd3) &&
                        !load_settings_entry)
                        first_lesson_frame_ready <= 1'b1;
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_page_right    <= load_page_right;
                    display_settings_entry <= load_settings_entry;
                    display_zoom_level    <= load_zoom_level;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                    display_commit_toggle <= ~display_commit_toggle;
                    display_commit_pending <= 1'b1;
                end
            end

            if (display_commit_pending &&
                (display_ack_sync[2] == display_commit_toggle))
                display_commit_pending <= 1'b0;

            // 上电后自动发起一次“扫描前 12 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                debug_event_toggle[0] <= ~debug_event_toggle[0];
                scan_start_pulse      <= 1'b1;
                scan_done             <= 1'b0;
                scan_kicked           <= 1'b1;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 4'd0;
                load_idx              <= 4'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                next_req_pending      <= 1'b0;
                if (home_request)
                    home_req_pending  <= 1'b1;
                image_req_pending     <= 1'b0;
                selected_image_idx    <= 4'd0;
                selected_image_zoom   <= 3'd2;
                selected_image_prev   <= 1'b0;
                selected_image_settings <= 1'b0;
                zoom_req_pending      <= 1'b0;
                selected_zoom_level   <= 3'd2;
                selected_zoom_idx     <= 4'd0;
                load_zoom_level       <= 3'd2;
                image_zoom0           <= 3'd2;
                image_zoom1           <= 3'd2;
                image_zoom2           <= 3'd2;
                image_zoom3           <= 3'd2;
                image_zoom4           <= 3'd2;
                image_zoom5           <= 3'd2;
                image_zoom6           <= 3'd2;
                image_zoom7           <= 3'd2;
                image_zoom8           <= 3'd2;
                image_zoom9           <= 3'd2;
                image_zoom10          <= 3'd2;
                image_zoom11          <= 3'd2;
                voice_available       <= 4'b0000;
                voice_req_pending     <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                scaler_started        <= 1'b0;
                scaler_done_seen      <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (key_next_press && !home_request && scan_done &&
                    (img_found_count > 4'd0))
                    next_req_pending <= 1'b1;

                // A return-home request always wins over a queued next-image
                // request.  It remains pending until the current atomic frame
                // write/commit has completed, then reloads image zero.
                if (home_request) begin
                    home_req_pending <= 1'b1;
                    next_req_pending <= 1'b0;
                    image_req_pending <= 1'b0;
                    zoom_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                    voice_req_pending <= 1'b0;
                    if (voice_reader_busy)
                        voice_stop_pulse <= 1'b1;
                end

                // Application navigation requests an exact page rather than
                // relying on relative key presses. Keep only the latest page
                // while a frame conversion is in flight; range validation is
                // deferred until the twelve-image scan has completed.
                if (image_request && !home_request) begin
                    selected_image_idx <= image_request_idx;
                    selected_image_zoom <= (image_request_zoom > 3'd4) ?
                                           3'd4 : image_request_zoom;
                    case (image_request_idx)
                        4'd0: image_zoom0 <= (image_request_zoom > 3'd4) ?
                                            3'd4 : image_request_zoom;
                        4'd1: image_zoom1 <= (image_request_zoom > 3'd4) ?
                                            3'd4 : image_request_zoom;
                        4'd2: image_zoom2 <= (image_request_zoom > 3'd4) ?
                                            3'd4 : image_request_zoom;
                        default: ;
                    endcase
                    selected_image_prev <= image_request_prev;
                    selected_image_settings <= image_request_settings;
                    image_req_pending  <= 1'b1;
                    next_req_pending   <= 1'b0;
                    zoom_req_pending   <= 1'b0;
                    auto_cnt           <= 32'd0;
                    if (narration_enable &&
                        (image_request_idx < 4'd3)) begin
                        selected_voice_idx <= image_request_idx[1:0];
                        voice_req_pending <= 1'b1;
                    end else begin
                        voice_req_pending <= 1'b0;
                    end
                    if (voice_reader_busy)
                        voice_stop_pulse <= 1'b1;
                end

                if (!narration_enable) begin
                    voice_req_pending <= 1'b0;
                    if (voice_reader_busy)
                        voice_stop_pulse <= 1'b1;
                end

                // Keep the latest selected image and its requested zoom.  A
                // busy frame conversion is never interrupted; the latest
                // complete request is applied afterwards.  Each image keeps
                // its own zoom level for later manual/automatic navigation.
                if (zoom_request && scan_done && (img_found_count > 4'd0)) begin
                    selected_zoom_level <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                    selected_zoom_idx   <= (zoom_image_idx < img_found_count) ?
                                           zoom_image_idx : 4'd0;
                    case ((zoom_image_idx < img_found_count) ? zoom_image_idx : 4'd0)
                        3'd0: image_zoom0 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        3'd1: image_zoom1 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        3'd2: image_zoom2 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        3'd3: image_zoom3 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        3'd4: image_zoom4 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        3'd5: image_zoom5 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        3'd6: image_zoom6 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        4'd7: image_zoom7 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        4'd8: image_zoom8 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        4'd9: image_zoom9 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        4'd10: image_zoom10 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                        default: image_zoom11 <= (zoom_level > 3'd4) ? 3'd4 : zoom_level;
                    endcase
                    // Keep the per-image setting even if HOME arrives at the
                    // same time, but never let a delayed SETTINGS preview
                    // override the higher-priority return-home request.
                    if (!home_request && !home_req_pending)
                        zoom_req_pending <= 1'b1;
                    auto_cnt            <= 32'd0;
                end

                // 自动播放开/关
                if (AUTO_PLAY_ENABLE && key_auto_press && scan_done &&
                    (img_found_count > 4'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (AUTO_PLAY_ENABLE && scan_done && auto_play_en &&
                    display_valid && !load_busy &&
                    !display_commit_pending && first_image_committed &&
                    (img_found_count > 4'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_done && !first_image_committed &&
                    !first_image_load_failed && bmp_ready &&
                    !voice_reader_busy && !load_busy &&
                    !display_commit_pending && (img_found_count != 4'd0)) begin
                    load_idx         <= home_image_idx;
                    load_page_right  <= 1'b0;
                    load_settings_entry <= 1'b0;
                    debug_event_toggle[1] <= ~debug_event_toggle[1];
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_zoom_level  <= (home_image_idx == 4'd12) ? 3'd2 : image_zoom0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    scaler_started   <= 1'b0;
                    scaler_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    home_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // Return to the first BMP after any in-flight frame has been
                // committed.  If it is already displayed, consume the request
                // without performing a redundant SDRAM write.
                else if (scan_done && bmp_ready && !voice_reader_busy &&
                         display_valid && !load_busy &&
                         !display_commit_pending && home_req_pending) begin
                    if (img_idx == home_image_idx) begin
                        home_req_pending <= 1'b0;
                        zoom_req_pending <= 1'b0;
                    end else begin
                        load_idx          <= home_image_idx;
                        load_page_right   <= 1'b0;
                        load_settings_entry <= 1'b0;
                        debug_event_toggle[2] <= ~debug_event_toggle[2];
                        pending_buf_idx   <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx     <= next_buf_lut(disp_buf_idx, display_valid);
                        load_zoom_level   <= (home_image_idx == 4'd12) ? 3'd2 : image_zoom0;
                        load_start_pulse  <= 1'b1;
                        load_busy         <= 1'b1;
                        source_done_seen  <= 1'b0;
                        scaler_started    <= 1'b0;
                        scaler_done_seen  <= 1'b0;
                        home_req_pending  <= 1'b0;
                        next_req_pending  <= 1'b0;
                        zoom_req_pending  <= 1'b0;
                        auto_cnt          <= 32'd0;
                    end
                end
                // Load the exact application page into the inactive buffer.
                // An unavailable index is a bounded no-op that preserves the
                // last complete frame instead of reading an uninitialized
                // sector or showing a partial page.
                else if (scan_done && !voice_reader_busy &&
                         display_valid && ((!load_busy && bmp_ready) ||
                         entry_hit_while_prefetch) &&
                         !display_commit_pending && image_req_pending) begin
                    if (selected_image_idx >= img_found_count) begin
                        image_req_pending <= 1'b0;
                    end else if ((selected_image_idx == img_idx) &&
                                 (selected_image_settings == display_settings_entry) &&
                                 ((selected_image_idx >= 4'd3) ||
                                  (selected_image_zoom == display_zoom_level))) begin
                        image_req_pending <= 1'b0;
                    end else if (PREFETCH_ENABLE && entry_cache_valid &&
                                 (selected_image_idx == 4'd0) &&
                                 (selected_image_zoom == 3'd2)) begin
                        if (first_image_committed && !selected_image_settings)
                            first_lesson_frame_ready <= 1'b1;
                        disp_buf_idx <= entry_cache_buf_idx;
                        img_idx <= selected_image_idx;
                        display_page_right <= selected_image_prev;
                        display_settings_entry <= selected_image_settings;
                        display_zoom_level <= 3'd2;
                        display_commit_toggle <= ~display_commit_toggle;
                        display_commit_pending <= 1'b1;
                        image_req_pending <= 1'b0;
                    end else if (PREFETCH_ENABLE && prefetch_valid &&
                                 (selected_image_idx == prefetch_idx)) begin
                        // The cache has already passed source/scaler/writer
                        // completion. Publish through the normal atomic video
                        // mailbox without issuing any SD read or SDRAM write.
                        if (first_image_committed && (selected_image_idx < 4'd3) &&
                            !selected_image_settings)
                            first_lesson_frame_ready <= 1'b1;
                        disp_buf_idx <= 2'd2;
                        img_idx <= selected_image_idx;
                        display_page_right <= selected_image_prev;
                        display_settings_entry <= selected_image_settings;
                        display_zoom_level <= 3'd2;
                        display_commit_toggle <= ~display_commit_toggle;
                        display_commit_pending <= 1'b1;
                        image_req_pending <= 1'b0;
                    end else begin
                        load_idx          <= selected_image_idx;
                        load_page_right   <= selected_image_prev;
                        load_settings_entry <= selected_image_settings;
                        debug_event_toggle[3] <= ~debug_event_toggle[3];
                        pending_buf_idx   <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx     <= next_buf_lut(disp_buf_idx, display_valid);
                        load_zoom_level   <= (selected_image_idx < 4'd3) ?
                                             selected_image_zoom :
                                             image_zoom_lut(selected_image_idx);
                        load_start_pulse  <= 1'b1;
                        load_busy         <= 1'b1;
                        source_done_seen  <= 1'b0;
                        scaler_started    <= 1'b0;
                        scaler_done_seen  <= 1'b0;
                        image_req_pending <= 1'b0;
                        auto_cnt          <= 32'd0;
                    end
                end
                // Load the selected BMP into the inactive buffer at that
                // image's requested zoom, then commit both as one frame.
                else if (scan_done && bmp_ready && !voice_reader_busy &&
                         display_valid && !load_busy &&
                         !display_commit_pending && zoom_req_pending) begin
                    if ((selected_zoom_idx == img_idx) &&
                        (selected_zoom_level == display_zoom_level)) begin
                        zoom_req_pending <= 1'b0;
                    end else begin
                        load_idx          <= selected_zoom_idx;
                        load_page_right   <= 1'b0;
                        load_settings_entry <= 1'b0;
                        debug_event_toggle[4] <= ~debug_event_toggle[4];
                        pending_buf_idx   <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx     <= next_buf_lut(disp_buf_idx, display_valid);
                        load_zoom_level   <= selected_zoom_level;
                        load_start_pulse  <= 1'b1;
                        load_busy         <= 1'b1;
                        source_done_seen  <= 1'b0;
                        scaler_started    <= 1'b0;
                        scaler_done_seen  <= 1'b0;
                        zoom_req_pending  <= 1'b0;
                        auto_cnt          <= 32'd0;
                    end
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && !voice_reader_busy &&
                         display_valid && !load_busy &&
                         !display_commit_pending && next_req_pending &&
                         (img_found_count != 4'd0)) begin
                    load_idx         <= next_from_current;
                    load_page_right  <= 1'b0;
                    load_settings_entry <= 1'b0;
                    debug_event_toggle[5] <= ~debug_event_toggle[5];
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_zoom_level  <= image_zoom_lut(next_from_current);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    scaler_started   <= 1'b0;
                    scaler_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && !voice_reader_busy &&
                         display_valid && !load_busy &&
                         !display_commit_pending && AUTO_PLAY_ENABLE &&
                         auto_play_en && auto_tick &&
                         (img_found_count > 4'd1)) begin
                    load_idx         <= next_from_current;
                    load_page_right  <= 1'b0;
                    load_settings_entry <= 1'b0;
                    debug_event_toggle[6] <= ~debug_event_toggle[6];
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_zoom_level  <= image_zoom_lut(next_from_current);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    scaler_started   <= 1'b0;
                    scaler_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end

                // Start one narration after its learning page is the complete
                // committed frame.  Missing or malformed trailers are bounded
                // no-ops and never block page navigation or HDMI video.
                if (narration_enable && voice_req_pending && scan_done &&
                    display_valid && !load_busy && !display_commit_pending &&
                    !home_req_pending && !image_req_pending &&
                    !zoom_req_pending && !voice_reader_busy && bmp_ready &&
                    voice_fifo_empty &&
                    (img_idx == {2'b00, selected_voice_idx})) begin
                    voice_req_pending <= 1'b0;
                    if (voice_available[selected_voice_idx])
                        voice_start_pulse <= 1'b1;
                end

                // Lowest priority: use SD idle time, never interrupt narration
                // or a queued navigation/zoom/home request. Once started, keep
                // the existing complete-frame transaction discipline. A quiz
                // request arriving during this read consumes its result next.
                if (PREFETCH_ENABLE && prefetch_enable &&
                    ((prefetch_target == 4'd0) || entry_cache_valid ||
                     first_lesson_frame_ready) &&
                    scan_done &&
                    display_valid && bmp_ready && !load_busy &&
                    !display_commit_pending && (disp_buf_idx != 2'd2) &&
                    !home_req_pending && !image_req_pending &&
                    !zoom_req_pending && !next_req_pending &&
                    !home_request && !image_request && !zoom_request &&
                    !key_next_press && !auto_play_en &&
                    !voice_req_pending && !voice_reader_busy &&
                    !voice_start_pulse &&
                    ((prefetch_target == 4'd0) ||
                     ((prefetch_target >= 4'd3) &&
                      (prefetch_target <= 4'd5))) &&
                    (prefetch_target < img_found_count) &&
                    !((prefetch_target == 4'd0) && entry_cache_valid) &&
                    !(prefetch_valid && (prefetch_idx == prefetch_target)) &&
                    !(prefetch_failed && (prefetch_failed_idx == prefetch_target))) begin
                    if (prefetch_target == 4'd0) begin
                        entry_cache_valid <= 1'b0;
                        pending_buf_idx <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx <= next_buf_lut(disp_buf_idx, display_valid);
                    end else begin
                        prefetch_valid <= 1'b0;
                        pending_buf_idx <= 2'd2;
                        write_buf_idx <= 2'd2;
                    end
                    load_idx <= prefetch_target;
                    load_page_right <= 1'b0;
                    load_settings_entry <= 1'b0;
                    load_zoom_level <= 3'd2;
                    load_start_pulse <= 1'b1;
                    load_busy <= 1'b1;
                    load_is_prefetch <= 1'b1;
                    load_is_entry_prefetch <= (prefetch_target == 4'd0);
                    source_done_seen <= 1'b0;
                    scaler_started <= 1'b0;
                    scaler_done_seen <= 1'b0;
                end
            end
        end
    end
end

fat32_volume_scanner #(.SEARCH_HOME(1'b1)) u_fat32_volume_scanner (
    .clk                      (clk),
    .rst                      (rst),
    .start                    (scan_start_pulse),
    .sd_init_done             (sd_init_done),
    .busy                     (fs_scan_busy),
    .done                     (fs_scan_done),
    .error_code               (fs_scan_error),
    .sectors_per_cluster      (fs_sectors_per_cluster),
    .sectors_per_cluster_shift(fs_sectors_per_cluster_shift),
    .fat_start_lba            (fs_fat_start_lba),
    .data_start_lba           (fs_data_start_lba),
    .max_cluster              (fs_max_cluster),
    .file_found_valid         (fs_file_found_valid),
    .file_found_index         (fs_file_found_index),
    .file_found_cluster       (fs_file_found_cluster),
    .file_found_size          (fs_file_found_size),
    .file_found_mask          (fs_file_found_mask),
    .sd_sec_read              (fs_scan_sd_read),
    .sd_sec_read_addr         (fs_scan_sd_read_addr),
    .sd_sec_read_data         (sd_sec_read_data),
    .sd_sec_read_data_valid   (sd_sec_read_data_valid),
    .sd_sec_read_end          (sd_sec_read_end),
    .sd_recover_pulse         (fs_scan_sd_recover_pulse)
);

fat32_virtual_sector_bridge u_fat32_virtual_sector_bridge (
    .clk                      (clk),
    .rst                      (rst),
    .sd_init_done             (sd_init_done),
    .metadata_clear           (scan_start_pulse),
    .metadata_valid           (fs_file_found_valid),
    .metadata_index           (fs_file_found_index),
    .metadata_cluster         (fs_file_found_cluster),
    .metadata_size            (fs_file_found_size),
    .metadata_mask            (bridge_metadata_mask),
    .sectors_per_cluster      (fs_sectors_per_cluster),
    .sectors_per_cluster_shift(fs_sectors_per_cluster_shift),
    .fat_start_lba            (fs_fat_start_lba),
    .data_start_lba           (fs_data_start_lba),
    .max_cluster              (fs_max_cluster),
    .virtual_read             (voice_reader_busy ?
                               voice_sd_sec_read : bmp_sd_sec_read),
    .virtual_read_addr        (voice_reader_busy ?
                               voice_sd_sec_read_addr : bmp_sd_sec_read_addr),
    .virtual_read_data        (virtual_sd_sec_read_data),
    .virtual_read_data_valid  (virtual_sd_sec_read_data_valid),
    .virtual_read_end         (virtual_sd_sec_read_end),
    .virtual_read_error       (virtual_sd_sec_read_error),
    .physical_read            (bridge_sd_read),
    .physical_read_addr       (bridge_sd_read_addr),
    .physical_read_data       (sd_sec_read_data),
    .physical_read_data_valid (sd_sec_read_data_valid),
    .physical_read_end        (sd_sec_read_end),
    .sd_recover_pulse         (bridge_sd_recover_pulse)
);

bmp_read #(.CROP_READ_ENABLE(1)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (1'b0),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (),
    .scan_found_valid       (),
    .scan_found_sector      (),
    .scan_found_total       (),
    .scan_found_voice       (),
    .scan_found_voice_offset(),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),
    .load_error_pulse       (bmp_load_error_pulse),
    .sd_recover_pulse       (bmp_sd_recover_pulse),

    .sd_init_done           (sd_init_done),
    .state_code             (bmp_state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .source_width           (bmp_source_width),
    .source_height          (bmp_source_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack_sd),
    .source_start           (scaler_source_start),
    .source_first_row       (bmp_source_first_row),
    .source_roi_rows        (bmp_source_row_count),
    .sd_sec_read            (bmp_sd_sec_read),
    .sd_sec_read_addr       (bmp_sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data_pipe),
    .sd_sec_read_data_valid (bmp_sd_sec_read_data_valid),
    .sd_sec_read_end        (bmp_sd_sec_read_end),
    .sd_sec_read_error      (bmp_sd_sec_read_error),
    .bmp_data_wr_en         (bmp_source_valid),
    .bmp_data               (bmp_source_data)
);

lesson_voice_reader u_lesson_voice_reader (
    .clk                    (clk),
    .rst                    (rst),
    .start                  (voice_start_pulse),
    .stop                   (voice_stop_pulse),
    .bmp_sector             (voice_sector_lut(selected_voice_idx)),
    .voice_byte_offset      (voice_offset_lut(selected_voice_idx)),
    .expected_page          (selected_voice_idx),
    .buffer_ready           (voice_fifo_space_available),
    .speed_level            (voice_speed_level),
    .speed_toggle           (voice_speed_toggle),
    .ready                  (voice_reader_ready),
    .busy                   (voice_reader_busy),
    .voice_start_pulse      (voice_reader_start_pulse),
    .voice_end_pulse        (voice_reader_end_pulse),
    .voice_error_pulse      (voice_reader_error_pulse),
    .sd_recover_pulse       (voice_sd_recover_pulse),
    .voice_page             (voice_reader_page),
    .voice_sample_total     (voice_reader_sample_total),
    .voice_data_valid       (voice_reader_data_valid),
    .voice_data             (voice_reader_data),
    .voice_data_speed       (voice_reader_speed),
    .sd_sec_read            (voice_sd_sec_read),
    .sd_sec_read_addr       (voice_sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data_pipe),
    .sd_sec_read_data_valid (voice_sd_sec_read_data_valid),
    .sd_sec_read_end        (voice_sd_sec_read_end),
    .sd_sec_read_error      (voice_sd_sec_read_error)
);

assign voice_sample_total = voice_reader_sample_total;

bmp_nearest_scaler #(
    .OUTPUT_WIDTH     (640),
    .OUTPUT_HEIGHT    (480),
    .MAX_SOURCE_WIDTH (1280),
    .EMIT_DIV         (6),
    .SOURCE_ROI_ENABLE(1),
    .ZOOM_FOCUS_LEFT  (1)
) u_bmp_nearest_scaler (
    .clk             (clk),
    .rst             (rst),
    .start           (scaler_start_pulse),
    .zoom_level      (load_zoom_level),
    .source_width    (bmp_source_width),
    .source_height   (bmp_source_height),
    .source_valid    (bmp_source_valid),
    .source_rgb      (bmp_source_data),
    .output_valid    (scaled_data_valid),
    .output_rgb      (scaled_data),
    .busy            (scaler_busy),
    .done            (scaler_done),
    .source_start    (scaler_source_start),
    .source_overrun  (scaler_overrun),
    .source_first_row(bmp_source_first_row),
    .source_row_count(bmp_source_row_count)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .recover                (bmp_sd_recover_pulse || voice_sd_recover_pulse ||
                             fs_scan_sd_recover_pulse || bridge_sd_recover_pulse),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
