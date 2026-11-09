# Package the validated RTL endpoint for IP Integrator; no board pinout is guessed.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build board_endpoint_ip-[clock seconds]-[pid]]
if {[file exists $out]} {error "Use a new output directory; refusing to replace an existing IP package"}
file mkdir $out
create_project endpoint_pack [file join $out project] -part xcvu9p_CIV-flgb2104-2-i
set f [open [file join $root config board_endpoint_sources.txt] r]
set names [split [string trim [read $f]] \n]
close $f
foreach n $names {
    set src [file join $root rtl [string trim $n].sv]
    if {![file exists $src]} {set src [file join $root rtl [string trim $n].v]}
    add_files $src
}
set_property top w4a8_board_ip [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir [file join $out ip] -vendor xiyuan.local -library accelerator -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name w4a8_board_endpoint $core
set_property display_name {W4A8 LINEAR board endpoint} $core
set_property description {AXI4-Lite task mailbox and 64-bit AXI4 DDR master; requires a board shell.} $core
set_property version 1.0 $core
set_property core_revision 1 $core
# Replace any name-based inference with explicit, audited bus maps.
foreach bus [ipx::get_bus_interfaces -of_objects $core] {ipx::remove_bus_interface [get_property name $bus] $core}
foreach mm [ipx::get_memory_maps -of_objects $core] {ipx::remove_memory_map [get_property name $mm] $core}
foreach sp [ipx::get_address_spaces -of_objects $core] {ipx::remove_address_space [get_property name $sp] $core}
proc map_port {bus logical physical} {
    set p [ipx::add_port_map $logical $bus]
    set_property physical_name $physical $p
}
proc parameter {bus name value} {
    set p [ipx::add_bus_parameter $name $bus]
    set_property value $value $p
}
set control [ipx::add_bus_interface S_AXI $core]
set_property interface_mode slave $control
set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 $control
set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $control
foreach n {AWADDR AWVALID AWREADY WDATA WSTRB WVALID WREADY BRESP BVALID BREADY ARADDR ARVALID ARREADY RDATA RRESP RVALID RREADY} {
    map_port $control $n s_axi_[string tolower $n]
}
foreach {n v} {PROTOCOL AXI4LITE ADDR_WIDTH 12 DATA_WIDTH 32 READ_WRITE_MODE READ_WRITE} {parameter $control $n $v}
set mm [ipx::add_memory_map S_AXI $core]
set block [ipx::add_address_block registers $mm]
set_property base_address 0 $block
set_property range 4096 $block
set_property width 32 $block
set_property usage register $block
set_property slave_memory_map_ref S_AXI $control
set memory [ipx::add_bus_interface M_AXI $core]
set_property interface_mode master $memory
set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 $memory
set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $memory
foreach n {ARVALID ARREADY ARADDR ARID ARLEN ARSIZE ARBURST RVALID RREADY RDATA RID RRESP RLAST AWVALID AWREADY AWADDR AWID AWLEN AWSIZE AWBURST WVALID WREADY WDATA WSTRB WLAST BVALID BREADY BID BRESP} {
    map_port $memory $n m_axi_[string tolower $n]
}
foreach {n v} {PROTOCOL AXI4 ADDR_WIDTH 64 DATA_WIDTH 64 ID_WIDTH 4 READ_WRITE_MODE READ_WRITE SUPPORTS_NARROW_BURST 1 HAS_BURST 1 HAS_CACHE 0 HAS_LOCK 0 HAS_PROT 0 HAS_QOS 0 HAS_REGION 0 MAX_BURST_LENGTH 256} {parameter $memory $n $v}
set address_space [ipx::add_address_space M_AXI $core]
set_property range 18446744073709551616 $address_space
set_property width 64 $address_space
set_property master_address_space_ref M_AXI $memory
set clkbus [ipx::add_bus_interface clk $core]
set_property interface_mode slave $clkbus
set_property bus_type_vlnv xilinx.com:signal:clock:1.0 $clkbus
set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 $clkbus
map_port $clkbus CLK clk
parameter $clkbus ASSOCIATED_BUSIF S_AXI:M_AXI
parameter $clkbus ASSOCIATED_RESET rst
parameter $clkbus FREQ_HZ 100000000
set rstbus [ipx::add_bus_interface rst $core]
set_property interface_mode slave $rstbus
set_property bus_type_vlnv xilinx.com:signal:reset:1.0 $rstbus
set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 $rstbus
map_port $rstbus RST rst
parameter $rstbus POLARITY ACTIVE_HIGH
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
puts "W4A8_ENDPOINT_IP_PACKAGE_PASS [get_property vlnv $core] output=$out"
close_project
exit
