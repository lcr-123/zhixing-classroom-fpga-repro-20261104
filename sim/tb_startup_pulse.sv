`timescale 1ns/1ps

module tb_startup_pulse;
    reg clk = 1'b0;
    reg rst = 1'b1;
    wire pulse;
    integer cycle;
    integer pulse_count;

    always #5 clk = ~clk;

    startup_pulse #(
        .CNT_MAX(4)
    ) dut (
        .I_clk(clk),
        .I_rst(rst),
        .O_pulse(pulse)
    );

    task fail;
        input [8*96-1:0] message;
        begin
            $display("TEST_FAIL tb_startup_pulse: %0s", message);
            $fatal(1);
        end
    endtask

    initial begin
        pulse_count = 0;
        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        for (cycle = 1; cycle <= 10; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (pulse)
                pulse_count = pulse_count + 1;
            if ((cycle == 4) && !pulse)
                fail("pulse missing at CNT_MAX");
            if ((cycle != 4) && pulse)
                fail("pulse asserted on the wrong cycle");
        end

        if (pulse_count != 1)
            fail("pulse was not exactly one clock wide");

        $display("TEST_PASS tb_startup_pulse");
        $finish;
    end
endmodule
