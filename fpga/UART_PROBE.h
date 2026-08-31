#pragma once

// Command-driven UART replacement for a small logic analyzer.  The module is
// intentionally implemented in CppHDL: its generated SystemVerilog is used by
// the FPGA build, while the same state machine can be exercised by native and
// Verilator tests.

#include <cpphdl.h>
#include "UARTProbeMemory.h"

using namespace cpphdl;

template<size_t CLOCK_HZ = 50'000'000, size_t BAUD = 115'200,
    size_t SAMPLE_DIV = 5'000, size_t DEPTH = 1'024,
    size_t SCHEMA = 0x32485445, size_t AUTO_DUMP_CYCLES = 0>
class UARTProbe : public Module
{
public:
    static constexpr size_t PROBE_BITS = 96;
    static constexpr size_t RECORD_BITS = 128;
    static constexpr size_t RECORD_BYTES = RECORD_BITS / 8;
    static constexpr size_t HEADER_BYTES = 32;
    static constexpr size_t TRAILER_BYTES = 8;
    static constexpr size_t CLKS_PER_BIT = (CLOCK_HZ + BAUD / 2) / BAUD;
    static constexpr size_t HALF_CLKS = CLKS_PER_BIT / 2;
    static constexpr size_t ADDR_BITS = clog2(DEPTH);
    static constexpr size_t COUNT_BITS = clog2(DEPTH + 1);
    static constexpr size_t SAMPLE_COUNTER_BITS =
        SAMPLE_DIV <= 1 ? 1 : clog2(SAMPLE_DIV);
    static constexpr size_t BAUD_COUNTER_BITS = clog2(CLKS_PER_BIT);
    static constexpr size_t HEARTBEAT_COUNTER_BITS = clog2(CLOCK_HZ);
    static constexpr size_t HEARTBEAT_BYTES = 18;

    static_assert(CLOCK_HZ > BAUD * 8,
        "UARTProbe requires at least eight clocks per UART bit");
    static_assert(SAMPLE_DIV > 0, "UARTProbe SAMPLE_DIV must be nonzero");
    static_assert(DEPTH > 1 && (DEPTH & (DEPTH - 1)) == 0,
        "UARTProbe DEPTH must be a power of two");

    _PORT(bool) uart_rx_in;
    // Independent out-of-band capture trigger, normally driven by the USB
    // UART RTS output. Any transition after synchronization starts a dump.
    _PORT(bool) dump_trigger_in;
    _PORT(bool) uart_tx_out;
    // Bytes 4..31 of each record. Bytes 0..3 are the local timestamp.
    _PORT(logic<PROBE_BITS>) probe_in;
    _PORT(bool) dumping_out;

private:
    UARTProbeMemory<RECORD_BITS, DEPTH> capture_memory;

    reg<u32> timestamp_reg;
    reg<u<SAMPLE_COUNTER_BITS>> sample_counter_reg;
    reg<u<ADDR_BITS>> write_addr_reg;
    reg<u<COUNT_BITS>> sample_count_reg;
    reg<u1> capture_full_reg;

    reg<u<ADDR_BITS>> dump_addr_reg;
    reg<u<COUNT_BITS>> dump_count_reg;
    reg<u<COUNT_BITS>> dump_record_reg;
    reg<u32> dump_sequence_reg;
    reg<u8> dump_byte_reg;
    // 0 idle, 1 header, 2 RAM read, 3 record, 4 trailer.
    reg<u<3>> dump_state_reg;
    reg<logic<RECORD_BITS>> read_record_reg;
    reg<logic<32>> crc_reg;

    reg<u1> rx_sync1_reg;
    reg<u1> rx_sync2_reg;
    reg<u1> rx_busy_reg;
    reg<u<BAUD_COUNTER_BITS>> rx_baud_counter_reg;
    reg<u<4>> rx_bit_reg;
    reg<u8> rx_shift_reg;
    reg<u<3>> command_state_reg;
    reg<u1> trigger_sync1_reg;
    reg<u1> trigger_sync2_reg;
    reg<u1> trigger_previous_reg;
    reg<u<3>> trigger_warmup_reg;
    reg<u32> auto_dump_counter_reg;

