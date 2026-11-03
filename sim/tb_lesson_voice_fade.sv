`timescale 1ns/1ps
module tb_lesson_voice_fade;
reg ac=0,pc=0,rst=1,start=0,ending=0,stop=0,control=0;
reg [1:0] clip=0;
reg [7:0] head=8'h40;
integer supplied=0,available=0,accepted=0,discarded=0;
wire read,accept,bclk,lrck,dout,valid;
wire [23:0] left_pcm,right_pcm;
always #5 ac=~ac;
always #2 pc=~pc;
hdmi_audio_tone_i2s_64fs dut (
    .I_mclk(ac),.I_rst(rst),.I_lab_active(1'b1),
    .I_lab_frequency(2'd0),.I_lab_amplitude(2'd2),
    .I_lab_waveform(2'd0),.I_lab_muted(1'b1),.I_song_enable(1'b0),
    .I_lab_control_toggle(control),.I_voice_volume(3'd4),
    .I_voice_volume_toggle(1'b0),.I_practice_prev_tone_toggle(1'b0),
    .I_practice_next_tone_toggle(1'b0),
    .I_boot_success_tone_toggle(1'b0),
    .I_voice_start_toggle(start),.I_voice_end_toggle(ending),
    .I_voice_stop_toggle(stop),.I_voice_clip_index(clip),
    .I_voice_fifo_data(head),.I_voice_fifo_speed(2'd3),
    .I_voice_fifo_valid(supplied<available),
    .I_voice_fifo_empty(supplied>=available),.I_voice_played_to_end(1'b0),
    .O_voice_fifo_read(read),
    .O_voice_sample_accept(accept),.O_voice_source_step(),
    .O_voice_subtitle_active(),
    .O_voice_subtitle_clip(),.O_voice_subtitle_cue(),.O_voice_subtitle_toggle(),
    .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout)
);
I2S_receiver receiver(pc,rst,bclk,lrck,dout,valid,left_pcm,right_pcm);
always @(posedge ac) begin
    if(read && supplied<available) begin
        supplied<=supplied+1;
        if(accept) accepted<=accepted+1;
        else discarded<=discarded+1;
    end
end
task sample(output integer v);
begin : get_sample
    forever begin
        @(negedge pc);
        if(valid) begin
            if(left_pcm!==right_pcm) $fatal(1,"I2S mono channels differ");
            v=$signed(left_pcm);
            disable get_sample;
        end
    end
end endtask
task begin_clip(input [1:0] c,input [7:0] pcm,input integer length);
begin
    @(negedge ac); clip=c; head=pcm; supplied=0; available=length;
    start=~start;
    wait(dut.S_voice_active && dut.S_voice_clip==c);
end endtask
integer i,v,previous,changes,frozen_accept,zero_seen,negative_seen;
integer tiny_peak;
task reach_full;
begin
    previous=0; changes=0;
    for(i=0;i<550;i=i+1) begin
        sample(v);
        if(v<previous || v-previous>131072)
            $fatal(1,"fade-in is discontinuous: %0d -> %0d",previous,v);
        if(v!=previous) changes=changes+1;
        previous=v;
    end
    if(v!=4194304 || changes<30) $fatal(1,"fade-in did not reach full PCM");
end endtask
task reach_silence;
begin
    previous=4194304; changes=0;
    for(i=0;i<550;i=i+1) begin
        sample(v);
        if(v>previous || previous-v>131072)
            $fatal(1,"fade-out is discontinuous: %0d -> %0d",previous,v);
        if(v!=previous) changes=changes+1;
        previous=v;
    end
    if(v!=0 || dut.S_voice_active || changes<30)
        $fatal(1,"fade-out failed to finish within 550 frames");
end endtask
initial begin
    repeat(8) @(negedge ac); rst=0;
    repeat(20) @(negedge ac);
    begin_clip(0,8'h40,2000); reach_full();
    // Other audio mailboxes must never override narration's envelope.
    @(negedge ac); control=~control;
    repeat(90) begin sample(v); if(v!=4194304) $fatal(1,"control interrupted speech"); end
    @(negedge ac); available=supplied; ending=~ending;
    reach_silence();
    if(discarded!=0) $fatal(1,"natural EOF discarded samples");

    begin_clip(1,8'h40,2000); reach_full();
    @(negedge ac); stop=~stop;
    wait(dut.S_voice_fading); frozen_accept=accepted;
    reach_silence();
    wait(supplied==available);
    if(accepted!=frozen_accept || discarded==0)
        $fatal(1,"cancelled bytes counted as audible samples");
    repeat(12) @(negedge ac);

    // FIFO was emptied before a new producer starts, while old audible tail
    // is still fading. Latest pending page replaces the previous request.
    begin_clip(0,8'h40,2000); reach_full();
    @(negedge ac); available=supplied; ending=~ending;
    wait(dut.S_voice_fading && dut.S_voice_envelope==24);
    @(negedge ac); head=8'hc0; supplied=0; available=2000; clip=1; start=~start;
    repeat(12) @(negedge ac); clip=2; start=~start;
    zero_seen=0; negative_seen=0;
    repeat(1100) begin
        sample(v);
        if(v==0) zero_seen=1;
        if(v<0) begin
            if(!zero_seen) $fatal(1,"new page bypassed zero crossing");
            negative_seen=1;
        end
    end
    if(!negative_seen || dut.S_voice_clip!=2 || v!=-4194304)
        $fatal(1,"replacement page lost or failed to fade in");
    @(negedge ac); stop=~stop;
    wait(dut.S_voice_fading);
    @(negedge ac); rst=1; start=0; ending=0; stop=0; control=0; available=0; supplied=0;
    repeat(8) @(negedge ac); rst=0;
    repeat(10) sample(v);
    if(v!=0 || dut.S_voice_active || dut.S_voice_start_pending)
        $fatal(1,"reset interrupted envelope did not clear");

    // Empty FIFO is a bounded silent wait; an EOF must still release it.
    begin_clip(0,8'h40,0);
    repeat(40) begin sample(v); if(v!=0) $fatal(1,"underflow not silent"); end
    @(negedge ac); ending=~ending;
    repeat(100) sample(v);
    if(dut.S_voice_active) $fatal(1,"empty EOF stuck active");
    @(negedge ac); supplied=0; available=1; clip=1; start=~start; ending=~ending;
    tiny_peak=0;
    repeat(100) begin sample(v); if(v>tiny_peak) tiny_peak=v; end
    if(supplied!=1 || dut.S_voice_active || dut.S_voice_start_pending || tiny_peak==0)
        $fatal(1,"simultaneous start/end lost tiny clip");
    // Reset with retained high source tokens must not replay a stale start.
    @(negedge ac); rst=1; start=1; ending=1; stop=1; available=0; supplied=0;
    repeat(8) @(negedge ac); rst=0;
    repeat(15) sample(v);
    if(dut.S_voice_active || dut.S_voice_start_pending || read)
        $fatal(1,"retained source tokens replayed after audio reset");
    // A new start arriving on the pending-activation edge supersedes it.
    @(negedge ac); clip=0; available=2000; start=~start;
    @(negedge ac); clip=2; start=~start;
    repeat(20) @(negedge ac);
    if(!dut.S_voice_active || dut.S_voice_clip!=2 || dut.S_voice_start_pending)
        $fatal(1,"newest start lost at pending activation");
    // Lose valid for one requested read, then refill: no stuck pending read.
    wait(read);
    @(negedge ac); available=supplied;
    repeat(5) sample(v);
    @(negedge ac); available=supplied+20;
    frozen_accept=accepted;
    repeat(10) sample(v);
    if(accepted<=frozen_accept) $fatal(1,"empty read prevented refill retry");
    @(negedge ac); stop=~stop;
    repeat(600) sample(v);
    if(dut.S_voice_active || dut.S_voice_start_pending)
        $fatal(1,"late cancellation stuck active");
    @(negedge ac); available=20; supplied=0; start=~start; stop=~stop;
    repeat(20) sample(v);
    if(dut.S_voice_active || dut.S_voice_start_pending || accept)
        $fatal(1,"simultaneous stop/start replayed cancelled content");
    $display("TEST_PASS lesson fade: decoded I2S in/out, cancel, replacement, EOF, reset");
    $finish;
end
initial begin #30000000; $fatal(1,"fade test timeout"); end
endmodule
