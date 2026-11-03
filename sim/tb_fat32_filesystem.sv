`timescale 1ns/1ps

module tb_fat32_filesystem #(parameter HOME_TEST = 0);
    // Home modes: absent/end, late, early+duplicate, bad cluster, empty, absent/EOC.
    integer home_mode = 0;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sd_init_done = 1'b0;
    reg scanner_start = 1'b0;
    reg reader_start = 1'b0;
    reg reader_stop = 1'b0;
    reg reader_allow_next_sector = 1'b1;
    reg media_superfloppy = 1'b0;
    reg inject_short_sector = 1'b0;
    reg inject_overlong_sector = 1'b0;
    reg inject_missing_end = 1'b0;
    reg inject_bad_chain = 1'b0;
    reg simultaneous_end = 1'b0;
    reg inject_bad_bpb = 1'b0;
    reg inject_directory_end = 1'b0;
    reg [31:0] media_total_sectors = 32'd400;
    reg [31:0] media_fat_sectors = 32'd2;
    reg [31:0] media_root_cluster = 32'd5;
    reg override_edge_clusters = 1'b0;
    reg [31:0] edge_cluster = 32'd2;
    integer range_case;

    wire scanner_busy;
    wire scanner_done;
    wire [7:0] scanner_error;
    wire [7:0] sectors_per_cluster;
    wire [2:0] sectors_per_cluster_shift;
    wire [31:0] fat_start_lba;
    wire [31:0] data_start_lba;
    wire [31:0] max_cluster;
    wire file_found_valid;
    wire [3:0] file_found_index;
    wire [31:0] file_found_cluster;
    wire [31:0] file_found_size;
    wire [11:0] file_found_mask;
    wire scanner_sd_read;
    wire [31:0] scanner_sd_addr;
    wire scanner_recover;

    wire reader_busy;
    wire reader_done;
    wire reader_data_valid;
    wire [7:0] reader_data_byte;
    wire [31:0] reader_data_offset;
    wire [7:0] reader_error;
    wire reader_sd_read;
    wire [31:0] reader_sd_addr;
    wire reader_recover;

    reg bridge_virtual_read = 1'b0;
    reg [31:0] bridge_virtual_addr = 32'd0;
    wire [7:0] bridge_virtual_data;
    wire bridge_virtual_valid;
    wire bridge_virtual_end;
    wire bridge_virtual_error;
    wire bridge_physical_read;
    wire [31:0] bridge_physical_addr;
    wire bridge_recover;
    wire [12:0] bridge_metadata_mask;

    reg [31:0] reader_first_cluster = 32'd20;
    reg [31:0] reader_file_size = 32'd1500;
    reg [31:0] reader_start_offset = 32'd0;
    reg [31:0] reader_length = 32'd0;

    wire sd_req = scanner_sd_read | reader_sd_read | bridge_physical_read;
    wire [31:0] sd_addr = scanner_sd_read ? scanner_sd_addr :
                          (reader_sd_read ? reader_sd_addr :
                           bridge_physical_addr);
    reg [7:0] sd_data = 8'd0;
    reg sd_valid = 1'b0;
    reg sd_end = 1'b0;

    reg model_busy = 1'b0;
    reg request_seen = 1'b0;
    reg [31:0] model_lba = 32'd0;
    integer model_byte_index = 0;
    integer found_count = 0;
    reg [31:0] found_cluster0 = 32'd0;
    reg [31:0] found_size0 = 32'd0;
    integer stream_count = 0;
    integer bridge_stream_count = 0;
    integer bridge_expected_offset = 0;
    integer error_count = 0;
    reg recover_seen = 1'b0;
    integer perf_cycles = 0;
    integer perf_physical_reads = 0;
    integer perf_fat_reads = 0;

    always #5 clk = ~clk;

    function automatic [31:0] partition_base;
        begin
            partition_base = media_superfloppy ? 32'd0 : 32'd32;
        end
    endfunction

    function automatic [7:0] word_byte;
        input [31:0] value;
        input integer byte_number;
        begin
            case (byte_number)
                0: word_byte = value[7:0];
                1: word_byte = value[15:8];
                2: word_byte = value[23:16];
                default: word_byte = value[31:24];
            endcase
        end
    endfunction

    function automatic [7:0] halfword_byte;
        input [15:0] value;
        input integer byte_number;
        begin
            halfword_byte = byte_number == 0 ? value[7:0] : value[15:8];
        end
    endfunction

    function automatic [7:0] boot_byte;
        input integer byte_index;
        begin
            boot_byte = 8'h00;
            case (byte_index)
                0: boot_byte = 8'heb;
                1: boot_byte = 8'h58;
                2: boot_byte = 8'h90;
                11: boot_byte = halfword_byte(16'd512, 0);
                12: boot_byte = inject_bad_bpb ? 8'd4 : halfword_byte(16'd512, 1);
                13: boot_byte = 8'd2;
                14: boot_byte = halfword_byte(16'd2, 0);
                15: boot_byte = halfword_byte(16'd2, 1);
                16: boot_byte = 8'd2;
                17, 18: boot_byte = 8'd0;
                19, 20: boot_byte = 8'd0;
                22, 23: boot_byte = 8'd0;
                32: boot_byte = word_byte(media_total_sectors, 0);
                33: boot_byte = word_byte(media_total_sectors, 1);
                34: boot_byte = word_byte(media_total_sectors, 2);
                35: boot_byte = word_byte(media_total_sectors, 3);
                36: boot_byte = word_byte(media_fat_sectors, 0);
                37: boot_byte = word_byte(media_fat_sectors, 1);
                38: boot_byte = word_byte(media_fat_sectors, 2);
                39: boot_byte = word_byte(media_fat_sectors, 3);
                40, 41: boot_byte = 8'd0;
                44: boot_byte = word_byte(media_root_cluster, 0);
                45: boot_byte = word_byte(media_root_cluster, 1);
                46: boot_byte = word_byte(media_root_cluster, 2);
                47: boot_byte = word_byte(media_root_cluster, 3);
                510: boot_byte = 8'h55;
                511: boot_byte = 8'haa;
                default: ;
            endcase
        end
    endfunction

    function automatic [7:0] mbr_byte;
        input integer byte_index;
        begin
            mbr_byte = 8'h00;
            if (byte_index == 466)
                mbr_byte = 8'h0c;
            else if ((byte_index >= 470) && (byte_index <= 473))
                mbr_byte = word_byte(32'd32, byte_index - 470);
            else if (byte_index == 510)
                mbr_byte = 8'h55;
            else if (byte_index == 511)
                mbr_byte = 8'haa;
        end
    endfunction

    function automatic [31:0] fat_entry_value;
        input integer cluster_number;
        begin
            case (cluster_number)
                0: fat_entry_value = 32'h0fff_fff8;
                1: fat_entry_value = 32'h0fff_ffff;
                5: fat_entry_value = 32'd9;
                9: fat_entry_value = 32'h0fff_ffff;
                20: fat_entry_value = inject_bad_chain ? 32'd20 : 32'd25;
                25: fat_entry_value = 32'h0fff_ffff;
                default: fat_entry_value = 32'h0fff_ffff;
            endcase
        end
    endfunction

    function automatic [7:0] fat_byte;
        input integer byte_index;
        integer cluster_number;
        integer sub_index;
        reg [31:0] value;
        begin
            cluster_number = byte_index / 4;
            sub_index = byte_index % 4;
            value = fat_entry_value(cluster_number);
            fat_byte = word_byte(value, sub_index);
        end
    endfunction

    function automatic [31:0] directory_cluster;
        input integer file_number;
        begin
            if (HOME_TEST && file_number == 0)
                directory_cluster = home_mode == 3 ? 32'd0 : 32'd30;
            else if (override_edge_clusters &&
                ((file_number == 1) || (file_number == 12)))
                directory_cluster = edge_cluster;
            else if (file_number == 1)
                directory_cluster = 32'd20;
            else
                directory_cluster = 32'd30 + file_number;
        end
    endfunction

    function automatic [31:0] directory_size;
        input integer file_number;
        begin
            directory_size = (HOME_TEST && file_number == 0 && home_mode == 4) ?
                             32'd0 : file_number == 1 ? 32'd1500 : 32'd1024;
        end
    endfunction

    function automatic [7:0] directory_entry_byte;
        input integer file_number;
        input integer byte_in_entry;
        reg [31:0] cluster_value;
        reg [31:0] size_value;
        begin
            cluster_value = directory_cluster(file_number);
            size_value = directory_size(file_number);
            directory_entry_byte = 8'h00;
            case (byte_in_entry)
                0: directory_entry_byte = file_number < 10 ? "0" : "1";
                1: directory_entry_byte = file_number < 10 ?
                                          ("0" + file_number) :
                                          ("0" + file_number - 10);
                2, 3, 4, 5, 6, 7: directory_entry_byte = " ";
                8: directory_entry_byte = "B";
                9: directory_entry_byte = "M";
                10: directory_entry_byte = "P";
                11: directory_entry_byte = 8'h20;
                20: directory_entry_byte = word_byte(cluster_value >> 16, 0);
                21: directory_entry_byte = word_byte(cluster_value >> 16, 1);
                26: directory_entry_byte = word_byte(cluster_value, 0);
                27: directory_entry_byte = word_byte(cluster_value, 1);
                28: directory_entry_byte = word_byte(size_value, 0);
                29: directory_entry_byte = word_byte(size_value, 1);
                30: directory_entry_byte = word_byte(size_value, 2);
                31: directory_entry_byte = word_byte(size_value, 3);
                default: directory_entry_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] root_directory_byte;
        input integer root_sector;
        input integer byte_index;
        integer entry_index;
        integer byte_in_entry;
        integer file_number;
        begin
            entry_index = byte_index / 32;
            byte_in_entry = byte_index % 32;
            root_directory_byte = 8'he5;
            if (root_sector == 0) begin
                if (entry_index < 10) begin
                    file_number = entry_index + 1;
                    root_directory_byte = directory_entry_byte(file_number,
                                                                byte_in_entry);
                end else if (entry_index == 10) begin
                    root_directory_byte = byte_in_entry == 11 ? 8'h0f : 8'h41;
                end
            end else if (root_sector == 2) begin
                if (entry_index < 2) begin
                    file_number = entry_index + 11;
                    root_directory_byte = directory_entry_byte(file_number,
                                                                byte_in_entry);
                end else if ((entry_index == 2) && (byte_in_entry == 0) &&
                             (!HOME_TEST || home_mode == 0)) begin
                    root_directory_byte = 8'h00;
                end
            end
            if (HOME_TEST && ((root_sector == 3 && home_mode >= 1 && home_mode <= 4) ||
                              (root_sector == 1 && home_mode == 2))) begin
                if (entry_index < 2)
                    root_directory_byte = directory_entry_byte(0, byte_in_entry);
            end
            if (inject_directory_end && (root_sector == 0) &&
                (entry_index == 0) && (byte_in_entry == 0))
                root_directory_byte = 8'h00;
        end
    endfunction

    function automatic [7:0] file_pattern;
        input integer logical_offset;
        begin
            file_pattern = logical_offset[7:0] ^ logical_offset[15:8];
        end
    endfunction

    function automatic [7:0] card_byte;
        input [31:0] lba;
        input integer byte_index;
        reg [31:0] part;
        reg [31:0] fat0;
        reg [31:0] data0;
        reg [31:0] root0;
        reg [31:0] root1;
        reg [31:0] file_cluster20_lba;
        reg [31:0] file_cluster25_lba;
        integer logical_offset;
        begin
            part = partition_base();
            fat0 = part + 32'd2;
            data0 = part + 32'd2 + (media_fat_sectors << 1);
            root0 = data0 + 32'd6;
            root1 = data0 + 32'd14;
            file_cluster20_lba = data0 + 32'd36;
            file_cluster25_lba = data0 + 32'd46;
            card_byte = 8'h00;

            if (!media_superfloppy && (lba == 32'd0))
                card_byte = mbr_byte(byte_index);
            else if (lba == part)
                card_byte = boot_byte(byte_index);
            else if ((lba == fat0) || (lba == fat0 + media_fat_sectors))
                card_byte = fat_byte(byte_index);
            else if (lba == root0)
                card_byte = root_directory_byte(0, byte_index);
            else if (lba == root0 + 32'd1)
                card_byte = root_directory_byte(1, byte_index);
            else if (lba == root1)
                card_byte = root_directory_byte(2, byte_index);
            else if (lba == root1 + 32'd1)
                card_byte = root_directory_byte(3, byte_index);
            else if (HOME_TEST && lba >= data0 + 32'd56 && lba < data0 + 32'd58)
                card_byte = file_pattern((lba - data0 - 32'd56) * 512 + byte_index);
            else if ((lba >= file_cluster20_lba) &&
                     (lba < file_cluster20_lba + 32'd2)) begin
                logical_offset = (lba - file_cluster20_lba) * 512 + byte_index;
                card_byte = file_pattern(logical_offset);
            end else if ((lba >= file_cluster25_lba) &&
                         (lba < file_cluster25_lba + 32'd2)) begin
                logical_offset = 1024 +
                                 (lba - file_cluster25_lba) * 512 + byte_index;
                card_byte = file_pattern(logical_offset);
            end
        end
    endfunction

    fat32_volume_scanner #(
        .SEARCH_HOME(HOME_TEST),
        .SD_PROGRESS_TIMEOUT_CYCLES(64),
        .MAX_ROOT_CLUSTERS(8)
    ) scanner (
        .clk(clk),
        .rst(rst),
        .start(scanner_start),
        .sd_init_done(sd_init_done),
        .busy(scanner_busy),
        .done(scanner_done),
        .error_code(scanner_error),
        .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_cluster_shift(sectors_per_cluster_shift),
        .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),
        .max_cluster(max_cluster),
        .file_found_valid(file_found_valid),
        .file_found_index(file_found_index),
        .file_found_cluster(file_found_cluster),
        .file_found_size(file_found_size),
        .file_found_mask(file_found_mask),
        .sd_sec_read(scanner_sd_read),
        .sd_sec_read_addr(scanner_sd_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(sd_end),
        .sd_recover_pulse(scanner_recover)
    );

    fat32_file_reader #(
        .SD_PROGRESS_TIMEOUT_CYCLES(64),
        .MAX_CHAIN_CLUSTERS(16)
    ) reader (
        .clk(clk),
        .rst(rst),
        .sd_init_done(sd_init_done),
        .start(reader_start),
        .stop(reader_stop),
        .allow_next_sector(reader_allow_next_sector),
        .first_cluster(reader_first_cluster),
        .file_size(reader_file_size),
        .start_offset(reader_start_offset),
        .read_length(reader_length),
        .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_cluster_shift(sectors_per_cluster_shift),
        .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),
        .max_cluster(max_cluster),
        .busy(reader_busy),
        .done(reader_done),
        .sector_done(),
        .data_valid(reader_data_valid),
        .data_byte(reader_data_byte),
        .data_offset(reader_data_offset),
        .error_code(reader_error),
        .sd_sec_read(reader_sd_read),
        .sd_sec_read_addr(reader_sd_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(sd_end),
        .sd_recover_pulse(reader_recover)
    );

    fat32_virtual_sector_bridge #(
        .SD_PROGRESS_TIMEOUT_CYCLES(64),
        .MAX_CHAIN_CLUSTERS(16)
    ) bridge (
        .clk(clk),
        .rst(rst),
        .sd_init_done(sd_init_done),
        .metadata_clear(scanner_start),
        .metadata_valid(file_found_valid),
        .metadata_index(file_found_index),
        .metadata_cluster(file_found_cluster),
        .metadata_size(file_found_size),
        .metadata_mask(bridge_metadata_mask),
        .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_cluster_shift(sectors_per_cluster_shift),
        .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),
        .max_cluster(max_cluster),
        .virtual_read(bridge_virtual_read),
        .virtual_read_addr(bridge_virtual_addr),
        .virtual_read_data(bridge_virtual_data),
        .virtual_read_data_valid(bridge_virtual_valid),
        .virtual_read_end(bridge_virtual_end),
        .virtual_read_error(bridge_virtual_error),
        .physical_read(bridge_physical_read),
        .physical_read_addr(bridge_physical_addr),
        .physical_read_data(sd_data),
        .physical_read_data_valid(sd_valid),
        .physical_read_end(sd_end),
        .sd_recover_pulse(bridge_recover)
    );

    always @(posedge clk) begin
        perf_cycles <= perf_cycles + 1;
        sd_valid <= 1'b0;
        sd_end <= 1'b0;

        if (rst) begin
            model_busy <= 1'b0;
            request_seen <= 1'b0;
            model_lba <= 32'd0;
            model_byte_index <= 0;
            recover_seen <= 1'b0;
        end else begin
            if (!sd_req)
                request_seen <= 1'b0;

            if (!model_busy && sd_req && !request_seen) begin
                model_busy <= 1'b1;
                request_seen <= 1'b1;
                model_lba <= sd_addr;
                model_byte_index <= 0;
                perf_physical_reads <= perf_physical_reads + 1;
                if ((sd_addr >= fat_start_lba) &&
                    (sd_addr < fat_start_lba + 32'd4))
                    perf_fat_reads <= perf_fat_reads + 1;
            end else if (model_busy) begin
                if (inject_short_sector && (model_byte_index == 16)) begin
                    sd_end <= 1'b1;
                    model_busy <= 1'b0;
                end else if ((model_byte_index < 512) ||
                             (inject_overlong_sector && model_byte_index == 512)) begin
                    sd_valid <= 1'b1;
                    sd_data <= card_byte(model_lba, model_byte_index);
                    model_byte_index <= model_byte_index + 1;
                    if (simultaneous_end && (model_byte_index == 511)) begin
                        sd_end <= 1'b1;
                        model_busy <= 1'b0;
                    end
                end else begin
                    sd_end <= !inject_missing_end;
                    model_busy <= 1'b0;
                end
            end

            if (scanner_recover || reader_recover || bridge_recover)
                recover_seen <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (file_found_valid) begin
            found_count <= found_count + 1;
            if (file_found_index == 4'd0) begin
                found_cluster0 <= file_found_cluster;
                found_size0 <= file_found_size;
            end
        end

        if (reader_data_valid) begin
            if (reader_data_offset != (reader_start_offset + stream_count)) begin
                $display("ERROR data offset got=%0d expected=%0d",
                         reader_data_offset, reader_start_offset + stream_count);
                error_count <= error_count + 1;
            end
            if (reader_data_byte != file_pattern(reader_start_offset + stream_count)) begin
                $display("ERROR data byte offset=%0d got=%02x expected=%02x",
                         reader_start_offset + stream_count, reader_data_byte,
                         file_pattern(reader_start_offset + stream_count));
                error_count <= error_count + 1;
            end
            stream_count <= stream_count + 1;
        end


        if (bridge_virtual_valid) begin
            if (bridge_virtual_data !=
                (((bridge_expected_offset + bridge_stream_count) >= 1500) ?
                 8'd0 : file_pattern(bridge_expected_offset + bridge_stream_count))) begin
                $display("ERROR bridge byte offset=%0d got=%02x expected=%02x",
                         bridge_expected_offset + bridge_stream_count,
                         bridge_virtual_data,
                         file_pattern(bridge_expected_offset +
                                      bridge_stream_count));
                error_count <= error_count + 1;
            end
            bridge_stream_count <= bridge_stream_count + 1;
        end
    end

    task automatic pulse_scanner_start;
        begin
            @(posedge clk);
            scanner_start <= 1'b1;
            @(posedge clk);
            scanner_start <= 1'b0;
        end
    endtask

    task automatic run_virtual_sector;
        input [31:0] virtual_address;
        input integer expected_offset;
        integer timeout;
        integer start_cycles;
        integer start_reads;
        integer start_fat_reads;
        begin
            bridge_virtual_addr = virtual_address;
            bridge_expected_offset = expected_offset;
            bridge_stream_count = 0;
            start_cycles = perf_cycles;
            start_reads = perf_physical_reads;
            start_fat_reads = perf_fat_reads;
            @(posedge clk);
            bridge_virtual_read = 1'b1;
            timeout = 0;
            while (!bridge_virtual_end && (timeout < 10000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!bridge_virtual_end) begin
                $display("ERROR bridge timeout address=%08x", virtual_address);
                error_count = error_count + 1;
            end else if (bridge_virtual_error) begin
                $display("ERROR bridge error address=%08x", virtual_address);
                error_count = error_count + 1;
            end
            @(posedge clk);
            bridge_virtual_read = 1'b0;
            if (bridge_stream_count != 512) begin
                $display("ERROR bridge count=%0d expected=512",
                         bridge_stream_count);
                error_count = error_count + 1;
            end
            $display("PERF_FAT32 virtual_lba=%08x cycles=%0d physical_reads=%0d fat_reads=%0d data_reads=%0d",
                     virtual_address, perf_cycles - start_cycles,
                     perf_physical_reads - start_reads,
                     perf_fat_reads - start_fat_reads,
                     (perf_physical_reads - start_reads) -
                     (perf_fat_reads - start_fat_reads));
            repeat (3) @(posedge clk);
        end
    endtask

    task automatic run_virtual_error;
        input [31:0] virtual_address;
        integer timeout;
        begin
            @(negedge clk);
            bridge_virtual_addr = virtual_address;
            bridge_expected_offset = virtual_address[19:0] * 512;
            bridge_stream_count = 0;
            bridge_virtual_read = 1'b1;
            timeout = 0;
            while (!bridge_virtual_end && (timeout < 10000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!bridge_virtual_end || !bridge_virtual_error) begin
                $display("ERROR expected bounded bridge error address=%08x", virtual_address);
                error_count = error_count + 1;
            end
            // A held request must receive exactly one error response.
            repeat (100) begin
                @(negedge clk);
                if (bridge_virtual_end || bridge_virtual_valid) begin
                    $display("ERROR repeated response after bridge failure");
                    error_count = error_count + 1;
                end
            end
            bridge_virtual_read = 1'b0;
            repeat (5) @(negedge clk);
        end
    endtask

    task automatic wait_scanner_done;
        integer timeout;
        begin
            timeout = 0;
            while (!scanner_done && (timeout < 20000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!scanner_done) begin
                $display("ERROR scanner timeout");
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic run_reader;
        input [31:0] offset_value;
        input [31:0] length_value;
        integer timeout;
        begin
            reader_start_offset = offset_value;
            reader_length = length_value;
            stream_count = 0;
            @(posedge clk);
            reader_start = 1'b1;
            @(posedge clk);
            reader_start = 1'b0;
            timeout = 0;
            while (!reader_done && (timeout < 10000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!reader_done) begin
                $display("ERROR reader timeout offset=%0d length=%0d",
                         offset_value, length_value);
                error_count = error_count + 1;
            end else begin
                if (reader_error != 8'h00) begin
                    $display("ERROR reader error=%02x", reader_error);
                    error_count = error_count + 1;
                end
                if (stream_count != length_value) begin
                    $display("ERROR reader count=%0d expected=%0d",
                             stream_count, length_value);
                    error_count = error_count + 1;
                end
            end
            repeat (3) @(posedge clk);
        end
    endtask

    task automatic reset_dut;
        begin
            rst = 1'b1;
            sd_init_done = 1'b0;
            scanner_start = 1'b0;
            reader_start = 1'b0;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            sd_init_done = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    initial if (!HOME_TEST) begin
        media_superfloppy = 1'b0;
        inject_short_sector = 1'b0;
        reset_dut();

        found_count = 0;
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h00) begin
            $display("ERROR MBR scan error=%02x", scanner_error);
            error_count = error_count + 1;
        end
        if ((file_found_mask != 12'hfff) || (found_count != 12)) begin
            $display("ERROR MBR resources mask=%03x count=%0d",
                     file_found_mask, found_count);
            error_count = error_count + 1;
        end
        if ((sectors_per_cluster != 8'd2) ||
            (sectors_per_cluster_shift != 3'd1) ||
            (fat_start_lba != 32'd34) ||
            (data_start_lba != 32'd38) ||
            (max_cluster != 32'd198)) begin
            $display("ERROR MBR layout spc=%0d shift=%0d fat=%0d data=%0d max=%0d",
                     sectors_per_cluster, sectors_per_cluster_shift,
                     fat_start_lba, data_start_lba, max_cluster);
            error_count = error_count + 1;
        end
        if ((found_cluster0 != 32'd20) || (found_size0 != 32'd1500)) begin
            $display("ERROR file01 metadata cluster=%0d size=%0d",
                     found_cluster0, found_size0);
            error_count = error_count + 1;
        end

        run_reader(32'd1100, 32'd400);
        run_reader(32'd900, 32'd300);
        run_virtual_sector(32'h8000_0000, 0);
        run_virtual_sector(32'h8000_0001, 512);
        run_virtual_sector(32'h8000_0002, 1024);
        run_virtual_sector(32'h8000_0000, 0);
        run_virtual_error(32'h8000_0003);
        run_virtual_error(32'h80c0_0000);
        run_virtual_error(32'h7000_0000);
        run_virtual_sector(32'h8000_0000, 0);

        inject_short_sector = 1'b1;
        run_virtual_error(32'h8000_0001);
        inject_short_sector = 1'b0;
        run_virtual_sector(32'h8000_0000, 0);

        inject_overlong_sector = 1'b1;
        run_virtual_error(32'h8000_0001);
        inject_overlong_sector = 1'b0;
        run_virtual_sector(32'h8000_0000, 0);

        inject_missing_end = 1'b1;
        run_virtual_error(32'h8000_0001);
        inject_missing_end = 1'b0;
        run_virtual_sector(32'h8000_0000, 0);
        run_virtual_sector(32'h8000_0001, 512);
        inject_bad_chain = 1'b1;
        run_virtual_error(32'h8000_0002);
        inject_bad_chain = 1'b0;

        simultaneous_end = 1'b1;
        run_reader(32'd0, 32'd512);
        run_virtual_sector(32'h8000_0000, 0);
        run_virtual_sector(32'h8000_0001, 512);
        run_virtual_sector(32'h8000_0002, 1024);
        simultaneous_end = 1'b0;

        media_superfloppy = 1'b1;
        simultaneous_end = 1'b1;
        reset_dut();
        found_count = 0;
        pulse_scanner_start();
        wait_scanner_done();
        if ((scanner_error != 8'h00) || (file_found_mask != 12'hfff) ||
            (fat_start_lba != 32'd2) || (data_start_lba != 32'd6)) begin
            $display("ERROR superfloppy scan error=%02x mask=%03x fat=%0d data=%0d",
                     scanner_error, file_found_mask,
                     fat_start_lba, data_start_lba);
            error_count = error_count + 1;
        end

        media_superfloppy = 1'b0;
        simultaneous_end = 1'b0;
        // Repeat scans without reset: validation must use this volume's
        // layout, not flags left by the preceding successful/failed scan.
        media_total_sectors = 32'd514; // max cluster 255, FAT capacity 256
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h00 || max_cluster != 32'd255)
            $fatal(1, "last representable FAT cluster rejected");
        repeat (3) @(posedge clk);
        media_total_sectors = 32'd516; // max cluster equals FAT capacity
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h21 || file_found_mask != 0)
            $fatal(1, "FAT capacity boundary accepted");
        repeat (3) @(posedge clk);
        media_total_sectors = 32'd400;
        media_root_cluster = 32'd199; // one beyond this volume's max 198
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h24 || file_found_mask != 0)
            $fatal(1, "out-of-volume root cluster accepted");
        repeat (3) @(posedge clk);
        media_root_cluster = 32'h1000_0005;
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h24 || file_found_mask != 0)
            $fatal(1, "high root cluster bits truncated");
        repeat (3) @(posedge clk);
        media_root_cluster = 32'd5;
        simultaneous_end = 1'b1;
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h00 || file_found_mask != 12'hfff)
            $fatal(1, "valid scan after validation failure did not recover");
        simultaneous_end = 1'b0;

        // First and last entries alternate valid/invalid cluster metadata
        // without resetting the parser. Neighbours must not inherit stale
        // range flags; include exact bounds and nonzero high cluster bits.
        override_edge_clusters = 1'b1;
        simultaneous_end = 1'b1;
        for (range_case = 0; range_case < 7; range_case = range_case + 1) begin
            case (range_case)
                0: edge_cluster = 32'd2;
                1: edge_cluster = 32'd0;
                2: edge_cluster = 32'd198;
                3: edge_cluster = 32'd199;
                4: edge_cluster = 32'd1;
                5: edge_cluster = 32'h0001_0014;
                6: edge_cluster = 32'h1000_0014;
            endcase
            found_count = 0;
            pulse_scanner_start();
            wait_scanner_done();
            if ((edge_cluster >= 2) && (edge_cluster <= 198)) begin
                if (scanner_error != 0 || file_found_mask != 12'hfff ||
                    found_count != 12 || found_cluster0 != edge_cluster)
                    $fatal(1, "valid edge cluster lost case=%0d", range_case);
            end else if (scanner_error != 8'h22 ||
                         file_found_mask != 12'h7fe || found_count != 10)
                $fatal(1, "bad edge cluster/stale neighbour case=%0d mask=%03x count=%0d",
                       range_case, file_found_mask, found_count);
            repeat (3) @(posedge clk);
        end
        // A larger volume also exercises high-less with low-greater, equal
        // high halves, and high-greater with low-less (max = 0x00020010).
        media_fat_sectors = 32'd2048;
        media_total_sectors = 32'd266272;
        for (range_case = 0; range_case < 4; range_case = range_case + 1) begin
            case (range_case)
                0: edge_cluster = 32'h0001_ffff;
                1: edge_cluster = 32'h0002_0011;
                2: edge_cluster = 32'h0002_0010;
                3: edge_cluster = 32'h0003_0000;
            endcase
            found_count = 0;
            pulse_scanner_start();
            wait_scanner_done();
            if (max_cluster != 32'h0002_0010)
                $fatal(1, "large-volume test layout wrong");
            if (edge_cluster <= 32'h0002_0010) begin
                if (scanner_error != 0 || file_found_mask != 12'hfff ||
                    found_count != 12 || found_cluster0 != edge_cluster)
                    $fatal(1, "valid large edge cluster lost case=%0d", range_case);
            end else if (scanner_error != 8'h22 ||
                         file_found_mask != 12'h7fe || found_count != 10)
                $fatal(1, "bad large edge cluster/stale neighbour case=%0d", range_case);
            repeat (3) @(posedge clk);
        end
        media_fat_sectors = 32'd2;
        media_total_sectors = 32'd400;
        override_edge_clusters = 1'b0;
        simultaneous_end = 1'b0;

        inject_bad_bpb = 1'b1;
        reset_dut();
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h21 || file_found_mask != 0)
            $fatal(1, "invalid BPB accepted");
        inject_bad_bpb = 1'b0;
        inject_directory_end = 1'b1;
        reset_dut();
        pulse_scanner_start();
        wait_scanner_done();
        if (scanner_error != 8'h22 || file_found_mask != 0)
            $fatal(1, "entries after directory end were accepted");
        inject_directory_end = 1'b0;
        inject_overlong_sector = 1'b1;
        reset_dut();
        pulse_scanner_start();
        wait_scanner_done();
        if ((scanner_error != 8'h10) || !recover_seen)
            $fatal(1, "overlong sector was not rejected");
        inject_overlong_sector = 1'b0;
        inject_short_sector = 1'b1;
        reset_dut();
        pulse_scanner_start();
        wait_scanner_done();
        if ((scanner_error != 8'h10) || !recover_seen) begin
            $display("ERROR short-sector handling error=%02x recover=%0d",
                     scanner_error, recover_seen);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("TEST_PASS tb_fat32_filesystem");
        else
            $display("TEST_FAIL tb_fat32_filesystem errors=%0d", error_count);

        if (error_count != 0)
            $fatal(1, "tb_fat32_filesystem failed");
        $finish;
    end

endmodule
