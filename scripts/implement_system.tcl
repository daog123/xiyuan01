if {[llength $argv]==2 && [lindex $argv 0] eq "--from-synthesis"} {
    open_checkpoint [lindex $argv 1]
} else {
set target_top llm_top
if {[llength $argv]>=2 && [lindex $argv 0] eq "--top"} {
    set target_top [lindex $argv 1]
    if {$target_top ni {llm_top llm_graph_top}} {error "Unsupported top"}
    set argv [lrange $argv 2 end]
}
set root [file normalize [file join [file dirname [info script]] ..]]
set f [open [file join $root config system_sources.txt] r]
set names [split [string trim [read $f]] "\n"]
close $f
foreach name $names {read_verilog -sv [file join $root rtl [string trim $name].sv]}
read_xdc clock.xdc
set generics {}
foreach {key value} $argv {
    if {![string is integer -strict $value] || $value<=0} {error "Invalid hardware parameter: $key=$value"}
    lappend generics "$key=$value"
}
synth_design -top $target_top -part xcvu9p-flga2104-2L-e -mode out_of_context -flatten_hierarchy rebuilt -generic $generics
}
set_property HD.CLK_SRC BUFGCE_X0Y0 [get_ports clk]
write_checkpoint -force synthesized.dcp
report_utilization -file utilization_synth.rpt
report_timing_summary -file timing_synth.rpt
opt_design
place_design
phys_opt_design -directive AggressiveExplore
route_design
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $hold_path] && [get_property SLACK $hold_path]<0} {
    phys_opt_design -hold_fix
    route_design
}
write_checkpoint -force routed.dcp
report_utilization -file utilization_routed.rpt
report_timing_summary -report_unconstrained -file timing_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -delay_type min -max_paths 1]
if {![llength $setup] || ![llength $hold]} {error "No constrained internal timing paths"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set f [open timing_values.txt w]
puts $f "WNS=$wns WHS=$whs"
close $f
if {$wns<0 || $whs<0} {error "Timing not closed: WNS=$wns WHS=$whs"}
set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]
set boxes [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]
if {[llength $latches] || [llength $boxes]} {error "Latch or blackbox inferred"}
puts "SYSTEM_OOC_IMPLEMENTATION_PASS WNS=$wns WHS=$whs"
exit
