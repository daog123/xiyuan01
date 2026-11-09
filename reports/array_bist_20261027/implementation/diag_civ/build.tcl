set_param general.maxThreads 8
read_verilog -sv [list {E:/speed-up/rtl/mac_pe.sv} {E:/speed-up/rtl/w4a8_wave.sv} {E:/speed-up/experiments/array_bist_20261027/array_bist_engine.sv} {E:/speed-up/experiments/array_bist_20261027/done_telemetry.sv} {E:/speed-up/experiments/array_bist_20261027/array_selftest_top.sv}]
set_property include_dirs {E:/speed-up/experiments/array_bist_20261027} [current_fileset]
synth_design -top array_selftest_top -part xcvu9p_CIV-flgb2104-2-i -flatten_hierarchy none -generic {MODE=0 CORRUPT_GOLDEN=0}
create_clock -name cfg_osc -period 16.000 [get_pins startup/CFGMCLK]
create_generated_clock -name selftest_clk -divide_by 8 -source [get_pins startup/CFGMCLK] [get_pins clock_divider/O]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file {E:/speed-up/experiments/array_bist_20261027/diag_civ/timing.rpt}
report_utilization -file {E:/speed-up/experiments/array_bist_20261027/diag_civ/utilization.rpt}
report_drc -file {E:/speed-up/experiments/array_bist_20261027/diag_civ/drc.rpt}
if {[llength [get_ports]] != 0} {error "unexpected general-purpose IO"}
set bad [get_timing_paths -quiet -max_paths 1 -slack_lesser_than 0]
if {[llength $bad] != 0} {error "negative setup slack"}
write_checkpoint -force {E:/speed-up/experiments/array_bist_20261027/diag_civ/routed.dcp}
write_bitstream -force {E:/speed-up/experiments/array_bist_20261027/diag_civ/array_selftest.bit}
puts "ARRAY_AUTONOMOUS_BITSTREAM_PASS variant=diag_civ"
exit
