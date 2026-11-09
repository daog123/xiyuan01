set root [file dirname [file normalize [info script]]]
read_verilog -sv [file join $root rtl w4a8_gemv_stream.sv]
set f [open clock.xdc w]
puts $f {create_clock -name core_clk -period 10 [get_ports clk]}
close $f
read_xdc clock.xdc
set_param general.maxThreads 4
synth_design -top w4a8_gemv_stream -part xcvu9p-flga2104-2L-e -mode out_of_context -flatten_hierarchy rebuilt
set_property HD.CLK_SRC BUFGCE_X0Y0 [get_ports clk]
report_utilization -file utilization_synth.rpt
write_checkpoint -force synthesized.dcp
opt_design
place_design
phys_opt_design -directive AggressiveExplore
route_design
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]<0} {phys_opt_design -hold_fix;route_design}
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
report_route_status -file route_status.rpt
write_checkpoint -force routed.dcp
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set f [open timing_values.txt w]
puts $f "WNS=$wns WHS=$whs"
close $f
if {$wns<0 || $whs<0} {error "Timing not closed"}
if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] || [llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]]} {error "Blackbox or latch"}
puts "ROUND8_OOC_PASS WNS=$wns WHS=$whs"
exit
