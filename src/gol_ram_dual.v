/**
 * gol_ram_dual.v — 64K×4 dual-port: port A read (display), port B read/write (engine).
 * Allows display and engine to read the same bank simultaneously for correct GOL double-buffer.
 * 1-cycle read latency on both ports. Gowin EBR/BSRAM inference.
 */
module gol_ram_dual (
    input  wire        clk,
    input  wire [15:0]  addr_a,   // display read
    output reg  [3:0]   dout_a,
    input  wire [15:0]  addr_b,
    input  wire        we_b,
    input  wire [3:0]   din_b,
    output reg  [3:0]   dout_b
);
    reg [3:0] mem [0:65535];

    always @(posedge clk) begin
        dout_a <= mem[addr_a];
    end
    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
endmodule
