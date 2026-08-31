`default_nettype none

import Predef_pkg::*;


module UARTProbe #(
    parameter CLOCK_HZ = 'h2FAF080
,   parameter BAUD = 'h1C200
,   parameter SAMPLE_DIV = 'h1388
,   parameter DEPTH = 'h400
,   parameter SCHEMA = 'h32485445
,   parameter AUTO_DUMP_CYCLES = 'h0
 )
 (
    input wire clk
,   input wire reset
,   input wire uart_rx_in
,   input wire dump_trigger_in
,   output wire uart_tx_out
,   input wire[96-1:0] probe_in
,   output wire dumping_out
);
    localparam  PROBE_BITS = 64'h60;
    localparam  RECORD_BITS = 64'h80;
    localparam  RECORD_BYTES = 64'h10;
    localparam  HEADER_BYTES = 64'h20;
    localparam  TRAILER_BYTES = 64'h8;
    localparam  CLKS_PER_BIT = ((CLOCK_HZ + (BAUD/'h2)))/BAUD;
    localparam  HALF_CLKS = CLKS_PER_BIT/'h2;
    localparam  ADDR_BITS = $clog2(DEPTH);
    localparam  COUNT_BITS = $clog2(DEPTH + 'h1);
    localparam  SAMPLE_COUNTER_BITS = (SAMPLE_DIV<='h1) ? ('h1) : ($clog2(SAMPLE_DIV));
    localparam  BAUD_COUNTER_BITS = $clog2(CLKS_PER_BIT);
    localparam  HEARTBEAT_COUNTER_BITS = $clog2(CLOCK_HZ);
    localparam  HEARTBEAT_BYTES = 64'h12;


    // regs and combs
    reg[32-1:0] timestamp_reg;
    reg[SAMPLE_COUNTER_BITS-1:0] sample_counter_reg;
    reg[ADDR_BITS-1:0] write_addr_reg;
    reg[COUNT_BITS-1:0] sample_count_reg;
    reg capture_full_reg;
    reg[ADDR_BITS-1:0] dump_addr_reg;
    reg[COUNT_BITS-1:0] dump_count_reg;
    reg[COUNT_BITS-1:0] dump_record_reg;
    reg[32-1:0] dump_sequence_reg;
    reg[8-1:0] dump_byte_reg;
    reg[3-1:0] dump_state_reg;
    reg[128-1:0] read_record_reg;
    reg[32-1:0] crc_reg;
    reg rx_sync1_reg;
    reg rx_sync2_reg;
    reg rx_busy_reg;
    reg[BAUD_COUNTER_BITS-1:0] rx_baud_counter_reg;
    reg[4-1:0] rx_bit_reg;
    reg[8-1:0] rx_shift_reg;
    reg[3-1:0] command_state_reg;
    reg trigger_sync1_reg;
    reg trigger_sync2_reg;
    reg trigger_previous_reg;
    reg[3-1:0] trigger_warmup_reg;
    reg[32-1:0] auto_dump_counter_reg;
    reg tx_busy_reg;
    reg[BAUD_COUNTER_BITS-1:0] tx_baud_counter_reg;
    reg[4-1:0] tx_bits_remaining_reg;
    reg[10-1:0] tx_shift_reg;
    reg[HEARTBEAT_COUNTER_BITS-1:0] heartbeat_counter_reg;
    reg[5-1:0] heartbeat_byte_reg;
    reg heartbeat_active_reg;
    logic[128-1:0] sample_comb;
    logic capture_write_comb;
    logic capture_read_comb;
    logic tx_comb;
    logic dumping_comb;

    // members
    wire capture_memory__write_in;
    wire[$clog2(DEPTH)-1:0] capture_memory__write_addr_in;
    wire[RECORD_BITS-1:0] capture_memory__write_data_in;
    wire capture_memory__read_in;
    wire[$clog2(DEPTH)-1:0] capture_memory__read_addr_in;
    wire[RECORD_BITS-1:0] capture_memory__read_data_out;
    UARTProbeMemory #(
        RECORD_BITS
,       DEPTH
    ) capture_memory (
        .clk(clk)
,       .reset(reset)
,       .write_in(capture_memory__write_in)
,       .write_addr_in(capture_memory__write_addr_in)
,       .write_data_in(capture_memory__write_data_in)
,       .read_in(capture_memory__read_in)
,       .read_addr_in(capture_memory__read_addr_in)
,       .read_data_out(capture_memory__read_data_out)
    );

    // tmp variables
    logic[32-1:0] timestamp_reg_tmp;
    logic[SAMPLE_COUNTER_BITS-1:0] sample_counter_reg_tmp;
    logic[ADDR_BITS-1:0] write_addr_reg_tmp;
    logic[COUNT_BITS-1:0] sample_count_reg_tmp;
    logic capture_full_reg_tmp;
    logic[ADDR_BITS-1:0] dump_addr_reg_tmp;
    logic[COUNT_BITS-1:0] dump_count_reg_tmp;
    logic[COUNT_BITS-1:0] dump_record_reg_tmp;
    logic[32-1:0] dump_sequence_reg_tmp;
    logic[8-1:0] dump_byte_reg_tmp;
    logic[3-1:0] dump_state_reg_tmp;
    logic[128-1:0] read_record_reg_tmp;
    logic[32-1:0] crc_reg_tmp;
    logic rx_sync1_reg_tmp;
    logic rx_sync2_reg_tmp;
    logic rx_busy_reg_tmp;
    logic[BAUD_COUNTER_BITS-1:0] rx_baud_counter_reg_tmp;
    logic[4-1:0] rx_bit_reg_tmp;
    logic[8-1:0] rx_shift_reg_tmp;
    logic[3-1:0] command_state_reg_tmp;
    logic trigger_sync1_reg_tmp;
    logic trigger_sync2_reg_tmp;
    logic trigger_previous_reg_tmp;
    logic[3-1:0] trigger_warmup_reg_tmp;
    logic[32-1:0] auto_dump_counter_reg_tmp;
    logic tx_busy_reg_tmp;
    logic[BAUD_COUNTER_BITS-1:0] tx_baud_counter_reg_tmp;
    logic[4-1:0] tx_bits_remaining_reg_tmp;
    logic[10-1:0] tx_shift_reg_tmp;
    logic[HEARTBEAT_COUNTER_BITS-1:0] heartbeat_counter_reg_tmp;
    logic[5-1:0] heartbeat_byte_reg_tmp;
    logic heartbeat_active_reg_tmp;


    always_comb begin : sample_comb_func  // sample_comb_func
        sample_comb = 'h0;
        sample_comb['h0 +:32] = timestamp_reg;
        sample_comb['h20 +:RECORD_BITS - 'h1 - 'h20 + 1] = probe_in;
    end

    always_comb begin : capture_write_comb_func  // capture_write_comb_func
        capture_write_comb=(dump_state_reg == 'h0) && (unsigned'(32'(sample_counter_reg)) == (SAMPLE_DIV - 'h1));
    end

    always_comb begin : capture_read_comb_func  // capture_read_comb_func
        capture_read_comb=dump_state_reg == 'h2;
    end

    always_comb begin : tx_comb_func  // tx_comb_func
        tx_comb=(tx_busy_reg) ? (tx_shift_reg['h0]) : (1);
    end

    always_comb begin : dumping_comb_func  // dumping_comb_func
        dumping_comb=dump_state_reg != 'h0;
    end

    function logic[8-1:0] header_byte (input logic[31:0] index);
        logic[8-1:0] value;
        value = unsigned'(8'h0);
        case (index)
        'h0: begin
            value = unsigned'(8'(85));
        end
        'h1: begin
            value = unsigned'(8'(80));
        end
        'h2: begin
            value = unsigned'(8'(82));
        end
        'h3: begin
            value = unsigned'(8'(66));
        end
        'h4: begin
            value = unsigned'(8'h1);
        end
        'h5: begin
            value = unsigned'(8'(HEADER_BYTES));
        end
        'h6: begin
            value = unsigned'(8'(RECORD_BYTES));
        end
        'h7: begin
            value = unsigned'(8'h3);
        end
        'h8: begin
            value = unsigned'(8'(unsigned'(8'(unsigned'(32'(dump_count_reg))))));
        end
        'h9: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(dump_count_reg)) >>> 'h8)))));
        end
        'hA: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(dump_count_reg)) >>> 'h10)))));
        end
        'hB: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(dump_count_reg)) >>> 'h18)))));
        end
        'hC: begin
            value = unsigned'(8'(unsigned'(8'(SAMPLE_DIV))));
        end
        'hD: begin
            value = unsigned'(8'(unsigned'(8'((SAMPLE_DIV >>> 'h8)))));
        end
        'hE: begin
            value = unsigned'(8'(unsigned'(8'((SAMPLE_DIV >>> 'h10)))));
        end
        'hF: begin
            value = unsigned'(8'(unsigned'(8'((SAMPLE_DIV >>> 'h18)))));
        end
        'h10: begin
            value = unsigned'(8'(unsigned'(8'(CLOCK_HZ))));
        end
        'h11: begin
            value = unsigned'(8'(unsigned'(8'((CLOCK_HZ >>> 'h8)))));
        end
        'h12: begin
            value = unsigned'(8'(unsigned'(8'((CLOCK_HZ >>> 'h10)))));
        end
        'h13: begin
            value = unsigned'(8'(unsigned'(8'((CLOCK_HZ >>> 'h18)))));
        end
        'h14: begin
            value = unsigned'(8'(unsigned'(8'(unsigned'(32'(dump_sequence_reg))))));
        end
        'h15: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(dump_sequence_reg)) >>> 'h8)))));
        end
        'h16: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(dump_sequence_reg)) >>> 'h10)))));
        end
        'h17: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(dump_sequence_reg)) >>> 'h18)))));
        end
        'h18: begin
            value = unsigned'(8'(unsigned'(8'(DEPTH))));
        end
        'h19: begin
            value = unsigned'(8'(unsigned'(8'((DEPTH >>> 'h8)))));
        end
        'h1A: begin
            value = unsigned'(8'(unsigned'(8'((DEPTH >>> 'h10)))));
        end
        'h1B: begin
            value = unsigned'(8'(unsigned'(8'((DEPTH >>> 'h18)))));
        end
        'h1C: begin
            value = unsigned'(8'(unsigned'(8'(SCHEMA))));
        end
        'h1D: begin
            value = unsigned'(8'(unsigned'(8'((SCHEMA >>> 'h8)))));
        end
        'h1E: begin
            value = unsigned'(8'(unsigned'(8'((SCHEMA >>> 'h10)))));
        end
        'h1F: begin
            value = unsigned'(8'(unsigned'(8'((SCHEMA >>> 'h18)))));
        end
        default: begin
            value = unsigned'(8'h0);
        end
        endcase
        return unsigned'(8'(value));
    endfunction

    function logic[8-1:0] record_byte (
        input logic[128-1:0] record
,       input logic[31:0] index
    );
        logic[8-1:0] value;
        logic[31:0] byte_index;
        value = unsigned'(8'h0);
        for (byte_index='h0;byte_index < RECORD_BYTES;byte_index=byte_index+1) begin
            if (index == byte_index) begin
                value = unsigned'(8'(unsigned'(8'(record[byte_index*'h8 +:8]))));
            end
        end
        return unsigned'(8'(value));
    endfunction

    function logic[32-1:0] crc32_byte (
        input logic[32-1:0] crc
,       input logic[8-1:0] data
    );
        logic[32-1:0] value;
        logic[31:0] bit_index;
        value = crc;
        for (bit_index='h0;bit_index < 'h8;bit_index=bit_index+1) begin
            logic mix; mix = value['h0] ^ data[bit_index];
            value = value >> 'h1;
            if (mix) begin
                value = value ^ 'hEDB88320;
            end
        end
        return value;
    endfunction

    function logic[8-1:0] trailer_byte (input logic[31:0] index);
        logic[8-1:0] value;
        logic[32-1:0] final_crc;
        value = unsigned'(8'h0);
        final_crc = crc_reg ^ 'hFFFFFFFF;
        case (index)
        'h0: begin
            value = unsigned'(8'(69));
        end
        'h1: begin
            value = unsigned'(8'(78));
        end
        'h2: begin
            value = unsigned'(8'(68));
        end
        'h3: begin
            value = unsigned'(8'(33));
        end
        'h4: begin
            value = unsigned'(8'(unsigned'(8'(unsigned'(32'(final_crc))))));
        end
        'h5: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(final_crc)) >>> 'h8)))));
        end
        'h6: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(final_crc)) >>> 'h10)))));
        end
        'h7: begin
            value = unsigned'(8'(unsigned'(8'((unsigned'(32'(final_crc)) >>> 'h18)))));
        end
        default: begin
            value = unsigned'(8'h0);
        end
        endcase
        return unsigned'(8'(value));
    endfunction

    function logic[8-1:0] heartbeat_byte (input logic[31:0] index);
        logic[8-1:0] value;
        value = unsigned'(8'h0);
        case (index)
        'h0: begin
            value = unsigned'(8'(85));
        end
        'h1: begin
            value = unsigned'(8'(65));
        end
        'h2: begin
            value = unsigned'(8'(82));
        end
        'h3: begin
            value = unsigned'(8'(84));
        end
        'h4: begin
            value = unsigned'(8'(95));
        end
        'h5: begin
            value = unsigned'(8'(80));
        end
        'h6: begin
            value = unsigned'(8'(82));
        end
        'h7: begin
            value = unsigned'(8'(79));
        end
        'h8: begin
            value = unsigned'(8'(66));
        end
        'h9: begin
            value = unsigned'(8'(69));
        end
        'hA: begin
            value = unsigned'(8'(95));
        end
        'hB: begin
            value = unsigned'(8'(82));
        end
        'hC: begin
            value = unsigned'(8'(69));
        end
        'hD: begin
            value = unsigned'(8'(65));
        end
        'hE: begin
            value = unsigned'(8'(68));
        end
        'hF: begin
            value = unsigned'(8'(89));
        end
        'h10: begin
            value = unsigned'(8'(13));
        end
        'h11: begin
            value = unsigned'(8'(10));
        end
        default: begin
            value = unsigned'(8'h0);
        end
        endcase
        return unsigned'(8'(value));
    endfunction

    generate  // _assign
        assign capture_memory__write_in = capture_write_comb;
        assign capture_memory__write_addr_in = write_addr_reg;
        assign capture_memory__write_data_in = sample_comb;
        assign capture_memory__read_in = capture_read_comb;
        assign capture_memory__read_addr_in = dump_addr_reg;
        assign uart_tx_out = tx_comb;
        assign dumping_out = dumping_comb;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic received_valid;
        logic start_dump;
        logic[8-1:0] received_byte;
        logic[8-1:0] send_byte;
        logic[10-1:0] new_shift;
        logic[31:0] bit_index;
        received_valid = 0;
        start_dump = 0;
        received_byte = unsigned'(8'h0);
        send_byte = unsigned'(8'h0);
        new_shift = 'h3FF;
        if (reset) begin
            timestamp_reg_tmp = '0;
            sample_counter_reg_tmp = '0;
            write_addr_reg_tmp = '0;
            sample_count_reg_tmp = '0;
            capture_full_reg_tmp = '0;
            dump_addr_reg_tmp = '0;
            dump_count_reg_tmp = '0;
            dump_record_reg_tmp = '0;
            dump_sequence_reg_tmp = '0;
            dump_byte_reg_tmp = '0;
            dump_state_reg_tmp = '0;
            read_record_reg_tmp = '0;
            crc_reg_tmp = 'hFFFFFFFF;
            rx_sync1_reg_tmp = unsigned'(1'h1);
            rx_sync2_reg_tmp = unsigned'(1'h1);
            rx_busy_reg_tmp = '0;
            rx_baud_counter_reg_tmp = '0;
            rx_bit_reg_tmp = '0;
            rx_shift_reg_tmp = '0;
            command_state_reg_tmp = '0;
            trigger_sync1_reg_tmp = '0;
            trigger_sync2_reg_tmp = '0;
            trigger_previous_reg_tmp = '0;
            trigger_warmup_reg_tmp = '0;
            auto_dump_counter_reg_tmp = '0;
            tx_busy_reg_tmp = '0;
            tx_baud_counter_reg_tmp = '0;
            tx_bits_remaining_reg_tmp = '0;
            tx_shift_reg_tmp = 'h3FF;
            heartbeat_counter_reg_tmp = '0;
            heartbeat_byte_reg_tmp = '0;
            heartbeat_active_reg_tmp = unsigned'(1'h1);
            disable _work;
        end
        timestamp_reg_tmp = unsigned'(32'(timestamp_reg + 'h1));
        rx_sync1_reg_tmp = unsigned'(1'(uart_rx_in));
        rx_sync2_reg_tmp = rx_sync1_reg;
        trigger_sync1_reg_tmp = unsigned'(1'(dump_trigger_in));
        trigger_sync2_reg_tmp = trigger_sync1_reg;
        if (trigger_warmup_reg != 'h7) begin
            trigger_warmup_reg_tmp = trigger_warmup_reg + 'h1;
            trigger_previous_reg_tmp = trigger_sync2_reg;
        end
        else begin
            if (trigger_sync2_reg != trigger_previous_reg) begin
                start_dump=1;
            end
            trigger_previous_reg_tmp = trigger_sync2_reg;
        end
        if (((AUTO_DUMP_CYCLES != 'h0) && (dump_state_reg == 'h0)) && capture_full_reg) begin
            if (unsigned'(32'(auto_dump_counter_reg)) == (AUTO_DUMP_CYCLES - 'h1)) begin
                auto_dump_counter_reg_tmp = '0;
                start_dump=1;
            end
            else begin
                auto_dump_counter_reg_tmp = unsigned'(32'(auto_dump_counter_reg + 'h1));
            end
        end
        if ((dump_state_reg == 'h0) && !heartbeat_active_reg) begin
            if (unsigned'(32'(heartbeat_counter_reg)) == (CLOCK_HZ - 'h1)) begin
                heartbeat_counter_reg_tmp = '0;
                heartbeat_byte_reg_tmp = '0;
                heartbeat_active_reg_tmp = unsigned'(1'h1);
            end
            else begin
                heartbeat_counter_reg_tmp = heartbeat_counter_reg + 'h1;
            end
        end
        if (dump_state_reg == 'h0) begin
            if (unsigned'(32'(sample_counter_reg)) == (SAMPLE_DIV - 'h1)) begin
                sample_counter_reg_tmp = '0;
                write_addr_reg_tmp = write_addr_reg + 'h1;
                if (unsigned'(32'(sample_count_reg)) < DEPTH) begin
                    sample_count_reg_tmp = sample_count_reg + 'h1;
                end
                if (unsigned'(32'(sample_count_reg)) == (DEPTH - 'h1)) begin
                    capture_full_reg_tmp = unsigned'(1'h1);
                end
            end
            else begin
                sample_counter_reg_tmp = sample_counter_reg + 'h1;
            end
        end
        if (!rx_busy_reg) begin
            if (!rx_sync2_reg) begin
                rx_busy_reg_tmp = unsigned'(1'h1);
                rx_baud_counter_reg_tmp = HALF_CLKS - 'h1;
                rx_bit_reg_tmp = '0;
            end
        end
        else begin
            if (rx_baud_counter_reg != 'h0) begin
                rx_baud_counter_reg_tmp = rx_baud_counter_reg - 'h1;
            end
            else begin
                if (rx_bit_reg == 'h0) begin
                    if (rx_sync2_reg) begin
                        rx_busy_reg_tmp = '0;
                    end
                    else begin
                        rx_bit_reg_tmp = 'h1;
                        rx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                    end
                end
                else begin
                    if (rx_bit_reg<='h8) begin
                        for (bit_index='h0;bit_index < 'h8;bit_index=bit_index+1) begin
                            if (unsigned'(32'(rx_bit_reg)) == (bit_index + 'h1)) begin
                                rx_shift_reg_tmp[bit_index] = rx_sync2_reg;
                            end
                        end
                        rx_bit_reg_tmp = rx_bit_reg + 'h1;
                        rx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                    end
                    else begin
                        if (rx_sync2_reg) begin
                            received_valid=1;
                            received_byte = rx_shift_reg;
                        end
                        rx_busy_reg_tmp = '0;
                    end
                end
            end
        end
        if (received_valid) begin
            if (dump_state_reg != 'h0) begin
                command_state_reg_tmp = '0;
            end
            else begin
                if ((command_state_reg == 'h0) && (received_byte == 68)) begin
                    command_state_reg_tmp = 'h1;
                end
                else begin
                    if ((command_state_reg == 'h1) && (received_byte == 85)) begin
                        command_state_reg_tmp = 'h2;
                    end
                    else begin
                        if ((command_state_reg == 'h2) && (received_byte == 77)) begin
                            command_state_reg_tmp = 'h3;
                        end
                        else begin
                            if ((command_state_reg == 'h3) && (received_byte == 80)) begin
                                command_state_reg_tmp = '0;
                                start_dump=1;
                            end
                            else begin
                                command_state_reg_tmp = (received_byte == 68) ? ('h1) : ('h0);
                            end
                        end
                    end
                end
            end
        end
        if (start_dump && (dump_state_reg == 'h0)) begin
            auto_dump_counter_reg_tmp = '0;
            dump_count_reg_tmp = sample_count_reg;
            dump_record_reg_tmp = '0;
            dump_byte_reg_tmp = '0;
            dump_addr_reg_tmp = (capture_full_reg) ? ((((unsigned'(32'(sample_counter_reg)) == (SAMPLE_DIV - 'h1))) ? (write_addr_reg + 'h1) : (write_addr_reg))) : ('h0);
            crc_reg_tmp = 'hFFFFFFFF;
            dump_state_reg_tmp = 'h1;
            heartbeat_counter_reg_tmp = '0;
            heartbeat_byte_reg_tmp = '0;
            heartbeat_active_reg_tmp = '0;
        end
        if (tx_busy_reg) begin
            if (tx_baud_counter_reg != 'h0) begin
                tx_baud_counter_reg_tmp = tx_baud_counter_reg - 'h1;
            end
            else begin
                if (tx_bits_remaining_reg == 'h1) begin
                    tx_busy_reg_tmp = '0;
                    tx_bits_remaining_reg_tmp = '0;
                    tx_shift_reg_tmp = 'h3FF;
                end
                else begin
                    tx_shift_reg_tmp = tx_shift_reg >> 'h1;
                    tx_shift_reg_tmp['h9] = 'h1;
                    tx_bits_remaining_reg_tmp = tx_bits_remaining_reg - 'h1;
                    tx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                end
            end
        end
        else begin
            if (dump_state_reg == 'h1) begin
                send_byte = header_byte(dump_byte_reg);
                new_shift = 'h0;
                new_shift['h0] = 'h0;
                for (bit_index='h0;bit_index < 'h8;bit_index=bit_index+1) begin
                    new_shift[bit_index + 'h1] = send_byte[bit_index];
                end
                new_shift['h9] = 'h1;
                tx_shift_reg_tmp = new_shift;
                tx_busy_reg_tmp = unsigned'(1'h1);
                tx_bits_remaining_reg_tmp = 'hA;
                tx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                if (unsigned'(32'(dump_byte_reg)) == (HEADER_BYTES - 'h1)) begin
                    dump_byte_reg_tmp = '0;
                    dump_state_reg_tmp = (dump_count_reg == 'h0) ? ('h4) : ('h2);
                end
                else begin
                    dump_byte_reg_tmp = unsigned'(8'(dump_byte_reg + 'h1));
                end
            end
            else begin
                if (dump_state_reg == 'h2) begin
                    dump_state_reg_tmp = 'h5;
                end
                else begin
                    if (dump_state_reg == 'h5) begin
                        read_record_reg_tmp = capture_memory__read_data_out;
                        dump_byte_reg_tmp = '0;
                        dump_state_reg_tmp = 'h3;
                    end
                    else begin
                        if (dump_state_reg == 'h3) begin
                            send_byte = record_byte(read_record_reg, dump_byte_reg);
                            new_shift = 'h0;
                            new_shift['h0] = 'h0;
                            for (bit_index='h0;bit_index < 'h8;bit_index=bit_index+1) begin
                                new_shift[bit_index + 'h1] = send_byte[bit_index];
                            end
                            new_shift['h9] = 'h1;
                            tx_shift_reg_tmp = new_shift;
                            tx_busy_reg_tmp = unsigned'(1'h1);
                            tx_bits_remaining_reg_tmp = 'hA;
                            tx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                            crc_reg_tmp = crc32_byte(crc_reg, unsigned'(8'(send_byte)));
                            if (unsigned'(32'(dump_byte_reg)) == (RECORD_BYTES - 'h1)) begin
                                dump_byte_reg_tmp = '0;
                                dump_addr_reg_tmp = dump_addr_reg + 'h1;
                                dump_record_reg_tmp = dump_record_reg + 'h1;
                                dump_state_reg_tmp = (((unsigned'(32'(dump_record_reg)) + 'h1) == unsigned'(32'(dump_count_reg)))) ? ('h4) : ('h2);
                            end
                            else begin
                                dump_byte_reg_tmp = unsigned'(8'(dump_byte_reg + 'h1));
                            end
                        end
                        else begin
                            if (dump_state_reg == 'h4) begin
                                send_byte = trailer_byte(dump_byte_reg);
                                new_shift = 'h0;
                                new_shift['h0] = 'h0;
                                for (bit_index='h0;bit_index < 'h8;bit_index=bit_index+1) begin
                                    new_shift[bit_index + 'h1] = send_byte[bit_index];
                                end
                                new_shift['h9] = 'h1;
                                tx_shift_reg_tmp = new_shift;
                                tx_busy_reg_tmp = unsigned'(1'h1);
                                tx_bits_remaining_reg_tmp = 'hA;
                                tx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                                if (unsigned'(32'(dump_byte_reg)) == (TRAILER_BYTES - 'h1)) begin
                                    dump_byte_reg_tmp = '0;
                                    dump_state_reg_tmp = '0;
                                    dump_sequence_reg_tmp = unsigned'(32'(dump_sequence_reg + 'h1));
                                    sample_counter_reg_tmp = '0;
                                    write_addr_reg_tmp = '0;
                                    sample_count_reg_tmp = '0;
                                    capture_full_reg_tmp = '0;
                                end
                                else begin
                                    dump_byte_reg_tmp = unsigned'(8'(dump_byte_reg + 'h1));
                                end
                            end
                            else begin
                                if (heartbeat_active_reg) begin
                                    send_byte = heartbeat_byte(heartbeat_byte_reg);
                                    new_shift = 'h0;
                                    new_shift['h0] = 'h0;
                                    for (bit_index='h0;bit_index < 'h8;bit_index=bit_index+1) begin
                                        new_shift[bit_index + 'h1] = send_byte[bit_index];
                                    end
                                    new_shift['h9] = 'h1;
                                    tx_shift_reg_tmp = new_shift;
                                    tx_busy_reg_tmp = unsigned'(1'h1);
                                    tx_bits_remaining_reg_tmp = 'hA;
                                    tx_baud_counter_reg_tmp = CLKS_PER_BIT - 'h1;
                                    if (unsigned'(32'(heartbeat_byte_reg)) == (HEARTBEAT_BYTES - 'h1)) begin
                                        heartbeat_byte_reg_tmp = '0;
                                        heartbeat_active_reg_tmp = '0;
                                        heartbeat_counter_reg_tmp = '0;
                                    end
                                    else begin
                                        heartbeat_byte_reg_tmp = heartbeat_byte_reg + 'h1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    endtask

    always @(posedge clk) begin
        timestamp_reg_tmp = timestamp_reg;
        sample_counter_reg_tmp = sample_counter_reg;
        write_addr_reg_tmp = write_addr_reg;
        sample_count_reg_tmp = sample_count_reg;
        capture_full_reg_tmp = capture_full_reg;
        dump_addr_reg_tmp = dump_addr_reg;
        dump_count_reg_tmp = dump_count_reg;
        dump_record_reg_tmp = dump_record_reg;
        dump_sequence_reg_tmp = dump_sequence_reg;
        dump_byte_reg_tmp = dump_byte_reg;
        dump_state_reg_tmp = dump_state_reg;
        read_record_reg_tmp = read_record_reg;
        crc_reg_tmp = crc_reg;
        rx_sync1_reg_tmp = rx_sync1_reg;
        rx_sync2_reg_tmp = rx_sync2_reg;
        rx_busy_reg_tmp = rx_busy_reg;
        rx_baud_counter_reg_tmp = rx_baud_counter_reg;
        rx_bit_reg_tmp = rx_bit_reg;
        rx_shift_reg_tmp = rx_shift_reg;
        command_state_reg_tmp = command_state_reg;
        trigger_sync1_reg_tmp = trigger_sync1_reg;
        trigger_sync2_reg_tmp = trigger_sync2_reg;
        trigger_previous_reg_tmp = trigger_previous_reg;
        trigger_warmup_reg_tmp = trigger_warmup_reg;
        auto_dump_counter_reg_tmp = auto_dump_counter_reg;
        tx_busy_reg_tmp = tx_busy_reg;
        tx_baud_counter_reg_tmp = tx_baud_counter_reg;
        tx_bits_remaining_reg_tmp = tx_bits_remaining_reg;
        tx_shift_reg_tmp = tx_shift_reg;
        heartbeat_counter_reg_tmp = heartbeat_counter_reg;
        heartbeat_byte_reg_tmp = heartbeat_byte_reg;
        heartbeat_active_reg_tmp = heartbeat_active_reg;

        _work(reset);

        timestamp_reg <= timestamp_reg_tmp;
        sample_counter_reg <= sample_counter_reg_tmp;
        write_addr_reg <= write_addr_reg_tmp;
        sample_count_reg <= sample_count_reg_tmp;
        capture_full_reg <= capture_full_reg_tmp;
        dump_addr_reg <= dump_addr_reg_tmp;
        dump_count_reg <= dump_count_reg_tmp;
        dump_record_reg <= dump_record_reg_tmp;
        dump_sequence_reg <= dump_sequence_reg_tmp;
        dump_byte_reg <= dump_byte_reg_tmp;
        dump_state_reg <= dump_state_reg_tmp;
        read_record_reg <= read_record_reg_tmp;
        crc_reg <= crc_reg_tmp;
        rx_sync1_reg <= rx_sync1_reg_tmp;
        rx_sync2_reg <= rx_sync2_reg_tmp;
        rx_busy_reg <= rx_busy_reg_tmp;
        rx_baud_counter_reg <= rx_baud_counter_reg_tmp;
        rx_bit_reg <= rx_bit_reg_tmp;
        rx_shift_reg <= rx_shift_reg_tmp;
        command_state_reg <= command_state_reg_tmp;
        trigger_sync1_reg <= trigger_sync1_reg_tmp;
        trigger_sync2_reg <= trigger_sync2_reg_tmp;
        trigger_previous_reg <= trigger_previous_reg_tmp;
        trigger_warmup_reg <= trigger_warmup_reg_tmp;
        auto_dump_counter_reg <= auto_dump_counter_reg_tmp;
        tx_busy_reg <= tx_busy_reg_tmp;
        tx_baud_counter_reg <= tx_baud_counter_reg_tmp;
        tx_bits_remaining_reg <= tx_bits_remaining_reg_tmp;
        tx_shift_reg <= tx_shift_reg_tmp;
        heartbeat_counter_reg <= heartbeat_counter_reg_tmp;
        heartbeat_byte_reg <= heartbeat_byte_reg_tmp;
        heartbeat_active_reg <= heartbeat_active_reg_tmp;
    end


endmodule
