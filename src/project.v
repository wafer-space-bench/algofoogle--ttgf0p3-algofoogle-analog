/*
 * Copyright (c) 2026 Anton Maurovic
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_algofoogle_gf_analog (
    input  wire       VGND,
    input  wire       VDPWR,    // 3.3v core power supply
//    input  wire       VAPWR,    // second analog power supply (VAA)
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    inout  wire [7:0] ua,       // Analog pins, only ua[5:0] can be used
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);


    wire vco_out; // Weakly buffered output from main VCO block.
    wire ana_vco_in; // Buffered VCO output, going into the digital block.

    wire vin = ua[0]; // Analog VCO control voltage.

    // Main VGA control block ("slow" 25MHz domain), and DAC driver interface:
    wire [8:0] dacn;
    controller controller_0 (
        .VDD        (VDPWR),
        .VSS        (VGND),
        .clk        (clk),
        .rst_n      (rst_n),
        .ui_in      (ui_in),
        .uio_in     (uio_in),
        .uo_out     (uo_out),
        .dacn       (dacn)
    );

    // DAC-driven VCO, with output buffers going to dac_vco_in and ua[3].
    wire dac_vco_osc;
    wire dac_vco_buf_mid;
    wire dac_vco_in;
    wire ua3buf_mid;
    vco_combo vco_combo_0 (
        .VPWR       (VDPWR),
        .VGND       (VGND),
        .dn         (dacn),
        .vco_osc    (dac_vco_osc),
        .vco_vin    (ua[2])
    );
    bufinv_2 dvtxb0 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (dac_vco_osc),
        .Y          (dac_vco_buf_mid) // dac_vco_in 
    );
    bufinv_2 dvtxb1 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (dac_vco_buf_mid),
        .Y          (dac_vco_in)
    );
    bufinv_2 ua3buf0 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (dac_vco_in),
        .Y          (ua3buf_mid)
    );
    bufinv_2 ua3buf1 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (ua3buf_mid),
        .Y          (ua[3])
    );

    wire [5:0] avo;
    wire [5:0] dvo;
    clkdiv clkdiv_0 (
        .VDD        (VDPWR),
        .VSS        (VGND),
        .ana_vco_in (ana_vco_in),
        .dac_vco_in (dac_vco_in),
        .avo        (avo),
        .dvo        (dvo),
        .uio_oe     (uio_oe)
    );
    assign uio_out = {
        dvo[5], dvo[4], dvo[1], dvo[0],
        avo[5], avo[4], avo[1], avo[0]
    };

    // Buffer vco_out and send it out ua[1]:
    wire ua1buf_mid;
    bufinv_2 ua1buf0 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (vco_out),
        .Y          (ua1buf_mid)
    );
    bufinv_2 ua1buf1 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (ua1buf_mid),
        .Y          (ua[1])
    );

    // Also buffer vco_out and send it all the way across the tile
    // to another buffer that drives the signal into the clkdiv block:
    wire txdigbuf_mid;
    wire vco_tx;
    wire rxdigbuf_mid;
    bufinv_2 txdigbuf0 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (vco_out),
        .Y          (txdigbuf_mid)
    );
    bufinv_2 txua1buf1 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (txdigbuf_mid),
        .Y          (vco_tx)
    );
    bufinv_2 rxdigbuf0 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (vco_tx),
        .Y          (rxdigbuf_mid)
    );
    bufinv_2 rxua1buf1 (
        .VCC        (VDPWR),
        .VSS        (VGND),
        .A          (rxdigbuf_mid),
        .Y          (ana_vco_in)
    );

    csringosc csringosc_0 (
        .VCC    (VDPWR),
        .VSS    (VGND),
        .vin    (vin),
        .osc_out(vco_out)
        // .vbiasp(),
        // .vbiasn(),
        // .osc_raw(),
    );

    wire _unused = &{ena, avo[3:2], dvo[3:2], 0};

endmodule
