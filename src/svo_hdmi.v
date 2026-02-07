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
    input  wire [511:0] pop_count,  // pop_count[16*i+15:16*i] = count of species i (0-31)
    input  wire [4:0]  dout_display, // display bank read data (1-cycle latency)
    output wire [15:0] addr_display, // address to display bank
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire [11:0] pixel_x,
    output wire [11:0] pixel_y,
    output wire        video_sof,  // raw SOF every frame
    output wire        gen_sof,    // gated SOF for engine (every GEN_DIV frames)
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

            // SOF: assert for 2 cycles at start of frame so engine (same clk) reliably samples it
            if (v_count == 12'd0 && h_count == 12'd0) begin
                video_sof_r <= 1;
                frame_cnt   <= frame_cnt + 16'd1;
            end else if (v_count == 12'd0 && h_count == 12'd1) begin
                video_sof_r <= 1;
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
    // GEN_DIV: 1=60 gen/sec, 2=30, 4=15. Change localparam to slow evolution.
    localparam [1:0] GEN_DIV = 2'd1;  // 2'd2 or 2'd4 for slower
    assign gen_sof = video_sof_r && (
        (GEN_DIV == 2'd1) ? 1'b1 :
        (GEN_DIV == 2'd2) ? ~frame_cnt[0] :
        (frame_cnt[1:0] == 2'd0)  // GEN_DIV 4: every 4th frame
    );

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

    // Debug panel: top-left. Gen/Frm hex, state, heartbeat. Uses delayed coords to match r,g,b.
    localparam [11:0] DX = 12'd8;
    localparam [11:0] DY = 12'd8;
    localparam [11:0] LINE_H = 12'd8;
    localparam [11:0] GAP = 12'd4;

    wire [11:0] px = pixel_x_d1 - DX;
    wire [11:0] py = pixel_y_d1 - DY;

    // Hex font 0-F: 8 rows x 8 cols. digit[3:0], row[2:0] -> 8-bit row pattern (MSB left)
    function [7:0] hex_row;
        input [3:0] d;
        input [2:0] row;
        case ({d, row})
            {4'd0,3'd0}: hex_row=8'h3C; {4'd0,3'd1}: hex_row=8'h42; {4'd0,3'd2}: hex_row=8'h81; {4'd0,3'd3}: hex_row=8'h81; {4'd0,3'd4}: hex_row=8'h81; {4'd0,3'd5}: hex_row=8'h81; {4'd0,3'd6}: hex_row=8'h42; {4'd0,3'd7}: hex_row=8'h3C;
            {4'd1,3'd0}: hex_row=8'h08; {4'd1,3'd1}: hex_row=8'h18; {4'd1,3'd2}: hex_row=8'h08; {4'd1,3'd3}: hex_row=8'h08; {4'd1,3'd4}: hex_row=8'h08; {4'd1,3'd5}: hex_row=8'h08; {4'd1,3'd6}: hex_row=8'h08; {4'd1,3'd7}: hex_row=8'h3E;
            {4'd2,3'd0}: hex_row=8'h3C; {4'd2,3'd1}: hex_row=8'h42; {4'd2,3'd2}: hex_row=8'h01; {4'd2,3'd3}: hex_row=8'h02; {4'd2,3'd4}: hex_row=8'h04; {4'd2,3'd5}: hex_row=8'h08; {4'd2,3'd6}: hex_row=8'h10; {4'd2,3'd7}: hex_row=8'h7F;
            {4'd3,3'd0}: hex_row=8'h3C; {4'd3,3'd1}: hex_row=8'h42; {4'd3,3'd2}: hex_row=8'h01; {4'd3,3'd3}: hex_row=8'h0C; {4'd3,3'd4}: hex_row=8'h02; {4'd3,3'd5}: hex_row=8'h81; {4'd3,3'd6}: hex_row=8'h42; {4'd3,3'd7}: hex_row=8'h3C;
            {4'd4,3'd0}: hex_row=8'h02; {4'd4,3'd1}: hex_row=8'h06; {4'd4,3'd2}: hex_row=8'h0A; {4'd4,3'd3}: hex_row=8'h12; {4'd4,3'd4}: hex_row=8'h22; {4'd4,3'd5}: hex_row=8'h7F; {4'd4,3'd6}: hex_row=8'h02; {4'd4,3'd7}: hex_row=8'h02;
            {4'd5,3'd0}: hex_row=8'h7F; {4'd5,3'd1}: hex_row=8'h80; {4'd5,3'd2}: hex_row=8'h80; {4'd5,3'd3}: hex_row=8'hFC; {4'd5,3'd4}: hex_row=8'h02; {4'd5,3'd5}: hex_row=8'h01; {4'd5,3'd6}: hex_row=8'h82; {4'd5,3'd7}: hex_row=8'h7C;
            {4'd6,3'd0}: hex_row=8'h3C; {4'd6,3'd1}: hex_row=8'h42; {4'd6,3'd2}: hex_row=8'h80; {4'd6,3'd3}: hex_row=8'hFC; {4'd6,3'd4}: hex_row=8'h82; {4'd6,3'd5}: hex_row=8'h81; {4'd6,3'd6}: hex_row=8'h42; {4'd6,3'd7}: hex_row=8'h3C;
            {4'd7,3'd0}: hex_row=8'h7F; {4'd7,3'd1}: hex_row=8'h01; {4'd7,3'd2}: hex_row=8'h02; {4'd7,3'd3}: hex_row=8'h04; {4'd7,3'd4}: hex_row=8'h08; {4'd7,3'd5}: hex_row=8'h10; {4'd7,3'd6}: hex_row=8'h20; {4'd7,3'd7}: hex_row=8'h40;
            {4'd8,3'd0}: hex_row=8'h3C; {4'd8,3'd1}: hex_row=8'h42; {4'd8,3'd2}: hex_row=8'h81; {4'd8,3'd3}: hex_row=8'h3C; {4'd8,3'd4}: hex_row=8'h42; {4'd8,3'd5}: hex_row=8'h81; {4'd8,3'd6}: hex_row=8'h42; {4'd8,3'd7}: hex_row=8'h3C;
            {4'd9,3'd0}: hex_row=8'h3C; {4'd9,3'd1}: hex_row=8'h42; {4'd9,3'd2}: hex_row=8'h81; {4'd9,3'd3}: hex_row=8'h43; {4'd9,3'd4}: hex_row=8'h3D; {4'd9,3'd5}: hex_row=8'h01; {4'd9,3'd6}: hex_row=8'h42; {4'd9,3'd7}: hex_row=8'h3C;
            {4'd10,3'd0}: hex_row=8'h18; {4'd10,3'd1}: hex_row=8'h24; {4'd10,3'd2}: hex_row=8'h42; {4'd10,3'd3}: hex_row=8'h81; {4'd10,3'd4}: hex_row=8'hFF; {4'd10,3'd5}: hex_row=8'h81; {4'd10,3'd6}: hex_row=8'h81; {4'd10,3'd7}: hex_row=8'h81;
            {4'd11,3'd0}: hex_row=8'hFC; {4'd11,3'd1}: hex_row=8'h82; {4'd11,3'd2}: hex_row=8'h82; {4'd11,3'd3}: hex_row=8'hFC; {4'd11,3'd4}: hex_row=8'h82; {4'd11,3'd5}: hex_row=8'h82; {4'd11,3'd6}: hex_row=8'h82; {4'd11,3'd7}: hex_row=8'hFC;
            {4'd12,3'd0}: hex_row=8'h3C; {4'd12,3'd1}: hex_row=8'h42; {4'd12,3'd2}: hex_row=8'h81; {4'd12,3'd3}: hex_row=8'h80; {4'd12,3'd4}: hex_row=8'h80; {4'd12,3'd5}: hex_row=8'h81; {4'd12,3'd6}: hex_row=8'h42; {4'd12,3'd7}: hex_row=8'h3C;
            {4'd13,3'd0}: hex_row=8'hFC; {4'd13,3'd1}: hex_row=8'h82; {4'd13,3'd2}: hex_row=8'h81; {4'd13,3'd3}: hex_row=8'h81; {4'd13,3'd4}: hex_row=8'h81; {4'd13,3'd5}: hex_row=8'h82; {4'd13,3'd6}: hex_row=8'h82; {4'd13,3'd7}: hex_row=8'hFC;
            {4'd14,3'd0}: hex_row=8'h7F; {4'd14,3'd1}: hex_row=8'h80; {4'd14,3'd2}: hex_row=8'h80; {4'd14,3'd3}: hex_row=8'h7F; {4'd14,3'd4}: hex_row=8'h80; {4'd14,3'd5}: hex_row=8'h80; {4'd14,3'd6}: hex_row=8'h80; {4'd14,3'd7}: hex_row=8'h7F;
            {4'd15,3'd0}: hex_row=8'h7F; {4'd15,3'd1}: hex_row=8'h80; {4'd15,3'd2}: hex_row=8'h80; {4'd15,3'd3}: hex_row=8'h7F; {4'd15,3'd4}: hex_row=8'h80; {4'd15,3'd5}: hex_row=8'h80; {4'd15,3'd6}: hex_row=8'h80; {4'd15,3'd7}: hex_row=8'h80;
            default: hex_row=8'h00;
        endcase
    endfunction

    // Line 0: "GOL" (24px) + St 0-5 (8px) + heartbeat (4px) — heartbeat flashes if frames advance
    wire line0 = (py >= 12'd0 && py < LINE_H);
    wire in_gol = line0 && (px >= 12'd0 && px < 12'd24);
    wire in_st = line0 && (px >= 12'd28 && px < 12'd36);
    wire in_heartbeat = line0 && (px >= 12'd40 && px < 12'd44);
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

    // Line 1: Gen XXXX (4 hex digits)
    wire line1 = (py >= LINE_H + GAP && py < LINE_H + GAP + LINE_H);
    wire in_gen_hex = line1 && (px >= 12'd0 && px < 12'd32);
    wire [2:0] gen_char_col = px[2:0];
    wire [1:0] gen_char_idx = px[4:3];
    wire [3:0] gen_nibble = (gen_char_idx == 2'd0) ? debug_gen[15:12] : (gen_char_idx == 2'd1) ? debug_gen[11:8] : (gen_char_idx == 2'd2) ? debug_gen[7:4] : debug_gen[3:0];
    wire [7:0] gen_row_bits = hex_row(gen_nibble, py[2:0]);
    wire gen_hex_pix = (gen_char_col == 3'd0) ? gen_row_bits[7] : (gen_char_col == 3'd1) ? gen_row_bits[6] : (gen_char_col == 3'd2) ? gen_row_bits[5] : (gen_char_col == 3'd3) ? gen_row_bits[4] : (gen_char_col == 3'd4) ? gen_row_bits[3] : (gen_char_col == 3'd5) ? gen_row_bits[2] : (gen_char_col == 3'd6) ? gen_row_bits[1] : gen_row_bits[0];

    // Line 2: Frm XXXX (4 hex digits)
    wire line2 = (py >= (LINE_H + GAP) * 2 && py < (LINE_H + GAP) * 2 + LINE_H);
    wire in_frm_hex = line2 && (px >= 12'd0 && px < 12'd32);
    wire [2:0] frm_char_col = px[2:0];
    wire [1:0] frm_char_idx = px[4:3];
    wire [3:0] frm_nibble = (frm_char_idx == 2'd0) ? frame_cnt[15:12] : (frm_char_idx == 2'd1) ? frame_cnt[11:8] : (frm_char_idx == 2'd2) ? frame_cnt[7:4] : frame_cnt[3:0];
    wire [7:0] frm_row_bits = hex_row(frm_nibble, py[2:0]);
    wire frm_hex_pix = (frm_char_col == 3'd0) ? frm_row_bits[7] : (frm_char_col == 3'd1) ? frm_row_bits[6] : (frm_char_col == 3'd2) ? frm_row_bits[5] : (frm_char_col == 3'd3) ? frm_row_bits[4] : (frm_char_col == 3'd4) ? frm_row_bits[3] : (frm_char_col == 3'd5) ? frm_row_bits[2] : (frm_char_col == 3'd6) ? frm_row_bits[1] : frm_row_bits[0];

    // Line 3: St bar (0-5) + B=ram_select + I=init_done
    wire line3 = (py >= (LINE_H + GAP) * 3 && py < (LINE_H + GAP) * 3 + LINE_H);
    wire in_st_bar = line3 && (px >= 12'd0 && px < 12'd48);
    wire [2:0] st_seg = px[5:3];
    wire st_seg_on = (st_seg <= debug_state[2:0]);
    wire in_b_block = line3 && (px >= 12'd52 && px < 12'd60);
    wire in_i_block = line3 && (px >= 12'd64 && px < 12'd72);

    wire in_panel = (pixel_x_d1 >= DX && pixel_x_d1 < DX + 12'd88 && pixel_y_d1 >= DY && pixel_y_d1 < DY + (LINE_H + GAP) * 3 + LINE_H);

    // Population panel: top-right, 32 species rows (color swatch + 4 hex digits = population)
    localparam [11:0] POP_X = 12'd1234;   // 1280 - 8 - 38
    localparam [11:0] POP_Y = 12'd8;
    localparam [11:0] POP_W = 12'd38;     // 6 swatch + 4 hex chars × 8 = 38
    localparam [11:0] POP_H = 12'd256;    // 32 rows × 8 px (hex font)
    wire in_pop = (pixel_x_d1 >= POP_X && pixel_x_d1 < POP_X + POP_W && pixel_y_d1 >= POP_Y && pixel_y_d1 < POP_Y + POP_H);
    wire [11:0] pop_px = pixel_x_d1 - POP_X;
    wire [11:0] pop_py = pixel_y_d1 - POP_Y;
    wire [4:0] pop_row = pop_py[6:2];     // 0-31 (8px per row)
    wire [15:0] pop_val = (pop_row == 5'd0) ? pop_count[15:0] : (pop_row == 5'd1) ? pop_count[31:16] : (pop_row == 5'd2) ? pop_count[47:32] : (pop_row == 5'd3) ? pop_count[63:48] :
                          (pop_row == 5'd4) ? pop_count[79:64] : (pop_row == 5'd5) ? pop_count[95:80] : (pop_row == 5'd6) ? pop_count[111:96] : (pop_row == 5'd7) ? pop_count[127:112] :
                          (pop_row == 5'd8) ? pop_count[143:128] : (pop_row == 5'd9) ? pop_count[159:144] : (pop_row == 5'd10) ? pop_count[175:160] : (pop_row == 5'd11) ? pop_count[191:176] :
                          (pop_row == 5'd12) ? pop_count[207:192] : (pop_row == 5'd13) ? pop_count[223:208] : (pop_row == 5'd14) ? pop_count[239:224] : (pop_row == 5'd15) ? pop_count[255:240] :
                          (pop_row == 5'd16) ? pop_count[271:256] : (pop_row == 5'd17) ? pop_count[287:272] : (pop_row == 5'd18) ? pop_count[303:288] : (pop_row == 5'd19) ? pop_count[319:304] :
                          (pop_row == 5'd20) ? pop_count[335:320] : (pop_row == 5'd21) ? pop_count[351:336] : (pop_row == 5'd22) ? pop_count[367:352] : (pop_row == 5'd23) ? pop_count[383:368] :
                          (pop_row == 5'd24) ? pop_count[399:384] : (pop_row == 5'd25) ? pop_count[415:400] : (pop_row == 5'd26) ? pop_count[431:416] : (pop_row == 5'd27) ? pop_count[447:432] :
                          (pop_row == 5'd28) ? pop_count[463:448] : (pop_row == 5'd29) ? pop_count[479:464] : (pop_row == 5'd30) ? pop_count[495:480] : pop_count[511:496];
    wire in_swatch = in_pop && (pop_px < 12'd6);   // 6px color swatch per row
    wire in_pop_hex = in_pop && (pop_px >= 12'd6);  // hex digits area (4 chars × 8px)
    wire [11:0] pop_px_rel = pop_px - 12'd6;  // Gowin: no bit-select on expr
    wire [1:0] pop_char_idx = pop_px_rel[4:3];  // 0-3
    wire [3:0] pop_nibble = (pop_char_idx == 2'd0) ? pop_val[15:12] : (pop_char_idx == 2'd1) ? pop_val[11:8] : (pop_char_idx == 2'd2) ? pop_val[7:4] : pop_val[3:0];
    wire [7:0] pop_row_bits = hex_row(pop_nibble, pop_py[2:0]);
    wire [2:0] pop_char_col = pop_px_rel[2:0];  // column within 8px char
    wire pop_hex_pix = (pop_char_col == 3'd0) ? pop_row_bits[7] : (pop_char_col == 3'd1) ? pop_row_bits[6] : (pop_char_col == 3'd2) ? pop_row_bits[5] : (pop_char_col == 3'd3) ? pop_row_bits[4] : (pop_char_col == 3'd4) ? pop_row_bits[3] : (pop_char_col == 3'd5) ? pop_row_bits[2] : (pop_char_col == 3'd6) ? pop_row_bits[1] : pop_row_bits[0];
    // Species color LUT (match video_source_gol, 32 species)
    wire [7:0] pop_r = (pop_row==5'd0)?8'd12:(pop_row==5'd1)?8'd255:(pop_row==5'd2)?8'd0:(pop_row==5'd3)?8'd100:(pop_row==5'd4)?8'd255:(pop_row==5'd5)?8'd255:(pop_row==5'd6)?8'd0:(pop_row==5'd7)?8'd255:(pop_row==5'd8)?8'd180:(pop_row==5'd9)?8'd0:(pop_row==5'd10)?8'd255:(pop_row==5'd11)?8'd200:(pop_row==5'd12)?8'd255:(pop_row==5'd13)?8'd100:(pop_row==5'd14)?8'd255:(pop_row==5'd15)?8'd255:(pop_row==5'd16)?8'd140:(pop_row==5'd17)?8'd80:(pop_row==5'd18)?8'd200:(pop_row==5'd19)?8'd60:(pop_row==5'd20)?8'd255:(pop_row==5'd21)?8'd100:(pop_row==5'd22)?8'd255:(pop_row==5'd23)?8'd60:(pop_row==5'd24)?8'd180:(pop_row==5'd25)?8'd255:(pop_row==5'd26)?8'd60:(pop_row==5'd27)?8'd200:(pop_row==5'd28)?8'd255:(pop_row==5'd29)?8'd100:(pop_row==5'd30)?8'd255:8'd180;
    wire [7:0] pop_g = (pop_row==5'd0)?8'd12:(pop_row==5'd1)?8'd80:(pop_row==5'd2)?8'd255:(pop_row==5'd3)?8'd180:(pop_row==5'd4)?8'd220:(pop_row==5'd5)?8'd50:(pop_row==5'd6)?8'd255:(pop_row==5'd7)?8'd120:(pop_row==5'd8)?8'd100:(pop_row==5'd9)?8'd200:(pop_row==5'd10)?8'd150:(pop_row==5'd11)?8'd255:(pop_row==5'd12)?8'd100:(pop_row==5'd13)?8'd255:(pop_row==5'd14)?8'd255:(pop_row==5'd15)?8'd255:(pop_row==5'd16)?8'd80:(pop_row==5'd17)?8'd200:(pop_row==5'd18)?8'd140:(pop_row==5'd19)?8'd140:(pop_row==5'd20)?8'd60:(pop_row==5'd21)?8'd255:(pop_row==5'd22)?8'd200:(pop_row==5'd23)?8'd255:(pop_row==5'd24)?8'd60:(pop_row==5'd25)?8'd100:(pop_row==5'd26)?8'd180:(pop_row==5'd27)?8'd255:(pop_row==5'd28)?8'd60:(pop_row==5'd29)?8'd60:(pop_row==5'd30)?8'd180:8'd180;
    wire [7:0] pop_b = (pop_row==5'd0)?8'd24:(pop_row==5'd1)?8'd255:(pop_row==5'd2)?8'd200:(pop_row==5'd3)?8'd255:(pop_row==5'd4)?8'd0:(pop_row==5'd5)?8'd150:(pop_row==5'd6)?8'd120:(pop_row==5'd7)?8'd80:(pop_row==5'd8)?8'd255:(pop_row==5'd9)?8'd255:(pop_row==5'd10)?8'd0:(pop_row==5'd11)?8'd100:(pop_row==5'd12)?8'd255:(pop_row==5'd13)?8'd255:(pop_row==5'd14)?8'd100:(pop_row==5'd15)?8'd255:(pop_row==5'd16)?8'd200:(pop_row==5'd17)?8'd140:(pop_row==5'd18)?8'd80:(pop_row==5'd19)?8'd255:(pop_row==5'd20)?8'd100:(pop_row==5'd21)?8'd60:(pop_row==5'd22)?8'd60:(pop_row==5'd23)?8'd200:(pop_row==5'd24)?8'd255:(pop_row==5'd25)?8'd60:(pop_row==5'd26)?8'd255:(pop_row==5'd27)?8'd60:(pop_row==5'd28)?8'd180:(pop_row==5'd29)?8'd255:(pop_row==5'd30)?8'd100:8'd255;
    wire [7:0] pop_dbg_r = in_swatch ? pop_r : (in_pop_hex && pop_hex_pix) ? 8'hFF : (in_pop_hex && !pop_hex_pix) ? 8'd40 : 8'd0;
    wire [7:0] pop_dbg_g = in_swatch ? pop_g : (in_pop_hex && pop_hex_pix) ? 8'hFF : (in_pop_hex && !pop_hex_pix) ? 8'd40 : 8'd0;
    wire [7:0] pop_dbg_b = in_swatch ? pop_b : (in_pop_hex && pop_hex_pix) ? 8'hFF : (in_pop_hex && !pop_hex_pix) ? 8'd40 : 8'd0;

    wire show_debug = in_panel | in_pop;
    wire hb_on = in_heartbeat && frame_cnt[0];  // Heartbeat: flashes every 2 frames if frames advance
    wire [7:0] debug_r = in_pop ? pop_dbg_r : (in_gol && gol_pix ? 8'hFF : (in_st && st_pix) ? 8'hFF : hb_on ? 8'hFF : (in_gen_hex && gen_hex_pix) ? 8'h00 : (in_frm_hex && frm_hex_pix) ? 8'h00 : (in_st_bar && st_seg_on) ? 8'hFF : (in_b_block && ram_select) ? 8'd0 : (in_i_block && init_done) ? 8'd0 : 8'd0);
    wire [7:0] debug_g = in_pop ? pop_dbg_g : (in_gol && gol_pix ? 8'hFF : (in_st && st_pix) ? 8'hFF : hb_on ? 8'hFF : (in_gen_hex && gen_hex_pix) ? 8'hFF : (in_frm_hex && frm_hex_pix) ? 8'hFF : (in_st_bar && st_seg_on) ? 8'h80 : (in_b_block && ram_select) ? 8'hFF : (in_i_block && init_done) ? 8'hFF : 8'd0);
    wire [7:0] debug_b = in_pop ? pop_dbg_b : (in_gol && gol_pix ? 8'hFF : (in_st && st_pix) ? 8'hFF : hb_on ? 8'hFF : (in_gen_hex && gen_hex_pix) ? 8'h00 : (in_frm_hex && frm_hex_pix) ? 8'h00 : (in_st_bar && st_seg_on) ? 8'h80 : (in_b_block && ram_select) ? 8'hFF : (in_i_block && init_done) ? 8'hFF : 8'd0);

    // Semi-transparent overlay (60% debug + 40% GOL) so grid shows through; pop panel opaque
    wire [7:0] blend_r = show_debug ? (in_pop ? pop_dbg_r : ((debug_r * 3 + r) >> 2)) : r;
    wire [7:0] blend_g = show_debug ? (in_pop ? pop_dbg_g : ((debug_g * 3 + g) >> 2)) : g;
    wire [7:0] blend_b = show_debug ? (in_pop ? pop_dbg_b : ((debug_b * 3 + b) >> 2)) : b;

    // For DVI_TX_Top: debug overlay on top of GOL, black during INIT
    assign rgb_r  = init_done_d1 ? blend_r : 8'd0;
    assign rgb_g  = init_done_d1 ? blend_g : 8'd0;
    assign rgb_b  = init_done_d1 ? blend_b : 8'd0;
    assign rgb_hs = hsync_d1;
    assign rgb_vs = vsync_d1;
    assign rgb_de = de_d1;
endmodule
