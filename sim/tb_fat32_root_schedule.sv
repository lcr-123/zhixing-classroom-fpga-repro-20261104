`timescale 1ns/1ps

module tb_fat32_root_schedule;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, init_done = 0, start = 0;
    reg [7:0] cluster_sectors = 1;
    // 0: files at the last sector of the third cluster; 1: endless chain;
    // 2: EOF; 3: self loop; 4: invalid cluster; 5: short read; 6: no end.
    integer scenario = 0;
    reg simultaneous_end = 0;
    wire busy, done, found_valid, read_req, recover;
    wire [7:0] error_code;
    wire [31:0] read_addr, found_cluster, found_size;
    wire [3:0] found_index;
    wire [11:0] found_mask;
    reg [7:0] data = 0;
    reg valid = 0, read_end = 0;
    reg model_active = 0, request_seen = 0;
    integer byte_index = 0;
    reg [31:0] active_lba = 0;
    integer requests = 0, found_count = 0, fat_reads = 0;
    integer expected_cluster = 0, expected_sector = 0;
    reg expected_fat = 0, recover_seen = 0;
    reg check_sequence = 1;
    reg [11:0] published_mask = 0;
    reg previous_done = 0;

    fat32_volume_scanner #(
        .SD_PROGRESS_TIMEOUT_CYCLES(32), .MAX_ROOT_CLUSTERS(3)
    ) dut (
        .clk(clk), .rst(rst), .start(start), .sd_init_done(init_done),
        .busy(busy), .done(done), .error_code(error_code),
        .sectors_per_cluster(), .sectors_per_cluster_shift(),
        .fat_start_lba(), .data_start_lba(), .max_cluster(),
        .file_found_valid(found_valid), .file_found_index(found_index),
        .file_found_cluster(found_cluster), .file_found_size(found_size),
        .file_found_mask(found_mask), .sd_sec_read(read_req),
        .sd_sec_read_addr(read_addr), .sd_sec_read_data(data),
        .sd_sec_read_data_valid(valid), .sd_sec_read_end(read_end),
        .sd_recover_pulse(recover)
    );

    function automatic [31:0] cluster_number(input integer ordinal);
        cluster_number = 5 + ordinal * 4;
    endfunction
    function automatic [31:0] root_lba(input integer ordinal);
        root_lba = 514 + (cluster_number(ordinal) - 2) * cluster_sectors;
    endfunction
    function automatic [7:0] byte_of(input [31:0] value, input integer i);
        byte_of = value >> (8 * i);
    endfunction
    function automatic [7:0] card_byte(input [31:0] lba, input integer i);
        integer entry, pos, file_number, ordinal;
        reg [31:0] next_cluster;
        begin
            card_byte = 0;
            if (lba == 0) begin
                case (i)
                    0: card_byte = 8'heb;
                    12: card_byte = 2;
                    13: card_byte = cluster_sectors;
                    14: card_byte = 2;
                    16: card_byte = 2;
                    32,33,34,35: card_byte = byte_of(32'd30000, i-32);
                    37: card_byte = 1; // 256 FAT sectors, enough for spc=1
                    44: card_byte = 5;
                    510: card_byte = 8'h55;
                    511: card_byte = 8'haa;
                    default: ;
                endcase
            end else if (lba == 2) begin
                ordinal = (i / 4 - 5) / 4;
                next_cluster = cluster_number(ordinal + 1);
                if (scenario == 2) next_cluster = 32'h0fff_fff8;
                if (scenario == 3) next_cluster = i / 4;
                if (scenario == 4) next_cluster = 32'h0fff_fff7;
                card_byte = byte_of(next_cluster, i % 4);
            end else begin
                // Every other directory slot is deleted. Keep the final
                // valid entry at byte 511 to test end/commit priority.
                card_byte = 8'he5;
                if (scenario == 0 &&
                    lba == root_lba(2) + cluster_sectors - 1) begin
                    entry = i / 32;
                    pos = i % 32;
                    file_number = entry - 3;
                    if (entry >= 4) begin
                        card_byte = 0;
                        case (pos)
                            0: card_byte = file_number < 10 ? "0" : "1";
                            1: card_byte = "0" + file_number % 10;
                            2,3,4,5,6,7: card_byte = " ";
                            8: card_byte = "B";
                            9: card_byte = "M";
                            10: card_byte = "P";
                            11: card_byte = 8'h20;
                            26: card_byte = 40 + file_number;
                            29: card_byte = 2;
                            default: ;
                        endcase
                    end
                end
            end
        end
    endfunction

    // Check only accepted physical requests, using an independent expected
    // LBA sequence rather than the DUT state/index/decision registers.
    always @(posedge clk) begin
        valid <= 0;
        read_end <= 0;
        if (rst || !init_done) begin
            model_active <= 0;
            request_seen <= 0;
        end else begin
            if (!read_req) request_seen <= 0;
            if (!model_active && read_req && !request_seen) begin
                if (check_sequence) begin
                    if (requests == 0) begin
                        if (read_addr != 0) $fatal(1, "expected boot LBA 0");
                    end else if (expected_fat) begin
                        if (read_addr != 2) $fatal(1, "expected FAT LBA 2 got %0d", read_addr);
                        fat_reads = fat_reads + 1;
                        expected_fat = 0;
                        expected_cluster = expected_cluster + 1;
                    end else begin
                        if (read_addr != root_lba(expected_cluster) + expected_sector)
                            $fatal(1, "root LBA got %0d expected %0d", read_addr,
                                   root_lba(expected_cluster) + expected_sector);
                        expected_sector = expected_sector + 1;
                        if (expected_sector == cluster_sectors) begin
                            expected_sector = 0;
                            expected_fat = 1;
                        end
                    end
                end
                requests = requests + 1;
                active_lba <= read_addr;
                byte_index <= 0;
                model_active <= 1;
                request_seen <= 1;
            end else if (model_active) begin
                if (scenario == 5 && active_lba != 0 && byte_index == 17) begin
                    read_end <= 1;
                    model_active <= 0;
                end else if (byte_index < 512) begin
                    valid <= 1;
                    data <= card_byte(active_lba, byte_index);
                    byte_index <= byte_index + 1;
                    if (simultaneous_end && byte_index == 511 && scenario != 6) begin
                        read_end <= 1;
                        model_active <= 0;
                    end
                end else begin
                    read_end <= scenario != 6;
                    model_active <= 0;
                end
            end
            if (recover) recover_seen = 1;
            if (found_valid) begin
                if (published_mask[found_index]) $fatal(1, "duplicate file published");
                if (found_index >= 12 || found_cluster != 41 + found_index || found_size != 512)
                    $fatal(1, "incorrect file metadata");
                published_mask[found_index] = 1;
                found_count = found_count + 1;
            end
            if (done && previous_done) $fatal(1, "done must pulse once");
        end
        previous_done <= done;
    end

    // The physical controller returns to WAIT one cycle after READ_END.
    // Its next sampling edge must see read_req low, despite delayed parsing.
    integer physical_end_checks = 0;
    always @(posedge clk) begin
        if (!rst && init_done && read_end) begin
            #1;
            if (read_req) $fatal(1, "physical end did not release request in the same cycle");
            physical_end_checks = physical_end_checks + 1;
        end
    end

    task automatic clear_observation;
        requests = 0;
        found_count = 0;
        fat_reads = 0;
        expected_cluster = 0;
        expected_sector = 0;
        expected_fat = 0;
        recover_seen = 0;
        published_mask = 0;
    endtask
    task automatic launch;
        @(negedge clk);
        clear_observation();
        start = 1;
        @(negedge clk);
        start = 0;
    endtask
    task automatic finish_scan(input [7:0] expected_error, input integer expected_requests);
        integer cycles;
        begin
            cycles = 0;
            while (!done && cycles < 250000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!done) $fatal(1, "scan exceeded bound");
            if (error_code != expected_error || requests != expected_requests)
                $fatal(1, "scenario %0d error=%02x requests=%0d expected %02x/%0d",
                       scenario, error_code, requests, expected_error, expected_requests);
            if (expected_error == 0) begin
                if (found_mask != 12'hfff || found_count != 12 || published_mask != 12'hfff)
                    $fatal(1, "final-sector commit missing");
            end else if (found_mask != 0 || found_count != 0)
                $fatal(1, "failed scan published files");
            if ((expected_error == 8'h10) != recover_seen)
                $fatal(1, "incorrect recovery pulse");
            repeat (5) @(negedge clk);
            if (busy || read_req || done) $fatal(1, "scan did not return idle");
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        init_done = 1;
        // Back-to-back scans change cluster sizes without resetting. Last
        // allowed cluster must still consume every sector before limit error.
        cluster_sectors = 1;
        launch();
        finish_scan(0, 6);
        cluster_sectors = 2;
        simultaneous_end = 1;
        launch();
        wait (model_active && active_lba != 0 && active_lba != 2);
        @(negedge clk); start = 1;
        repeat (4) @(negedge clk);
        start = 0;
        finish_scan(0, 9);
        cluster_sectors = 128;
        launch();
        finish_scan(0, 387);

        scenario = 1;
        launch();
        finish_scan(8'h23, 387);
        cluster_sectors = 2;
        scenario = 2;
        launch(); finish_scan(8'h22, 4);
        scenario = 3;
        launch(); finish_scan(8'h23, 4);
        scenario = 4;
        launch(); finish_scan(8'h24, 4);
        scenario = 5;
        launch(); finish_scan(8'h10, 2);
        scenario = 6;
        launch(); finish_scan(8'h10, 1);

        scenario = 0;
        launch();
        wait (model_active && active_lba != 0);
        @(negedge clk); init_done = 0;
        repeat (5) @(negedge clk);
        if (busy || read_req || found_valid || done) $fatal(1, "init loss did not abort");
        init_done = 1;
        launch(); finish_scan(0, 9);

        launch();
        wait (model_active && active_lba != 0);
        @(negedge clk); rst = 1;
        repeat (4) @(negedge clk);
        if (busy || read_req || found_valid || done) $fatal(1, "reset did not abort");
        rst = 0;
        cluster_sectors = 1;
        simultaneous_end = 0;
        launch(); finish_scan(0, 6);
        if (physical_end_checks < 800) $fatal(1, "insufficient physical end coverage");
        // Abort with raw end/final byte pending at the response boundary.
        launch();
        wait (read_end);
        @(negedge clk); init_done = 0;
        repeat (5) @(negedge clk);
        if (busy || read_req || found_valid || done) $fatal(1, "pending response survived init loss");
        init_done = 1;
        launch(); finish_scan(0, 6);
        launch();
        wait (read_end);
        @(negedge clk); rst = 1;
        repeat (4) @(negedge clk);
        if (busy || read_req || found_valid || done) $fatal(1, "pending response survived reset");
        rst = 0;
        launch(); finish_scan(0, 6);
        $display("TEST_PASS tb_fat32_root_schedule sizes=1/2/128 bounded_chain recovery busy_start");
        $finish;
    end
endmodule
