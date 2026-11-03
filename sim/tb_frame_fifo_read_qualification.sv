`timescale 1ns/1ps

module tb_frame_fifo_read_qualification;
    localparam A = 12;
    localparam B = 8;
    reg mem_clk = 0, rst = 1, read_req = 0;
    reg refresh = 0, mem_busy = 0, wr_busy = 0;
    reg dual_read = 0;
    reg [1:0] index_a = 0, index_b = 1;
    reg [A-1:0] length = 0;
    reg [5:0] used_a = 0, used_b = 0;
    wire ack, finish, rd_en, target, fifo_clear, rd_busy;
    wire [A-1:0] addr;
    integer count_a = 0, count_b = 0;
    integer limit_a = 0, limit_b = 0;
    integer base_a = 'h100, base_b = 'h200;
    integer i;
    always #4 mem_clk = ~mem_clk;

    // Count only actual read commands; compare every address and FIFO target.
    always @(posedge mem_clk) if (!rst && rd_en) begin
        if (!rd_busy || fifo_clear) $fatal(1, "read outside burst or during clear");
        if (target) begin
            if (count_b >= limit_b || addr !== ((base_b + count_b) & 'hfff))
                $fatal(1, "unexpected B command %0d addr=%h", count_b, addr);
            count_b = count_b + 1;
        end else begin
            if (count_a >= limit_a || addr !== ((base_a + count_a) & 'hfff))
                $fatal(1, "unexpected A command %0d addr=%h", count_a, addr);
            count_a = count_a + 1;
        end
    end

    frame_fifo_read_dual #(.ADDR_BITS(A), .BURST_BITS(6),
        .FIFO_DEPTH(32), .BURST_SIZE(B)) dut (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(refresh), .Sdr_busy(mem_busy), .App_wr_busy(wr_busy),
        .O_rd_busy(rd_busy), .App_rd_en(rd_en), .App_rd_addr(addr),
        .read_req(read_req), .read_req_ack(ack), .read_finish(finish),
        .read_addr_0(12'h100), .read_addr_1(12'h200),
        .read_addr_2(12'h300), .read_addr_3(12'h400),
        .read_addr_index_a(index_a), .read_addr_index_b(index_b),
        .dual_read(dual_read), .read_len(length), .fifo_aclr(fifo_clear),
        .wrusedw_a(used_a), .wrusedw_b(used_b), .read_target(target));

    task automatic begin_frame(input integer words, input integer dual_mode,
        input integer ia, input integer ib);
        begin
            @(negedge mem_clk);
            count_a=0; count_b=0;
            limit_a=((words+B-1)/B)*B;
            limit_b=dual_mode ? limit_a : 0;
            base_a=(ia+1)*'h100; base_b=(ib+1)*'h100;
            length=words; dual_read=dual_mode; index_a=ia; index_b=ib;
            read_req=1;
            wait(ack);
            @(negedge mem_clk); read_req=0;
        end
    endtask

    task automatic end_frame;
        begin
            wait(finish);
            @(negedge mem_clk);
            if (count_a!=limit_a || count_b!=limit_b)
                $fatal(1,"lost reads A=%0d/%0d B=%0d/%0d",
                    count_a,limit_a,count_b,limit_b);
            // Ensure stale qualification cannot launch an extra burst.
            repeat(8) @(negedge mem_clk);
        end
    endtask

    initial begin
        repeat(3) @(negedge mem_clk);
        rst=0;
        begin_frame(0,1,0,1); end_frame();
        begin_frame(1,0,2,3); end_frame();
        begin_frame(7,1,0,1); end_frame();
        begin_frame(8,0,3,0); end_frame();
        begin_frame(9,1,1,2); end_frame();
        begin_frame(17,0,2,0); end_frame();

        // A refresh and full FIFO both block new bursts, independently.
        refresh=1; used_a=24;
        begin_frame(9,0,0,1);
        repeat(20) @(negedge mem_clk);
        if(count_a!=0) $fatal(1,"read started during refresh");
        refresh=0;
        repeat(20) @(negedge mem_clk);
        if(count_a!=0) $fatal(1,"read started with insufficient FIFO space");
        used_a=0; end_frame();

        // Primary FIFO progresses while the secondary FIFO is full.
        used_b=24;
        begin_frame(16,1,0,1);
        wait(count_a==16);
        repeat(20) @(negedge mem_clk);
        if(count_b!=0 || finish) $fatal(1,"blocked B was dropped or issued");
        used_b=0; end_frame();

        // SDRAM and writer busy independently hold off arbitration.
        mem_busy=1;
        begin_frame(8,0,0,1);
        repeat(20) @(negedge mem_clk);
        if(count_a!=0) $fatal(1,"read started while SDRAM busy");
        mem_busy=0; wr_busy=1;
        repeat(20) @(negedge mem_clk);
        if(count_a!=0) $fatal(1,"read started while writer busy");
        wr_busy=0; end_frame();

        // A new frame during a burst is acknowledged after the old burst has
        // drained. Its new length, index and target must replace the old flags.
        begin_frame(24,0,0,1);
        wait(count_a==3);
        @(negedge mem_clk);
        length=9; dual_read=1; index_a=2; index_b=3; read_req=1;
        wait(ack);
        @(negedge mem_clk);
        if(count_a!=8 || count_b!=0 || !fifo_clear || rd_busy)
            $fatal(1,"busy request did not wait for a complete old burst");
        count_a=0; count_b=0; limit_a=16; limit_b=16;
        base_a='h300; base_b='h400; read_req=0;
        end_frame();

        // Carry out of the address-sized beat count must terminate, rather
        // than wrap to zero and issue another frame's worth of requests.
        begin_frame(4095,0,0,1); end_frame();

        begin_frame(24,1,0,1);
        wait(count_a==3);
        @(negedge mem_clk); rst=1; read_req=0;
        repeat(2) @(negedge mem_clk);
        rst=0;
        repeat(20) @(negedge mem_clk);
        if(rd_en || ack || finish || rd_busy) $fatal(1,"reset left active control");
        begin_frame(0,0,2,3); end_frame();
        begin_frame(8,1,2,3); end_frame();
        $display("TEST_PASS tb_frame_fifo_read_qualification");
        $finish;
    end
    initial begin #2000000; $fatal(1,"qualification test timeout"); end
endmodule
