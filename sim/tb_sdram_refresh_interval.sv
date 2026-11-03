`timescale 1ns/1ps
`include "global_def.v"

module tb_sdram_refresh_interval;
    localparam integer REFRESH_INTERVAL = `SELF_REFRESH_INTERVAL;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst = 1;
    reg ack = 0;
    reg busy = 0;
    reg app_ref = 0;
    wire init_done, req, refresh_active;
    sdr_init_ref dut (
        .Sdr_clk(clk), .Rst(rst), .Sdr_init_req(1'b0),
        .Sdr_init_mode(4'd0), .Sdr_init_done(init_done),
        .App_ref_req(app_ref), .Sdr_ref_req(req), .Sdr_ref_ack(ack),
        .Sdr_rw_vld(busy), .Sdr_init_ref_vld(refresh_active),
        .Sdr_init_ref_ras(), .Sdr_init_ref_cas(), .Sdr_init_ref_we(),
        .Sdr_init_ref_ba(), .Sdr_init_ref_addr()
    );
    integer cycles = 0;
    integer last_request = -1;
    integer requests = 0;
    reg previous_req = 0;
    always @(negedge clk) begin
        if (!rst && init_done) begin
            cycles = cycles + 1;
            if (req) begin
                if (previous_req)
                    $fatal(1, "Refresh request wider than one cycle");
                if (last_request >= 0 && cycles - last_request != 3907)
                    $fatal(1, "Refresh spacing %0d, expected 3907", cycles - last_request);
                last_request = cycles;
                requests = requests + 1;
            end
            previous_req = req;
            // Model an idle controller accepting a request. The physical
            // command encoder and SDRAM array are outside this test.
            ack = req;
        end else begin
            ack = 0;
            previous_req = 0;
        end
    end
    initial begin
        if (`SDR_CLK_PERIOD != 8)
            $fatal(1, "SDRAM clock period is %0d ns", `SDR_CLK_PERIOD);
        if (REFRESH_INTERVAL != 3906)
            $fatal(1, "SDRAM refresh interval is %0d cycles, expected 3906", REFRESH_INTERVAL);
        if (REFRESH_INTERVAL - 10 <= 0)
            $fatal(1, "SDRAM refresh request threshold is invalid");
        repeat (5) @(negedge clk);
        rst = 0;
        wait (init_done === 1'b1);
        repeat (5 * 3907) @(posedge clk);
        if (requests != 5)
            $fatal(1, "Received %0d refresh requests, expected 5", requests);
        @(posedge clk);
        #1;
        rst = 1;
        repeat (4) @(negedge clk);
        if (req !== 0 || refresh_active !== 0)
            $fatal(1, "Reset must clear refresh request and activity");
        $display("TEST_PASS SDRAM refresh interval=%0d cycles, requests=%0d, reset clears scheduler", REFRESH_INTERVAL, requests);
        $finish;
    end
    initial begin
        #3000000;
        $fatal(1, "Refresh scheduler timeout");
    end
endmodule
