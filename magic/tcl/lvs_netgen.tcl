set layout [readnet spice $project.lvs.spice]   ;# "L": Overall SPICE netlist extracted from layout.
set schem  [readnet spice /dev/null]            ;# "S": Placeholder for schematic netlist; we'll add to it as needed, depending on what we're LVSing.

if {$project eq "tt_um_algofoogle_gf_analog"} {

    # === LVS the whole design... ===

    # --- Add netlists that contribute to the overall schematics of the design ---

    # Add spice files of any analog block(s), e.g:
    readnet spice ../xschem/simulation/csringosc.spice $schem
    readnet spice ../xschem/simulation/bufinv_2.spice $schem
    readnet spice ../xschem/simulation/vco_combo.spice $schem

    # Add GL verilog of digital block(s) (i.e. flat file from LibreLane hardening):
    readnet verilog ../verilog/gl/controller.pnl.v $schem
    readnet verilog ../verilog/gl/fastblock.pnl.v $schem

    # Top-level abstract integration verilog, e.g. main project.v, or LVS-tweaked version:
    # readnet verilog ../src/LVS-project.v $schem
    readnet verilog ../src/project.v $schem

    lvs "$layout $project" "$schem $project" \
        $::env(PDK_ROOT)/$::env(PDK)/libs.tech/netgen/$::env(PDK)_setup.tcl \
        $report_file \
        -blackbox

} else {

    # === LVS just a specific cell ===

    # Load SPICE netlist:
    readnet spice ../xschem/simulation/$project.spice $schem
    
    lvs "$layout $project" "$schem $project" \
        $::env(PDK_ROOT)/$::env(PDK)/libs.tech/netgen/$::env(PDK)_setup.tcl \
        $report_file \
        -blackbox

}