    reg<u1> tx_busy_reg;
    reg<u<BAUD_COUNTER_BITS>> tx_baud_counter_reg;
    reg<u<4>> tx_bits_remaining_reg;
    reg<logic<10>> tx_shift_reg;
    reg<u<HEARTBEAT_COUNTER_BITS>> heartbeat_counter_reg;
    reg<u<5>> heartbeat_byte_reg;
    reg<u1> heartbeat_active_reg;

    logic<RECORD_BITS> sample_comb;
    logic<RECORD_BITS>& sample_comb_func()
    {
        sample_comb = 0;
        sample_comb.bits(31, 0) = timestamp_reg;
        sample_comb.bits(RECORD_BITS - 1, 32) = probe_in();
        return sample_comb;
    }

    bool capture_write_comb;
    bool& capture_write_comb_func()
    {
        capture_write_comb = dump_state_reg == 0
            && (uint32_t)sample_counter_reg == SAMPLE_DIV - 1;
        return capture_write_comb;
    }

    bool capture_read_comb;
    bool& capture_read_comb_func()
    {
        capture_read_comb = dump_state_reg == 2;
        return capture_read_comb;
    }

    bool tx_comb;
    bool& tx_comb_func()
    {
        tx_comb = tx_busy_reg ? (bool)tx_shift_reg[0] : true;
        return tx_comb;
    }

    bool dumping_comb;
    bool& dumping_comb_func()
    {
        dumping_comb = dump_state_reg != 0;
        return dumping_comb;
    }

    u8 header_byte(uint32_t index)
    {
        u8 value = 0;
        switch (index) {
        case 0: value = 'U'; break;
        case 1: value = 'P'; break;
        case 2: value = 'R'; break;
        case 3: value = 'B'; break;
        case 4: value = 1; break; // protocol version
        case 5: value = HEADER_BYTES; break;
        case 6: value = RECORD_BYTES; break;
        case 7: value = 3; break; // chronological records + CRC32 trailer
        case 8: value = (uint8_t)(uint32_t)dump_count_reg; break;
        case 9: value = (uint8_t)((uint32_t)dump_count_reg >> 8); break;
        case 10: value = (uint8_t)((uint32_t)dump_count_reg >> 16); break;
        case 11: value = (uint8_t)((uint32_t)dump_count_reg >> 24); break;
        case 12: value = (uint8_t)SAMPLE_DIV; break;
        case 13: value = (uint8_t)(SAMPLE_DIV >> 8); break;
        case 14: value = (uint8_t)(SAMPLE_DIV >> 16); break;
        case 15: value = (uint8_t)(SAMPLE_DIV >> 24); break;
        case 16: value = (uint8_t)CLOCK_HZ; break;
        case 17: value = (uint8_t)(CLOCK_HZ >> 8); break;
        case 18: value = (uint8_t)(CLOCK_HZ >> 16); break;
        case 19: value = (uint8_t)(CLOCK_HZ >> 24); break;
        case 20: value = (uint8_t)(uint32_t)dump_sequence_reg; break;
        case 21: value = (uint8_t)((uint32_t)dump_sequence_reg >> 8); break;
        case 22: value = (uint8_t)((uint32_t)dump_sequence_reg >> 16); break;
        case 23: value = (uint8_t)((uint32_t)dump_sequence_reg >> 24); break;
        case 24: value = (uint8_t)DEPTH; break;
        case 25: value = (uint8_t)(DEPTH >> 8); break;
        case 26: value = (uint8_t)(DEPTH >> 16); break;
        case 27: value = (uint8_t)(DEPTH >> 24); break;
        case 28: value = (uint8_t)SCHEMA; break;
        case 29: value = (uint8_t)(SCHEMA >> 8); break;
        case 30: value = (uint8_t)(SCHEMA >> 16); break;
        case 31: value = (uint8_t)(SCHEMA >> 24); break;
        default: value = 0; break;
        }
        return value;
    }

