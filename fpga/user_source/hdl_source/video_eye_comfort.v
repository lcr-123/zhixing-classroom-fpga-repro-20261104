`timescale 1ns/1ps

// Final pixel stage. enable is committed in vertical blank by the OSD state
// controller. R is unchanged, G loses floor(G/16), B loses floor(B/4).
// No multipliers, clipping, frame storage, or backpressure.
module video_eye_comfort (
    input wire pixel_clk,
    input wire pixel_rst,
    input wire enable,
    input wire in_hs,
    input wire in_vs,
    input wire in_de,
    input wire [23:0] in_rgb,
    output reg out_hs,
    output reg out_vs,
    output reg out_de,
    output reg [23:0] out_rgb
);
wire [7:0] green = in_rgb[15:8] - {4'd0, in_rgb[15:12]};
wire [7:0] blue = in_rgb[7:0] - {2'd0, in_rgb[7:2]};
always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        out_hs <= 1'b0;
        out_vs <= 1'b0;
        out_de <= 1'b0;
        out_rgb <= 24'd0;
    end else begin
        out_hs <= in_hs;
        out_vs <= in_vs;
        out_de <= in_de;
        out_rgb <= !in_de ? 24'd0 :
                   enable ? {in_rgb[23:16], green, blue} : in_rgb;
    end
end
endmodule
