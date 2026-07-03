`default_nettype none


module controller(
    // Top TT ports:
    input           clk,
    input           rst_n,
    input   [7:0]   ui_in,
    input   [7:0]   uio_in,
    output  [7:0]   uo_out,
    // Bottom ports going to DAC:
    output  [8:0]   dacn, // DAC internally needs complementary outputs (hence 'n').
    // LHS ports going to fastblock:
    output  [2:0]   clksel, // 0=ana_vco_in, 1=dac_vco_in, 2=sysclk, 3=sysclkdelayed, 4+ = ?
    output          sysclk,
    output  [2:0]   sysclkdelay, // Delay sysclk by [mux]+[buffer]*sysclkdelay
    output          worker_reset,
    output  [2:0]   mode,
    output  [9:0]   operand_a,
    output  [9:0]   operand_b,
    input           done,
    input   [5:0]   computed
);

    assign sysclk = clk;

    wire test_mode = ui_in[6];

    // DAC set to 203 (/512) should get close to 1.31V which
    // should make the VCO oscillate near 133MHz:
    localparam [8:0] DAC_DEFAULT = 9'd203;

    // DAC data load interface (connects to dac_loader):
    wire [2:0] dac_data = ui_in[2:0];
    wire dac_load = ui_in[3];
    wire dac_shift = ui_in[4];

    wire [8:0] dac;
    wire vco_disable = ui_in[5];
    assign dacn = ~(vco_disable ? 0 : dac);

    reg [1:0] R;
    reg [1:0] G;
    reg [1:0] B;
    wire vsync;
    wire hsync;
    wire hblank;

    wire reset = ~rst_n;

    assign worker_reset = reset || hblank; // Hold the worker in (a nice long) reset during VGA HBLANK period.

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

    assign operand_a = h;
    assign operand_b = v;

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
        .o_hblank   (hblank),
        .o_visible  (visible)
    );

    wire in_dac_debug = (v < 16) && (h < (9*16));

    wire checkerboard = (h[0]^v[0]);
    wire border = ((v==0) || (v==479) || (h==0) || (h==639)) && checkerboard;

    // {Rr,Gg,Bb} order:
    wire [5:0] rgb_unreg = {6{border}} | (
        // Debug: 9 DAC bits are exposed as black and white 16x16 squares, with grey dividing lines:
        in_dac_debug    ?   ((h[3:2]==0) ? 6'b01_01_01 : {{6}{dac[8-h[9:4]]}}) :
        // While the worker is still working, show its computation progress:
        (!done)         ?   (computed) :
        // Otherwise, fall through to simple XOR colour pattern:
                            (h[5:0] ^ v[5:0])
    );

    dac_loader #(.DAC_DEFAULT(DAC_DEFAULT)) dac_loader (
        .clk        (clk),
        .reset      (reset),
        .load       (dac_load),
        .shift      (dac_shift),
        .data_in    (dac_data),
        .dac_inc    (test_mode && hmax),
        .dac_out    (dac),
        .clksel_out (clksel),
        .clkdly_out (sysclkdelay),
        .mode_out   (mode)
    );

endmodule


// This provides an interface enabling 18 bits to be shifted in
// as lots of 3 (MSB-first). It buffers until the instant that the
// 6th lot of 3 is shifted in, at which point it presents the
// concatenated 9 bits registered at dac_out, and 3 triplets for
// each of clksel_out, clkdly_out, and mode_out.
// - load:  must be asserted (high) for the duration of the shift sequence.
// - shift: rising edge causes 3 bits on data_in to be sampled.
// If "load" is deasserted before the 6th rising edge of "shift",
// the buffered data will be abandoned and the outputs will remain as-is.
// If "shift" rising edges continue, after the 6th, while "load" is still
// asserted then the 7th & 8th lots of data_in bits will end up being ignored
// and the next round of 6 rising edges on "shift" will continue the
// cycle of registering a new output on dac_out (so long as "load"
// remains asserted).
module dac_loader #(
    parameter [8:0] DAC_DEFAULT     = 9'b1_0000_0000,
    parameter [2:0] CLKSEL_DEFAULT  = 3'd1, // 1 = dac_vco_in.
    parameter [2:0] CLKDLY_DEFAULT  = 3'd1, // 1 = one dlyc delay on sysclk.
    parameter [2:0] MODE_DEFAULT    = 3'd1  // 1 = count up to v (operand_b).
) (
    input               clk,
    input               reset,
    input               load,
    input               shift,
    input       [2:0]   data_in,
    input               dac_inc,
    output  reg [8:0]   dac_out,
    output  reg [2:0]   clksel_out,
    output  reg [2:0]   clkdly_out,
    output  reg [2:0]   mode_out
);

    reg [14:0] dac_buf; // Only need to buffer 15 bits of 18.
    reg [2:0] state;

    // Sync SHIFT using 3-bit shift reg (to catch rising/falling edges):
    reg [2:0] shift_buffer;
    always @(posedge clk) shift_buffer <= (reset ? 3'd0 : {shift_buffer[1:0], shift});
    wire shift_rise = (shift_buffer[2:1]==2'b01);

    // Sync LOAD; only needs 2 bits because we don't care about edges:
    reg [1:0] load_buffer;
    always @(posedge clk) load_buffer <= (reset ? 2'd0 : {load_buffer[0], load});
    wire load_active = load_buffer[1];

    wire final_load = (state == 5); // Means we'll be done when we hit 6 shifts in total.

    wire [17:0] dac_temp = {dac_buf, data_in};

    // When dac_inc is active, this is effectively a test mode where we want to see
    // the DAC increment every line. In order to see that reliably, it is best to go
    // into mode 0 (count-up-to-3000) *at reset* instead of MODE_DEFAULT.
    wire [2:0] default_mode = dac_inc ? 0 : MODE_DEFAULT;

    always @(posedge clk) begin

        // "dac_buf": clear on reset, or shift data in:
        if (reset)
            dac_buf <= 0;
        else if (shift_rise) // Could add "&& load_active" but we don't care.
            dac_buf <= dac_temp[14:0]; // i.e. {dac_buf[2:0], data_in};

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
        
        // "dac_out": set default value on reset, or reg new data on 6th shift,
        // or increment if dac_inc is set:
        if (reset)
            {dac_out, clksel_out, clkdly_out, mode_out} <= {DAC_DEFAULT, CLKSEL_DEFAULT, CLKDLY_DEFAULT, default_mode};
        else if (load_active && shift_rise && final_load)
            {dac_out, clksel_out, clkdly_out, mode_out} <= dac_temp;
        else if (dac_inc)
            dac_out <= dac_out + 1;
        
    end

endmodule