    u8 record_byte(logic<RECORD_BITS> record, uint32_t index)
    {
        u8 value = 0;
        uint32_t byte_index;
        for (byte_index = 0; byte_index < RECORD_BYTES; ++byte_index) {
            if (index == byte_index) {
                value = (uint8_t)record.bits(
                    byte_index * 8 + 7, byte_index * 8);
            }
        }
        return value;
    }

    logic<32> crc32_byte(logic<32> crc, u8 data)
    {
        logic<32> value = crc;
        uint32_t bit_index;
        for (bit_index = 0; bit_index < 8; ++bit_index) {
            bool mix = (bool)value[0] ^ (bool)data[bit_index];
            value = value >> 1;
            if (mix) {
                value = value ^ 0xedb88320U;
            }
        }
        return value;
    }

    u8 trailer_byte(uint32_t index)
    {
        u8 value = 0;
        logic<32> final_crc = crc_reg ^ 0xffffffffU;
        switch (index) {
        case 0: value = 'E'; break;
        case 1: value = 'N'; break;
        case 2: value = 'D'; break;
        case 3: value = '!'; break;
        case 4: value = (uint8_t)(uint32_t)final_crc; break;
        case 5: value = (uint8_t)((uint32_t)final_crc >> 8); break;
        case 6: value = (uint8_t)((uint32_t)final_crc >> 16); break;
        case 7: value = (uint8_t)((uint32_t)final_crc >> 24); break;
        default: value = 0; break;
        }
        return value;
    }

    u8 heartbeat_byte(uint32_t index)
    {
        u8 value = 0;
        switch (index) {
        case 0: value = 'U'; break;
        case 1: value = 'A'; break;
        case 2: value = 'R'; break;
        case 3: value = 'T'; break;
        case 4: value = '_'; break;
        case 5: value = 'P'; break;
        case 6: value = 'R'; break;
        case 7: value = 'O'; break;
        case 8: value = 'B'; break;
        case 9: value = 'E'; break;
        case 10: value = '_'; break;
        case 11: value = 'R'; break;
        case 12: value = 'E'; break;
        case 13: value = 'A'; break;
        case 14: value = 'D'; break;
        case 15: value = 'Y'; break;
        case 16: value = '\r'; break;
        case 17: value = '\n'; break;
        default: value = 0; break;
        }
        return value;
    }

public:
    void _assign()
    {
        capture_memory.write_in = _ASSIGN_COMB(capture_write_comb_func());
        capture_memory.write_addr_in = _ASSIGN_REG(write_addr_reg);
        capture_memory.write_data_in = _ASSIGN_COMB(sample_comb_func());
        capture_memory.read_in = _ASSIGN_COMB(capture_read_comb_func());
        capture_memory.read_addr_in = _ASSIGN_REG(dump_addr_reg);
        capture_memory.__inst_name = __inst_name + "/capture_memory";
        capture_memory._assign();
        uart_tx_out = _ASSIGN_COMB(tx_comb_func());
        dumping_out = _ASSIGN_COMB(dumping_comb_func());
    }

