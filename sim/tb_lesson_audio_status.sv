`timescale 1ns/1ps
module tb_lesson_audio_status;
reg ac=0, pc=0, ar=1, pr=1, start=0, stop=0, consume=0, fb=0;
reg [31:0] total=0;
reg [1:0] source_clip=0;
reg [1:0] source_step=1;
wire [8:0] progress;
wire [1:0] clip;
wire valid;
wire played_to_end;
always #5 ac=~ac;
always #7 pc=~pc;
lesson_audio_status dut(ac,ar,start,stop,total,source_clip,consume,source_step,played_to_end,pc,pr,fb,progress,clip,valid);
reg [11:0] last_payload;
reg [11:0] last_display;
reg last_fb=0;
always @(posedge pc) begin
    last_fb=fb || ar || pr;
    #1;
    if (!ar && !pr && !last_fb && {valid,clip,progress} !== last_display)
        $fatal(1,"display changed outside frame boundary");
    last_display={valid,clip,progress};
end
task boundary;
begin
    @(negedge pc); fb=1;
    @(negedge pc); fb=0;
    repeat(20) @(negedge pc);
end endtask
task snapshot;
begin boundary(); boundary(); boundary(); end endtask
task begin_clip(input integer n,input [1:0] c);
begin
    @(negedge ac); total=n; source_clip=c; start=~start;
    repeat(12) @(negedge ac);
    snapshot();
    if (progress!==0 || clip!==c || valid!==(n>0 && n<=4000000))
        $fatal(1,"bad start n=%0d progress=%0d",n,progress);
    if (played_to_end) $fatal(1,"new clip inherited completion");
end endtask
task accept_sample;
begin
    @(negedge ac); consume=1;
    @(negedge ac); consume=0;
    repeat(300) @(negedge ac);
end endtask
integer n,i,expected;
initial begin
    repeat(5) @(negedge ac); ar=0; pr=0;
    for(n=1;n<=7;n=n+1) begin
        case(n)
            1: expected=1; 2: expected=2; 3: expected=3;
            4: expected=255; 5: expected=256; 6: expected=257;
            7: expected=1024;
        endcase
        begin_clip(expected,n%3);
        for(i=1;i<=expected;i=i+1) begin
            accept_sample();
            if (dut.fraction !== (i*256/expected))
                $fatal(1,"ratio n=%0d sample=%0d got=%0d",expected,i,dut.fraction);
        end
        snapshot();
        if (progress!==256) $fatal(1,"completed clip not full");
        if (!played_to_end) $fatal(1,"audible completion missing");
        accept_sample(); snapshot();
        if(progress!==256) $fatal(1,"overread exceeded full");
    end
    begin_clip(4000000,2);
    for(i=0;i<15625;i=i+1) accept_sample();
    snapshot();
    if(progress!==1 || dut.count!==15625 || dut.total!==4000000)
        $fatal(1,"maximum duration truncated");
    repeat(5) snapshot();
    if(progress!==1) $fatal(1,"idle/early stop advanced progress");
    @(negedge ac); stop=~stop;
    repeat(12) @(negedge ac); snapshot();
    if(valid || progress!=0) $fatal(1,"navigation retained old progress");
    if(played_to_end) $fatal(1,"navigation retained audible completion");
    begin_clip(3,2); accept_sample(); snapshot();
    if(!valid || progress!=85) $fatal(1,"same page restart retained stale progress");
    // A navigation cancellation wins over a coincident header validation.
    @(negedge ac); stop=~stop; start=~start; total=2; source_clip=0;
    repeat(12) @(negedge ac); snapshot();
    if(valid || progress!=0) $fatal(1,"start/stop priority");
    begin_clip(0,0); begin_clip(4000001,1);
    accept_sample(); snapshot();
    if(valid || progress!=0) $fatal(1,"invalid total accepted");
    begin_clip(4,0);
    source_step=0; accept_sample(); snapshot();
    if(progress!=0 || dut.count!=0) $fatal(1,"zero-step sample moved progress");
    source_step=2; accept_sample(); snapshot();
    if(progress!=128 || dut.count!=2) $fatal(1,"two-step sample wrong progress");
    accept_sample(); snapshot();
    if(progress!=256 || dut.count!=4) $fatal(1,"two-step EOF not full");
    source_step=1;
    begin_clip(3,1); accept_sample();
    @(negedge pc); pr=1;
    repeat(4) @(negedge pc); pr=0;
    snapshot();
    if(!valid || clip!=1 || progress!=85) $fatal(1,"video reset recovery");
    @(negedge ac); ar=1;
    repeat(4) @(negedge ac); ar=0;
    snapshot();
    if(valid) $fatal(1,"audio reset retained stale snapshot");
    $display("TEST_PASS lesson audio status: ratios, 250s, idle, CDC, resets");
    $finish;
end
initial begin #100000000; $fatal(1,"timeout"); end
endmodule
