/**
 * svo_hdmi.v — 720p60 HDMI timing, video_sof, pixel coords, video_source_gol.
 * Outputs RGB + sync for DVI_TX_Top (submodule), and 10-bit TMDS if needed.
 */
module svo_hdmi (
    input  wire        clk,         // pixel clock 74.25 MHz
    input  wire        rst,
    input  wire        init_done,  // 0 during engine INIT → output black
    input  wire        ram_select,  // which bank is display (for video_source_gol)
    input  wire [3:0]  debug_state, // engine FSM state (0=INIT..5=IDLE)
    input  wire [15:0] debug_gen,   // generations completed
    input  wire [3:0]  dout_display, // display bank read data (1-cycle latency)
    output wire [15:0] addr_display, // address to display bank
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire [11:0] pixel_x,
    output wire [11:0] pixel_y,
    output wire        video_sof,
    // Aligned RGB + sync for DVI_TX_Top (1-cycle delayed to match pipelined RGB)
    output wire [7:0]  rgb_r,
    output wire [7:0]  rgb_g,
    output wire [7:0]  rgb_b,
    output wire        rgb_hs,
    output wire        rgb_vs,
    output wire        rgb_de
);
    // 720p60: 1280×720, 74.25 MHz. h_total=1650, v_total=750
    localparam [11:0] H_ACTIVE = 12'd1280;
    localparam [11:0] H_FP     = 12'd110;
    localparam [11:0] H_SYNC  = 12'd40;
    localparam [11:0] H_BP    = 12'd220;
    localparam [11:0] H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 1650

    localparam [11:0] V_ACTIVE = 12'd720;
    localparam [11:0] V_FP     = 12'd5;
    localparam [11:0] V_SYNC  = 12'd5;
    localparam [11:0] V_BP    = 12'd20;
    localparam [11:0] V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 750

    reg [11:0] h_count, v_count;
    reg        hsync_r, vsync_r, de_r;
    reg [11:0] pixel_x_r, pixel_y_r;
    reg        video_sof_r;
    reg [15:0] frame_cnt;  // debug: increment on SOF

    always @(posedge clk) begin
        if (rst) begin
            h_count   <= 12'd0;
            v_count   <= 12'd0;
            hsync_r   <= 0;
            vsync_r   <= 0;
            de_r      <= 0;
            pixel_x_r <= 12'd0;
            pixel_y_r <= 12'd0;
            video_sof_r <= 0;
            frame_cnt <= 16'd0;
        end else begin
            video_sof_r <= 0;
            if (h_count == H_TOTAL - 12'd1) begin
                h_count <= 12'd0;
                if (v_count == V_TOTAL - 12'd1)
                    v_count <= 12'd0;
                else
                    v_count <= v_count + 12'd1;
            end else
                h_count <= h_count + 12'd1;

            if (v_count == 12'd0 && h_count == 12'd0) begin
                video_sof_r <= 1;
                frame_cnt   <= frame_cnt + 16'd1;
            end

            de_r <= (h_count < H_ACTIVE && v_count < V_ACTIVE);
            pixel_x_r <= h_count[11:0];
            pixel_y_r <= v_count[11:0];

            // Sync: active high in sync region (DVI/HDMI often positive)
            hsync_r <= (h_count >= H_ACTIVE + H_FP && h_count < H_ACTIVE + H_FP + H_SYNC);
            vsync_r <= (v_count >= V_ACTIVE + V_FP && v_count < V_ACTIVE + V_FP + V_SYNC);
        end
    end

    assign hsync    = hsync_r;
    assign vsync    = vsync_r;
    assign de       = de_r;
    assign pixel_x  = pixel_x_r;
    assign pixel_y  = pixel_y_r;
    assign video_sof = video_sof_r;

    // Video source: pixel -> grid, color LUT, display bank read (1-cycle latency)
    wire [7:0] r, g, b;
    video_source_gol video_gol (
        .clk(clk),
        .pixel_x(pixel_x_r),
        .pixel_y(pixel_y_r),
        .de(de_r),
        .dout(dout_display),
        .addr(addr_display),
        .r(r),
        .g(g),
        .b(b)
    );

    // Align TMDS with pipelined RGB: delay de/sync by 1 cycle (video_source_gol has 1-cycle read latency)
    reg        de_d1;
    reg        hsync_d1, vsync_d1;
    reg        init_done_d1;
    reg [11:0] pixel_x_d1, pixel_y_d1;  // align with pipelined r,g,b for debug overlay
    always @(posedge clk) begin
        de_d1        <= de_r;
        hsync_d1     <= hsync_r;
        vsync_d1     <= vsync_r;
        init_done_d1 <= init_done;
        pixel_x_d1   <= pixel_x_r;
        pixel_y_d1   <= pixel_y_r;
    end

    // Debug panel: top-left, multiple lines. Uses delayed coords to match r,g,b.
    localparam [11:0] DX = 12'd8;
    localparam [11:0] DY = 12'd8;
    localparam [11:0] LINE_H = 12'd8;
    localparam [11:0] GAP = 12'd4;

    wire [11:0] px = pixel_x_d1 - DX;
    wire [11:0] py = pixel_y_d1 - DY;

    // Line 0: "GOL" (24px) + state digit 0-5 (8px)
    wire line0 = (py >= 12'd0 && py < LINE_H);
    wire in_gol = line0 && (px >= 12'd0 && px < 12'd24);
    wire in_st = line0 && (px >= 12'd28 && px < 12'd36);  // state digit after 4px gap
    wire [2:0] gol_char = px[4:2];   // 0=G, 1=O, 2=L (px/8)
    wire [2:0] gol_row = py[2:0];
    wire [2:0] gol_col = px[2:0];
    wire [7:0] gol_font = (gol_char == 3'd0) ? (gol_row == 0 ? 8'h3C : gol_row == 1 ? 8'h42 : gol_row == 2 ? 8'h81 : gol_row == 3 ? 8'h81 : gol_row == 4 ? 8'h8F : gol_row == 5 ? 8'h82 : gol_row == 6 ? 8'h42 : 8'h3C) :
                          (gol_char == 3'd1) ? (gol_row == 0 ? 8'h3C : gol_row == 1 ? 8'h42 : gol_row == 2 ? 8'h81 : gol_row == 3 ? 8'h81 : gol_row == 4 ? 8'h81 : gol_row == 5 ? 8'h81 : gol_row == 6 ? 8'h42 : 8'h3C) :
                          (gol_row == 0 ? 8'h80 : gol_row == 1 ? 8'h80 : gol_row == 2 ? 8'h80 : gol_row == 3 ? 8'h80 : gol_row == 4 ? 8'h80 : gol_row == 5 ? 8'h80 : gol_row == 6 ? 8'h80 : 8'hFF);
    wire gol_pix = (gol_col == 0) ? gol_font[7] : (gol_col == 1) ? gol_font[6] : (gol_col == 2) ? gol_font[5] : (gol_col == 3) ? gol_font[4] : (gol_col == 4) ? gol_font[3] : (gol_col == 5) ? gol_font[2] : (gol_col == 6) ? gol_font[1] : gol_font[0];
    // State digit 0-5 (8x8 font, MSB left) — digit at px 28..35
    wire [11:0] st_off = px - 12'd28;
    wire [2:0] st_row = py[2:0];
    wire [2:0] st_col = st_off[2:0];
    wire [7:0] st_font = (debug_state == 4'd0) ? (st_row == 0 ? 8'h3C : st_row == 1 ? 8'h42 : st_row == 2 ? 8'h81 : st_row == 3 ? 8'h81 : st_row == 4 ? 8'h81 : st_row == 5 ? 8'h81 : st_row == 6 ? 8'h42 : 8'h3C) :
                         (debug_state == 4'd1) ? (st_row == 0 ? 8'h08 : st_row == 1 ? 8'h18 : st_row == 2 ? 8'h08 : st_row == 3 ? 8'h08 : st_row == 4 ? 8'h08 : st_row == 5 ? 8'h08 : st_row == 6 ? 8'h08 : 8'h3E) :
                         (debug_state == 4'd2) ? (st_row == 0 ? 8'h3C : st_row == 1 ? 8'h42 : st_row == 2 ? 8'h01 : st_row == 3 ? 8'h02 : st_row == 4 ? 8'h04 : st_row == 5 ? 8'h08 : st_row == 6 ? 8'h10 : 8'h7F) :
                         (debug_state == 4'd3) ? (st_row == 0 ? 8'h3C : st_row == 1 ? 8'h42 : st_row == 2 ? 8'h01 : st_row == 3 ? 8'h0C : st_row == 4 ? 8'h02 : st_row == 5 ? 8'h81 : st_row == 6 ? 8'h42 : 8'h3C) :
                         (debug_state == 4'd4) ? (st_row == 0 ? 8'h02 : st_row == 1 ? 8'h06 : st_row == 2 ? 8'h0A : st_row == 3 ? 8'h12 : st_row == 4 ? 8'h22 : st_row == 5 ? 8'h7F : st_row == 6 ? 8'h02 : 8'h02) :
                         (st_row == 0 ? 8'h7F : st_row == 1 ? 8'h80 : st_row == 2 ? 8'h80 : st_row == 3 ? 8'hFC : st_row == 4 ? 8'h02 : st_row == 5 ? 8'h01 : st_row == 6 ? 8'h82 : 8'h7C);  // 5
    wire st_pix = (st_col == 0) ? st_font[7] : (st_col == 1) ? st_font[6] : (st_col == 2) ? st_font[5] : (st_col == 3) ? st_font[4] : (st_col == 4) ? st_font[3] : (st_col == 5) ? st_font[2] : (st_col == 6) ? st_font[1] : st_font[0];

    // Line 1: frame bar (F: frame)
    wire line1 = (py >= LINE_H + GAP && py < LINE_H + GAP + LINE_H);
    wire in_fr_bar = line1 && (px >= 12'd0 && px < 12'd64);
    wire [11:0] fr_fill = {4'd0, frame_cnt[7:0]};
    wire fr_bar_on = px < fr_fill;

    // Line 2: gen bar (G: gen)
    wire line2 = (py >= (LINE_H + GAP) * 2 && py < (LINE_H + GAP) * 2 + LINE_H);
    wire in_gen_bar = line2 && (px >= 12'd0 && px < 12'd128);
    wire [11:0] gen_fill = {4'd0, debug_gen[7:0]};
    wire gen_bar_on = px < gen_fill;

    // Line 3: state bar (6 segments: state 0=1 seg, state 5=6 seg; segment i lit when i<=state)
    wire line3 = (py >= (LINE_H + GAP) * 3 && py < (LINE_H + GAP) * 3 + LINE_H);
    wire in_st_bar = line3 && (px >= 12'd0 && px < 12'd48);
    wire [2:0] st_seg = px[5:3];  // 0..5
    wire st_seg_on = (st_seg <= debug_state[2:0]);

    // Line 4: B=ram_select, I=init_done (two 8px blocks)
    wire line4 = (py >= (LINE_H + GAP) * 4 && py < (LINE_H + GAP) * 4 + LINE_H);
    wire in_b_block = line4 && (px >= 12'd0 && px < 12'd8);
    wire in_i_block = line4 && (px >= 12'd12 && px < 12'd20);

    wire in_panel = (pixel_x_d1 >= DX && pixel_x_d1 < DX + 12'd128 && pixel_y_d1 >= DY && pixel_y_d1 < DY + (LINE_H + GAP) * 4 + LINE_H);
    wire show_debug = in_panel;
    wire [7:0] debug_r = in_gol && gol_pix ? 8'hFF : (in_st && st_pix) ? 8'hFF : (in_fr_bar && fr_bar_on) ? (frame_cnt[5:0] << 2) : (in_gen_bar && gen_bar_on) ? 8'd0 : (in_st_bar && st_seg_on) ? 8'hFF : (in_b_block && ram_select) ? 8'd0 : (in_i_block && init_done) ? 8'd0 : 8'd0;
    wire [7:0] debug_g = in_gol && gol_pix ? 8'hFF : (in_st && st_pix) ? 8'hFF : (in_fr_bar && fr_bar_on) ? 8'd0 : (in_gen_bar && gen_bar_on) ? 8'hFF : (in_st_bar && st_seg_on) ? 8'h80 : (in_b_block && ram_select) ? 8'hFF : (in_i_block && init_done) ? 8'hFF : 8'd0;
    wire [7:0] debug_b = in_gol && gol_pix ? 8'hFF : (in_st && st_pix) ? 8'hFF : (in_fr_bar && fr_bar_on) ? (8'd255 - (frame_cnt[5:0] << 2)) : (in_gen_bar && gen_bar_on) ? 8'd0 : (in_st_bar && st_seg_on) ? 8'h80 : (in_b_block && ram_select) ? 8'hFF : (in_i_block && init_done) ? 8'hFF : 8'd0;

    // For DVI_TX_Top: debug overlay on top of GOL, black during INIT
    assign rgb_r  = init_done_d1 ? (show_debug ? debug_r : r) : 8'd0;
    assign rgb_g  = init_done_d1 ? (show_debug ? debug_g : g) : 8'd0;
    assign rgb_b  = init_done_d1 ? (show_debug ? debug_b : b) : 8'd0;
    assign rgb_hs = hsync_d1;
    assign rgb_vs = vsync_d1;
    assign rgb_de = de_d1;
endmodule
