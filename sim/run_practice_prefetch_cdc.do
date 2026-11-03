onerror {quit -code 1}
onbreak {quit -code 1}
set stream [open fpga/user_source/hdl_source/top_tf_hdmi_audio.v r]
quietly set top [read $stream]
close $stream
set begin [string first "// Acknowledged mailbox: keep the complete prefetch" $top]
set end [string first "// Publish the complete application state" $top $begin]
if {$begin < 0 || $end < 0} { error "missing production prefetch mailbox" }
file mkdir out/practice_prefetch_cdc
set stream [open out/practice_prefetch_cdc/mailbox.vh w]
puts $stream [string range $top $begin [expr {$end-1}]]
close $stream
foreach pattern {{\.PREFETCH_ENABLE\s+\(1'b1\)} {parameter BUF2_ADDR\s*= FRAME_PIXELS \* 2;} {\.read_addr_2\s+\(BUF2_ADDR\)} {\.write_addr_2\s+\(BUF2_ADDR\)}} {
    if {![regexp $pattern $top]} { error "production cache not enabled/addressed: $pattern" }
}
vlib work
vlog -sv sim/tb_practice_prefetch_cdc.sv
vsim work.tb_practice_prefetch_cdc
run -all
quit -f
