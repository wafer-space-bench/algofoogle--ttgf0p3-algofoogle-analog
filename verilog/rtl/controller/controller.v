`default_nettype none

//TODO:
// - Option for making DAC increment.

module controller(
    input           clk,
    input           rst_n,
    input   [7:0]   ui_in,
    input   [7:0]   uio_in,

    output  [7:0]   uo_out,
    output  [8:0]   dacn // DAC internally needs complementary outputs (hence 'n').
);

    wire test_mode = ui_in[6];

    // DAC set to 256 (/512) should get close to 1.65V which
    // should make the VCO oscillate near 205MHz:
    localparam [8:0] DAC_DEFAULT = 9'b1_0000_0000;

    // DAC data load interface (connects to dac_loader):
    wire [2:0] dac_data = ui_in[2:0];
    wire dac_load = ui_in[3];
    wire dac_shift = ui_in[4];

    wire [8:0] dac;
    wire vco_disable = ui_in[5];
    assign dacn = ~(vco_disable ? 0 : dac);

    wire reset = ~rst_n;

    reg [1:0] R;
    reg [1:0] G;
    reg [1:0] B;
    wire vsync;
    wire hsync;

    // Tiny VGA PMOD:
    assign uo_out = {
        hsync, B[0], G[0], R[0],
        vsync, B[1], G[1], R[1]
    };

    // Ensure unregistered RGB values get visible-gated and registered:
    always @(posedge clk)
        if (reset)
            {R,G,B} <= 0;
        else
            {R,G,B} <= rgb_unreg & {{6}{visible}};

    wire vga_mode = ui_in[7];

    wire [9:0] h;
    wire [9:0] v;
    wire visible;
    wire hmax;

    vga_sync vga_sync (
        .clk        (clk),
        .reset      (reset),
        .mode       (vga_mode),
        .o_hsync    (hsync),
        .o_vsync    (vsync),
        .o_hpos     (h),
        .o_vpos     (v),
        .o_hmax     (hmax), // End of line?
        // .o_vmax     (),
        // .o_vblank   (),
        // .o_hblank   (),
        .o_visible  (visible)
    );

    wire in_dac_debug = (v < 16) && (h < (9*16));

    // {Rr,Gg,Bb} order:
    wire [5:0] rgb_unreg = 
        // Debug: 9 DAC bits are exposed as black and white 16x16 squares, with grey dividing lines:
        in_dac_debug    ?   ((h[3:2]==0) ? 6'b01_01_01 : {{6}{dac[8-h[9:4]]}}) : 
        // Simple XOR colour pattern otherwise:
                            (h[5:0] ^ v[5:0]);

    dac_loader #(.DAC_DEFAULT(DAC_DEFAULT)) dac_loader (
        .clk        (clk),
        .reset      (reset),
        .load       (dac_load),
        .shift      (dac_shift),
        .data_in    (dac_data),
        .dac_inc    (test_mode && hmax),
        .dac_out    (dac)
    );

endmodule


// This provides an interface enabling 9 bits to be shifted in
// as lots of 3 (MSB-first). It buffers until the instant that the
// 3rd lot of 3 is shifted in, at which point it presents the
// concatenated 9 bits registered at dac_out.
// - load:  must be asserted (high) for the duration of the shift sequence.
// - shift: rising edge causes 3 bits on data_in to be sampled.
// If "load" is deasserted before the 3rd rising edge of "shift",
// the buffered data will be abandoned and dac_out will remain as-is.
// If "shift" rising edges continue, after the 3rd, while "load" is still
// asserted then the 4th lot of data_in bits will end up being ignored
// and the next round of 3 rising edges on "shift" will continue the
// cycle of registering a new output on dac_out (so long as "load"
// remains asserted).
module dac_loader #(
    parameter [8:0] DAC_DEFAULT = 9'b1_0000_0000
) (
    input               clk,
    input               reset,
    input               load,
    input               shift,
    input       [2:0]   data_in,
    input               dac_inc,
    output  reg [8:0]   dac_out
);
    reg [5:0] dac_buf; // Only need to buffer 6 bits of 9.
    reg [1:0] state;

    // Sync SHIFT using 3-bit shift reg (to catch rising/falling edges):
    reg [2:0] shift_buffer;
    always @(posedge clk) shift_buffer <= (reset ? 3'd0 : {shift_buffer[1:0], shift});
    wire shift_rise = (shift_buffer[2:1]==2'b01);

    // Sync LOAD; only needs 2 bits because we don't care about edges:
    reg [1:0] load_buffer;
    always @(posedge clk) load_buffer <= (reset ? 2'd0 : {load_buffer[0], load});
    wire load_active = load_buffer[1];

    wire final_load = (state == 2); // Even state[1] would work.

    wire [8:0] dac_temp = {dac_buf, data_in};

    always @(posedge clk) begin

        // "dac_buf": clear on reset, or shift data in:
        if (reset)
            dac_buf <= 0;
        else if (shift_rise) // Could add "&& load_active" but we don't care.
            dac_buf <= dac_temp[5:0]; // i.e. {dac_buf[2:0], data_in};

        // "state": count shifts, resetting on system reset or if "load" deasserts.
        if (reset)
            state <= 0;
        else if (!load_active)
            state <= 0;
        else if (shift_rise)
            state <= state + 1;
        // "state" can roll over; we don't care as
        // host would just need to do an extra dummy shift
        // if it plans on keeping "load" asserted.
        
        // "dac_out": set default value on reset, or reg new data on 3rd shift,
        // or increment if dac_inc is set:
        if (reset)
            dac_out <= DAC_DEFAULT;
        else if (load_active && shift_rise && final_load)
            dac_out <= dac_temp;
        else if (dac_inc)
            dac_out <= dac_out + 1;
        
    end

endmodule
