/**
 * top_ram.v — Minimal top for Segment 1: two gol_ram banks only (for synthesis check).
 * Not the final top; used to verify BRAM inference for 2× 64K×4.
 */
module top_ram (
    input  wire        clk,
    input  wire [15:0] addr0,
    input  wire        we0,
    input  wire [3:0]  din0,
    output wire [3:0]  dout0,
    input  wire [15:0] addr1,
    input  wire        we1,
    input  wire [3:0]  din1,
    output wire [3:0]  dout1
);
    gol_ram bank0 (
        .clk(clk),
        .addr(addr0),
        .we(we0),
        .din(din0),
        .dout(dout0)
    );
    gol_ram bank1 (
        .clk(clk),
        .addr(addr1),
        .we(we1),
        .din(din1),
        .dout(dout1)
    );
endmodule
