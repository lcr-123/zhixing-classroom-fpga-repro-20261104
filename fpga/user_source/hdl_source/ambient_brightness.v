// H-resolution MTreg=69: raw = lux * 1.2. Compare in raw units: no divider.
// Five levels, 20% boundary hysteresis, three consecutive samples per step.
module ambient_brightness #(
    parameter integer STALE_CYCLES=75_000_000,
    parameter integer CONFIRM_SAMPLES=3
) (
    input wire clk, rst,
    input wire [15:0] sample_raw,
    input wire sample_valid, sensor_valid, watchdog_tick,
    output reg signed [2:0] level,
    output wire valid,
    output reg [15:0] filtered_raw
);
// STALE_CYCLES counts watchdog enables (production: one every 5 us).
localparam integer STALE_WIDTH=STALE_CYCLES<=1 ? 1 : $clog2(STALE_CYCLES);
localparam integer CONFIRM_WIDTH=CONFIRM_SAMPLES<=1 ? 1 : $clog2(CONFIRM_SAMPLES+1);
reg [STALE_WIDTH-1:0] stale_count;
reg initialized;
reg [CONFIRM_WIDTH-1:0] confirmation;
reg direction_up;
reg signed [2:0] next_level;
wire [17:0] filter_sum={2'b0,filtered_raw}+{1'b0,filtered_raw,1'b0}+
    {2'b0,sample_raw}+18'd2;
wire [15:0] filtered_next=initialized ? filter_sum[17:2] : sample_raw;
assign valid=sensor_valid && initialized && (stale_count<STALE_CYCLES-1);
always @* begin
    next_level=level;
    case (level)
        -3'sd2: if (filtered_next>72) next_level=-3'sd1;
        -3'sd1: if (filtered_next<48) next_level=-3'sd2;
                  else if (filtered_next>216) next_level=0;
         3'sd0: if (filtered_next<144) next_level=-3'sd1;
                  else if (filtered_next>576) next_level=1;
         3'sd1: if (filtered_next<384) next_level=0;
                  else if (filtered_next>1440) next_level=2;
         3'sd2: if (filtered_next<960) next_level=1;
        default: next_level=0;
    endcase
end
always @(posedge clk) begin
    if (rst) begin
        level<=0; filtered_raw<=0; initialized<=0; stale_count<=0;
        confirmation<=0; direction_up<=0;
    end else if (!sensor_valid || (stale_count>=STALE_CYCLES-1 && !sample_valid)) begin
        initialized<=0; level<=0; stale_count<=0; confirmation<=0;
    end else if (sample_valid) begin
        stale_count<=0; initialized<=1; filtered_raw<=filtered_next;
        if (next_level==level) confirmation<=0;
        else if (CONFIRM_SAMPLES<=1 ||
                 (confirmation>=CONFIRM_SAMPLES-1 && direction_up==(next_level>level))) begin
            level<=next_level; confirmation<=0;
        end else begin
            confirmation<=(confirmation!=0 && direction_up==(next_level>level)) ?
                confirmation+1'b1 : 4'd1;
            direction_up<=next_level>level;
        end
    end else if (watchdog_tick && stale_count<STALE_CYCLES-1)
        stale_count<=stale_count+1'b1;
end
endmodule
