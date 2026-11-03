`timescale 1ns/1ps

module clock_reset_manager #(
    parameter integer STABLE_CYCLES = 1024,
    parameter integer COUNTER_WIDTH = 10
) (
    input  wire ref_clk,
    input  wire ext_rst_n,
    input  wire sys_pll_lock,
    input  wire video_pll_lock,
    input  wire audio_pll_lock,
    input  wire sd_clk,
    input  wire mem_clk,
    input  wire video_clk,
    input  wire hdmi_5x_clk,
    input  wire audio_clk,
    output wire ref_rst,
    output wire sd_rst,
    output wire mem_rst,
    output wire video_rst,
    output wire hdmi_5x_rst,
    output wire audio_rst
);

reg [COUNTER_WIDTH-1:0] stable_count;
// This is the single source for every domain's reset-release synchronizer.
// Preserve it so physical optimization cannot equivalence-merge the source
// into an arbitrary application register and create a false recovery path.
reg stable_ready /* fehdl keep="true" */;
reg [2:0] ref_release /* fehdl keep="true" */;
reg [2:0] sd_release /* fehdl keep="true" */;
reg [2:0] mem_release /* fehdl keep="true" */;
reg [2:0] video_release /* fehdl keep="true" */;
reg [2:0] hdmi_5x_release /* fehdl keep="true" */;
reg [2:0] audio_release /* fehdl keep="true" */;

wire all_locked = sys_pll_lock && video_pll_lock && audio_pll_lock;
wire stable_reset_n = ext_rst_n && all_locked;

always @(posedge ref_clk or negedge stable_reset_n) begin
    if (!stable_reset_n) begin
        stable_count <= {COUNTER_WIDTH{1'b0}};
        stable_ready <= 1'b0;
    end else if (!stable_ready) begin
        if (stable_count == STABLE_CYCLES - 1) begin
            stable_ready <= 1'b1;
        end else begin
            stable_count <= stable_count + 1'b1;
        end
    end
end

always @(posedge ref_clk or negedge stable_ready) begin
    if (!stable_ready)
        ref_release <= 3'b000;
    else
        ref_release <= {ref_release[1:0], 1'b1};
end

always @(posedge sd_clk or negedge stable_ready) begin
    if (!stable_ready)
        sd_release <= 3'b000;
    else
        sd_release <= {sd_release[1:0], 1'b1};
end

always @(posedge mem_clk or negedge stable_ready) begin
    if (!stable_ready)
        mem_release <= 3'b000;
    else
        mem_release <= {mem_release[1:0], 1'b1};
end

always @(posedge video_clk or negedge stable_ready) begin
    if (!stable_ready)
        video_release <= 3'b000;
    else
        video_release <= {video_release[1:0], 1'b1};
end

always @(posedge hdmi_5x_clk or negedge stable_ready) begin
    if (!stable_ready)
        hdmi_5x_release <= 3'b000;
    else
        hdmi_5x_release <= {hdmi_5x_release[1:0], 1'b1};
end

always @(posedge audio_clk or negedge stable_ready) begin
    if (!stable_ready)
        audio_release <= 3'b000;
    else
        audio_release <= {audio_release[1:0], 1'b1};
end

assign ref_rst   = ~ref_release[2];
assign sd_rst    = ~sd_release[2];
assign mem_rst   = ~mem_release[2];
assign video_rst = ~video_release[2];
assign hdmi_5x_rst = ~hdmi_5x_release[2];
assign audio_rst = ~audio_release[2];

endmodule
