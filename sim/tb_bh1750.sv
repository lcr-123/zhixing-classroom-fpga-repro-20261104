`timescale 1ns/1ps
module tb_bh1750;
reg clk=0, rst=1;
always #10 clk=~clk;
tri1 scl,sda;
reg slave_low=0, force_scl=0, force_sda=0;
assign scl=force_scl ? 1'b0 : 1'bz;
assign sda=(slave_low || force_sda) ? 1'b0 : 1'bz;
wire [15:0] raw, errors;
wire sample, valid;
reg present=1, nack_command=0;
reg [15:0] light=16'h8390;
integer commands=0, samples=0, stops=0, powerups=0;
integer command_index=0;
integer cycles=0, conversion_stop=0;
reg conversion_pending=0;
always @(posedge clk) cycles=cycles+1;
reg [7:0] addr,cmd;
reg master_ack;
bh1750_reader #(.TICK_CYCLES(8),.TIMEOUT_TICKS(40),
    .POWERUP_CYCLES(20),.MEASURE_CYCLES(120)) dut (
    .clk(clk),.rst(rst),.scl(scl),.sda(sda),.sample_raw(raw),
    .sample_valid(sample),.sensor_valid(valid),.error_count(errors),.watchdog_tick());
task check(input bit ok,input string message);
    if(!ok) begin $display("TEST_FAIL %s",message); $fatal(1); end
endtask
task get_byte(output reg [7:0] data);
    integer i;
    begin for(i=7;i>=0;i=i-1) begin @(posedge scl); #1; data[i]=sda; end end
endtask
task ack_slave(input bit accept);
    begin @(negedge scl); #2; slave_low=accept;
        @(posedge scl); @(negedge scl); #2; slave_low=0; end
endtask
task send_byte(input [7:0] data, input bit expected_ack);
    integer i;
    begin
        for(i=7;i>=0;i=i-1) begin
            #2; slave_low=!data[i]; @(posedge scl); @(negedge scl);
        end
        #2; slave_low=0; @(posedge scl); #1;
        check(sda==!expected_ack,"master ACK high byte / NACK final byte");
        @(negedge scl);
    end
endtask
task wait_stop;
    begin : stop_wait
        forever begin @(posedge sda); #1; if(scl===1'b1) disable stop_wait; end
    end
endtask
// Pin-level slave: validates addresses, opcodes, ACK/NACK and distinct STOPs.
initial forever begin
    @(negedge sda);
    if(scl===1'b1 && !rst && present && !force_sda) begin
        if(conversion_pending) begin
            check(cycles-conversion_stop>=120,"measurement wait is never shortened by shared tick");
            conversion_pending=0;
        end
        get_byte(addr);
        check(addr==8'h46 || addr==8'h47,"7-bit 0x23 address");
        ack_slave(1);
        if(addr[0]) begin
            send_byte(light[15:8],1); send_byte(light[7:0],0);
        end else begin
            get_byte(cmd);
            if(cmd==8'h01) begin command_index=0; powerups=powerups+1; end
            case(command_index)
                0: check(cmd==8'h01,"power on");
                1: check(cmd==8'h07,"reset data register");
                2: check(cmd==8'h42,"MTreg high=69");
                3: check(cmd==8'h65,"MTreg low=69");
                default: check(cmd==8'h20,"single high-resolution mode");
            endcase
            command_index=command_index+1; commands=commands+1;
            ack_slave(!nack_command);
        end
        wait_stop(); stops=stops+1;
        if(!addr[0] && cmd==8'h20) begin
            conversion_stop=cycles; conversion_pending=1;
        end
    end
end
always @(posedge clk) if(sample) begin
    check(raw==light,"MSB-first exact measurement"); samples=samples+1;
end
initial begin
    repeat(6) @(negedge clk); rst=0;
    wait(samples==3); check(valid && commands==7,"three real readings");
    // Stretch SCL while the master releases it, then allow completion.
    @(negedge scl); force_scl=1;
    repeat(100) @(negedge clk); force_scl=0;
    wait(samples==4); check(errors==0,"finite clock stretch accepted");
    nack_command=1; wait(errors==1); check(!valid,"command NACK invalidates sample");
    nack_command=0; wait(samples==5); check(powerups>=2,"reinitialize after NACK");
    // Disconnect at a STOP; floating bus gives address NACK, never zero lux.
    wait_stop(); present=0;
    wait(errors==2); check(!valid,"missing module fails closed");
    present=1; wait(samples==6);
    // Held-low SCL must release both master outputs after bounded timeout.
    wait_stop(); force_scl=1;
    wait(errors==3); check(!valid,"stuck clock bounded failure");
    force_scl=0; wait(samples==7);
    wait_stop(); force_sda=1;
    wait(errors==4); check(!valid,"stuck data bus bounded recovery");
    force_sda=0; wait(samples==8);
    // Reset interrupts a transaction without retaining a partial word.
    @(negedge scl); rst=1; slave_low=0;
    repeat(8) @(negedge clk);
    check(!dut.bus.scl_low && !dut.bus.sda_low && !valid,"reset releases bus");
    $display("TEST_PASS bh1750 pin protocol, init, STOP, ACK/NACK, stretch, disconnect, stuck buses, reset");
    $finish;
end
initial begin #20000000; $fatal(1,"TEST_FAIL timeout"); end
endmodule
