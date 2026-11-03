// Independent, open-drain BH1750 bus. No connection to HDMI DDC or ready.
// Default tick is 5 us: four phases/bit give a conservative 50 kHz bus.
module bh1750_i2c #(
    parameter integer TICK_CYCLES = 250,
    parameter integer TIMEOUT_TICKS = 1000,
    parameter [6:0] ADDRESS = 7'h23
) (
    input wire clk, rst, start, read_mode,
    input wire [7:0] command,
    inout wire scl, sda,
    output wire tick,
    output reg busy, done, error,
    output reg [15:0] result
);
reg scl_low, sda_low;
assign scl = scl_low ? 1'b0 : 1'bz;
assign sda = sda_low ? 1'b0 : 1'bz;
reg scl_meta, scl_sync, sda_meta, sda_sync;
localparam integer DIV_WIDTH=TICK_CYCLES<=1 ? 1 : $clog2(TICK_CYCLES);
localparam integer TIMEOUT_WIDTH=TIMEOUT_TICKS<=1 ? 1 : $clog2(TIMEOUT_TICKS+1);
reg [DIV_WIDTH-1:0] divider;
reg [TIMEOUT_WIDTH-1:0] timeout_count;
assign tick=(divider==TICK_CYCLES-1);
reg [4:0] state;
reg [7:0] shift;
reg [2:0] bit_index;
reg [1:0] byte_index;
reg reading;
reg [7:0] opcode;
reg [3:0] recovery_count;
localparam IDLE=0, START_A=1, START_B=2, BIT_LOW=3, BIT_RISE=4,
    BIT_WAIT=5, BIT_FALL=6, ACK_LOW=7, ACK_RISE=8, ACK_WAIT=9,
    ACK_FALL=10, STOP_LOW=11, STOP_RISE=12, STOP_WAIT=13,
    STOP_RELEASE=14, REC_LOW=15, REC_RISE=16, REC_WAIT=17, REC_FALL=18;
wire receiving = reading && (byte_index != 0);
// One free-running enable also clocks the long measurement/watchdog timers.
// It is an enable in clk's domain, never a generated/gated clock.
always @(posedge clk) begin
    if (rst || tick) divider<=0;
    else divider<=divider+1'b1;
end
always @(posedge clk) begin
    if (rst) begin
        scl_meta<=1; scl_sync<=1; sda_meta<=1; sda_sync<=1;
    end else begin
        scl_meta<=scl; scl_sync<=scl_meta;
        sda_meta<=sda; sda_sync<=sda_meta;
    end
end
always @(posedge clk) begin
    if (rst) begin
        state<=IDLE; timeout_count<=0;
        scl_low<=0; sda_low<=0; busy<=0; done<=0; error<=0;
        result<=0; shift<=0; bit_index<=7; byte_index<=0;
        reading<=0; opcode<=0; recovery_count<=0;
    end else begin
        done<=0;
        if (state == IDLE) begin
            timeout_count<=0;
            if (start) begin
                busy<=1; error<=0; result<=0; reading<=read_mode;
                opcode<=command; byte_index<=0; bit_index<=7;
                shift<={ADDRESS,read_mode}; recovery_count<=0;
                state<=START_A;
            end
        end else if (tick) begin
            // Stretching and a held-low clock always have a bounded exit.
            if (!scl_low && !scl_sync) timeout_count<=timeout_count+1'b1;
            else timeout_count<=0;
            if (timeout_count >= TIMEOUT_TICKS-1) begin
                scl_low<=0; sda_low<=0; busy<=0;
                done<=1; error<=1; state<=IDLE;
            end else case (state)
                START_A: begin
                    if (scl_sync) begin
                        if (!sda_sync) begin error<=1; state<=REC_LOW; end
                        else begin sda_low<=1; state<=START_B; end
                    end
                end
                START_B: begin scl_low<=1; state<=BIT_LOW; end
                BIT_LOW: begin
                    sda_low<=receiving ? 1'b0 : !shift[bit_index];
                    state<=BIT_RISE;
                end
                BIT_RISE: begin scl_low<=0; state<=BIT_WAIT; end
                BIT_WAIT: if (scl_sync) state<=BIT_FALL;
                BIT_FALL: begin
                    if (receiving) shift[bit_index]<=sda_sync;
                    scl_low<=1;
                    if (bit_index==0) state<=ACK_LOW;
                    else begin bit_index<=bit_index-1'b1; state<=BIT_LOW; end
                end
                ACK_LOW: begin
                    // Read high byte ACK, final low byte NACK. TX releases SDA.
                    sda_low<=receiving && (byte_index==1);
                    if (receiving) begin
                        if (byte_index==1) result[15:8]<=shift;
                        else result[7:0]<=shift;
                    end
                    state<=ACK_RISE;
                end
                ACK_RISE: begin scl_low<=0; state<=ACK_WAIT; end
                ACK_WAIT: if (scl_sync) state<=ACK_FALL;
                ACK_FALL: begin
                    scl_low<=1;
                    if (!receiving && sda_sync) begin error<=1; state<=STOP_LOW; end
                    else if ((!reading && byte_index==1) ||
                             (reading && byte_index==2)) state<=STOP_LOW;
                    else begin
                        byte_index<=byte_index+1'b1; bit_index<=7;
                        shift<=opcode; state<=BIT_LOW;
                    end
                end
                STOP_LOW: begin sda_low<=1; scl_low<=1; state<=STOP_RISE; end
                STOP_RISE: begin scl_low<=0; state<=STOP_WAIT; end
                STOP_WAIT: if (scl_sync) state<=STOP_RELEASE;
                STOP_RELEASE: begin
                    sda_low<=0; busy<=0; done<=1; state<=IDLE;
                end
                REC_LOW: begin scl_low<=1; sda_low<=0; state<=REC_RISE; end
                REC_RISE: begin scl_low<=0; state<=REC_WAIT; end
                REC_WAIT: if (scl_sync) state<=REC_FALL;
                REC_FALL: begin
                    scl_low<=1;
                    if (recovery_count==8) state<=STOP_LOW;
                    else begin recovery_count<=recovery_count+1'b1; state<=REC_LOW; end
                end
                default: begin
                    scl_low<=0; sda_low<=0; busy<=0; done<=1;
                    error<=1; state<=IDLE;
                end
            endcase
        end
    end
