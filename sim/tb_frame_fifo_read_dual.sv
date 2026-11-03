`timescale 1ns/1ps

module tb_frame_fifo_read_dual;
    localparam ADDR_BITS = 12;
    localparam BURST_BITS = 6;
    localparam BURST_SIZE = 8;

    reg mem_clk = 1'b0;
    reg rst = 1'b1;
    reg read_req = 1'b0;
    reg Sdr_init_ref_vld = 1'b0;
    reg Sdr_busy = 1'b0;
    reg App_wr_busy = 1'b0;
    reg [1:0] read_addr_index_a = 2'd0;
    reg [1:0] read_addr_index_b = 2'd1;
    reg dual_read = 1'b1;
    reg [ADDR_BITS-1:0] read_len = 12'd16;
    reg [BURST_BITS-1:0] wrusedw_a = {BURST_BITS{1'b0}};
    reg [BURST_BITS-1:0] wrusedw_b = {BURST_BITS{1'b0}};
    wire read_req_ack;
    wire read_finish;
    wire App_rd_en;
    wire [ADDR_BITS-1:0] App_rd_addr;
    wire read_target;
    reg issued_target [0:63];
    reg [ADDR_BITS-1:0] issued_addr [0:63];
    integer issue_count = 0;
    integer i;
    integer reads_a = 0;
    integer reads_b = 0;
    reg check_first_request = 1'b1;

    always #4 mem_clk = ~mem_clk;

    always @(posedge mem_clk) begin
        if (App_rd_en) begin
            issued_target[issue_count] = read_target;
            issued_addr[issue_count] = App_rd_addr;
            issue_count = issue_count + 1;
            if (check_first_request) begin
                if (read_target) begin
                if (App_rd_addr < 12'h200 || App_rd_addr >= 12'h210)
                    $fatal(1, "target B address out of range: %h", App_rd_addr);
                reads_b = reads_b + 1;
            end else begin
                if (App_rd_addr < 12'h100 || App_rd_addr >= 12'h110)
                    $fatal(2, "target A address out of range: %h", App_rd_addr);
                    reads_a = reads_a + 1;
                end
            end
        end
    end

    task automatic request_frame;
        begin
            @(negedge mem_clk);
            read_req = 1'b1;
            wait (read_req_ack);
            @(negedge mem_clk);
            read_req = 1'b0;
        end
    endtask

    frame_fifo_read_dual #(
        .ADDR_BITS(ADDR_BITS),
        .BURST_BITS(BURST_BITS),
        .FIFO_DEPTH(32),
        .BURST_SIZE(BURST_SIZE)
    ) dut (
        .rst(rst),
        .mem_clk(mem_clk),
        .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy(Sdr_busy),
        .App_wr_busy(App_wr_busy),
        .O_rd_busy(),
        .App_rd_en(App_rd_en),
        .App_rd_addr(App_rd_addr),
        .read_req(read_req),
        .read_req_ack(read_req_ack),
        .read_finish(read_finish),
        .read_addr_0(12'h100),
        .read_addr_1(12'h200),
        .read_addr_2(12'h300),
        .read_addr_3(12'h400),
        .read_addr_index_a(read_addr_index_a),
        .read_addr_index_b(read_addr_index_b),
        .dual_read(dual_read),
        .read_len(read_len),
        .fifo_aclr(),
        .wrusedw_a(wrusedw_a),
        .wrusedw_b(wrusedw_b),
        .read_target(read_target)
    );

    initial begin
        repeat (3) @(posedge mem_clk);
        rst = 1'b0;
        request_frame();
        wait (read_finish);
        #1;
        if (issue_count != 32)
            reads_a = -1000;
        for (i = 0; i < 32; i = i + 1) begin
            if (issued_target[i] != ((i / BURST_SIZE) % 2))
                reads_a = -1000;
            if (!issued_target[i] &&
                issued_addr[i] != (12'h100 + ((i / (2 * BURST_SIZE)) * BURST_SIZE) + (i % BURST_SIZE)))
                reads_a = -1000;
            if (issued_target[i] &&
                issued_addr[i] != (12'h200 + ((i / (2 * BURST_SIZE)) * BURST_SIZE) + (i % BURST_SIZE)))
                reads_b = -1000;
        end
        check_first_request = 1'b0;

        // Single mode only fills the primary FIFO.
        @(negedge mem_clk);
        issue_count = 0;
        dual_read = 1'b0;
        read_addr_index_a = 2'd2;
        read_len = 12'd8;
        request_frame();
        wait (read_finish);
        #1;
        if (issue_count != 8)
            reads_a = -1000;
        for (i = 0; i < 8; i = i + 1) begin
            if (issued_target[i])
                reads_a = -1000;
            if (issued_addr[i] != (12'h300 + i))
                reads_a = -1000;
        end

        // Refresh and FIFO pressure hold off a burst without losing it.
        @(negedge mem_clk);
        issue_count = 0;
        read_addr_index_a = 2'd0;
        read_len = 12'd8;
        Sdr_init_ref_vld = 1'b1;
        wrusedw_a = 6'd24;
        request_frame();
        repeat (20) @(posedge mem_clk);
        if (issue_count != 0)
            reads_a = -1000;
        @(negedge mem_clk);
        Sdr_init_ref_vld = 1'b0;
        wrusedw_a = 6'd0;
        wait (read_finish);
        #1;
        if (issue_count != 8)
            reads_a = -1000;

        if (reads_a != 16 || reads_b != 16)
            $fatal(3, "dual read counts mismatch: A=%0d B=%0d", reads_a, reads_b);

        $display("TEST_PASS tb_frame_fifo_read_dual");
        $finish;
    end

    initial begin
        #10000;
        $fatal(4, "test timeout");
    end
endmodule
