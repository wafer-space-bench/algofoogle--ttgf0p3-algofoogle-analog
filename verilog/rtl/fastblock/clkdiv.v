`default_nettype none

//NOTE: If you change any of these cells, the port names may need to be altered in any instance.
`define DFFCELL     gf180mcu_fd_sc_mcu7t5v0__dffq_1
`define INVCELL     gf180mcu_fd_sc_mcu7t5v0__inv_1

// This is to manage lint checking to not report about unconnected power pins.
// Thanks https://github.com/dlmiles/ttgf0p2-ringosc-5inv/blob/main/src/project.v
`ifndef LINT_OFF_PINMISSING_POWER_PINS
`ifdef USE_POWER_PINS
`define LINT_OFF_PINMISSING_POWER_PINS /* verilator lint_off PINMISSING */
`define LINT_ON_PINMISSING_POWER_PINS /* verilator lint_on PINMISSING */
`else
`define LINT_OFF_PINMISSING_POWER_PINS /* */
`define LINT_ON_PINMISSING_POWER_PINS /* */
`endif
`endif

// This uses a DFF standard cell (clocked by the input clk), inverts its output,
// and feeds it back to the D input. This creates a half-clock-rate output (halfclk).
module divcell(
    input clk,
    output halfclk
);
    wire nq_feedback;
    `LINT_OFF_PINMISSING_POWER_PINS
    (* keep_hierarchy *) `DFFCELL dff_notouch_ (.CLK(clk), .D(nq_feedback), .Q(halfclk));
    (* keep_hierarchy *) `INVCELL inv_notouch_ (.I(halfclk), .ZN(nq_feedback)); // DFF's inverted Q loops back to D, making a clk divider stage.
    `LINT_ON_PINMISSING_POWER_PINS
endmodule


module clkdiv(
    input ana_vco_in,
    input dac_vco_in,
    //NOTE: For testing, only [5:4,1:0] of each of avo & dvo are
    // exposed on the 8 TT bidir pins. The other 4 pins still exist in
    // the macro but are exposed on the bottom side (and may or may not be
    // connected to any output on the chip).
    output [5:0] avo, // ana_vco outputs.
    output [5:0] dvo, // dac_vco outputs.
    // The following are just here for simply driving uio_oe pins all
    // high (to make all the bidir pins outputs):
    output [7:0] uio_oe
);

    assign uio_oe = 8'b1111_1111;

    // Clock divider chain, starting at ana_vco_in (repeated back out as avo[0]),
    // and ending at avo[5] (frequency divided by 32):
    assign avo[0] = ana_vco_in; // avo[0] is the raw ana_vco_in clk.
    (* keep_hierarchy *) divcell ana_div_chain [4:0] (
        .clk    (avo[4:0]),
        .halfclk(avo[5:1]) // Each higher stage of avo[5:1] is the clk divided in turn.
    );

    // Clock divider chain, as above, but for dac_vco_in:
    assign dvo[0] = dac_vco_in;
    (* keep_hierarchy *) divcell dac_div_chain [4:0] (
        .clk    (dvo[4:0]),
        .halfclk(dvo[5:1])
    );

endmodule

