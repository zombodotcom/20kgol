/**
 * tb_gol_engine.v — Testbench for gol_engine: init writes both banks, SOF swap, no write to display bank.
 * Runs init (2*65536 cycles), then pulses video_sof and checks ram_select toggles; samples RAM.
 */
`timescale 1ns/1ps

module tb_gol_engine;
    reg        clk = 0;
    reg        rst = 1;
    reg        video_sof = 0;
    wire       ram_select;
    wire       init_done;
    wire [15:0] addr;
    wire        we0, we1;
    wire [3:0]  din;
    wire [3:0]  dout0, dout1;

    gol_engine uut (
        .clk(clk),
        .rst(rst),
        .video_sof(video_sof),
        .dout_bank0(dout0),
        .dout_bank1(dout1),
        .ram_select(ram_select),
        .init_done(init_done),
        .addr(addr),
        .we0(we0),
        .we1(we1),
        .din(din)
    );

    wire [15:0] addr0 = addr;
    wire [15:0] addr1 = addr;
    gol_ram bank0 (.clk(clk), .addr(addr0), .we(we0), .din(din), .dout(dout0));
    gol_ram bank1 (.clk(clk), .addr(addr1), .we(we1), .din(din), .dout(dout1));

    always #5 clk = ~clk;

    integer cycle;
    initial begin
        cycle = 0;
        rst = 1;
        #100;
        rst = 0;
        // Run past init: 2*65536 = 131072 cycles (two phases per address)
        while (cycle < 131100) begin
            @(posedge clk);
            cycle = cycle + 1;
        end
        // Now engine should be in IDLE, ram_select still 0, init_done high
        if (ram_select !== 0) begin
            $display("FAIL: after init ram_select should be 0, got %b", ram_select);
            $finish;
        end
        if (init_done !== 1) begin
            $display("FAIL: after init init_done should be 1, got %b", init_done);
            $finish;
        end
        // Pulse SOF
        @(posedge clk);
        video_sof = 1;
        @(posedge clk);
        video_sof = 0;
        @(posedge clk);
        // After SOF engine starts; ram_select flips when SOF is seen (next cycle)
        repeat (20) @(posedge clk);
        // ram_select should have flipped to 1 (display was 0, now display is 1)
        if (ram_select !== 1) begin
            $display("FAIL: after first SOF ram_select should be 1, got %b", ram_select);
            $finish;
        end
        // Run many cycles (one frame is 65536*(1+8+1+1) = 720896 min), then SOF again
        for (cycle = 0; cycle < 720900; cycle = cycle + 1)
            @(posedge clk);
        @(posedge clk);
        video_sof = 1;
        @(posedge clk);
        video_sof = 0;
        repeat (20) @(posedge clk);
        // ram_select should flip back to 0
        if (ram_select !== 0) begin
            $display("FAIL: after second SOF ram_select should be 0, got %b", ram_select);
            $finish;
        end
        $display("PASS: init and SOF swap");
        $finish;
    end
endmodule
