`timescale 1ns/1ps

module debug_uart #(
    parameter integer CLK_FRE = 50,
    parameter integer BAUD_RATE = 115200,
    parameter integer STATUS_INTERVAL_CYCLES = 50000000,
    parameter [31:0] BUILD_ID = 32'h20260903
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] state_code,
    input  wire [3:0] app_state,
    input  wire [3:0] app_target_image,
    input  wire [12:0] sd_debug_event_toggle,
    input  wire       video_commit_toggle,
    input  wire       display_valid,
    input  wire       sdram_init_done,
    input  wire       sdram_refresh_active,
    input  wire       sdram_busy,
    input  wire       audio_pll_lock,
    input  wire       audio_valid,
    input  wire       axis_ready,
    input  wire [1:0] write_buf_idx,
    input  wire [1:0] disp_buf_idx,
    output reg signed [2:0] video_brightness,
    output reg  [1:0] video_contrast,
    output reg        video_osd_enable,
    output reg        video_subtitle_enable,
    output reg        video_control_toggle,
    output reg        thumbnail_request_toggle,
    input  wire       thumbnail_done_toggle,
    input  wire [15:0] thumbnail_frame_id,
    input  wire [31:0] thumbnail_crc32,
    output reg  [12:0] thumbnail_read_addr,
    input  wire [15:0] thumbnail_read_data,
    input  wire       uart_rx_pin,
    output wire       uart_tx_pin
);

localparam [7:0] PROTOCOL_VERSION = 8'h01;
localparam [7:0] TYPE_HELLO       = 8'h01;
localparam [7:0] TYPE_STATUS      = 8'h02;
localparam [7:0] TYPE_IMAGE_BEGIN = 8'h10;
localparam [7:0] TYPE_IMAGE_DATA  = 8'h11;
localparam [7:0] TYPE_IMAGE_END   = 8'h12;
localparam [7:0] TYPE_PING        = 8'h80;
localparam [7:0] TYPE_GET_STATUS  = 8'h81;
localparam [7:0] TYPE_SET_BRIGHTNESS = 8'h84;
localparam [7:0] TYPE_SET_CONTRAST = 8'h85;
localparam [7:0] TYPE_SET_OSD     = 8'h86;
localparam [7:0] TYPE_GET_THUMBNAIL = 8'h87;
localparam [7:0] FLAG_ACK         = 8'h01;
localparam [1:0] PAYLOAD_NONE     = 2'd0;
localparam [1:0] PAYLOAD_HELLO    = 2'd1;
localparam [1:0] PAYLOAD_STATUS   = 2'd2;
localparam [2:0] PAYLOAD_IMAGE_BEGIN = 3'd3;
localparam [2:0] PAYLOAD_IMAGE_DATA  = 3'd4;
localparam [2:0] PAYLOAD_IMAGE_END   = 3'd5;
localparam integer MAX_CMD_PAYLOAD = 16;
localparam integer IMAGE_CHUNKS = 40;
localparam integer IMAGE_WORDS_PER_CHUNK = 120;

localparam [1:0] THUMB_IDLE  = 2'd0;
localparam [1:0] THUMB_BEGIN = 2'd1;
localparam [1:0] THUMB_DATA  = 2'd2;
localparam [1:0] THUMB_END   = 2'd3;

localparam [3:0] RX_SYNC0   = 4'd0;
localparam [3:0] RX_SYNC1   = 4'd1;
localparam [3:0] RX_VERSION = 4'd2;
localparam [3:0] RX_TYPE    = 4'd3;
localparam [3:0] RX_FLAGS   = 4'd4;
localparam [3:0] RX_SEQ_LO  = 4'd5;
localparam [3:0] RX_SEQ_HI  = 4'd6;
localparam [3:0] RX_LEN_LO  = 4'd7;
localparam [3:0] RX_LEN_HI  = 4'd8;
localparam [3:0] RX_PAYLOAD = 4'd9;
localparam [3:0] RX_CRC_LO  = 4'd10;
localparam [3:0] RX_CRC_HI  = 4'd11;

function [15:0] crc16_next;
    input [15:0] crc;
    input [7:0] data;
    integer bit_index;
    reg [15:0] value;
    begin
        value = crc ^ {data, 8'h00};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            if (value[15])
                value = (value << 1) ^ 16'h1021;
            else
                value = value << 1;
        end
        crc16_next = value;
    end
endfunction

wire [7:0] uart_rx_data;
wire       uart_rx_valid;
wire       uart_tx_ready;
reg  [7:0] uart_tx_data;
wire       uart_tx_valid;

reg [3:0] state_meta;
reg [3:0] state_sync;
reg [1:0] write_idx_meta;
reg [1:0] write_idx_sync;
reg [1:0] disp_idx_meta;
reg [1:0] disp_idx_sync;
reg [6:0] flags_meta;
reg [6:0] flags_sync;

reg        tx_active;
reg [8:0]  tx_index;
reg [7:0]  packet_type;
reg [7:0]  packet_flags;
reg [15:0] packet_sequence;
reg [15:0] packet_length;
reg [2:0]  packet_payload;
reg [15:0] tx_crc;
reg [15:0] next_sequence;
reg [7:0]  status_byte0;
reg [7:0]  status_byte1;
reg [7:0]  status_byte2;
reg [7:0]  status_byte3;
reg [7:0]  status_app_state;
reg [7:0]  status_app_target;
reg [7:0]  status_event_count [0:13];
reg [7:0]  event_count [0:13];
reg [13:0] event_sync1;
reg [13:0] event_sync2;
reg [13:0] event_sync3;
wire [13:0] event_edges = event_sync3 ^ event_sync2;
integer event_index;
integer snapshot_index;

reg        hello_pending;
reg        ping_pending;
reg        control_ack_pending;
reg        status_pending;
reg [15:0] ping_sequence;
reg [7:0]  control_ack_type;
reg [15:0] control_ack_sequence;
reg [31:0] status_counter;

reg        thumbnail_done_meta;
reg [15:0] thumbnail_frame_meta;
reg [15:0] thumbnail_frame_sync;
reg [31:0] thumbnail_crc_meta;
reg [31:0] thumbnail_crc_sync;
reg        thumbnail_done_sync;
reg        thumbnail_done_seen;
reg        thumbnail_busy;
reg [1:0]  thumbnail_phase;
reg [5:0]  thumbnail_chunk;
reg [12:0] thumbnail_chunk_base;
reg [15:0] thumbnail_frame_latched;
reg [31:0] thumbnail_crc_latched;
reg [31:0] thumbnail_drop_count;

reg [3:0]  rx_state;
reg [7:0]  rx_version;
reg [7:0]  rx_type;
reg [7:0]  rx_flags;
reg [15:0] rx_sequence;
reg [15:0] rx_length;
reg [15:0] rx_crc;
reg [7:0]  rx_crc_low;
reg [15:0] rx_payload_count;
reg [7:0]  rx_payload0;

assign uart_tx_valid = tx_active;

always @(*) begin
    if (tx_index == 0)
        uart_tx_data = 8'hA5;
    else if (tx_index == 1)
        uart_tx_data = 8'h5A;
    else if (tx_index == 2)
        uart_tx_data = PROTOCOL_VERSION;
    else if (tx_index == 3)
        uart_tx_data = packet_type;
    else if (tx_index == 4)
        uart_tx_data = packet_flags;
    else if (tx_index == 5)
        uart_tx_data = packet_sequence[7:0];
    else if (tx_index == 6)
        uart_tx_data = packet_sequence[15:8];
    else if (tx_index == 7)
        uart_tx_data = packet_length;
    else if (tx_index == 8)
        uart_tx_data = 8'h00;
    else if (tx_index < 9 + packet_length) begin
        case (packet_payload)
            PAYLOAD_HELLO: begin
                case (tx_index - 9)
                    0:  uart_tx_data = PROTOCOL_VERSION;
                    1:  uart_tx_data = 8'h1F;
                    2:  uart_tx_data = 8'h00;
                    3:  uart_tx_data = 8'h00;
                    4:  uart_tx_data = CLK_FRE * 1000000;
                    5:  uart_tx_data = (CLK_FRE * 1000000) >> 8;
                    6:  uart_tx_data = (CLK_FRE * 1000000) >> 16;
                    7:  uart_tx_data = (CLK_FRE * 1000000) >> 24;
                    8:  uart_tx_data = BAUD_RATE;
                    9:  uart_tx_data = BAUD_RATE >> 8;
                    10: uart_tx_data = BAUD_RATE >> 16;
                    11: uart_tx_data = BAUD_RATE >> 24;
                    12: uart_tx_data = BUILD_ID[7:0];
                    13: uart_tx_data = BUILD_ID[15:8];
                    14: uart_tx_data = BUILD_ID[23:16];
                    15: uart_tx_data = BUILD_ID[31:24];
                    default: uart_tx_data = 8'h00;
                endcase
            end
            PAYLOAD_STATUS: begin
                case (tx_index - 9)
                    0: uart_tx_data = status_byte0;
                    1: uart_tx_data = status_byte1;
                    2: uart_tx_data = status_byte2;
                    3: uart_tx_data = status_byte3;
                    4: uart_tx_data = status_app_state;
                    5: uart_tx_data = status_app_target;
                    6: uart_tx_data = status_event_count[0];
                    7: uart_tx_data = status_event_count[1];
                    8: uart_tx_data = status_event_count[2];
                    9: uart_tx_data = status_event_count[3];
                    10: uart_tx_data = status_event_count[4];
                    11: uart_tx_data = status_event_count[5];
                    12: uart_tx_data = status_event_count[6];
                    13: uart_tx_data = status_event_count[7];
                    14: uart_tx_data = status_event_count[8];
                    15: uart_tx_data = status_event_count[9];
                    16: uart_tx_data = status_event_count[10];
                    17: uart_tx_data = status_event_count[11];
                    18: uart_tx_data = status_event_count[12];
                    19: uart_tx_data = status_event_count[13];
                    default: uart_tx_data = 8'h00;
                endcase
            end
            PAYLOAD_IMAGE_BEGIN: begin
                case (tx_index - 9)
                    0:  uart_tx_data = 8'd80;
                    1:  uart_tx_data = 8'd0;
                    2:  uart_tx_data = 8'd60;
                    3:  uart_tx_data = 8'd0;
                    4:  uart_tx_data = 8'd1;
                    5:  uart_tx_data = 8'd0;
                    6:  uart_tx_data = thumbnail_frame_latched[7:0];
                    7:  uart_tx_data = thumbnail_frame_latched[15:8];
                    8:  uart_tx_data = 8'h80;
                    9:  uart_tx_data = 8'h25;
                    10: uart_tx_data = 8'h00;
                    11: uart_tx_data = 8'h00;
                    default: uart_tx_data = 8'h00;
                endcase
            end
            PAYLOAD_IMAGE_DATA: begin
                if (tx_index == 9)
                    uart_tx_data = thumbnail_frame_latched[7:0];
                else if (tx_index == 10)
                    uart_tx_data = thumbnail_frame_latched[15:8];
                else if (tx_index == 11)
                    uart_tx_data = thumbnail_chunk;
                else if (tx_index == 12)
                    uart_tx_data = 8'h00;
                else if ((tx_index - 13) & 1'b1)
                    uart_tx_data = thumbnail_read_data[15:8];
                else
                    uart_tx_data = thumbnail_read_data[7:0];
            end
            PAYLOAD_IMAGE_END: begin
                case (tx_index - 9)
                    0: uart_tx_data = thumbnail_frame_latched[7:0];
                    1: uart_tx_data = thumbnail_frame_latched[15:8];
                    2: uart_tx_data = thumbnail_crc_latched[7:0];
                    3: uart_tx_data = thumbnail_crc_latched[15:8];
                    4: uart_tx_data = thumbnail_crc_latched[23:16];
                    5: uart_tx_data = thumbnail_crc_latched[31:24];
                    6: uart_tx_data = thumbnail_drop_count[7:0];
                    7: uart_tx_data = thumbnail_drop_count[15:8];
                    8: uart_tx_data = thumbnail_drop_count[23:16];
                    9: uart_tx_data = thumbnail_drop_count[31:24];
                    default: uart_tx_data = 8'h00;
                endcase
            end
            default: uart_tx_data = 8'h00;
        endcase
    end else if (tx_index == 9 + packet_length)
        uart_tx_data = tx_crc[7:0];
    else
        uart_tx_data = tx_crc[15:8];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_meta     <= 4'd0;
        state_sync     <= 4'd0;
        write_idx_meta <= 2'd0;
        write_idx_sync <= 2'd0;
        disp_idx_meta  <= 2'd0;
        disp_idx_sync  <= 2'd0;
        flags_meta     <= 7'd0;
        flags_sync     <= 7'd0;
    end else begin
        state_meta     <= state_code;
        state_sync     <= state_meta;
        write_idx_meta <= write_buf_idx;
        write_idx_sync <= write_idx_meta;
        disp_idx_meta  <= disp_buf_idx;
        disp_idx_sync  <= disp_idx_meta;
        flags_meta     <= {axis_ready, audio_valid, audio_pll_lock,
                           sdram_busy, sdram_refresh_active,
                           sdram_init_done, display_valid};
        flags_sync     <= flags_meta;
    end
end

// Toggle counters form a read-only sideband and cannot stall the display.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        event_sync1 <= 14'd0;
        event_sync2 <= 14'd0;
        event_sync3 <= 14'd0;
        for (event_index = 0; event_index < 14; event_index = event_index + 1)
            event_count[event_index] <= 8'd0;
    end else begin
        event_sync1 <= {video_commit_toggle, sd_debug_event_toggle};
        event_sync2 <= event_sync1;
        event_sync3 <= event_sync2;
        for (event_index = 0; event_index < 14; event_index = event_index + 1)
            if (event_edges[event_index])
                event_count[event_index] <= event_count[event_index] + 8'd1;
    end
end

// The pixel and UART clocks are related but share rising edges. Sampling the
// stable handshake bundle on the falling edge leaves a full half-cycle for
// the physical crossing before it enters the rising-edge logic below.
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thumbnail_done_meta  <= 1'b0;
        thumbnail_frame_meta <= 16'd0;
        thumbnail_crc_meta   <= 32'd0;
    end else begin
        thumbnail_done_meta  <= thumbnail_done_toggle;
        thumbnail_frame_meta <= thumbnail_frame_id;
        thumbnail_crc_meta   <= thumbnail_crc32;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_active       <= 1'b0;
        tx_index        <= 6'd0;
        packet_type     <= 8'd0;
        packet_flags    <= 8'd0;
        packet_sequence <= 16'd0;
        packet_length   <= 8'd0;
        packet_payload  <= PAYLOAD_NONE;
        tx_crc           <= 16'hFFFF;
        next_sequence    <= 16'd0;
        status_byte0     <= 8'd0;
        status_byte1     <= 8'd0;
        status_byte2     <= 8'd0;
        status_byte3     <= 8'd0;
        status_app_state <= 8'd0;
        status_app_target <= 8'd0;
        for (snapshot_index = 0; snapshot_index < 14; snapshot_index = snapshot_index + 1)
            status_event_count[snapshot_index] <= 8'd0;
        hello_pending    <= 1'b1;
        ping_pending     <= 1'b0;
        control_ack_pending <= 1'b0;
        status_pending   <= 1'b0;
        ping_sequence    <= 16'd0;
        control_ack_type <= 8'd0;
        control_ack_sequence <= 16'd0;
        status_counter   <= 32'd0;
        video_brightness <= 3'sd0;
        video_contrast <= 2'd1;
        video_osd_enable <= 1'b1;
        video_subtitle_enable <= 1'b1;
        video_control_toggle <= 1'b0;
        thumbnail_request_toggle <= 1'b0;
        thumbnail_done_sync      <= 1'b0;
        thumbnail_done_seen      <= 1'b0;
        thumbnail_frame_sync     <= 16'd0;
        thumbnail_crc_sync       <= 32'd0;
        thumbnail_busy           <= 1'b0;
        thumbnail_phase          <= THUMB_IDLE;
        thumbnail_chunk          <= 6'd0;
        thumbnail_chunk_base     <= 13'd0;
        thumbnail_frame_latched  <= 16'd0;
        thumbnail_crc_latched    <= 32'd0;
        thumbnail_drop_count     <= 32'd0;
        thumbnail_read_addr      <= 13'd0;
        rx_state         <= RX_SYNC0;
        rx_version       <= 8'd0;
        rx_type          <= 8'd0;
        rx_flags         <= 8'd0;
        rx_sequence      <= 16'd0;
        rx_length        <= 16'd0;
        rx_crc           <= 16'hFFFF;
        rx_crc_low       <= 8'd0;
        rx_payload_count <= 16'd0;
        rx_payload0      <= 8'd0;
    end else begin
        thumbnail_done_sync <= thumbnail_done_meta;
        thumbnail_frame_sync <= thumbnail_frame_meta;
        thumbnail_crc_sync <= thumbnail_crc_meta;
        if (thumbnail_done_sync != thumbnail_done_seen) begin
            thumbnail_done_seen     <= thumbnail_done_sync;
            thumbnail_busy          <= 1'b0;
            thumbnail_phase         <= THUMB_BEGIN;
            thumbnail_chunk         <= 6'd0;
            thumbnail_chunk_base    <= 13'd0;
            thumbnail_frame_latched <= thumbnail_frame_sync;
            thumbnail_crc_latched   <= thumbnail_crc_sync;
        end

        if (status_counter == STATUS_INTERVAL_CYCLES - 1) begin
            status_counter <= 32'd0;
            status_pending <= 1'b1;
        end else begin
            status_counter <= status_counter + 1'b1;
        end

        if (!tx_active) begin
            tx_index <= 6'd0;
            tx_crc   <= 16'hFFFF;
            if (hello_pending) begin
                tx_active       <= 1'b1;
                packet_type     <= TYPE_HELLO;
                packet_flags    <= 8'h00;
                packet_sequence <= next_sequence;
                packet_length   <= 8'd16;
                packet_payload  <= PAYLOAD_HELLO;
                next_sequence   <= next_sequence + 1'b1;
                hello_pending   <= 1'b0;
            end else if (ping_pending) begin
                tx_active       <= 1'b1;
                packet_type     <= TYPE_PING;
                packet_flags    <= FLAG_ACK;
                packet_sequence <= ping_sequence;
                packet_length   <= 8'd0;
                packet_payload  <= PAYLOAD_NONE;
                ping_pending    <= 1'b0;
            end else if (control_ack_pending) begin
                tx_active       <= 1'b1;
                packet_type     <= control_ack_type;
                packet_flags    <= FLAG_ACK;
                packet_sequence <= control_ack_sequence;
                packet_length   <= 8'd0;
                packet_payload  <= PAYLOAD_NONE;
                control_ack_pending <= 1'b0;
            end else if (thumbnail_phase == THUMB_BEGIN) begin
                tx_active       <= 1'b1;
                packet_type     <= TYPE_IMAGE_BEGIN;
                packet_flags    <= 8'h00;
                packet_sequence <= next_sequence;
                packet_length   <= 16'd12;
                packet_payload  <= PAYLOAD_IMAGE_BEGIN;
                next_sequence   <= next_sequence + 1'b1;
            end else if (thumbnail_phase == THUMB_DATA) begin
                tx_active       <= 1'b1;
                packet_type     <= TYPE_IMAGE_DATA;
                packet_flags    <= 8'h00;
                packet_sequence <= next_sequence;
                packet_length   <= 16'd244;
                packet_payload  <= PAYLOAD_IMAGE_DATA;
                next_sequence   <= next_sequence + 1'b1;
                thumbnail_read_addr <= thumbnail_chunk_base;
            end else if (thumbnail_phase == THUMB_END) begin
                tx_active       <= 1'b1;
                packet_type     <= TYPE_IMAGE_END;
                packet_flags    <= 8'h00;
                packet_sequence <= next_sequence;
                packet_length   <= 16'd10;
                packet_payload  <= PAYLOAD_IMAGE_END;
                next_sequence   <= next_sequence + 1'b1;
            end else if (status_pending) begin
                tx_active       <= 1'b1;
                packet_type     <= TYPE_STATUS;
                packet_flags    <= 8'h00;
                packet_sequence <= next_sequence;
                packet_length   <= 8'd20;
                packet_payload  <= PAYLOAD_STATUS;
                next_sequence   <= next_sequence + 1'b1;
                status_byte0    <= {4'd0, state_sync};
                status_byte1    <= {1'b0, flags_sync};
                status_byte2    <= {6'd0, write_idx_sync};
                status_byte3    <= {6'd0, disp_idx_sync};
                status_app_state <= {4'd0, app_state};
                status_app_target <= {4'd0, app_target_image};
                for (snapshot_index = 0; snapshot_index < 14; snapshot_index = snapshot_index + 1)
                    status_event_count[snapshot_index] <= event_count[snapshot_index];
                status_pending  <= 1'b0;
            end
        end else if (uart_tx_ready) begin
            if ((packet_payload == PAYLOAD_IMAGE_DATA) &&
                (tx_index >= 13) && (tx_index < 9 + packet_length) &&
                ((tx_index - 13) & 1'b1))
                thumbnail_read_addr <= thumbnail_read_addr + 1'b1;

            if ((tx_index >= 2) && (tx_index < 9 + packet_length))
                tx_crc <= crc16_next(tx_crc, uart_tx_data);

            if (tx_index == 10 + packet_length) begin
                tx_active <= 1'b0;
                tx_index  <= 6'd0;
                if (packet_payload == PAYLOAD_IMAGE_BEGIN) begin
                    thumbnail_phase <= THUMB_DATA;
                end else if (packet_payload == PAYLOAD_IMAGE_DATA) begin
                    if (thumbnail_chunk == IMAGE_CHUNKS - 1) begin
                        thumbnail_phase <= THUMB_END;
                    end else begin
                        thumbnail_chunk      <= thumbnail_chunk + 1'b1;
                        thumbnail_chunk_base <= thumbnail_chunk_base + IMAGE_WORDS_PER_CHUNK;
                    end
                end else if (packet_payload == PAYLOAD_IMAGE_END) begin
                    thumbnail_phase <= THUMB_IDLE;
                end
            end else begin
                tx_index <= tx_index + 1'b1;
            end
        end

        if (uart_rx_valid) begin
            case (rx_state)
                RX_SYNC0: begin
                    if (uart_rx_data == 8'hA5)
                        rx_state <= RX_SYNC1;
                end
                RX_SYNC1: begin
                    if (uart_rx_data == 8'h5A) begin
                        rx_state <= RX_VERSION;
                        rx_crc   <= 16'hFFFF;
                    end else if (uart_rx_data != 8'hA5) begin
                        rx_state <= RX_SYNC0;
                    end
                end
                RX_VERSION: begin
                    rx_version <= uart_rx_data;
                    rx_crc     <= crc16_next(16'hFFFF, uart_rx_data);
                    rx_state   <= RX_TYPE;
                end
                RX_TYPE: begin
                    rx_type  <= uart_rx_data;
                    rx_crc   <= crc16_next(rx_crc, uart_rx_data);
                    rx_state <= RX_FLAGS;
                end
                RX_FLAGS: begin
                    rx_flags <= uart_rx_data;
                    rx_crc   <= crc16_next(rx_crc, uart_rx_data);
                    rx_state <= RX_SEQ_LO;
                end
                RX_SEQ_LO: begin
                    rx_sequence[7:0] <= uart_rx_data;
                    rx_crc           <= crc16_next(rx_crc, uart_rx_data);
                    rx_state         <= RX_SEQ_HI;
                end
                RX_SEQ_HI: begin
                    rx_sequence[15:8] <= uart_rx_data;
                    rx_crc            <= crc16_next(rx_crc, uart_rx_data);
                    rx_state          <= RX_LEN_LO;
                end
                RX_LEN_LO: begin
                    rx_length[7:0] <= uart_rx_data;
                    rx_crc         <= crc16_next(rx_crc, uart_rx_data);
                    rx_state       <= RX_LEN_HI;
                end
                RX_LEN_HI: begin
                    rx_length[15:8] <= uart_rx_data;
                    rx_crc          <= crc16_next(rx_crc, uart_rx_data);
                    if ({uart_rx_data, rx_length[7:0]} == 16'd0) begin
                        rx_state <= RX_CRC_LO;
                    end else if ((uart_rx_data == 8'd0) &&
                                 (rx_length[7:0] <= MAX_CMD_PAYLOAD)) begin
                        rx_payload_count <= 16'd0;
                        rx_state         <= RX_PAYLOAD;
                    end else begin
                        rx_state <= RX_SYNC0;
                    end
                end
                RX_PAYLOAD: begin
                    rx_crc <= crc16_next(rx_crc, uart_rx_data);
                    if (rx_payload_count == 0)
                        rx_payload0 <= uart_rx_data;
                    if (rx_payload_count + 1'b1 == rx_length)
                        rx_state <= RX_CRC_LO;
                    else
                        rx_payload_count <= rx_payload_count + 1'b1;
                end
                RX_CRC_LO: begin
                    rx_crc_low <= uart_rx_data;
                    rx_state   <= RX_CRC_HI;
                end
                RX_CRC_HI: begin
                    if ((rx_crc == {uart_rx_data, rx_crc_low}) &&
                        (rx_version == PROTOCOL_VERSION)) begin
                        if ((rx_type == TYPE_PING) && !(rx_flags & FLAG_ACK)) begin
                            ping_pending  <= 1'b1;
                            ping_sequence <= rx_sequence;
                        end else if (rx_type == TYPE_GET_STATUS) begin
                            status_pending <= 1'b1;
                        end else if ((rx_type == TYPE_SET_BRIGHTNESS) &&
                                     (rx_length == 16'd1) &&
                                     ((rx_payload0 <= 8'd2) ||
                                      (rx_payload0 >= 8'hFE))) begin
                            video_brightness <= rx_payload0[2:0];
                            video_control_toggle <= ~video_control_toggle;
                            control_ack_pending <= 1'b1;
                            control_ack_type <= rx_type;
                            control_ack_sequence <= rx_sequence;
                        end else if ((rx_type == TYPE_SET_CONTRAST) &&
                                     (rx_length == 16'd1) &&
                                     (rx_payload0 <= 8'd3)) begin
                            video_contrast <= rx_payload0[1:0];
                            video_control_toggle <= ~video_control_toggle;
                            control_ack_pending <= 1'b1;
                            control_ack_type <= rx_type;
                            control_ack_sequence <= rx_sequence;
                        end else if ((rx_type == TYPE_SET_OSD) &&
                                     (rx_length == 16'd1)) begin
                            video_osd_enable <= rx_payload0[0];
                            video_subtitle_enable <= rx_payload0[1];
                            video_control_toggle <= ~video_control_toggle;
                            control_ack_pending <= 1'b1;
                            control_ack_type <= rx_type;
                            control_ack_sequence <= rx_sequence;
                        end else if (rx_type == TYPE_GET_THUMBNAIL) begin
                            if (!thumbnail_busy &&
                                (thumbnail_phase == THUMB_IDLE)) begin
                                thumbnail_request_toggle <=
                                    ~thumbnail_request_toggle;
                                thumbnail_busy <= 1'b1;
                            end else begin
                                thumbnail_drop_count <=
                                    thumbnail_drop_count + 1'b1;
                            end
                        end
                    end
                    rx_state <= RX_SYNC0;
                end
                default: rx_state <= RX_SYNC0;
            endcase
        end
    end
end

uart_rx #(
    .CLK_FRE   (CLK_FRE),
    .BAUD_RATE (BAUD_RATE)
) uart_rx_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .rx_data       (uart_rx_data),
    .rx_data_valid (uart_rx_valid),
    .rx_data_ready (1'b1),
    .rx_pin        (uart_rx_pin)
);

uart_tx #(
    .CLK_FRE   (CLK_FRE),
    .BAUD_RATE (BAUD_RATE)
) uart_tx_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .tx_data       (uart_tx_data),
    .tx_data_valid (uart_tx_valid),
    .tx_data_ready (uart_tx_ready),
    .tx_pin        (uart_tx_pin)
);

endmodule