    void _work(bool reset)
    {
        bool received_valid = false;
        bool start_dump = false;
        u8 received_byte = 0;
        u8 send_byte = 0;
        logic<10> new_shift = 0x3ff;
        uint32_t bit_index;

        if (reset) {
            capture_memory._work(true);
            timestamp_reg.clr();
            sample_counter_reg.clr();
            write_addr_reg.clr();
            sample_count_reg.clr();
            capture_full_reg.clr();
            dump_addr_reg.clr();
            dump_count_reg.clr();
            dump_record_reg.clr();
            dump_sequence_reg.clr();
            dump_byte_reg.clr();
            dump_state_reg.clr();
            read_record_reg.clr();
            crc_reg._next = 0xffffffffU;
            rx_sync1_reg._next = 1;
            rx_sync2_reg._next = 1;
            rx_busy_reg.clr();
            rx_baud_counter_reg.clr();
            rx_bit_reg.clr();
            rx_shift_reg.clr();
            command_state_reg.clr();
            trigger_sync1_reg.clr();
            trigger_sync2_reg.clr();
            trigger_previous_reg.clr();
            trigger_warmup_reg.clr();
            auto_dump_counter_reg.clr();
            tx_busy_reg.clr();
            tx_baud_counter_reg.clr();
            tx_bits_remaining_reg.clr();
            tx_shift_reg._next = 0x3ff;
            heartbeat_counter_reg.clr();
            heartbeat_byte_reg.clr();
            heartbeat_active_reg._next = 1;
            return;
        }

        timestamp_reg._next = timestamp_reg + 1;
        rx_sync1_reg._next = uart_rx_in();
        rx_sync2_reg._next = rx_sync1_reg;
        trigger_sync1_reg._next = dump_trigger_in();
        trigger_sync2_reg._next = trigger_sync1_reg;
        if (trigger_warmup_reg != 7) {
            trigger_warmup_reg._next = trigger_warmup_reg + 1;
            trigger_previous_reg._next = trigger_sync2_reg;
        }
        else {
            if (trigger_sync2_reg != trigger_previous_reg) {
                start_dump = true;
            }
            trigger_previous_reg._next = trigger_sync2_reg;
        }

        // Diagnostic images can transmit captures without relying on either
        // physical UART input. Counting starts only after the circular history
        // is full, so every autonomous response contains DEPTH records.
        if (AUTO_DUMP_CYCLES != 0 && dump_state_reg == 0
            && capture_full_reg) {
            if ((uint32_t)auto_dump_counter_reg == AUTO_DUMP_CYCLES - 1) {
                auto_dump_counter_reg.clr();
                start_dump = true;
            }
            else {
                auto_dump_counter_reg._next = auto_dump_counter_reg + 1;
            }
        }

        if (dump_state_reg == 0 && !heartbeat_active_reg) {
            if ((uint32_t)heartbeat_counter_reg == CLOCK_HZ - 1) {
                heartbeat_counter_reg.clr();
                heartbeat_byte_reg.clr();
                heartbeat_active_reg._next = 1;
            }
            else {
                heartbeat_counter_reg._next = heartbeat_counter_reg + 1;
            }
        }

        // Capture continuously while no dump is in progress. The memory is a
        // circular history, so DUMP always returns the newest DEPTH records in
        // chronological order.
        if (dump_state_reg == 0) {
            if ((uint32_t)sample_counter_reg == SAMPLE_DIV - 1) {
                sample_counter_reg.clr();
                write_addr_reg._next = write_addr_reg + 1;
                if ((uint32_t)sample_count_reg < DEPTH) {
                    sample_count_reg._next = sample_count_reg + 1;
                }
                if ((uint32_t)sample_count_reg == DEPTH - 1) {
                    capture_full_reg._next = 1;
                }
            }
            else {
                sample_counter_reg._next = sample_counter_reg + 1;
            }
        }

        // UART receiver, 8N1, sampled at the middle of every bit.
        if (!rx_busy_reg) {
            if (!rx_sync2_reg) {
                rx_busy_reg._next = 1;
                rx_baud_counter_reg._next = HALF_CLKS - 1;
                rx_bit_reg.clr();
            }
        }
        else if (rx_baud_counter_reg != 0) {
            rx_baud_counter_reg._next = rx_baud_counter_reg - 1;
        }
        else if (rx_bit_reg == 0) {
            if (rx_sync2_reg) {
                rx_busy_reg.clr();
            }
            else {
                rx_bit_reg._next = 1;
                rx_baud_counter_reg._next = CLKS_PER_BIT - 1;
            }
        }
        else if ((uint32_t)rx_bit_reg <= 8) {
            for (bit_index = 0; bit_index < 8; ++bit_index) {
                if ((uint32_t)rx_bit_reg == bit_index + 1) {
                    rx_shift_reg._next[bit_index] = rx_sync2_reg;
                }
            }
            rx_bit_reg._next = rx_bit_reg + 1;
            rx_baud_counter_reg._next = CLKS_PER_BIT - 1;
        }
        else {
            if (rx_sync2_reg) {
                received_valid = true;
                received_byte = rx_shift_reg;
            }
            rx_busy_reg.clr();
        }

        // A four-byte command prevents line noise during configuration from
        // accidentally freezing a capture.
        if (received_valid) {
            if (dump_state_reg != 0) {
                command_state_reg.clr();
            }
            else if (command_state_reg == 0 && received_byte == 'D') {
                command_state_reg._next = 1;
            }
            else if (command_state_reg == 1 && received_byte == 'U') {
                command_state_reg._next = 2;
            }
            else if (command_state_reg == 2 && received_byte == 'M') {
                command_state_reg._next = 3;
            }
            else if (command_state_reg == 3 && received_byte == 'P') {
                command_state_reg.clr();
                start_dump = true;
            }
            else {
                command_state_reg._next = received_byte == 'D' ? 1 : 0;
            }
        }

        if (start_dump && dump_state_reg == 0) {
            auto_dump_counter_reg.clr();
            dump_count_reg._next = sample_count_reg;
            dump_record_reg.clr();
            dump_byte_reg.clr();
            // A trigger can coincide with a circular-buffer sample. In that
            // case write_addr_reg still names the slot being written, so the
            // oldest record is the following slot.
            dump_addr_reg._next = capture_full_reg
                ? (((uint32_t)sample_counter_reg == SAMPLE_DIV - 1)
                    ? write_addr_reg + 1 : write_addr_reg)
                : 0;
            crc_reg._next = 0xffffffffU;
            dump_state_reg._next = 1;
            heartbeat_counter_reg.clr();
            heartbeat_byte_reg.clr();
            heartbeat_active_reg.clr();
        }

        // UART transmitter. The stop bit is held for CLKS_PER_BIT clocks;
        // dump scheduling occurs only after it has completed.
        if (tx_busy_reg) {
            if (tx_baud_counter_reg != 0) {
                tx_baud_counter_reg._next = tx_baud_counter_reg - 1;
            }
            else if (tx_bits_remaining_reg == 1) {
                tx_busy_reg.clr();
                tx_bits_remaining_reg.clr();
                tx_shift_reg._next = 0x3ff;
            }
            else {
                tx_shift_reg._next = tx_shift_reg >> 1;
                tx_shift_reg._next[9] = 1;
                tx_bits_remaining_reg._next = tx_bits_remaining_reg - 1;
                tx_baud_counter_reg._next = CLKS_PER_BIT - 1;
            }
        }
        else if (dump_state_reg == 1) {
            send_byte = header_byte(dump_byte_reg);
            new_shift = 0;
            new_shift[0] = 0;
            for (bit_index = 0; bit_index < 8; ++bit_index) {
                new_shift[bit_index + 1] = send_byte[bit_index];
            }
            new_shift[9] = 1;
            tx_shift_reg._next = new_shift;
            tx_busy_reg._next = 1;
            tx_bits_remaining_reg._next = 10;
            tx_baud_counter_reg._next = CLKS_PER_BIT - 1;
            if ((uint32_t)dump_byte_reg == HEADER_BYTES - 1) {
                dump_byte_reg.clr();
                dump_state_reg._next = dump_count_reg == 0 ? 4 : 2;
            }
            else {
                dump_byte_reg._next = dump_byte_reg + 1;
            }
        }
        else if (dump_state_reg == 2) {
            // Issue the synchronous block-RAM read.
            dump_state_reg._next = 5;
        }
        else if (dump_state_reg == 5) {
            // The RAM output from state 2 is now stable.
            read_record_reg._next = capture_memory.read_data_out();
            dump_byte_reg.clr();
            dump_state_reg._next = 3;
        }
        else if (dump_state_reg == 3) {
            send_byte = record_byte(read_record_reg, dump_byte_reg);
            new_shift = 0;
            new_shift[0] = 0;
            for (bit_index = 0; bit_index < 8; ++bit_index) {
                new_shift[bit_index + 1] = send_byte[bit_index];
            }
            new_shift[9] = 1;
            tx_shift_reg._next = new_shift;
            tx_busy_reg._next = 1;
            tx_bits_remaining_reg._next = 10;
            tx_baud_counter_reg._next = CLKS_PER_BIT - 1;
            crc_reg._next = crc32_byte(crc_reg, send_byte);
            if ((uint32_t)dump_byte_reg == RECORD_BYTES - 1) {
                dump_byte_reg.clr();
                dump_addr_reg._next = dump_addr_reg + 1;
                dump_record_reg._next = dump_record_reg + 1;
                dump_state_reg._next =
                    ((uint32_t)dump_record_reg + 1
                        == (uint32_t)dump_count_reg) ? 4 : 2;
            }
            else {
                dump_byte_reg._next = dump_byte_reg + 1;
            }
        }
        else if (dump_state_reg == 4) {
            send_byte = trailer_byte(dump_byte_reg);
            new_shift = 0;
            new_shift[0] = 0;
            for (bit_index = 0; bit_index < 8; ++bit_index) {
                new_shift[bit_index + 1] = send_byte[bit_index];
            }
            new_shift[9] = 1;
            tx_shift_reg._next = new_shift;
            tx_busy_reg._next = 1;
            tx_bits_remaining_reg._next = 10;
            tx_baud_counter_reg._next = CLKS_PER_BIT - 1;
            if ((uint32_t)dump_byte_reg == TRAILER_BYTES - 1) {
                dump_byte_reg.clr();
                dump_state_reg.clr();
                dump_sequence_reg._next = dump_sequence_reg + 1;
                // Re-arm a fresh circular capture after every download.
                sample_counter_reg.clr();
                write_addr_reg.clr();
                sample_count_reg.clr();
                capture_full_reg.clr();
            }
            else {
                dump_byte_reg._next = dump_byte_reg + 1;
            }
        }
        else if (heartbeat_active_reg) {
            send_byte = heartbeat_byte(heartbeat_byte_reg);
            new_shift = 0;
            new_shift[0] = 0;
            for (bit_index = 0; bit_index < 8; ++bit_index) {
                new_shift[bit_index + 1] = send_byte[bit_index];
            }
            new_shift[9] = 1;
            tx_shift_reg._next = new_shift;
            tx_busy_reg._next = 1;
            tx_bits_remaining_reg._next = 10;
            tx_baud_counter_reg._next = CLKS_PER_BIT - 1;
            if ((uint32_t)heartbeat_byte_reg == HEARTBEAT_BYTES - 1) {
                heartbeat_byte_reg.clr();
                heartbeat_active_reg.clr();
                heartbeat_counter_reg.clr();
            }
            else {
                heartbeat_byte_reg._next = heartbeat_byte_reg + 1;
            }
        }
        capture_memory._work(false);
    }

