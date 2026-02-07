/**
 * tmds_encoder.v — TMDS 8b/10b encoder for one HDMI/DVI channel.
 * Based on standard TMDS: transition minimized, DC balanced. One channel (R, G, or B).
 */
module tmds_encoder (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  data_in,
    input  wire [1:0]  ctrl_in,
    input  wire        de,
    output reg  [9:0]  tmds
);
    // Count ones in data for encoding choice
    wire [3:0] data_1s = data_in[0] + data_in[1] + data_in[2] + data_in[3] +
                        data_in[4] + data_in[5] + data_in[6] + data_in[7];
    wire use_xnor = (data_1s > 4'd4) || ((data_1s == 4'd4) && (data_in[0] == 0));

    // Encode with xor/xnor
    reg [8:0] enc_qm;
    integer i;
    always @(*) begin
        enc_qm[0] = data_in[0];
        for (i = 0; i < 7; i = i + 1)
            enc_qm[i+1] = use_xnor ? (enc_qm[i] ~^ data_in[i+1]) : (enc_qm[i] ^ data_in[i+1]);
        enc_qm[8] = use_xnor ? 1'b0 : 1'b1;
    end

    // Disparity for DC balancing
    wire [4:0] ones = enc_qm[0] + enc_qm[1] + enc_qm[2] + enc_qm[3] +
                      enc_qm[4] + enc_qm[5] + enc_qm[6] + enc_qm[7];
    wire [4:0] zeros = 5'd8 - ones;
    wire signed [4:0] balance = ones - zeros;

    // Running DC bias (signed)
    reg signed [4:0] bias;

    always @(posedge clk) begin
        if (rst) begin
            tmds <= 10'b1101010100;
            bias <= 5'sd0;
        end else if (!de) begin
            case (ctrl_in)
                2'b00: tmds <= 10'b1101010100;
                2'b01: tmds <= 10'b0010101011;
                2'b10: tmds <= 10'b0101010100;
                default: tmds <= 10'b1010101011;
            endcase
            bias <= 5'sd0;
        end else begin
            if (bias == 0 || balance == 0) begin
                if (enc_qm[8] == 0) begin
                    tmds <= {2'b10, ~enc_qm[7:0]};
                    bias <= bias - balance;
                end else begin
                    tmds <= {2'b01, enc_qm[7:0]};
                    bias <= bias + balance;
                end
            end else if ((bias > 0 && balance > 0) || (bias < 0 && balance < 0)) begin
                tmds <= {1'b1, enc_qm[8], ~enc_qm[7:0]};
                bias <= bias + {3'b0, enc_qm[8], 1'b0} - balance;
            end else begin
                tmds <= {1'b0, enc_qm[8], enc_qm[7:0]};
                bias <= bias - {3'b0, ~enc_qm[8], 1'b0} + balance;
            end
        end
    end
endmodule
