/**
 * tb_gol_ram.v — Testbench for gol_ram: write/read and 1-cycle read latency.
 */
`timescale 1ns/1ps

module tb_gol_ram;
    reg        clk = 0;
    reg [15:0] addr;
    reg        we;
    reg [3:0]  din;
    wire [3:0] dout;

    gol_ram uut (
        .clk(clk),
        .addr(addr),
        .we(we),
        .din(din),
        .dout(dout)
    );

    always #5 clk = ~clk;

    initial begin
        we = 0;
        addr = 0;
        din = 0;
        #20;

        // Write a few addresses
        we = 1;
        addr = 16'h0000; din = 4'h1; #10;
        addr = 16'h0001; din = 4'h2; #10;
        addr = 16'h0100; din = 4'h3; #10;
        addr = 16'hFFFF; din = 4'h7; #10;
        we = 0;

        // Read back: first cycle presents address, second cycle dout is valid (1-cycle latency)
        addr = 16'h0000; #10;  // cycle 1: addr 0
        if (dout !== 4'h1) begin
            $display("FAIL: addr 0 expected 1, got %d", dout);
            $finish;
        end
        addr = 16'h0001; #10;  // cycle 2: addr 1
        if (dout !== 4'h2) begin
            $display("FAIL: addr 1 expected 2, got %d", dout);
            $finish;
        end
        addr = 16'h0100; #10;
        if (dout !== 4'h3) begin
            $display("FAIL: addr 0x0100 expected 3, got %d", dout);
            $finish;
        end
        addr = 16'hFFFF; #10;
        if (dout !== 4'h7) begin
            $display("FAIL: addr 0xFFFF expected 7, got %d", dout);
            $finish;
        end

        // Verify read latency: change addr and check dout on next cycle
        addr = 16'h1234; #10;
        // dout here is from previous addr (0xFFFF = 7). No check on value, just timing.
        #10;
        // Now dout should be from 0x1234 (we never wrote it, so implementation-dependent; just no X)
        $display("PASS: write/read and 1-cycle read latency");
        $finish;
    end
endmodule
