`timescale 1ns/1ps

module tb_audio_waveform_read_ce;
    reg pixel_clk = 1'b0;
    reg pixel_rst = 1'b1;
    reg frame_boundary = 1'b0;
    reg in_hs = 1'b0;
    reg in_vs = 1'b0;
    reg in_de = 1'b0;
    reg [23:0] in_rgb = 24'd0;
    reg overlay_enable = 1'b0;
    reg [3:0] theme_index = 4'd0;
    reg audio_valid = 1'b0;
    reg [23:0] audio_sample = 24'd0;
    wire gated_hs, gated_vs, gated_de;
    wire [23:0] gated_rgb;
    wire reference_hs, reference_vs, reference_de;
    wire [23:0] reference_rgb;
    integer read_count = 0;
    integer frame_cycles = 0;
    reg count_frame = 1'b0;
    reg compare_outputs = 1'b0;
    integer x, y, n;

    always #5 pixel_clk = ~pixel_clk;

    audio_waveform_overlay gated (
        .pixel_clk(pixel_clk), .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary), .in_hs(in_hs), .in_vs(in_vs),
        .in_de(in_de), .in_rgb(in_rgb), .overlay_enable(overlay_enable),
        .theme_index(theme_index), .audio_valid(audio_valid),
        .audio_sample(audio_sample), .out_hs(gated_hs),
        .out_vs(gated_vs), .out_de(gated_de), .out_rgb(gated_rgb)
    );
    audio_waveform_overlay #(.GATE_SAMPLE_READ(0)) reference (
        .pixel_clk(pixel_clk), .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary), .in_hs(in_hs), .in_vs(in_vs),
        .in_de(in_de), .in_rgb(in_rgb), .overlay_enable(overlay_enable),
        .theme_index(theme_index), .audio_valid(audio_valid),
        .audio_sample(audio_sample), .out_hs(reference_hs),
        .out_vs(reference_vs), .out_de(reference_de), .out_rgb(reference_rgb)
    );

    always @(posedge pixel_clk) begin
        if (count_frame) begin
            frame_cycles = frame_cycles + 1;
            if (gated.sample_read_enable)
                read_count = read_count + 1;
            if (gated.sample_read_enable && (!in_de || !gated.frame_overlay_enable))
                $fatal(1, "RAM read during blanking or inactive page");
        end
    end

    always @(negedge pixel_clk) begin
        if (compare_outputs &&
            {gated_hs, gated_vs, gated_de, gated_rgb} !==
            {reference_hs, reference_vs, reference_de, reference_rgb})
            $fatal(1, "gated waveform differs from continuous read at cycle %0d", frame_cycles);
    end

    task automatic pulse_boundary;
        begin
            @(negedge pixel_clk);
            frame_boundary = 1'b1;
            @(negedge pixel_clk);
            frame_boundary = 1'b0;
        end
    endtask

    task automatic full_frame(input integer expected_reads);
        begin
            read_count = 0;
            frame_cycles = 0;
            for (y = 0; y < 525; y = y + 1) begin
                for (x = 0; x < 800; x = x + 1) begin
                    @(negedge pixel_clk);
                    count_frame = 1'b1;
                    in_de = (y < 480 && x < 640);
                    in_hs = (x < 96);
                    in_vs = (y < 2);
                    in_rgb = {x[7:0], y[7:0], (x + y) & 8'hff};
                    audio_valid = (x == 100 && (y % 13) == 0);
                    audio_sample = {y[7:0], x[7:0], 8'h55};
                end
            end
            @(posedge pixel_clk);
            #1;
            count_frame = 1'b0;
            audio_valid = 1'b0;
            if (frame_cycles != 800 * 525 || read_count != expected_reads)
                $fatal(1, "read count %0d/%0d, frame cycles %0d, enable=%b y=%0d base=%0d",
                       read_count, expected_reads, frame_cycles,
                       gated.frame_overlay_enable, gated.pixel_y, gated.sample_read_base);
        end
    endtask

    initial begin
        repeat (3) @(negedge pixel_clk);
        pixel_rst = 1'b0;
        for (n = 0; n < 256; n = n + 1) begin
            @(negedge pixel_clk);
            audio_valid = 1'b1;
            audio_sample = {n[7:0], 8'h40, 8'h00};
        end
        @(negedge pixel_clk);
        audio_valid = 1'b0;
        compare_outputs = 1'b1;

        pulse_boundary();
        full_frame(0);
        overlay_enable = 1'b1;
        theme_index = 4'd1;
        pulse_boundary();
        full_frame(640 * 32);
        pulse_boundary();
        overlay_enable = 1'b0;
        full_frame(640 * 32); // Page changes only at the next frame boundary.
        pulse_boundary();
        full_frame(0);

        @(negedge pixel_clk);
        pixel_rst = 1'b1;
        repeat (3) @(negedge pixel_clk);
        pixel_rst = 1'b0;
        pulse_boundary();
        full_frame(0);
        $display("TEST_PASS tb_audio_waveform_read_ce: full-frame 0/20480 reads, pixel equivalence, frame commit and reset");
        $finish;
    end

    initial begin
        #30000000;
        $fatal(1, "test timeout");
    end
endmodule
