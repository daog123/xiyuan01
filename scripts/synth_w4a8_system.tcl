set src [file normalize [file join [file dirname [info script]] ..]]
set out [file join $src build synth_w4a8_system]
file mkdir $out
read_verilog -sv [list \
    [file join $src rtl task_desc_pkg.sv] \
    [file join $src rtl sync_sdp_ram.sv] \
    [file join $src rtl w4_unpack.sv] \
    [file join $src rtl mac_pe.sv] \
    [file join $src rtl mac_array.sv] \
    [file join $src rtl w4a8_stream.sv] \
    [file join $src rtl task_controller.sv] \
    [file join $src rtl w4a8_system_top.sv]]
synth_design -top w4a8_system_top -part xcvu9p-flga2104-2L-e -flatten_hierarchy rebuilt
write_checkpoint -force [file join $out post_synth.dcp]
report_timing_summary -file [file join $out timing_synth.rpt]
report_utilization -file [file join $out utilization_synth.rpt]
puts "W4A8 system synthesis finished: $out"
exit
