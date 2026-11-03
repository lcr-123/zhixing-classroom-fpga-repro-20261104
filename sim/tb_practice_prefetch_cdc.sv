`timescale 1ns/1ps
module prefetch_cdc_case #(parameter PHASE = 0)(output reg done = 0);
    reg clk = 0;
    reg sd_card_clk = 0;
    reg rst_ref = 1;
    reg rst_sd = 1;
    reg practice_prefetch_valid_ref = 0;
    reg [3:0] practice_prefetch_image_ref = 0;
    reg prefetch_valid_mailbox_ref;
    reg [3:0] prefetch_image_mailbox_ref;
    reg prefetch_toggle_ref;
    reg [1:0] prefetch_ack_ref_sync;
    reg [2:0] prefetch_toggle_sd_sync;
    reg [4:0] prefetch_payload_sd_meta;
    reg [4:0] prefetch_payload_sd_sync;
    reg [4:0] prefetch_payload_sd;
    reg prefetch_ack_sd;
    reg [4:0] held_payload;
    reg held_toggle;
    integer j;
    always #10 clk = ~clk;
    initial begin
        #(PHASE + 0.25);
        forever #5 sd_card_clk = ~sd_card_clk;
    end
    `include "out/practice_prefetch_cdc/mailbox.vh"

    // The sender may alter neither payload nor toggle while awaiting ACK.
    always @(posedge clk) begin
        if (!rst_ref && prefetch_ack_ref_sync[1] != prefetch_toggle_ref) begin
            held_payload = {prefetch_valid_mailbox_ref, prefetch_image_mailbox_ref};
            held_toggle = prefetch_toggle_ref;
            #1;
            if ({prefetch_valid_mailbox_ref, prefetch_image_mailbox_ref} !== held_payload ||
                prefetch_toggle_ref !== held_toggle)
                $fatal(1, "phase %0d changed in-flight payload", PHASE);
        end
    end
    task automatic expect_payload(input [4:0] wanted);
        integer guard;
        begin
            guard = 0;
            while (prefetch_payload_sd !== wanted ||
                   prefetch_ack_ref_sync[1] != prefetch_toggle_ref) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 30) $fatal(1, "phase %0d lost latest payload %h", PHASE, wanted);
            end
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_ref = 0; rst_sd = 0;
        practice_prefetch_valid_ref = 1; practice_prefetch_image_ref = 3;
        expect_payload(5'h13);
        // Faster updates than round-trip ACK must converge to the last pair.
        for (j = 0; j < 40; j = j + 1) begin
            @(negedge clk);
            practice_prefetch_valid_ref = j[0];
            practice_prefetch_image_ref = 3 + (j % 3);
        end
        @(negedge clk);
        practice_prefetch_valid_ref = 1; practice_prefetch_image_ref = 5;
        expect_payload(5'h15);
        @(negedge clk); practice_prefetch_valid_ref = 0;
        expect_payload(5'h05);
        // Interrupt a request with the actual two-domain reset convention.
        @(negedge clk); practice_prefetch_image_ref = 4;
        @(negedge clk); rst_ref = 1; rst_sd = 1;
        repeat (4) @(negedge clk);
        if (prefetch_payload_sd != 0 || prefetch_toggle_ref != 0 || prefetch_ack_sd != 0)
            $fatal(1, "phase %0d reset retained cache hint", PHASE);
        rst_ref = 0; rst_sd = 0;
        practice_prefetch_valid_ref = 1;
        expect_payload(5'h14);
        done = 1;
    end
endmodule

module tb_practice_prefetch_cdc;
    wire [7:0] done;
    genvar n;
    generate for (n = 0; n < 8; n = n + 1) begin : phase_case
        prefetch_cdc_case #(.PHASE(n)) test_case(done[n]);
    end endgenerate
    initial begin
        wait (&done);
        $display("TEST_PASS production prefetch CDC 8 phases, busy coalescing, stable payload, reset, buffer wiring");
        $finish;
    end
    initial begin #100000; $fatal(1, "prefetch CDC watchdog"); end
endmodule
