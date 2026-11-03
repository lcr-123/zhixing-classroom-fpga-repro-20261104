`timescale 1ns/1ps

module tb_frame_fifo_write;
    localparam ADDR_BITS = 8;
    localparam BURST_BITS = 4;
    localparam BURST_SIZE = 8;
    localparam [ADDR_BITS-1:0] ZERO_ADDR = {ADDR_BITS{1'b0}};
    localparam [ADDR_BITS-1:0] TEST_LEN = BURST_SIZE * 2;

    reg clk = 0;
    reg rst = 1;
    reg write_req = 0;
    reg [BURST_BITS-1:0] rdusedw = 0;
    wire write_req_ack;
    wire write_finish;
    wire app_wr_en;
    wire [ADDR_BITS-1:0] app_wr_addr;
    integer writes = 0;
    integer timeout = 0;

    always #4 clk = ~clk;

    frame_fifo_write #(
        .ADDR_BITS(ADDR_BITS),
        .BURST_BITS(BURST_BITS),
        .BURST_SIZE(BURST_SIZE),
        .WRITE_V_FLIP(0),
        .FRAME_WIDTH(8),
        .FRAME_HEIGHT(1)
    ) dut (
        .rst(rst),
        .mem_clk(clk),
        .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0),
        .Sdr_busy(1'b0),
        .App_rd_busy(1'b0),
        .O_wr_busy(),
        .App_wr_en(app_wr_en),
        .App_wr_addr(app_wr_addr),
        .write_req(write_req),
        .write_req_ack(write_req_ack),
        .write_finish(write_finish),
        .write_addr_0(ZERO_ADDR),
        .write_addr_1(ZERO_ADDR),
        .write_addr_2(ZERO_ADDR),
        .write_addr_3(ZERO_ADDR),
        .write_addr_index(2'b00),
        .write_len(TEST_LEN),
        .fifo_aclr(),
        .rdusedw(rdusedw)
    );

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        write_req = 1;
        while (!write_req_ack && timeout < 16) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (!write_req_ack)
            $fatal(1);

        write_req = 0;
        wait (!write_req_ack);
        repeat (6) begin
            @(negedge clk);
            if (app_wr_en)
                $fatal(2);
        end

        rdusedw = BURST_SIZE + 1;
        timeout = 0;
        while (!write_finish && timeout < 64) begin
            @(negedge clk);
            if (app_wr_en) begin
                writes = writes + 1;
                if (writes == BURST_SIZE)
                    rdusedw = BURST_SIZE;
            end
            timeout = timeout + 1;
        end

        if (!write_finish)
            $fatal(3);
        if (writes != TEST_LEN)
            $fatal(4);
        if (app_wr_addr != TEST_LEN)
            $fatal(5);

        $finish;
    end
endmodule
