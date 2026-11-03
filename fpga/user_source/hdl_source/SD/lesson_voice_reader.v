`timescale 1ns/1ps

// Streams an LMV1 narration trailer embedded after a BMP pixel array.
// The SD controller returns whole 512-byte sectors and cannot be backpressured
// mid-sector, so this reader launches a new sector only when the asynchronous
// audio FIFO has room for another complete sector.
module lesson_voice_reader #(
    parameter integer SD_PROGRESS_TIMEOUT_CYCLES = 50_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        stop,
    input  wire [31:0] bmp_sector,
    input  wire [31:0] voice_byte_offset,
    input  wire [1:0]  expected_page,
    input  wire        buffer_ready,
    input  wire [1:0]  speed_level,
    input  wire        speed_toggle,

    output wire        ready,
    output wire        busy,
    output reg         voice_start_pulse,
    output reg         voice_end_pulse,
    output reg         voice_error_pulse,
    output reg         sd_recover_pulse,
    output reg  [1:0]  voice_page,
    output reg  [31:0] voice_sample_total,
    output reg         voice_data_valid,
    output reg  [7:0]  voice_data,
    output reg  [1:0]  voice_data_speed,

    output wire        sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    input  wire        sd_sec_read_error
);

localparam [1:0] ST_IDLE        = 2'd0;
localparam [1:0] ST_READ_SECTOR = 2'd1;
localparam [1:0] ST_WAIT_BUFFER = 2'd2;

reg [1:0]  state;
reg [9:0]  sector_byte_count;
reg [8:0]  first_sector_skip;
reg        first_sector;
// Only the 16-byte header needs an offset.  Payload length is tracked by
// payload_count, so do not keep a wide stream counter in every header CE.
reg [3:0]  header_byte_index;
reg        payload_phase;
reg [21:0] payload_count;
reg [21:0] sample_count;
reg [21:0] last_sample_index;
reg [9:0]  sample_count_overflow;
reg [21:0] header_sample_count;
reg [9:0]  header_sample_count_overflow;
reg [7:0]  magic0;
reg [7:0]  magic1;
reg [7:0]  magic2;
reg [7:0]  magic3;
reg [7:0]  header_page;
reg [7:0]  codec;
reg [15:0] sample_rate;
reg [31:0] payload_crc32;
reg        header_valid;
reg        stream_started;
reg        payload_complete;
reg        stop_pending;
reg        error_pending;
reg        format_v2;
reg [2:0]  speed_toggle_sync /* fehdl keep="true" */;
reg        speed_toggle_seen;
reg [1:0]  speed_meta /* fehdl keep="true" */;
reg [1:0]  speed_sync /* fehdl keep="true" */;
reg [1:0]  speed_current;
reg [1:0]  block_speed;
reg [2:0]  block_header_index;
reg [1:0]  block_track;
reg        block_header_phase;
reg [10:0] block_source_samples;
reg [10:0] track_length0, track_length1, track_length2;
reg [10:0] track_index;
reg [21:0] source_remaining;
reg        block_valid_latched;
wire [10:0] current_track_length =
    (block_track == 2'd0) ? track_length0 :
    (block_track == 2'd1) ? track_length1 : track_length2;
localparam integer PROGRESS_COUNT_WIDTH = (SD_PROGRESS_TIMEOUT_CYCLES > 1) ?
                                         $clog2(SD_PROGRESS_TIMEOUT_CYCLES) : 1;
reg [PROGRESS_COUNT_WIDTH-1:0] sd_progress_timeout_count;
reg sd_timeout_due;
wire       sd_progress_seen;
wire       sd_progress_timeout;

wire byte_in_stream = sd_sec_read_data_valid &&
                      (!first_sector ||
                       (sector_byte_count >= first_sector_skip));
wire header_match =
    (magic0 == "L") && (magic1 == "M") &&
    (magic2 == "V") &&
    (((magic3 == "1") && (codec == 8'd1)) ||
     ((magic3 == "2") && (codec == 8'd2))) &&
    (header_page[1:0] == voice_page) &&
    (header_page[7:2] == 6'd0) &&
    (sample_rate == 16'd16000) &&
    (header_sample_count_overflow == 10'd0) &&
    (header_sample_count != 22'd0) &&
    (header_sample_count <= 22'd4000000);

assign ready = (state == ST_IDLE);
assign busy = (state != ST_IDLE);
assign sd_sec_read = (state == ST_READ_SECTOR);

assign sd_progress_seen = sd_sec_read_data_valid || sd_sec_read_end;
assign sd_progress_timeout = (state == ST_READ_SECTOR) &&
    !sd_progress_seen && (SD_PROGRESS_TIMEOUT_CYCLES > 0) &&
    ((SD_PROGRESS_TIMEOUT_CYCLES <= 1) || sd_timeout_due);

// The count finishes at header byte 11, four beats before payload starts.
// Sample it every clock so SD fault/timeout priority is not in this wide CE.
// These private pipeline registers are never consumed before a fresh header;
// sample_count and its overflow bits are cleared on reset and every start.
always @(posedge clk) begin
    header_sample_count <= sample_count;
    header_sample_count_overflow <= sample_count_overflow;
end

always @(posedge clk) begin
    if (rst) begin
        speed_toggle_sync <= 3'd0;
        speed_toggle_seen <= 1'b0;
        speed_meta <= 2'd2;
        speed_sync <= 2'd2;
        speed_current <= 2'd2;
    end else begin
        speed_toggle_sync <= {speed_toggle_sync[1:0], speed_toggle};
        speed_meta <= speed_level;
        speed_sync <= speed_meta;
        if (speed_toggle_sync[2] != speed_toggle_seen) begin
            speed_toggle_seen <= speed_toggle_sync[2];
            speed_current <= (speed_sync <= 2'd2) ? speed_sync : 2'd1;
        end
    end
end

always @(posedge clk) begin
    if (rst || (state != ST_READ_SECTOR) || sd_progress_seen) begin
        sd_progress_timeout_count <= 32'd0;
        sd_timeout_due <= 1'b0;
    end else if (!sd_progress_timeout) begin
        sd_progress_timeout_count <= sd_progress_timeout_count + 32'd1;
        sd_timeout_due <= (sd_progress_timeout_count >= SD_PROGRESS_TIMEOUT_CYCLES - 2);
    end
end

// Keep the SD address enable independent of the header and payload register
// enables. A sector end is progress, so the timeout cannot coincide with it.
always @(posedge clk) begin
    if (rst)
        sd_sec_read_addr <= 32'd0;
    else if (state == ST_IDLE && start && buffer_ready && !sd_sec_read_error)
        sd_sec_read_addr <= bmp_sector + (voice_byte_offset >> 9);
    else if (state == ST_READ_SECTOR && sd_sec_read_end &&
             sector_byte_count == 10'd512 && !stop_pending &&
             !payload_complete && !error_pending && !sd_sec_read_error)
        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
end

// rst is already the clock_reset_manager output synchronized to this SD clock
// domain.  Keeping this application-layer state machine on a synchronous reset
// avoids adding another large asynchronous-reset tree to the placed design.
always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        sector_byte_count <= 10'd0;
        first_sector_skip <= 9'd0;
        first_sector <= 1'b1;
        header_byte_index <= 4'd0;
        payload_phase <= 1'b0;
        payload_count <= 22'd0;
        sample_count <= 22'd0;
        last_sample_index <= 22'd0;
        sample_count_overflow <= 10'd0;
        magic0 <= 8'd0;
        magic1 <= 8'd0;
        magic2 <= 8'd0;
        magic3 <= 8'd0;
        header_page <= 8'd0;
        codec <= 8'd0;
        sample_rate <= 16'd0;
        payload_crc32 <= 32'd0;
        header_valid <= 1'b0;
        stream_started <= 1'b0;
        payload_complete <= 1'b0;
        stop_pending <= 1'b0;
        error_pending <= 1'b0;
        voice_start_pulse <= 1'b0;
        voice_end_pulse <= 1'b0;
        voice_error_pulse <= 1'b0;
        sd_recover_pulse <= 1'b0;
        voice_page <= 2'd0;
        voice_sample_total <= 32'd0;
        voice_data_valid <= 1'b0;
        voice_data <= 8'd0;
        voice_data_speed <= 2'd3;
        format_v2 <= 1'b0;
        block_speed <= 2'd1;
        block_header_index <= 3'd0;
        block_track <= 2'd0;
        block_header_phase <= 1'b1;
        block_source_samples <= 11'd0;
        track_length0 <= 11'd0;
        track_length1 <= 11'd0;
        track_length2 <= 11'd0;
        track_index <= 11'd0;
        source_remaining <= 22'd0;
        block_valid_latched <= 1'b0;
    end else begin
        voice_start_pulse <= 1'b0;
        voice_end_pulse <= 1'b0;
        voice_error_pulse <= 1'b0;
        sd_recover_pulse <= 1'b0;
        voice_data_valid <= 1'b0;

        if ((state != ST_IDLE) && stop)
            stop_pending <= 1'b1;

        if (sd_progress_timeout || sd_sec_read_error) begin
            // A missing data token or controller error must release SD
            // ownership and restart the shared protocol stack. If audio had
            // started, close the clip cleanly so the audio domain cannot
            // remain busy. Short-sector qualification stays in the end
            // branch below so sector_byte_count does not fan out to every
            // header and payload register CE.
            state <= ST_IDLE;
            sector_byte_count <= 10'd0;
            stop_pending <= 1'b0;
            error_pending <= 1'b0;
            voice_error_pulse <= 1'b1;
            sd_recover_pulse <= 1'b1;
            if (stream_started)
                voice_end_pulse <= 1'b1;
        end else if (state == ST_READ_SECTOR) begin
            if (sd_sec_read_data_valid && !sd_sec_read_end)
                sector_byte_count <= sector_byte_count + 10'd1;

            if (byte_in_stream && !sd_sec_read_end) begin
                if (!payload_phase) begin
                    header_byte_index <= header_byte_index + 4'd1;
                    if (header_byte_index == 4'd15)
                        payload_phase <= 1'b1;
                    case (header_byte_index)
                        4'd0:  magic0 <= sd_sec_read_data;
                        4'd1:  magic1 <= sd_sec_read_data;
                        4'd2:  magic2 <= sd_sec_read_data;
                        4'd3:  magic3 <= sd_sec_read_data;
                        4'd4:  header_page <= sd_sec_read_data;
                        4'd5:  codec <= sd_sec_read_data;
                        4'd6:  sample_rate[7:0] <= sd_sec_read_data;
                        4'd7:  sample_rate[15:8] <= sd_sec_read_data;
                        4'd8: sample_count[7:0] <= sd_sec_read_data;
                        4'd9: sample_count[15:8] <= sd_sec_read_data;
                        4'd10: begin
                            sample_count[21:16] <= sd_sec_read_data[5:0];
                            sample_count_overflow[1:0] <= sd_sec_read_data[7:6];
                        end
                        4'd11: sample_count_overflow[9:2] <= sd_sec_read_data;
                        4'd12: payload_crc32[7:0] <= sd_sec_read_data;
                        4'd13: payload_crc32[15:8] <= sd_sec_read_data;
                        4'd14: payload_crc32[23:16] <= sd_sec_read_data;
                        4'd15: payload_crc32[31:24] <= sd_sec_read_data;
                        default: ;
                    endcase

                    // All validated fields precede the CRC. Commit the
                    // format at header byte 15 so payload byte 0 uses only
                    // registered qualification on the SD critical path.
                    if (header_byte_index == 4'd15) begin
                        header_valid <= header_match;
                        if (header_match) begin
                            voice_sample_total <= {10'd0, header_sample_count};
                            format_v2 <= (magic3 == "2");
                            source_remaining <= header_sample_count;
                        end else begin
                            error_pending <= 1'b1;
                        end
                    end

                    if (header_byte_index == 4'd12)
                        last_sample_index <= sample_count - 22'd1;

                end

                if (payload_phase && header_valid && !stream_started &&
                    !stop_pending && !error_pending) begin
                    stream_started <= 1'b1;
                    voice_start_pulse <= 1'b1;
                end

                if (payload_phase && header_valid &&
                    !payload_complete && !stop_pending && !format_v2) begin
                    voice_data <= sd_sec_read_data;
                    voice_data_speed <= 2'd3;
                    voice_data_valid <= 1'b1;
                    payload_count <= payload_count + 22'd1;
                    if (payload_count >= last_sample_index)
                        payload_complete <= 1'b1;
                end

                if (payload_phase && format_v2 && header_valid &&
                    !payload_complete && !stop_pending && !error_pending) begin
                    if (block_header_phase) begin
                        block_header_index <= block_header_index + 3'd1;
                        case (block_header_index)
                            3'd0: begin
                                block_source_samples[7:0] <= sd_sec_read_data;
                                block_speed <= speed_current;
                                block_valid_latched <= 1'b0;
                            end
                            3'd1: block_source_samples[10:8] <= sd_sec_read_data[2:0];
                            3'd2: track_length0[7:0] <= sd_sec_read_data;
                            3'd3: track_length0[10:8] <= sd_sec_read_data[2:0];
                            3'd4: track_length1[7:0] <= sd_sec_read_data;
                            3'd5: track_length1[10:8] <= sd_sec_read_data[2:0];
                            3'd6: track_length2[7:0] <= sd_sec_read_data;
                            3'd7: begin
                                track_length2[10:8] <= sd_sec_read_data[2:0];
                                block_valid_latched <=
                                    (block_source_samples != 0) &&
                                    (block_source_samples <= 11'd1024) &&
                                    ({11'd0,block_source_samples} <= source_remaining) &&
                                    (track_length0 != 0) &&
                                    (track_length0 <= 11'd1366) &&
                                    (track_length1 != 0) &&
                                    (track_length1 <= 11'd1024) &&
                                    ({sd_sec_read_data[2:0],track_length2[7:0]} != 11'd0) &&
                                    ({sd_sec_read_data[2:0],track_length2[7:0]} <= 11'd820);
                                block_header_phase <= 1'b0;
                                block_track <= 2'd0;
                                track_index <= 11'd0;
                            end
                        endcase
                        if ((block_header_index[0] == 1'b1) &&
                            (sd_sec_read_data[7:3] != 0))
                            error_pending <= 1'b1;
                    end else if (!block_valid_latched) begin
                        error_pending <= 1'b1;
                    end else begin
                        if (block_track == block_speed) begin
                            voice_data <= sd_sec_read_data;
                            voice_data_speed <= block_speed;
                            voice_data_valid <= 1'b1;
                        end
                        if (track_index == current_track_length - 11'd1) begin
                            track_index <= 11'd0;
                            if (block_track == 2'd2) begin
                                block_track <= 2'd0;
                                block_header_phase <= 1'b1;
                                block_header_index <= 3'd0;
                                source_remaining <= source_remaining -
                                                    {11'd0,block_source_samples};
                                if (source_remaining == {11'd0,block_source_samples})
                                    payload_complete <= 1'b1;
                            end else begin
                                block_track <= block_track + 2'd1;
                            end
                        end else begin
                            track_index <= track_index + 11'd1;
                        end
                    end
                end
            end

            if (sd_sec_read_end) begin
                if (sector_byte_count != 10'd512) begin
                    // A short sector is not a valid transfer even when the
                    // controller supplies an end pulse.
                    state <= ST_IDLE;
                    sector_byte_count <= 10'd0;
                    stop_pending <= 1'b0;
                    error_pending <= 1'b0;
                    voice_error_pulse <= 1'b1;
                    sd_recover_pulse <= 1'b1;
                    if (stream_started)
                        voice_end_pulse <= 1'b1;
                end else begin
                    sector_byte_count <= 10'd0;
                    first_sector <= 1'b0;

                    if (stop_pending || payload_complete || error_pending) begin
                        state <= ST_IDLE;
                        if (stream_started)
                            voice_end_pulse <= 1'b1;
                        if (error_pending)
                            voice_error_pulse <= 1'b1;
                        stop_pending <= 1'b0;
                    end else begin
                        state <= ST_WAIT_BUFFER;
                    end
                end
            end
        end else if (state == ST_WAIT_BUFFER) begin
            sector_byte_count <= 10'd0;
            if (stop_pending || stop) begin
                state <= ST_IDLE;
                if (stream_started)
                    voice_end_pulse <= 1'b1;
                stop_pending <= 1'b0;
            end else if (buffer_ready) begin
                state <= ST_READ_SECTOR;
            end
        end else begin
            sector_byte_count <= 10'd0;
            if (start && buffer_ready) begin
                state <= ST_READ_SECTOR;
                first_sector_skip <= voice_byte_offset[8:0];
                first_sector <= 1'b1;
                header_byte_index <= 4'd0;
                payload_phase <= 1'b0;
                payload_count <= 22'd0;
                sample_count <= 22'd0;
                last_sample_index <= 22'd0;
                sample_count_overflow <= 10'd0;
                magic0 <= 8'd0;
                magic1 <= 8'd0;
                magic2 <= 8'd0;
                magic3 <= 8'd0;
                header_page <= 8'd0;
                codec <= 8'd0;
                sample_rate <= 16'd0;
                payload_crc32 <= 32'd0;
                header_valid <= 1'b0;
                stream_started <= 1'b0;
                payload_complete <= 1'b0;
                stop_pending <= 1'b0;
                error_pending <= 1'b0;
                format_v2 <= 1'b0;
                block_header_phase <= 1'b1;
                block_header_index <= 3'd0;
                block_valid_latched <= 1'b0;
                voice_page <= expected_page;
            end
        end
    end
end

endmodule
