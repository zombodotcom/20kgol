/**
 * top_engine.v — Minimal top for Segment 2: gol_engine + 2× gol_ram (for synthesis check).
 * Not the final top; used to verify DFF count and no BRAM in FSM.
 */
module top_engine (
    input  wire       clk,
    input  wire       rst,
    input  wire       video_sof,
    output wire       ram_select,
    output wire [3:0] dout0_sample,  // optional: sample bank0 for debug
    output wire [3:0] dout1_sample
);
    wire [15:0] addr;
    wire        we0, we1;
    wire [3:0]  din;
    wire [3:0]  dout0, dout1;

    gol_engine engine (
        .clk(clk),
        .rst(rst),
        .video_sof(video_sof),
        .dout_bank0(dout0),
        .dout_bank1(dout1),
        .ram_select(ram_select),
        .addr(addr),
        .we0(we0),
        .we1(we1),
        .din(din)
    );

    gol_ram bank0 (
        .clk(clk),
        .addr(addr),
        .we(we0),
        .din(din),
        .dout(dout0)
    );

    gol_ram bank1 (
        .clk(clk),
        .addr(addr),
        .we(we1),
        .din(din),
        .dout(dout1)
    );

    assign dout0_sample = dout0;
    assign dout1_sample = dout1;
endmodule
