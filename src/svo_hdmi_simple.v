/**
 * svo_hdmi_simple.v — 720p60 timing only, solid white in active area.
 * No RAM, no engine. Use with top.v for "something simple" to verify HDMI path.
 */
module svo_hdmi_simple (
    input  wire        clk,
    input  wire        rst,
    output wire [7:0]  rgb_r,
    output wire [7:0]  rgb_g,
    output wire [7:0]  rgb_b,
    output wire        rgb_hs,
    output wire        rgb_vs,
    output wire        rgb_de
);
    localparam [11:0] H_ACTIVE = 12'd1280;
    localparam [11:0] H_FP     = 12'd110;
    localparam [11:0] H_SYNC  = 12'd40;
    localparam [11:0] H_BP    = 12'd220;
    localparam [11:0] H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;

    localparam [11:0] V_ACTIVE = 12'd720;
    localparam [11:0] V_FP     = 12'd5;
    localparam [11:0] V_SYNC  = 12'd5;
    localparam [11:0] V_BP    = 12'd20;
    localparam [11:0] V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [11:0] h_count, v_count;
    reg        hsync_r, vsync_r, de_r;

    always @(posedge clk) begin
        if (rst) begin
            h_count <= 12'd0;
            v_count <= 12'd0;
            hsync_r <= 0;
            vsync_r <= 0;
            de_r    <= 0;
        end else begin
            if (h_count == H_TOTAL - 12'd1) begin
                h_count <= 12'd0;
                if (v_count == V_TOTAL - 12'd1)
                    v_count <= 12'd0;
                else
                    v_count <= v_count + 12'd1;
            end else
                h_count <= h_count + 12'd1;

            de_r    <= (h_count < H_ACTIVE && v_count < V_ACTIVE);
            hsync_r <= (h_count >= H_ACTIVE + H_FP && h_count < H_ACTIVE + H_FP + H_SYNC);
            vsync_r <= (v_count >= V_ACTIVE + V_FP && v_count < V_ACTIVE + V_FP + V_SYNC);
        end
    end

    assign rgb_r  = de_r ? 8'hFF : 8'd0;
    assign rgb_g  = de_r ? 8'hFF : 8'd0;
    assign rgb_b  = de_r ? 8'hFF : 8'd0;
    assign rgb_hs = hsync_r;
    assign rgb_vs = vsync_r;
    assign rgb_de = de_r;
endmodule