end
endmodule

module bh1750_reader #(
    parameter integer TICK_CYCLES=250,
    parameter integer TIMEOUT_TICKS=1000,
    parameter integer POWERUP_CYCLES=2_500_000,
    parameter integer MEASURE_CYCLES=10_000_000,
    parameter [6:0] ADDRESS=7'h23
) (
    input wire clk, rst,
    inout wire scl, sda,
    output reg [15:0] sample_raw,
    output reg sample_valid,
    output reg sensor_valid,
    output wire watchdog_tick,
    output reg [15:0] error_count
);
localparam integer POWERUP_TICKS=(POWERUP_CYCLES+TICK_CYCLES-1)/TICK_CYCLES;
localparam integer MEASURE_TICKS=(MEASURE_CYCLES+TICK_CYCLES-1)/TICK_CYCLES;
localparam integer MAX_TICKS=POWERUP_TICKS>MEASURE_TICKS ? POWERUP_TICKS : MEASURE_TICKS;
localparam integer DELAY_WIDTH=MAX_TICKS<=1 ? 1 : $clog2(MAX_TICKS+1);
reg [DELAY_WIDTH-1:0] delay_count;
reg [2:0] state;
reg [2:0] init_index;
reg start, read_mode;
reg [7:0] command;
wire busy, done, error;
wire [15:0] result;
localparam DELAY=0, ISSUE=1, WAIT_DONE=2, CONVERT=3, READ=4;
bh1750_i2c #(.TICK_CYCLES(TICK_CYCLES),.TIMEOUT_TICKS(TIMEOUT_TICKS),
    .ADDRESS(ADDRESS)) bus (
    .clk(clk),.rst(rst),.start(start),.read_mode(read_mode),.command(command),
    .scl(scl),.sda(sda),.tick(watchdog_tick),
    .busy(busy),.done(done),.error(error),.result(result));
always @(posedge clk) begin
    if (rst) begin
        state<=DELAY; delay_count<=POWERUP_TICKS; init_index<=0;
        start<=0; read_mode<=0; command<=0;
        sample_raw<=0; sample_valid<=0; sensor_valid<=0; error_count<=0;
    end else begin
        start<=0; sample_valid<=0;
        case (state)
            DELAY: if (watchdog_tick) begin
                if (delay_count==0) state<=ISSUE;
                else delay_count<=delay_count-1'b1;
            end
            ISSUE: if (!busy) begin
                // Every opcode is a separate transaction with its own STOP.
                // Explicit MTreg=69 avoids retaining an earlier measurement time.
                case (init_index)
                    0: command<=8'h01;
                    1: command<=8'h07;
                    2: command<=8'h42;
                    3: command<=8'h65;
                    default: command<=8'h20;
                endcase
                read_mode<=0; start<=1; state<=WAIT_DONE;
            end
            WAIT_DONE: if (done) begin
                if (error) begin
                    sensor_valid<=0;
                    if (error_count!=16'hffff) error_count<=error_count+1'b1;
                    init_index<=0; delay_count<=MEASURE_TICKS; state<=DELAY;
                end else if (read_mode) begin
                    sample_raw<=result; sample_valid<=1; sensor_valid<=1;
                    init_index<=4; state<=ISSUE;
                end else if (init_index==4) begin
                    // Load the ceiling, not ceiling-1: the first enable may
                    // arrive just after STOP. Never shorten the datasheet wait.
                    delay_count<=MEASURE_TICKS; state<=CONVERT;
                end else begin init_index<=init_index+1'b1; state<=ISSUE; end
            end
            CONVERT: if (watchdog_tick) begin
                if (delay_count==0) state<=READ;
                else delay_count<=delay_count-1'b1;
            end
            READ: if (!busy) begin read_mode<=1; start<=1; state<=WAIT_DONE; end
            default: begin state<=DELAY; init_index<=0; sensor_valid<=0;
                delay_count<=POWERUP_TICKS; end
        endcase
    end
end
endmodule
