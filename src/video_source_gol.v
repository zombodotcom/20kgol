/**
 * video_source_gol.v — Pixel to grid mapping and 8-color LUT for Game of Life display.
 * 720p: grid 1024×720 (4×4 pixels per cell) full height; neon palette.
 */
module video_source_gol (
    input  wire        clk,
    input  wire [11:0] pixel_x,   // 0..1279 for 720p
    input  wire [11:0] pixel_y,   // 0..719
    input  wire        de,        // data enable (active video)
    input  wire [4:0]  dout,      // display bank read data (1-cycle latency)
    output reg  [15:0] addr,      // address to display bank: {gol_y[7:0], gol_x[7:0]}
    output reg  [7:0]  r, g, b    // 8b per channel for TMDS
);
    // 720p: 1280×720. Grid 256×256 at 4×4 = 1024×1024, 1024×720 visible (full height).
    localparam [11:0] GRID_OFFSET_X = 12'd128;  // (1280 - 1024) / 2
    localparam [11:0] GRID_OFFSET_Y = 12'd0;
    localparam [11:0] GRID_W = 12'd1024;
    localparam [11:0] GRID_H = 12'd720;         // 180 rows × 4

    wire in_grid = (pixel_x >= GRID_OFFSET_X && pixel_x < GRID_OFFSET_X + GRID_W &&
                    pixel_y >= GRID_OFFSET_Y && pixel_y < GRID_OFFSET_Y + GRID_H);
    wire [11:0] px_off = pixel_x - GRID_OFFSET_X;
    wire [11:0] py_off = pixel_y - GRID_OFFSET_Y;
    wire [11:0] gol_x_12 = px_off >> 2;         // 4 pixels per cell
    wire [11:0] gol_y_12 = py_off >> 2;
    wire [7:0] gol_x = gol_x_12[7:0];
    wire [7:0] gol_y = gol_y_12[7:0];

    // Request CURRENT cell; dout arrives 1 cycle later and matches current pixel (species <= dout)
    wire [15:0] addr_cur = {gol_y, gol_x};

    reg        de_d1;
    reg        in_grid_d1;
    reg [4:0]  species;   // dout delayed 1 cycle (now for current pixel)

    always @(posedge clk) begin
        addr       <= in_grid ? addr_cur : 16'd0;
        de_d1      <= de;
        in_grid_d1 <= in_grid;
        species    <= dout;
    end

    // Neon palette: 32 species (0=dead, 1-31 living)
    reg [7:0] rr, gg, bb;
    always @(*) begin
        case (species)
            5'd0:  begin rr = 8'd12;  gg = 8'd12;  bb = 8'd24;  end   // dead
            5'd1:  begin rr = 8'd255; gg = 8'd80;  bb = 8'd255; end   // magenta
            5'd2:  begin rr = 8'd0;   gg = 8'd255; bb = 8'd200; end   // cyan
            5'd3:  begin rr = 8'd100; gg = 8'd180; bb = 8'd255; end   // blue
            5'd4:  begin rr = 8'd255; gg = 8'd220; bb = 8'd0;   end   // amber
            5'd5:  begin rr = 8'd255; gg = 8'd50;  bb = 8'd150; end   // pink
            5'd6:  begin rr = 8'd0;   gg = 8'd255; bb = 8'd120; end   // lime
            5'd7:  begin rr = 8'd255; gg = 8'd120; bb = 8'd80;  end   // coral
            5'd8:  begin rr = 8'd180; gg = 8'd100; bb = 8'd255; end   // violet
            5'd9:  begin rr = 8'd0;   gg = 8'd200; bb = 8'd255; end   // teal
            5'd10: begin rr = 8'd255; gg = 8'd150; bb = 8'd0;   end   // orange
            5'd11: begin rr = 8'd200; gg = 8'd255; bb = 8'd100; end   // chartreuse
            5'd12: begin rr = 8'd255; gg = 8'd100; bb = 8'd255; end   // fuchsia
            5'd13: begin rr = 8'd100; gg = 8'd255; bb = 8'd255; end   // aqua
            5'd14: begin rr = 8'd255; gg = 8'd255; bb = 8'd100; end   // yellow
            5'd15: begin rr = 8'd255; gg = 8'd255; bb = 8'd255; end   // white
            5'd16: begin rr = 8'd140; gg = 8'd80;  bb = 8'd200; end   // purple
            5'd17: begin rr = 8'd80;  gg = 8'd200; bb = 8'd140; end   // mint
            5'd18: begin rr = 8'd200; gg = 8'd140; bb = 8'd80;  end   // tan
            5'd19: begin rr = 8'd60;  gg = 8'd140; bb = 8'd255; end   // sky
            5'd20: begin rr = 8'd255; gg = 8'd60;  bb = 8'd100; end   // rose
            5'd21: begin rr = 8'd100; gg = 8'd255; bb = 8'd60;  end   // spring
            5'd22: begin rr = 8'd255; gg = 8'd200; bb = 8'd60;  end   // gold
            5'd23: begin rr = 8'd60;  gg = 8'd255; bb = 8'd200; end   // turquoise
            5'd24: begin rr = 8'd180; gg = 8'd60;  bb = 8'd255; end   // lavender
            5'd25: begin rr = 8'd255; gg = 8'd100; bb = 8'd60;  end   // salmon
            5'd26: begin rr = 8'd60;  gg = 8'd180; bb = 8'd255; end   // light blue
            5'd27: begin rr = 8'd200; gg = 8'd255; bb = 8'd60;  end   // lime yellow
            5'd28: begin rr = 8'd255; gg = 8'd60;  bb = 8'd180; end   // hot pink
            5'd29: begin rr = 8'd100; gg = 8'd60;  bb = 8'd255; end   // indigo
            5'd30: begin rr = 8'd255; gg = 8'd180; bb = 8'd100; end   // peach
            default: begin rr = 8'd180; gg = 8'd180; bb = 8'd255; end  // 31: periwinkle
        endcase
    end

    always @(posedge clk) begin
        if (de_d1) begin
            if (in_grid_d1) begin
                r <= rr;
                g <= gg;
                b <= bb;
            end else begin
                r <= 8'd8;   // outside grid: dark navy (visible)
                g <= 8'd8;
                b <= 8'd28;
            end
        end else begin
            r <= 8'd8;
            g <= 8'd8;
            b <= 8'd28;
        end
    end
endmodule
