/**
 * gol_ram.v — 64K×4-bit synchronous single-port grid RAM for Game of Life.
 * Intended for Gowin BRAM/BSRAM inference. One cycle read latency (registered dout).
 */
module gol_ram (
    input  wire        clk,
    input  wire [15:0]  addr,
    input  wire        we,
    input  wire [4:0]   din,
    output reg  [4:0]   dout
);
    reg [4:0] mem [0:65535];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];
    end
endmodule

/**
 * gol_ram_dual — 64K×4 dual-port: port A read (display), port B read/write (engine).
 * 1-cycle read latency on both ports. In same file so Gowin finds it when compiling gol_ram.v.
 */
module gol_ram_dual (
    input  wire        clk,
    input  wire [15:0]  addr_a,
    output reg  [4:0]   dout_a,
    input  wire [15:0]  addr_b,
    input  wire        we_b,
    input  wire [4:0]   din_b,
    output reg  [4:0]   dout_b
);
    reg [4:0] mem [0:65535];

    always @(posedge clk) begin
        dout_a <= mem[addr_a];
    end
    // Port B: write-first so Gowin DPB infers WRITE_MODE0 = 2'b00/2'b01 (2'b10 not supported)
    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b <= we_b ? din_b : mem[addr_b];
    end
endmodule
