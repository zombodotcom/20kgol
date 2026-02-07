/**
 * video_source_gol.v — Pixel to grid mapping and 8-color LUT for Game of Life display.
 * 720p: grid 512×512 (2×2 pixels per cell) centered; 1-cycle read latency pipelined.
 */
module video_source_gol (
    input  wire        clk,
    input  wire [11:0] pixel_x,   // 0..1279 for 720p
    input  wire [11:0] pixel_y,   // 0..719
    input  wire        de,        // data enable (active video)
    input  wire [3:0]  dout,      // display bank read data (1-cycle latency)
    output reg  [15:0] addr,      // address to display bank: {gol_y[7:0], gol_x[7:0]}
    output reg  [7:0]  r, g, b    // 8b per channel for TMDS
);
    // 720p: 1280×720. Grid 256×256 at 2×2 = 512×512, centered.
    localparam [11:0] GRID_OFFSET_X = 12'd384;  // (1280 - 512) / 2
    localparam [11:0] GRID_OFFSET_Y = 12'd104;  // (720 - 512) / 2
    localparam [11:0] GRID_W = 12'd512;
    localparam [11:0] GRID_H = 12'd512;

    wire in_grid = (pixel_x >= GRID_OFFSET_X && pixel_x < GRID_OFFSET_X + GRID_W &&
                    pixel_y >= GRID_OFFSET_Y && pixel_y < GRID_OFFSET_Y + GRID_H);
    wire [11:0] gol_x_12 = (pixel_x - GRID_OFFSET_X) >> 1;
    wire [11:0] gol_y_12 = (pixel_y - GRID_OFFSET_Y) >> 1;
    wire [7:0] gol_x = gol_x_12[7:0];
    wire [7:0] gol_y = gol_y_12[7:0];

    // Prefetch: send addr for NEXT pixel so dout (1-cycle latency) matches current pixel
    wire [7:0] gol_x_next = (gol_x == 8'd255) ? 8'd0 : (gol_x + 8'd1);
    wire [7:0] gol_y_next = (gol_x == 8'd255) ? ((gol_y == 8'd255) ? 8'd0 : (gol_y + 8'd1)) : gol_y;
    wire [15:0] addr_next = {gol_y_next, gol_x_next};

    reg        de_d1;
    reg        in_grid_d1;
    reg [3:0]  species;   // dout delayed 1 cycle (now for current pixel)

    always @(posedge clk) begin
        addr       <= in_grid ? addr_next : 16'd0;
        de_d1      <= de;
        in_grid_d1 <= in_grid;
        species    <= dout;
    end

    // 8-entry color LUT: 0 = black (dead), 1..7 = distinct colors (case for synthesis)
    reg [7:0] rr, gg, bb;
    always @(*) begin
        case (species)
            4'd0: begin rr = 8'd0;   gg = 8'd0;   bb = 8'd0;   end
            4'd1: begin rr = 8'd255; gg = 8'd0;   bb = 8'd0;   end
            4'd2: begin rr = 8'd0;   gg = 8'd255; bb = 8'd0;   end
            4'd3: begin rr = 8'd0;   gg = 8'd0;   bb = 8'd255; end
            4'd4: begin rr = 8'd255; gg = 8'd255; bb = 8'd0;   end
            4'd5: begin rr = 8'd255; gg = 8'd0;   bb = 8'd255; end
            4'd6: begin rr = 8'd0;   gg = 8'd255; bb = 8'd255; end
            default: begin rr = 8'd255; gg = 8'd255; bb = 8'd255; end
        endcase
    end

    always @(posedge clk) begin
        if (de_d1) begin
            if (in_grid_d1) begin
                r <= rr;
                g <= gg;
                b <= bb;
            end else begin
                r <= 8'd0;
                g <= 8'd0;
                b <= 8'd0;
            end
        end else begin
            r <= 8'd0;
            g <= 8'd0;
            b <= 8'd0;
        end
    end
endmodule
