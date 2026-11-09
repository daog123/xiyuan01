set clock_site BUFGCE_X0Y0
if {[llength [get_sites -quiet $clock_site]] != 1} {
    set clock_site [lindex [lsort [get_sites -quiet BUFGCE*]] 0]
}
if {$clock_site eq ""} {puts "ERROR: no virtual OOC clock site available"; exit 4}
# Evaluation-only virtual source; no board or actual parent BUFG is confirmed.
set_property HD.CLK_SRC $clock_site [get_ports clk]
puts "OOC_CLOCK_SOURCE_ASSUMPTION=$clock_site"
report_utilization -file [file join $out utilization_synth.rpt]
report_utilization -hierarchical -file [file join $out utilization_hier_synth.rpt]
report_timing_summary -report_unconstrained -file [file join $out timing_synth.rpt]
report_timing -from [all_registers] -to [all_registers] -max_paths 10 -file [file join $out internal_timing_synth.rpt]
check_timing -verbose -file [file join $out check_timing_synth.rpt]
report_drc -file [file join $out drc_synth.rpt]
if {[llength [info commands report_ram_utilization]]} {
    report_ram_utilization -include_lutram -file [file join $out ram_synth.rpt]
}
set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]
set f [open [file join $out primitive_counts.txt] w]
puts $f "Vivado=[version -short]"
puts $f "Part=$part (evaluation only, board unspecified)"
puts $f "Configuration=ROWS:4 COLS:4 TILE_K:8 MAX_M:16 MAX_N:16 MAX_K:32 OPTIMIZED:$optimized DOUBLE_BUFFER:$double_buffer B_LOAD_GAP:0"
puts $f "Clock_period_ns=10.000"
puts $f "Virtual_OOC_clock_source=$clock_site (assumed, board unspecified)"
puts $f "Latch_count=[llength $latches]"
set refs [dict create]
foreach cell [get_cells -hier -filter {IS_PRIMITIVE == 1}] {
    set ref [get_property REF_NAME $cell]
    dict incr refs $ref
}
foreach ref [lsort [dict keys $refs]] {puts $f "$ref=[dict get $refs $ref]"}
close $f
if {[llength $latches]} {puts "ERROR: inferred latch(es): $latches"; exit 3}
puts "SYNTHESIS_PASS part=$part"
if {$impl} {
    # No board I/O placement. Internal routed timing in an OOC context only.
    opt_design
    place_design
    route_design
    write_checkpoint -force [file join $out routed_ooc.dcp]
    report_utilization -file [file join $out utilization_ooc.rpt]
    report_timing_summary -report_unconstrained -file [file join $out timing_ooc.rpt]
    report_timing -from [all_registers] -to [all_registers] -max_paths 10 -file [file join $out internal_timing_ooc.rpt]
    check_timing -verbose -file [file join $out check_timing_ooc.rpt]
    report_route_status -file [file join $out route_status_ooc.rpt]
    report_drc -file [file join $out drc_ooc.rpt]
    puts "OOC_IMPLEMENTATION_FINISHED"
}
exit
