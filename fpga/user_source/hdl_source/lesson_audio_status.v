`timescale 1ns/1ps

// Application-only observer. Neither clock domain can stall PCM or video.
module lesson_audio_status (
    input wire audio_clk, audio_rst,
    input wire source_start_toggle,
    input wire source_stop_toggle,
    input wire [31:0] source_total,
    input wire [1:0] source_clip,
    input wire consume,
    input wire [1:0] consume_step,
    output reg played_to_end,
    input wire pixel_clk, pixel_rst, frame_boundary,
    output reg [8:0] progress,
    output reg [1:0] clip,
    output reg valid
);
reg [2:0] start_sync /* fehdl keep="true" */;
reg start_seen;
reg [2:0] stop_sync /* fehdl keep="true" */;
reg stop_seen;
reg [3:0] start_warmup;
reg [31:0] total_meta /* fehdl keep="true" */;
reg [31:0] total_sync /* fehdl keep="true" */;
reg [1:0] clip_meta /* fehdl keep="true" */;
reg [1:0] clip_sync /* fehdl keep="true" */;
reg [21:0] total, count;
reg [22:0] remainder;
reg [8:0] fraction;
reg [1:0] audio_clip;
reg audio_valid;
wire [21:0] completion_threshold =
    (total > 22'd16) ? total - 22'd16 : total;
always @(posedge audio_clk) begin
    if (audio_rst) begin
        start_sync <= 0; start_seen <= 0; start_warmup <= 0;
        stop_sync <= 0; stop_seen <= 0;
        total_meta <= 0; total_sync <= 0;
        clip_meta <= 0; clip_sync <= 0;
        total <= 0; count <= 0; remainder <= 0; fraction <= 0;
        audio_clip <= 0; audio_valid <= 0;
        played_to_end <= 0;
    end else begin
        start_sync <= {start_sync[1:0],source_start_toggle};
        stop_sync <= {stop_sync[1:0],source_stop_toggle};
        stop_seen <= stop_sync[2];
        start_warmup <= {start_warmup[2:0],1'b1};
        total_meta <= source_total; total_sync <= total_meta;
        clip_meta <= source_clip; clip_sync <= clip_meta;
        if (!start_warmup[3]) begin
            start_seen <= start_sync[2];
        end else if (stop_sync[2] != stop_seen) begin
            start_seen <= start_sync[2];
            audio_valid <= 0;
            count <= 0; remainder <= 0; fraction <= 0;
            played_to_end <= 0;
        end else if (start_sync[2] != start_seen) begin
            start_seen <= start_sync[2];
            total <= total_sync[21:0]; count <= 0;
            remainder <= 0; fraction <= 0; audio_clip <= clip_sync;
            audio_valid <= (total_sync != 0 && total_sync <= 4000000);
            played_to_end <= 0;
        end else if (audio_valid) begin
            // Even the fastest legacy reads are 512 mclk cycles apart;
            // repeated subtraction needs at most 256 for a 1-byte clip.
            if (consume && consume_step != 0 && count < total) begin
                if (count + consume_step >= completion_threshold)
                    played_to_end <= 1'b1;
                if (count + consume_step >= total)
                    count <= total;
                else
                    count <= count + consume_step;
                remainder <= remainder + {13'd0,consume_step,8'd0};
            end else if (remainder >= {1'b0,total} && fraction < 9'd256) begin
                remainder <= remainder - {1'b0,total};
                fraction <= fraction + 1'b1;
            end
        end
    end
end

// Video requests at most one snapshot per frame. Payload stays unchanged
// until the next request; ACK crosses three stages, payload crosses two.
wire mailbox_rst = audio_rst | pixel_rst;
reg request /* fehdl keep="true" */;
reg [2:0] request_sync /* fehdl keep="true" */;
reg ack /* fehdl keep="true" */;
reg [11:0] mailbox /* fehdl keep="true" */;
always @(posedge audio_clk or posedge mailbox_rst) begin
    if (mailbox_rst) begin request_sync <= 0; ack <= 0; mailbox <= 0; end
    else begin
        request_sync <= {request_sync[1:0],request};
        if (request_sync[2] != ack) begin
            mailbox <= {audio_valid,audio_clip,fraction};
            ack <= request_sync[2];
        end
    end
end
reg [2:0] ack_sync /* fehdl keep="true" */;
reg [11:0] payload_meta /* fehdl keep="true" */;
reg [11:0] payload_sync /* fehdl keep="true" */;
always @(posedge pixel_clk or posedge mailbox_rst) begin
    if (mailbox_rst) begin
        request <= 0; ack_sync <= 0; payload_meta <= 0; payload_sync <= 0;
        progress <= 0; clip <= 0; valid <= 0;
    end else begin
        ack_sync <= {ack_sync[1:0],ack};
        payload_meta <= mailbox; payload_sync <= payload_meta;
        if (frame_boundary && ack_sync[2] == request) begin
            {valid,clip,progress} <= payload_sync;
            request <= ~request;
        end
    end
end
endmodule
