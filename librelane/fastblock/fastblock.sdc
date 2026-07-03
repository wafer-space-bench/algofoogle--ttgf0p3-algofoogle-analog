#NOTE: This has some notable edits from a copy of LibreLane's own scripts/base.sdc.

#set clock_port __VIRTUAL_CLK__

# Clock source is a specific pin in the design (after a clock-source mux):
# Note that it is normally derived from one of the VCOs,
# but could also come from a mux that selects the Tiny Tapeout "clk" input instead,
# but we don't care about that for our constraints (as it is a slower clock).
set clock_pin $::env(CLOCK_NET)

# Let's assign a name for this clock in the context of SDC:
set clock_name "worker_clk"

# Create the clock:
puts "\[INFO] Using clock pin $clock_pin and assigning clock name $clock_name"
create_clock -name $clock_name -period $::env(CLOCK_PERIOD) [get_pins $clock_pin]

# set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
# set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
# puts "\[INFO] Setting output delay to: $output_delay_value"
# puts "\[INFO] Setting input delay to: $input_delay_value"

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
} 

set clocks [get_clocks $clock_name]

# Commented out as we are assuming NO inputs are synchronous to worker_clk:
# set_input_delay $input_delay_value -clock $clocks [all_inputs]
# set_output_delay $output_delay_value -clock $clocks [all_outputs]

if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}

# set_driving_cell \
#     -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
#     -pin [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
#     [all_inputs]

# set_driving_cell \
#     -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
#     -pin [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
#     $clk_input ; # $clk_input would normally be set by: set clk_input [get_port $clock_port]

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

puts "\[INFO] Setting clock uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks
# default=0.25(ns), but maybe 0.5 is better?

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $clocks
# default=0.15(ns). We used to use 0.1

#NOTE: According to ChatGPT, set_clock_uncertainty and set_clock_transition are used
# only before CTS, and are effectively overridden by CTS & Liberty data later.

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
#ANTON: According to ChatGPT, LibreLane might use the 'ideal' case before CTS,
# then use propagated clocks after (or during??) CTS.
