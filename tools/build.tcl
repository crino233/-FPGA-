set root [file normalize [file join [file dirname [info script]] ..]]
set output_dir [file join $root build]
file mkdir $output_dir
cd [file join $root src td_project]
file copy -force [file join $root src app photo_font.dath] photo_font.dath
file copy -force [file join $root src app photo_subtitle_font.dath] photo_subtitle_font.dath
if {![file exists anlu_hdmi.al]} {
    create_project anlu_hdmi ./ -family EG4 -device EG4S20BG256
}
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run anlu_hdmi.al
add_include_dir ../user_source/hdl_source/SD
add_include_dir ../user_source/hdl_source/include
top_module top
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
read_adc ../app/badge_pins.adc
read_sdc ../user_source/constraints_source/timing.sdc
set_param rtl min_ripple_len 18
commit_param -step rtl
optimize_rtl
report_area -file ../../build/anlu_hdmi_rtl.area
optimize_gate
legalize_phy_inst
update_timing
report_area -file ../../build/anlu_hdmi_gate.area
report_timing_summary -file ../../build/anlu_hdmi_gate.timing
set_param place seed 1
commit_param -step place
place
update_timing -mode manhattan
report_area -file ../../build/anlu_hdmi_place.area
report_timing_summary -file ../../build/anlu_hdmi_place.timing
export_db ../../build/anlu_hdmi_place.db
set_param route fix_hold on
if {[catch {route} route_error]} {
    puts "Repair invalid routing with the hold buffers retained: $route_error"
    report_route_status -remove_invalid_route -drc -file ../../build/anlu_hdmi_route_repair.log
    export_db ../../build/anlu_hdmi_hold_repair.db
    set_param route effort routability
    if {[catch {route -incremental} route_retry_error]} {
        export_db ../../build/anlu_hdmi_hold_retry_failed.db
        error "Route retry failed: $route_retry_error"
    }
}
update_timing -mode final
fix_hold -eco
update_timing -mode final
report_area -file ../../build/anlu_hdmi_route.area
report_timing_summary -file ../../build/anlu_hdmi_route.timing
report_timing_status -file ../../build/anlu_hdmi_route.ts
report_route_status -drc
export_db ../../build/anlu_hdmi_route.db
bitgen -bit ../../build/anlu_hdmi.bit
puts "BADGE_BUILD_COMPLETE"
close_project
exit
