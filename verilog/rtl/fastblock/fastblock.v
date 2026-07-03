`default_nettype none

// See: https://gf180mcu-pdk.readthedocs.io/en/latest/digital/standard_cells/gf180mcu_fd_sc_mcu7t5v0/cells/clkbuf/gf180mcu_fd_sc_mcu7t5v0__clkbuf_8.html
`define CLKBUFFCELL gf180mcu_fd_sc_mcu7t5v0__clkbuf_8
// About 1.5ns delay. See: https://gf180mcu-pdk.readthedocs.io/en/latest/digital/standard_cells/gf180mcu_fd_sc_mcu7t5v0/cells/dlyc/gf180mcu_fd_sc_mcu7t5v0__dlyc_1.html
`define DELAYCELL   gf180mcu_fd_sc_mcu7t5v0__dlyc_1

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

module fastblock(
    // Bottom ports:
    input           ana_vco_in,
    input           dac_vco_in,
    // Side ports:
    input   [2:0]   clksel, // 0=ana_vco_in, 1=dac_vco_in, 2=sysclk, 3=sysclkdelayed, 4+ = ?
    input           sysclk,
    input   [2:0]   sysclkdelay, // Delay sysclk by [mux]+[buffer]*sysclkdelay
    input           reset,
    input   [2:0]   mode,
    input   [9:0]   operand_a,
    input   [9:0]   operand_b,
    output          done,
    output  [5:0]   computed,
    // Top ports, driven by clkdiv:
    output  [7:0]   uio_oe,
    output  [7:0]   uio_out
);

    wire [5:0] avo;
    wire [5:0] dvo;

    clkdiv clkdiv(
        .ana_vco_in (ana_vco_in),
        .dac_vco_in (dac_vco_in),
        .avo        (avo),
        .dvo        (dvo),
        .uio_oe     (uio_oe)
    );

    //NOTE: [3:2] not used in avo or dvo.
    assign uio_out = {
        dvo[5], dvo[4], dvo[1], dvo[0],
        avo[5], avo[4], avo[1], avo[0]
    };

    wire [7:0] delaychain; // [0] is sysclk as-is, but will also get a mux delay.
    assign delaychain[0] = sysclk;
    `LINT_OFF_PINMISSING_POWER_PINS
    (* keep_hierarchy *) `DELAYCELL delaychain_notouch_ [6:0] (
        .I(delaychain[6:0]),
        .Z(delaychain[7:1])
    );
    `LINT_ON_PINMISSING_POWER_PINS
    // Each higher bit in delaychain is sysclk delayed by another buffer cell level, i.e. ~1.5ns.

    //NOTE: Not sure what sort of delay this introduces;
    // it could be quite uneven depending on the value of sysclkdelay
    // (and hence the path that the clock signal takes).
    wire sysclkdelayed = delaychain[sysclkdelay];

    wire worker_clk_unbuffered =
        reset       ?   sysclk : // During reset, let CLK thru to the worker to help its sync. reset.
        (clksel==0) ?   ana_vco_in :
        (clksel==1) ?   dac_vco_in :
        (clksel==2) ?   sysclk :
        (clksel==3) ?   sysclkdelayed :
        /*clksel=?*/    0; // Disabled.

    wire worker_clk;
    `LINT_OFF_PINMISSING_POWER_PINS
    (* keep_hierarchy *) `CLKBUFFCELL workerclkbuff_notouch_ (.I(worker_clk_unbuffered), .Z(worker_clk));
    `LINT_ON_PINMISSING_POWER_PINS

    worker worker (
        .reset      (reset),
        .worker_clk (worker_clk),
        .mode       (mode),
        .h          (h),
        .v          (v),
        .done       (done),
        .computed   (computed)
    );

endmodule


module worker (
    input               clk, // Fast clock.
    input               reset,
    input       [2:0]   mode,
    input       [9:0]   operand_a,
    input       [9:0]   operand_b,
    output reg          done,
    output      [5:0]   computed
);
    // Synchronise the 'reset' signal to our [fast] clock:
    wire s_reset;
    sync resetsync (.clk(clk), .in(reset), .out(s_reset));

    // Counts up to 3000 (if it has enough time) and then pauses there until reset:
    reg [11:0] counter;
    always @(posedge clk) begin
        if (s_reset) begin
            counter <= 0;
            done <= 0;
        end else if (counter>=3000) begin
            done <= 1;
        end else begin
            counter <= counter + 1;
        end
    end
    assign computed = counter[11:6];
endmodule


module sync (
    input clk,
    input in,
    output out
);
    reg [1:0] buff;
    always @(posedge clk) buff <= {buff[0], in};
    assign out = buff[1];
endmodule


module edgesync (
    input clk,
    input reset,
    input in,
    output rising,
    output falling
);
    reg [2:0] buff;
    //NOTE: LSB is for sync (metastability mitigation),
    // while upper 2 bits are actual edge detection.
    always @(posedge clk) buff <= (reset ? 3'b000 : {buff[1:0], in});
    assign rising = (buff[2:1] == 2'b01);
    assign falling = (buff[2:1] == 2'b10);
endmodule