    void _strobe()
    {
        capture_memory._strobe();
        timestamp_reg.strobe();
        sample_counter_reg.strobe();
        write_addr_reg.strobe();
        sample_count_reg.strobe();
        capture_full_reg.strobe();
        dump_addr_reg.strobe();
        dump_count_reg.strobe();
        dump_record_reg.strobe();
        dump_sequence_reg.strobe();
        dump_byte_reg.strobe();
        dump_state_reg.strobe();
        read_record_reg.strobe();
        crc_reg.strobe();
        rx_sync1_reg.strobe();
        rx_sync2_reg.strobe();
        rx_busy_reg.strobe();
        rx_baud_counter_reg.strobe();
        rx_bit_reg.strobe();
        rx_shift_reg.strobe();
        command_state_reg.strobe();
        trigger_sync1_reg.strobe();
        trigger_sync2_reg.strobe();
        trigger_previous_reg.strobe();
        trigger_warmup_reg.strobe();
        auto_dump_counter_reg.strobe();
        tx_busy_reg.strobe();
        tx_baud_counter_reg.strobe();
        tx_bits_remaining_reg.strobe();
        tx_shift_reg.strobe();
        heartbeat_counter_reg.strobe();
        heartbeat_byte_reg.strobe();
        heartbeat_active_reg.strobe();
    }
};

template class UARTProbe<>;
