`timescale 1ns/1ps

module tb_clock_reset_manager;
    reg ref_clk = 1'b0;
    reg sd_clk = 1'b0;
    reg mem_clk = 1'b0;
    reg video_clk = 1'b0;
    reg hdmi_5x_clk = 1'b0;
    reg audio_clk = 1'b0;
    reg ext_rst_n = 1'b0;
    reg sys_pll_lock = 1'b0;
    reg video_pll_lock = 1'b0;
    reg audio_pll_lock = 1'b0;
    wire ref_rst;
    wire sd_rst;
    wire mem_rst;
    wire video_rst;
    wire hdmi_5x_rst;
    wire audio_rst;

    always #10 ref_clk = ~ref_clk;
    always #5 sd_clk = ~sd_clk;
    always #4 mem_clk = ~mem_clk;
    always #20 video_clk = ~video_clk;
    always #4 hdmi_5x_clk = ~hdmi_5x_clk;
    always #41 audio_clk = ~audio_clk;

    clock_reset_manager #(
        .STABLE_CYCLES(4),
        .COUNTER_WIDTH(2)
    ) dut (
        .ref_clk(ref_clk),
        .ext_rst_n(ext_rst_n),
        .sys_pll_lock(sys_pll_lock),
        .video_pll_lock(video_pll_lock),
        .audio_pll_lock(audio_pll_lock),
        .sd_clk(sd_clk),
        .mem_clk(mem_clk),
        .video_clk(video_clk),
        .hdmi_5x_clk(hdmi_5x_clk),
        .audio_clk(audio_clk),
        .ref_rst(ref_rst),
        .sd_rst(sd_rst),
        .mem_rst(mem_rst),
        .video_rst(video_rst),
        .hdmi_5x_rst(hdmi_5x_rst),
        .audio_rst(audio_rst)
    );

    initial begin
        repeat (3) @(posedge ref_clk);
        ext_rst_n = 1'b1;
        sys_pll_lock = 1'b1;
        video_pll_lock = 1'b1;
        repeat (5) @(posedge ref_clk);
        if (!ref_rst || !sd_rst || !mem_rst || !video_rst ||
            !hdmi_5x_rst || !audio_rst)
            $fatal(1, "reset released before all PLLs locked");

        audio_pll_lock = 1'b1;
        wait (!ref_rst && !sd_rst && !mem_rst && !video_rst &&
              !hdmi_5x_rst && !audio_rst);

        @(negedge ref_clk);
        #3 video_pll_lock = 1'b0;
        #1;
        if (!ref_rst || !sd_rst || !mem_rst || !video_rst ||
            !hdmi_5x_rst || !audio_rst)
            $fatal(2, "PLL lock loss did not asynchronously assert every domain reset");

        video_pll_lock = 1'b1;
        repeat (3) @(posedge ref_clk);
        if (!ref_rst)
            $fatal(3, "stable interval was shorter than configured");
        wait (!ref_rst && !sd_rst && !mem_rst && !video_rst &&
              !hdmi_5x_rst && !audio_rst);

        $display("TEST_PASS tb_clock_reset_manager");
        $finish;
    end
endmodule
