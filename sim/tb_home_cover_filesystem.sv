`timescale 1ns/1ps
module tb_home_cover_filesystem;
    tb_fat32_filesystem #(.HOME_TEST(1)) fixture();
    integer home_count = 0;
    integer mode;
    integer expected_home;
    always @(posedge fixture.clk)
        if (fixture.file_found_valid && fixture.file_found_index == 12) begin
            home_count <= home_count + 1;
            if (fixture.file_found_cluster != 30 || fixture.file_found_size != 1024)
                $fatal(1, "invalid cover metadata published");
        end
    initial begin
        fixture.reset_dut();
        for (mode = 1; mode <= 6; mode = mode + 1) begin
            @(negedge fixture.clk);
            fixture.home_mode = mode == 6 ? 0 : mode;
            fixture.simultaneous_end = mode[0];
            fixture.found_count = 0;
            home_count = 0;
            fixture.pulse_scanner_start();
            fixture.wait_scanner_done();
            repeat (3) @(negedge fixture.clk);
            expected_home = mode <= 2 ? 1 : 0;
            if (fixture.scanner_error != 0 || fixture.file_found_mask != 12'hfff ||
                fixture.found_count != 12 + expected_home || home_count != expected_home ||
                fixture.bridge_metadata_mask != (expected_home ? 13'h1fff : 13'h0fff))
                $fatal(1, "cover scan mode=%0d error=%02x count=%0d home=%0d mask=%04x",
                       mode, fixture.scanner_error, fixture.found_count,
                       home_count, fixture.bridge_metadata_mask);
            if (expected_home) begin
                fixture.run_virtual_sector(32'h80c00000, 0);
                fixture.run_virtual_sector(32'h80c00001, 512);
                fixture.run_virtual_error(32'h80c00002);
            end else fixture.run_virtual_error(32'h80c00000);
            fixture.run_virtual_error(32'h80d00000);
            fixture.run_virtual_sector(32'h80000000, 0);
        end
        if (fixture.error_count != 0) $fatal(1, "filesystem cover errors");
        $display("TEST_PASS tb_home_cover_filesystem: late/duplicate/bad/missing cover, EOC, rescan, virtual bounds");
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1, "home filesystem timeout");
    end
endmodule
