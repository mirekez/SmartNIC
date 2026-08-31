`timescale 1ns/1ps
`default_nettype none

module gt_idle_64b66b_test;
    reg clk = 1'b0;
    reg reset = 1'b1;
    wire [31:0] txdata;
    wire [1:0] txheader;
    wire [6:0] txsequence;
    reg [57:0] decoder_state;
    reg [31:0] decoded_word;
    reg [31:0] previous_txdata;
    reg [57:0] previous_scrambler_state;
    reg active_before;
    reg half_before;
    integer bit_index;

    always #1.5 clk = !clk;

    gt_idle_64b66b dut (
        .clk(clk), .reset(reset), .txdata(txdata),
        .txheader(txheader), .txsequence(txsequence)
    );

    integer word_index;
    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        decoder_state = {58{1'b1}};
        previous_txdata = 32'd0;
        previous_scrambler_state = {58{1'b1}};
        for (word_index = 0; word_index < 100; word_index = word_index + 1) begin
            active_before = dut.sequence_count != 6'd32;
            half_before = dut.data_half;
            #0.1;
            if (txheader !== 2'b01)
                $fatal(1, "bad control header");
            if (active_before) begin
                for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
                    decoded_word[bit_index] = txdata[bit_index] ^
                        decoder_state[38] ^ decoder_state[57];
                    decoder_state = {decoder_state[56:0], 1'b0};
                    decoder_state[0] = txdata[bit_index];
                end
                if (decoded_word !== (half_before ? 32'd0 : 32'h1e))
                    $fatal(1, "bad idle payload cycle=%0d got=%08x",
                           word_index, decoded_word);
            end else begin
                if (txdata !== previous_txdata)
                    $fatal(1, "TXDATA changed during gearbox pause");
                // On the first pause cycle the state reflects the word
                // accepted at the immediately preceding edge.  It must then
                // remain unchanged through the second pause cycle.
                if (half_before &&
                        dut.scrambler_state !== previous_scrambler_state)
                    $fatal(1, "scrambler advanced during gearbox pause");
            end
            previous_txdata = txdata;
            previous_scrambler_state = dut.scrambler_state;
            @(posedge clk);
            #0.1;
            @(negedge clk);
        end
        $display("PASS: GTX gearbox idle source");
        $finish;
    end
endmodule

`default_nettype wire
