# Independent IP Integrator smoke project. Does not instantiate board I/O or DDR IP.
if {$argc != 1} {error "Usage: -tclargs /path/to/packaged/ip"}
set repo [file normalize [lindex $argv 0]]
if {![file exists [file join $repo component.xml]]} {error "component.xml missing"}
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build board_ip_bd-[clock seconds]-[pid]]
create_project endpoint_bd $out -part xcvu9p_CIV-flgb2104-2-i
set_property ip_repo_paths $repo [current_project]
update_ip_catalog
create_bd_design endpoint_smoke
create_bd_cell -type ip -vlnv xiyuan.local:accelerator:w4a8_board_endpoint:1.0 endpoint
make_bd_intf_pins_external [get_bd_intf_pins endpoint/S_AXI]
make_bd_intf_pins_external [get_bd_intf_pins endpoint/M_AXI]
foreach name {clk rst ddr_ready} {make_bd_pins_external [get_bd_pins endpoint/$name]}
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports clk_0]
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports rst_0]
assign_bd_address -offset 0 -range 0x1000 -target_address_space [get_bd_addr_spaces S_AXI_0] [get_bd_addr_segs endpoint/S_AXI/registers]
assign_bd_address -offset 0x0000000800000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces endpoint/M_AXI] [get_bd_addr_segs M_AXI_0/Reg]
validate_bd_design
save_bd_design
set report [open [file join $out address.rpt] w]
foreach segment [get_bd_addr_segs] {
    puts $report "$segment offset=[get_property OFFSET $segment] range=[get_property RANGE $segment]"
}
close $report
generate_target all [get_files endpoint_smoke.bd]
make_wrapper -files [get_files endpoint_smoke.bd] -top -import
puts "W4A8_ENDPOINT_IP_BD_PASS output=$out"
close_project
exit
