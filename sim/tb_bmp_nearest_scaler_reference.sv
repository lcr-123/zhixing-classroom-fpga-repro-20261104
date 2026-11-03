`timescale 1ns/1ps

module tb_bmp_nearest_scaler_reference #(
    parameter integer PRODUCTION = 0
);
    localparam W = PRODUCTION ? 640 : 8;
    localparam H = PRODUCTION ? 480 : 8;
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg [15:0] source_width = 0, source_height = 0;
    reg [2:0] zoom_level = 2;
    reg source_valid = 0;
    reg [23:0] source_rgb = 0;
    wire source_start, output_valid, busy, done, source_overrun;
    wire [23:0] output_rgb;
    reg [23:0] captured [0:W*H-1];
    integer count = 0;
    integer zoom;
    always #5 clk = ~clk;
    always @(posedge clk) if (output_valid) begin
        if (count >= W*H) $fatal(1, "extra output pixel");
        captured[count] = output_rgb;
        count = count + 1;
    end

    bmp_nearest_scaler #(.OUTPUT_WIDTH(W), .OUTPUT_HEIGHT(H),
        .MAX_SOURCE_WIDTH(PRODUCTION ? 1280 : 32), .EMIT_DIV(4), .FILTER_ENABLE(0)) dut (
        .clk(clk), .rst(rst), .start(start), .source_width(source_width),
        .source_height(source_height), .zoom_level(zoom_level),
        .source_valid(source_valid), .source_rgb(source_rgb),
        .source_start(source_start), .output_valid(output_valid),
        .output_rgb(output_rgb), .busy(busy), .done(done),
        .source_overrun(source_overrun));

    task automatic run_case(input integer sw, input integer sh, input integer z);
        integer cw, ch, ox, oy, aw, ah, lb, tb;
        integer x, y, sx, sy;
        reg [23:0] expected;
        begin
            cw=sw; ch=sh; aw=W; ah=H; lb=0; tb=0;
            case (z)
                0: begin aw=W/2; ah=H/2; lb=W/4; tb=H/4; end
                1: begin aw=W*3/4; ah=H*3/4; lb=W/8; tb=H/8; end
                3: begin cw=sw*4/5; ch=sh*4/5; end
                4: begin cw=sw*2/3; ch=sh*2/3; end
            endcase
            if (cw==0) cw=1;
            if (ch==0) ch=1;
            ox=(sw-cw)/2; oy=(sh-ch)/2;
            @(negedge clk);
            count=0; source_width=sw; source_height=sh; zoom_level=z; start=1;
            @(negedge clk); start=0;
            wait(source_start);
            @(negedge clk);
            for (y=0; y<sh; y=y+1) begin
                for (x=0; x<sw; x=x+1) begin
                    source_rgb={y[7:0],x[7:0],8'h5A}; source_valid=1;
                    @(negedge clk); source_valid=0;
                    repeat(63) @(negedge clk);
                end
            end
            wait(!busy);
            @(posedge clk);
            #1; // consume the final registered output_valid before checking
            if (count!=W*H || source_overrun)
                $fatal(1,"invalid output count=%0d overrun=%b",count,source_overrun);
            for (y=0; y<H; y=y+1) begin
                for (x=0; x<W; x=x+1) begin
                    expected=0;
                    if (x>=lb && x<lb+aw && y>=tb && y<tb+ah) begin
                        sx=ox+(x-lb)*cw/aw;
                        sy=oy+((y-tb+1)*ch+ah-1)/ah-1;
                        expected={sy[7:0],sx[7:0],8'h5A};
                    end
                    if(captured[y*W+x]!==expected)
                        $fatal(1,"zoom=%0d %0dx%0d at %0d,%0d got=%h expected=%h",
                            z,sw,sh,x,y,captured[y*W+x],expected);
                end
            end
        end
    endtask

    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        if (PRODUCTION) begin
            // Real 19-bit frame counters and 150% three-row replay; then
            // change crop ratio/origin without resetting the production DUT.
            run_case(321,241,4);
            run_case(640,480,3);
        end else begin
            // All five ratios, odd dimensions, repeated starts without reset.
            for(zoom=0; zoom<5; zoom=zoom+1) run_case(7,7,zoom);
            run_case(6,5,3); // crop origin zero after a nonzero origin
            run_case(9,9,4);
            run_case(8,8,2);
        end
        $display("TEST_PASS tb_bmp_nearest_scaler_reference");
        $finish;
    end
    initial begin
        #(PRODUCTION ? 1000000000 : 2000000);
        $fatal(1,"reference test timeout");
    end
endmodule
