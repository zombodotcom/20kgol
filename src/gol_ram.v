/**
 * gol_ram.v — 64K×4-bit synchronous single-port grid RAM for Game of Life.
 * Intended for Gowin BRAM/BSRAM inference. One cycle read latency (registered dout).
 */
module gol_ram (
    input  wire        clk,
    input  wire [15:0]  addr,
    input  wire        we,
    input  wire [3:0]   din,
    output reg  [3:0]   dout
);
    reg [3:0] mem [0:65535];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];
    end
endmodule
