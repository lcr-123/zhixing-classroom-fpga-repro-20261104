`timescale 1ns/1ps

module tb_video_transition_blend;
    reg pixel_clk = 1'b0;
    reg pixel_rst = 1'b1;
    reg frame_boundary = 1'b0;
    reg in_de = 1'b0;
    reg [23:0] current_rgb;
    reg [23:0] next_rgb;
    reg transition_active;
    reg [4:0] transition_alpha;
    reg [1:0] transition_effect;
    wire [23:0] blended_rgb;
    integer alpha;
    integer expected;
    integer mismatch = 0;
    integer idle_case;
    integer a_value, b_value;
    integer reference_red, reference_green, reference_blue;

    always #5 pixel_clk = ~pixel_clk;

    video_transition_blend dut (
        .pixel_clk(pixel_clk),
        .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary),
        .in_de(in_de),
        .current_rgb(current_rgb),
        .next_rgb(next_rgb),
        .transition_active(transition_active),
        .transition_alpha(transition_alpha),
        .transition_effect(transition_effect),
        .blended_rgb(blended_rgb)
    );

    initial begin
        current_rgb = 24'h204060;
        next_rgb = 24'hA0C0E0;
        transition_active = 1'b0;
        transition_alpha = 5'd0;
        transition_effect = 2'd0;
        repeat (2) @(posedge pixel_clk);
        pixel_rst = 1'b0;
        #1;
        if (blended_rgb != current_rgb)
            $fatal(1, "inactive transition changed pixel");

        transition_active = 1'b1;
        transition_alpha = 5'd8;
        #1;
        if (blended_rgb != 24'h6080A0)
            $fatal(2, "half blend mismatch: %h", blended_rgb);

        current_rgb = 24'h000000;
        next_rgb = 24'hFFFFFF;
        transition_alpha = 5'd1;
        #1;
        if (blended_rgb != 24'h101010)
            $fatal(3, "rounded low-alpha blend mismatch: %h", blended_rgb);

        current_rgb = 24'h123456;
        next_rgb = 24'hFEDCBA;
        for (alpha = 0; alpha <= 16; alpha = alpha + 1) begin
            transition_alpha = alpha[4:0];
            #1;
            expected = ((((8'h12 * (16 - alpha)) + (8'hFE * alpha) + 8) >> 4) << 16) |
                       ((((8'h34 * (16 - alpha)) + (8'hDC * alpha) + 8) >> 4) << 8) |
                        (((8'h56 * (16 - alpha)) + (8'hBA * alpha) + 8) >> 4);
            if (blended_rgb != expected[23:0])
                mismatch = mismatch + 1;
        end

        current_rgb = 24'h000000;
        next_rgb = 24'hFFFFFF;
        transition_alpha = 5'd16;
        #1;
        if (blended_rgb != 24'hFFFFFF || mismatch != 0)
            $fatal(4, "full-alpha blend mismatch: %h", blended_rgb);

        // At coordinate (0,0), the first triangular shard has threshold 3.
        // It remains on the old picture at alpha 2 and flips at alpha 3.
        current_rgb = 24'h102030;
        next_rgb = 24'hA0B0C0;
        transition_effect = 2'd1;
        transition_alpha = 5'd2;
        #1;
        if (blended_rgb != current_rgb)
            $fatal(5, "shard revealed before its threshold: %h", blended_rgb);

        transition_alpha = 5'd3;
        #1;
        if (blended_rgb != next_rgb)
            $fatal(6, "shard did not reveal at its threshold: %h", blended_rgb);

        // Move to x=31,y=0, which lies on the same shard's diagonal crack.
        in_de = 1'b1;
        repeat (31) @(posedge pixel_clk);
        in_de = 1'b0;
        #1;
        if (blended_rgb != 24'hD8F4FF)
            $fatal(7, "shatter reveal-front highlight missing: %h", blended_rgb);

        transition_alpha = 5'd15;
        #1;
        if (blended_rgb != next_rgb)
            $fatal(8, "final shatter frame did not fully reveal target: %h", blended_rgb);

        // The practice page turn starts at x=616 on the top row for alpha 1:
        // old page, 12-pixel shadow, 3-pixel bright rim, then the new page.
        frame_boundary = 1'b1;
        @(posedge pixel_clk);
        frame_boundary = 1'b0;
        transition_effect = 2'd2;
        transition_alpha = 5'd1;
        #1;
        if (blended_rgb != current_rgb)
            $fatal(9, "page turn changed pixels before the moving edge");

        in_de = 1'b1;
        repeat (604) @(posedge pixel_clk);
        in_de = 1'b0;
        #1;
        if (blended_rgb != 24'h081018)
            $fatal(10, "page turn shadow mismatch: %h", blended_rgb);

        in_de = 1'b1;
        repeat (12) @(posedge pixel_clk);
        in_de = 1'b0;
        #1;
        if (blended_rgb != 24'hE8F2FF)
            $fatal(11, "page turn leading rim missing: %h", blended_rgb);

        in_de = 1'b1;
        repeat (3) @(posedge pixel_clk);
        in_de = 1'b0;
        #1;
        if (blended_rgb != next_rgb)
            $fatal(12, "new practice page did not enter from the right: %h", blended_rgb);

        // Previous-page turn mirrors the reveal: new pixels enter at x=0.
        frame_boundary = 1'b1;
        @(posedge pixel_clk);
        frame_boundary = 1'b0;
        transition_effect = 2'd3;
        transition_alpha = 5'd1;
        #1;
        if (blended_rgb != next_rgb)
            $fatal(13, "right page turn did not reveal from the left: %h", blended_rgb);
        in_de = 1'b1;
        repeat (22) @(posedge pixel_clk);
        in_de = 1'b0;
        #1;
        if (blended_rgb != 24'hE8F2FF)
            $fatal(14, "right page turn leading rim missing: %h", blended_rgb);
        in_de = 1'b1;
        repeat (3) @(posedge pixel_clk);
        in_de = 1'b0;
        #1;
        if (blended_rgb != 24'h081018)
            $fatal(15, "right page turn shadow mismatch: %h", blended_rgb);

        // Video and alpha continue to change outside transitions. All effect
        // selectors must keep both pixel operands and the fade result at zero.
        for (idle_case = 0; idle_case < 32; idle_case = idle_case + 1) begin
            transition_active = 1'b0;
            transition_effect = idle_case[1:0];
            transition_alpha = idle_case[4:0];
            current_rgb = 24'h010203 ^ (idle_case * 24'h011121);
            next_rgb = 24'hFEDCBA ^ (idle_case * 24'h010307);
            #1;
            if (dut.fade_current_rgb !== 24'd0 ||
                dut.fade_next_rgb !== 24'd0 ||
                dut.fade_rgb !== 24'd0)
                $fatal(16, "idle fade datapath still toggles");
            if (!transition_active && blended_rgb !== current_rgb)
                $fatal(17, "inactive transition changed output");
        end

        transition_active = 1'b1;
        transition_effect = 2'd0;
        transition_alpha = 5'd8;
        current_rgb = 24'h204060;
        next_rgb = 24'hA0C0E0;
        #1;
        if (blended_rgb !== 24'h6080A0)
            $fatal(18, "fade did not resume after other effects");

        // Exhaust all channel pairs and production alpha values. Three
        // different channel mappings also catch channel wiring mistakes.
        for (a_value = 0; a_value < 256; a_value = a_value + 1)
            for (b_value = 0; b_value < 256; b_value = b_value + 1)
                for (alpha = 0; alpha <= 16; alpha = alpha + 1) begin
                    current_rgb = {a_value[7:0], b_value[7:0], ~a_value[7:0]};
                    next_rgb = {b_value[7:0], a_value[7:0], ~b_value[7:0]};
                    transition_alpha = alpha[4:0];
                    #1;
                    reference_red = (a_value * (16-alpha) + b_value * alpha + 8) / 16;
                    reference_green = (b_value * (16-alpha) + a_value * alpha + 8) / 16;
                    reference_blue = ((255-a_value) * (16-alpha) + (255-b_value) * alpha + 8) / 16;
                    if (blended_rgb !== {reference_red[7:0], reference_green[7:0], reference_blue[7:0]})
                        $fatal(19, "fade pixel mismatch a=%0d b=%0d alpha=%0d", a_value,b_value,alpha);
                end
        $display("LOW_POWER_CHECK fade_idle_pixel_operands=constant exhaustive_rgb_cases=1114112");

        $display("TEST_PASS tb_video_transition_blend");
        $finish;
    end
endmodule
