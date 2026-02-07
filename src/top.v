/**
 * top.v — Game of Life on Tang Nano 20K. 256×256 toroidal, 7 species, 720p HDMI.
 * Port names I_clk, I_rst, O_tmds_* match constraints.cst (Sipeed pinout).
 */
module top (
    input  wire       I_clk,   // 27 MHz crystal (pin 4)
    input  wire       I_rst,   // active high reset (pin 88)
    output wire       O_tmds_clk_p,
    output wire       O_tmds_clk_n,
    output wire [2:0] O_tmds_data_p,
    output wire [2:0] O_tmds_data_n
);
    wire I_rst_n = ~I_rst;

    wire serial_clk;
    wire pll_lock;
    wire hdmi_rst_n;
    wire pix_clk;

    TMDS_rPLL u_tmds_rpll (
        .clkin  (I_clk       ),
        .clkout (serial_clk  ),
        .lock   (pll_lock    )
    );

    assign hdmi_rst_n = I_rst_n & pll_lock;

    CLKDIV u_clkdiv (
        .RESETN  (hdmi_rst_n ),
        .HCLKIN  (serial_clk ),
        .CLKOUT  (pix_clk    ),
        .CALIB   (1'b1       )
    );
    defparam u_clkdiv.DIV_MODE = "5";
    defparam u_clkdiv.GSREN    = "false";

    wire sys_rst = ~hdmi_rst_n;

    wire [15:0] addr_engine;
    wire        we0_engine, we1_engine;
    wire [3:0]  din_engine;
    wire [3:0]  dout_bank0_a, dout_bank0_b, dout_bank1_a, dout_bank1_b;

    wire [15:0] addr_display;
    wire        ram_select;

    // Dual-port: port A = display read, port B = engine read/write.
    // Engine reads DISPLAY bank (current frame), writes OTHER bank (next frame). INIT writes both via we0/we1.
    gol_ram_dual bank0 (
        .clk   (pix_clk),
        .addr_a(addr_display),
        .dout_a(dout_bank0_a),
        .addr_b(addr_engine),
        .we_b  (we0_engine),
        .din_b (din_engine),
        .dout_b(dout_bank0_b)
    );

    gol_ram_dual bank1 (
        .clk   (pix_clk),
        .addr_a(addr_display),
        .dout_a(dout_bank1_a),
        .addr_b(addr_engine),
        .we_b  (we1_engine),
        .din_b (din_engine),
        .dout_b(dout_bank1_b)
    );

    wire [3:0] dout_display = ram_select ? dout_bank1_a : dout_bank0_a;

    wire video_sof;
    wire init_done;
    wire [3:0] engine_state;
    wire [15:0] gen_count;
    gol_engine engine (
        .clk        (pix_clk),
        .rst        (sys_rst),
        .video_sof  (video_sof),
        .dout_bank0 (dout_bank0_b),
        .dout_bank1 (dout_bank1_b),
        .ram_select (ram_select),
        .init_done  (init_done),
        .state_out  (engine_state),
        .gen_count  (gen_count),
        .addr       (addr_engine),
        .we0        (we0_engine),
        .we1        (we1_engine),
        .din        (din_engine)
    );

    wire [7:0] rgb_r, rgb_g, rgb_b;
    wire       rgb_hs, rgb_vs, rgb_de;

    svo_hdmi svo (
        .clk          (pix_clk),
        .rst          (sys_rst),
        .init_done    (init_done),
        .ram_select   (ram_select),
        .debug_state  (engine_state),
        .debug_gen    (gen_count),
        .dout_display (dout_display),
        .addr_display (addr_display),
        .hsync        (),
        .vsync        (),
        .de           (),
        .pixel_x      (),
        .pixel_y      (),
        .video_sof    (video_sof),
        .rgb_r        (rgb_r),
        .rgb_g        (rgb_g),
        .rgb_b        (rgb_b),
        .rgb_hs       (rgb_hs),
        .rgb_vs       (rgb_vs),
        .rgb_de       (rgb_de)
    );

    DVI_TX_Top DVI_TX_Top_inst (
        .I_rst_n       (hdmi_rst_n   ),
        .I_serial_clk  (serial_clk   ),
        .I_rgb_clk     (pix_clk      ),
        .I_rgb_vs      (rgb_vs       ),
        .I_rgb_hs      (rgb_hs       ),
        .I_rgb_de      (rgb_de       ),
        .I_rgb_r       (rgb_r        ),
        .I_rgb_g       (rgb_g        ),
        .I_rgb_b       (rgb_b        ),
        .O_tmds_clk_p  (O_tmds_clk_p ),
        .O_tmds_clk_n  (O_tmds_clk_n ),
        .O_tmds_data_p (O_tmds_data_p),
        .O_tmds_data_n (O_tmds_data_n)
    );
endmodule
