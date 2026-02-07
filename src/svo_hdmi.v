/**
 * svo_hdmi.v — 720p60 HDMI timing, video_sof, pixel coords, video_source_gol.
 * Outputs RGB + sync for DVI_TX_Top (submodule), and 10-bit TMDS if needed.
 */
module svo_hdmi (
    input  wire        clk,         // pixel clock 74.25 MHz
    input  wire        rst,
    input  wire        init_done,  // 0 during engine INIT → output black
    input  wire        ram_select,  // which bank is display (for video_source_gol)
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

    // Debug overlay: "GOL" text (8x8 font) + frame bar at top-left. Uses delayed coords to match r,g,b.
    localparam [11:0] DEBUG_X0 = 12'd8;
    localparam [11:0] DEBUG_Y0 = 12'd8;
    localparam [11:0] DEBUG_TXT_W = 12'd24;   // 3 chars * 8
    localparam [11:0] DEBUG_TXT_H = 12'd8;
    localparam [11:0] DEBUG_BAR_W = 12'd64;
    localparam [11:0] DEBUG_BAR_H = 12'd8;
    wire in_debug_txt = (pixel_x_d1 >= DEBUG_X0 && pixel_x_d1 < DEBUG_X0 + DEBUG_TXT_W &&
                         pixel_y_d1 >= DEBUG_Y0 && pixel_y_d1 < DEBUG_Y0 + DEBUG_TXT_H);
    wire in_debug_bar = (pixel_x_d1 >= DEBUG_X0 && pixel_x_d1 < DEBUG_X0 + DEBUG_BAR_W &&
                         pixel_y_d1 >= DEBUG_Y0 + DEBUG_TXT_H + 4 && pixel_y_d1 < DEBUG_Y0 + DEBUG_TXT_H + 4 + DEBUG_BAR_H);
    wire [11:0] debug_px_off = pixel_x_d1 - DEBUG_X0;
    wire [11:0] debug_py_off = pixel_y_d1 - DEBUG_Y0;
    wire [3:0] debug_char = debug_px_off >> 3;  // 0=G, 1=O, 2=L
    wire [2:0] debug_row  = debug_py_off[2:0];
    wire [2:0] debug_col  = debug_px_off[2:0];
    // 8x8 font rows for G,O,L (MSB = left)
    wire [7:0] font_row = (debug_char == 3'd0) ? (debug_row == 0 ? 8'h3C : debug_row == 1 ? 8'h42 : debug_row == 2 ? 8'h81 : debug_row == 3 ? 8'h81 : debug_row == 4 ? 8'h8F : debug_row == 5 ? 8'h82 : debug_row == 6 ? 8'h42 : 8'h3C) :
                          (debug_char == 3'd1) ? (debug_row == 0 ? 8'h3C : debug_row == 1 ? 8'h42 : debug_row == 2 ? 8'h81 : debug_row == 3 ? 8'h81 : debug_row == 4 ? 8'h81 : debug_row == 5 ? 8'h81 : debug_row == 6 ? 8'h42 : 8'h3C) :
                          (debug_row == 0 ? 8'h80 : debug_row == 1 ? 8'h80 : debug_row == 2 ? 8'h80 : debug_row == 3 ? 8'h80 : debug_row == 4 ? 8'h80 : debug_row == 5 ? 8'h80 : debug_row == 6 ? 8'h80 : 8'hFF);
    wire debug_pixel = (debug_col == 3'd0) ? font_row[7] : (debug_col == 3'd1) ? font_row[6] : (debug_col == 3'd2) ? font_row[5] : (debug_col == 3'd3) ? font_row[4] : (debug_col == 3'd4) ? font_row[3] : (debug_col == 3'd5) ? font_row[2] : (debug_col == 3'd6) ? font_row[1] : font_row[0];
    // Frame bar: width proportional to frame_cnt[7:0], so it visibly changes every frame
    wire [11:0] bar_fill = {4'd0, frame_cnt[7:0]};
    wire in_bar_fill = debug_px_off < bar_fill;
    wire show_debug = in_debug_txt | in_debug_bar;
    wire [7:0] debug_r = (in_debug_txt && debug_pixel) ? 8'hFF : (in_debug_bar && in_bar_fill) ? frame_cnt[5:0] << 2 : 8'd0;
    wire [7:0] debug_g = (in_debug_txt && debug_pixel) ? 8'hFF : (in_debug_bar && in_bar_fill) ? 8'd0 : 8'd0;
    wire [7:0] debug_b = (in_debug_txt && debug_pixel) ? 8'hFF : (in_debug_bar && in_bar_fill) ? (8'd255 - (frame_cnt[5:0] << 2)) : 8'd0;

    // For DVI_TX_Top: debug overlay on top of GOL, black during INIT
    assign rgb_r  = init_done_d1 ? (show_debug ? debug_r : r) : 8'd0;
    assign rgb_g  = init_done_d1 ? (show_debug ? debug_g : g) : 8'd0;
    assign rgb_b  = init_done_d1 ? (show_debug ? debug_b : b) : 8'd0;
    assign rgb_hs = hsync_d1;
    assign rgb_vs = vsync_d1;
    assign rgb_de = de_d1;
endmodule
