`timescale 1ns/1ps

module tb_sd_card_addressing;
    localparam [31:0] TEST_SECTOR = 32'h0000_1234;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sd_sec_read = 1'b0;
    reg [31:0] sd_sec_read_addr = TEST_SECTOR;
    reg sd_sec_write = 1'b0;
    reg [31:0] sd_sec_write_addr = TEST_SECTOR;
    reg [7:0] sd_sec_write_data = 8'h5a;
    wire sd_init_done;
    wire sd_sec_read_end;
    wire sd_sec_write_end;
    wire [15:0] spi_clk_div;
    wire cmd_req;
    reg cmd_req_ack = 1'b0;
    reg cmd_req_error = 1'b0;
    wire [47:0] cmd;
    wire [7:0] cmd_r1;
    wire [15:0] cmd_data_len;
    reg [31:0] cmd_response_data = 32'd0;
    wire block_read_req;
    reg block_read_req_ack = 1'b0;
    wire block_write_req;
    reg block_write_req_ack = 1'b0;

    reg [31:0] ocr_value = 32'd0;
    reg command_pending = 1'b0;
    integer cmd58_count = 0;
    integer cmd16_count = 0;

    reg engine_rst = 1'b1;
    reg engine_cmd_req = 1'b0;
    wire engine_cmd_req_ack;
    wire [31:0] engine_cmd_response_data;
    wire engine_spi_wr_req;
    reg [7:0] engine_spi_data_out;

    always #5 clk = ~clk;

    sd_card_sec_read_write dut (
        .clk(clk),
        .rst(rst),
        .sd_init_done(sd_init_done),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(),
        .sd_sec_read_data_valid(),
        .sd_sec_read_end(sd_sec_read_end),
        .sd_sec_write(sd_sec_write),
        .sd_sec_write_addr(sd_sec_write_addr),
        .sd_sec_write_data(sd_sec_write_data),
        .sd_sec_write_data_req(),
        .sd_sec_write_end(sd_sec_write_end),
        .spi_clk_div(spi_clk_div),
        .cmd_req(cmd_req),
        .cmd_req_ack(cmd_req_ack),
        .cmd_req_error(cmd_req_error),
        .cmd(cmd),
        .cmd_r1(cmd_r1),
        .cmd_data_len(cmd_data_len),
        .cmd_response_data(cmd_response_data),
        .block_read_req(block_read_req),
        .block_read_valid(1'b0),
        .block_read_data(8'd0),
        .block_read_req_ack(block_read_req_ack),
        .block_write_req(block_write_req),
        .block_write_data(),
        .block_write_data_rd(1'b0),
        .block_write_req_ack(block_write_req_ack)
    );

    sd_card_cmd response_dut (
        .sys_clk(clk),
        .rst(engine_rst),
        .spi_clk_div(16'd0),
        .cmd_req(engine_cmd_req),
        .cmd_req_ack(engine_cmd_req_ack),
        .cmd_req_error(),
        .cmd({8'd58, 32'd0, 8'hff}),
        .cmd_r1(8'h00),
        .cmd_data_len(16'd4),
        .cmd_response_data(engine_cmd_response_data),
        .block_read_req(1'b0),
        .block_read_valid(),
        .block_read_data(),
        .block_read_req_ack(),
        .block_write_req(1'b0),
        .block_write_data(8'd0),
        .block_write_data_rd(),
        .block_write_req_ack(),
        .nCS_ctrl(),
        .clk_div(),
        .spi_wr_req(engine_spi_wr_req),
        .spi_wr_ack(1'b1),
        .spi_data_in(),
        .spi_data_out(engine_spi_data_out)
    );

    always @(*) begin
        engine_spi_data_out = 8'hff;
        if ((response_dut.state == 5'd4) && (response_dut.byte_cnt >= 16'd6))
            engine_spi_data_out = 8'h00;
        else if (response_dut.state == 5'd5) begin
            case (response_dut.byte_cnt)
                16'd0: engine_spi_data_out = 8'hc0;
                16'd1: engine_spi_data_out = 8'hff;
                16'd2: engine_spi_data_out = 8'h80;
                default: engine_spi_data_out = 8'h00;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_req_ack <= 1'b0;
            cmd_req_error <= 1'b0;
            cmd_response_data <= 32'd0;
            command_pending <= 1'b0;
            cmd58_count <= 0;
            cmd16_count <= 0;
        end else begin
            cmd_req_ack <= 1'b0;
            if (cmd_req && !command_pending) begin
                command_pending <= 1'b1;
                cmd_req_ack <= 1'b1;
                if (cmd[47:40] == 8'd58) begin
                    if (cmd_data_len != 16'd4)
                        $fatal(1, "CMD58 response length was not four bytes");
                    cmd_response_data <= ocr_value;
                    cmd58_count <= cmd58_count + 1;
                end else if (cmd[47:40] == 8'd16) begin
                    cmd16_count <= cmd16_count + 1;
                end
            end else if (!cmd_req) begin
                command_pending <= 1'b0;
            end
        end
    end

    task automatic pulse_reset;
        begin
            rst = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic check_card;
        input high_capacity;
        reg [31:0] expected_address;
        begin
            ocr_value = high_capacity ? 32'hc000_0000 : 32'h8000_0000;
            pulse_reset();
            wait (sd_init_done);
            expected_address = high_capacity ? TEST_SECTOR : (TEST_SECTOR << 9);

            if (cmd58_count != 1)
                $fatal(2, "CMD58 was not issued exactly once");
            if (dut.card_high_capacity !== high_capacity)
                $fatal(3, "CCS card type was not retained");
            if (high_capacity && (cmd16_count != 0))
                $fatal(4, "SDHC must not issue CMD16");
            if (!high_capacity && (cmd16_count != 1))
                $fatal(5, "SDSC must set the 512-byte block length");

            @(negedge clk);
            sd_sec_read = 1'b1;
            wait (cmd_req && (cmd[47:40] == 8'd17));
            if (cmd[39:8] != expected_address)
                $fatal(6, "CMD17 address mismatch: got %h expected %h", cmd[39:8], expected_address);
            @(negedge clk);
            sd_sec_read = 1'b0;
            wait (block_read_req);
            @(negedge clk);
            block_read_req_ack = 1'b1;
            @(negedge clk);
            block_read_req_ack = 1'b0;
            wait (sd_sec_read_end);
            wait (!sd_sec_read_end);

            @(negedge clk);
            sd_sec_write = 1'b1;
            wait (cmd_req && (cmd[47:40] == 8'd24));
            if (cmd[39:8] != expected_address)
                $fatal(7, "CMD24 address mismatch: got %h expected %h", cmd[39:8], expected_address);
            @(negedge clk);
            sd_sec_write = 1'b0;
            wait (block_write_req);
            @(negedge clk);
            block_write_req_ack = 1'b1;
            @(negedge clk);
            block_write_req_ack = 1'b0;
            wait (sd_sec_write_end);
            wait (!sd_sec_write_end);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        engine_rst = 1'b0;
        wait (response_dut.state == 5'd1);
        @(negedge clk);
        engine_cmd_req = 1'b1;
        wait (engine_cmd_req_ack);
        #1;
        if (engine_cmd_response_data != 32'hc0ff_8000)
            $fatal(8, "command response capture mismatch: %h", engine_cmd_response_data);
        @(negedge clk);
        engine_cmd_req = 1'b0;

        check_card(1'b0);
        check_card(1'b1);
        $display("TEST_PASS tb_sd_card_addressing");
        $finish;
    end

    initial begin
        #20000;
        $fatal(9, "test timeout");
    end
endmodule
