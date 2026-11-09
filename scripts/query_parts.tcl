set root [file normalize [file join [file dirname [info script]] ..]]
set build [file join $root build]
file mkdir $build
set f [open [file join $build installed_vu9p.txt] w]
puts $f "Vivado: [version -short]"
set parts [lsort [get_parts -quiet *vu9p*]]
puts $f "Installed VU9P parts: $parts"
if {[llength $parts] == 0} {close $f; puts "NO_VU9P_SUPPORT"; exit 2}
set preferred xcvu9p-flga2104-2L-e
if {[lsearch -exact $parts $preferred] >= 0} {set part $preferred} else {set part [lindex $parts 0]}
puts $f "Selected evaluation part: $part (not a confirmed board)"
close $f
set f [open [file join $build selected_part.txt] w]
puts $f $part
close $f
puts "SELECTED_PART=$part"
exit
