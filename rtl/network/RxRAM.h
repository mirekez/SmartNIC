#pragma once

// Eight-stream receive packet store built from Tribe's synthesizable RAM.
// Each stream owns two word-interleaved sub-banks.  A packet starts at an even
// logical word and successive words alternate sub-banks, allowing an unaligned
// EOP to commit both a completed word and its final partial word in one clock.

#include "../common/RAM.h"
#include "../common/ClockDomains.h"

using namespace cpphdl;

extern long _system_clock;

#define RX_RAM_FOR_EACH_PHYSICAL_BANK(M) \
    M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7) \
    M(8) M(9) M(10) M(11) M(12) M(13) M(14) M(15)

struct RxRAMWritePair
{
    // Keep this helper at the maximum supported widths.  cpphdl emits class
    // template parameters on RxRAM itself, but specializes packed helper
    // return types while generating SystemVerilog.  Fixed maximum fields keep
    // one generated RxRAM usable for both 160- and 320-bit configurations.
    logic<320> data0;
    logic<320> data1;
    u<16> row0;
    u<16> row1;
    u1 valid0;
    u1 valid1;
} __PACKED;

template<size_t LANE_WIDTH = 160, size_t READ_PORTS = 4,
    size_t BANK_DEPTH = 4096>
class RxRAM : public Module
{
public:
    static constexpr size_t STREAMS = 8;
    static constexpr size_t SUBBANKS = 2;
    static constexpr size_t PHYSICAL_BANKS = STREAMS * SUBBANKS;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t LOGICAL_ROWS = BANK_DEPTH * SUBBANKS;
    static constexpr size_t PHYSICAL_ROW_BITS = clog2(BANK_DEPTH);
    static constexpr size_t LOGICAL_ROW_BITS = clog2(LOGICAL_ROWS);
    static constexpr size_t HANDLE_BITS = LOGICAL_ROW_BITS + 3;
    static constexpr size_t READ_RR_BITS = READ_PORTS <= 1 ? 1 : clog2(READ_PORTS);
    static constexpr size_t FRAME_LENGTH_BITS = 14;
    static constexpr size_t COMPLETION_FIFO_WORDS = 4;

    static_assert(LANE_WIDTH == 160 || LANE_WIDTH == 320,
        "RxRAM supports 160-bit and 320-bit balanced streams");
    static_assert(READ_PORTS > 0 && READ_PORTS <= STREAMS,
        "RxRAM requires between one and eight read ports");
    static_assert((BANK_DEPTH & (BANK_DEPTH - 1)) == 0,
        "RxRAM bank depth must be a power of two");
    static_assert(LOGICAL_ROW_BITS <= 16,
        "RxRAM write helper supports at most 65536 logical rows per stream");

    // Eight independent InputBalancer-format streams.
    _PORT(logic<STREAMS>) valid_in;
    _PORT(logic<INPUT_BITS>) data_in;
    _PORT(logic<INPUT_BYTES>) keep_in;
    _PORT(logic<INPUT_BYTES>) sop_in;
    _PORT(logic<INPUT_BYTES>) eop_in;
    _PORT(logic<STREAMS>) ready_out;

    // One completion per packet and stream.  The handle identifies an aligned
    // first logical word; length is the exact number of packet bytes.
    _PORT(logic<STREAMS>) packet_valid_out;
    _PORT(logic<STREAMS * HANDLE_BITS>) packet_handle_out;
    _PORT(logic<STREAMS * FRAME_LENGTH_BITS>) packet_length_out;
    _PORT(logic<STREAMS>) packet_ready_in;

    // N logical read ports.  A request is (packet handle, zero-based word
    // index).  Conflicting requests are arbitrated; accepted data is returned
    // in order on the corresponding response port.
    _PORT(logic<READ_PORTS>) read_valid_in;
    _PORT(logic<READ_PORTS * HANDLE_BITS>) read_handle_in;
    _PORT(logic<READ_PORTS * LOGICAL_ROW_BITS>) read_word_in;
    _PORT(logic<READ_PORTS>) read_ready_out;
    _PORT(logic<READ_PORTS * LANE_WIDTH>) read_data_out;
    _PORT(logic<READ_PORTS>) read_valid_out;
    _PORT(logic<READ_PORTS>) read_ready_in;

    _PORT(bool) protocol_error_out;
    _PORT(bool) storage_full_out;

private:
    SmartNicRAM<LANE_WIDTH, BANK_DEPTH> banks[PHYSICAL_BANKS];

    reg<logic<LANE_WIDTH>> pack_data_reg[STREAMS];
    reg<u<clog2(LANE_BYTES + 1)>> pack_count_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> next_row_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> packet_start_reg[STREAMS];
    reg<u<FRAME_LENGTH_BITS>> packet_length_reg[STREAMS];
    reg<u1> in_frame_reg[STREAMS];

    reg<u<HANDLE_BITS>> completion_handle_reg[STREAMS][COMPLETION_FIFO_WORDS];
    reg<u<FRAME_LENGTH_BITS>> completion_length_reg[STREAMS][COMPLETION_FIFO_WORDS];
    reg<u<2>> completion_head_reg[STREAMS];
    reg<u<2>> completion_tail_reg[STREAMS];
    reg<u<3>> completion_count_reg[STREAMS];

    reg<u1> read_pipe_valid_reg[READ_PORTS];
    reg<u<4>> read_pipe_bank_reg[READ_PORTS];
    reg<u1> read_response_valid_reg[READ_PORTS];
    reg<logic<LANE_WIDTH>> read_response_data_reg[READ_PORTS];
    reg<u<READ_RR_BITS>> read_rr_reg[PHYSICAL_BANKS];

    reg<u1> protocol_error_reg;
    reg<u1> storage_full_reg;

    logic<PHYSICAL_BANKS> bank_write_valid_comb;
    logic<PHYSICAL_BANKS * LANE_WIDTH> bank_write_data_comb;
    logic<PHYSICAL_BANKS * PHYSICAL_ROW_BITS> bank_addr_comb;
    logic<PHYSICAL_BANKS> bank_read_comb;
    logic<READ_PORTS> read_ready_comb;
    logic<STREAMS> input_ready_comb;
    logic<STREAMS> packet_valid_comb;
    logic<STREAMS * HANDLE_BITS> packet_handle_comb;
    logic<STREAMS * FRAME_LENGTH_BITS> packet_length_comb;
    logic<READ_PORTS * LANE_WIDTH> read_data_comb;
    logic<READ_PORTS> read_valid_comb;

    static uint32_t request_handle(logic<136> handles,
        uint32_t port)
    {
        return (uint32_t)handles.bits(port * HANDLE_BITS + HANDLE_BITS - 1,
            port * HANDLE_BITS);
    }

    static uint32_t request_word(
        logic<112> words, uint32_t port)
    {
        return (uint32_t)words.bits(
            port * LOGICAL_ROW_BITS + LOGICAL_ROW_BITS - 1,
            port * LOGICAL_ROW_BITS);
    }

    static uint32_t request_logical_row(
        logic<136> handles, logic<112> words, uint32_t port)
    {
        return (request_handle(handles, port) >> 3)
            + request_word(words, port);
    }

    static uint32_t request_physical_bank(
        logic<136> handles, logic<112> words, uint32_t port)
    {
        uint32_t handle;
        uint32_t logical;
        handle = request_handle(handles, port);
        logical = request_logical_row(handles, words, port);
        return (handle & 7) * 2 + (logical & 1);
    }

    RxRAMWritePair write_pair_for_stream(uint32_t stream)
    {
        RxRAMWritePair pair;
        logic<320> pack_data;
        uint32_t pack_count;
        uint32_t logical_row;
        uint32_t byte;
        uint32_t bit;
        uint32_t flat;
        uint8_t input_byte;
        bool in_frame;
        bool keep;
        bool sop;
        bool eop;

        pair = {};
        pack_data = pack_data_reg[stream];
        pack_count = (uint32_t)pack_count_reg[stream];
        logical_row = (uint32_t)next_row_reg[stream];
        in_frame = (bool)in_frame_reg[stream];
        if (!(bool)valid_in()[stream] || !(bool)input_ready_comb_func()[stream]) {
            return pair;
        }
        for (byte = 0; byte < LANE_BYTES; ++byte) {
            flat = stream * LANE_BYTES + byte;
            keep = (bool)keep_in()[flat];
            sop = (bool)sop_in()[flat];
            eop = (bool)eop_in()[flat];
            if (keep) {
                if (sop) {
                    if ((logical_row & 1) != 0) {
                        ++logical_row;
                    }
                    pack_data = 0;
                    pack_count = 0;
                    in_frame = true;
                }
                if (in_frame) {
                    input_byte = (uint8_t)data_in().bits(flat * 8 + 7,
                        flat * 8);
                    for (bit = 0; bit < 8; ++bit) {
                        pack_data[pack_count * 8 + bit] =
                            (input_byte >> bit) & 1;
                    }
                    ++pack_count;
                    if (pack_count == LANE_BYTES) {
                        if (!(bool)pair.valid0) {
                            pair.data0 = pack_data;
                            pair.row0 = logical_row;
                            pair.valid0 = 1;
                        }
                        else {
                            pair.data1 = pack_data;
                            pair.row1 = logical_row;
                            pair.valid1 = 1;
                        }
                        ++logical_row;
                        pack_data = 0;
                        pack_count = 0;
                    }
                    if (eop) {
                        if (pack_count != 0) {
                            if (!(bool)pair.valid0) {
                                pair.data0 = pack_data;
                                pair.row0 = logical_row;
                                pair.valid0 = 1;
                            }
                            else {
                                pair.data1 = pack_data;
                                pair.row1 = logical_row;
                                pair.valid1 = 1;
                            }
                        }
                        in_frame = false;
                    }
                }
            }
        }
        return pair;
    }

    logic<PHYSICAL_BANKS>& bank_write_valid_comb_func()
    {
        uint32_t stream;
        uint32_t physical0;
        uint32_t physical1;
        RxRAMWritePair pair;
        bank_write_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            pair = write_pair_for_stream(stream);
            physical0 = stream * 2 + ((uint32_t)pair.row0 & 1);
            physical1 = stream * 2 + ((uint32_t)pair.row1 & 1);
            if ((bool)pair.valid0) {
                bank_write_valid_comb[physical0] = 1;
            }
            if ((bool)pair.valid1) {
                bank_write_valid_comb[physical1] = 1;
            }
        }
        return bank_write_valid_comb;
    }

    logic<PHYSICAL_BANKS * LANE_WIDTH>& bank_write_data_comb_func()
    {
        uint32_t stream;
        uint32_t bit;
        uint32_t physical0;
        uint32_t physical1;
        RxRAMWritePair pair;
        bank_write_data_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            pair = write_pair_for_stream(stream);
            physical0 = stream * 2 + ((uint32_t)pair.row0 & 1);
            physical1 = stream * 2 + ((uint32_t)pair.row1 & 1);
            if ((bool)pair.valid0) {
                for (bit = 0; bit < LANE_WIDTH; ++bit) {
                    bank_write_data_comb[physical0 * LANE_WIDTH + bit] =
                        pair.data0[bit];
                }
            }
            if ((bool)pair.valid1) {
                for (bit = 0; bit < LANE_WIDTH; ++bit) {
                    bank_write_data_comb[physical1 * LANE_WIDTH + bit] =
                        pair.data1[bit];
                }
            }
        }
        return bank_write_data_comb;
    }

    logic<READ_PORTS>& read_ready_comb_func()
    {
        uint32_t bank;
        uint32_t offset;
        uint32_t port;
        uint32_t candidate;
        bool response_free;
        bool pipe_free;
        bool found;

        read_ready_comb = 0;
        candidate = 0;
        response_free = false;
        pipe_free = false;
        for (bank = 0; bank < PHYSICAL_BANKS; ++bank) {
            found = false;
            if (!(bool)bank_write_valid_comb_func()[bank]) {
                for (offset = 0; offset < READ_PORTS; ++offset) {
                    candidate = ((uint32_t)read_rr_reg[bank] + offset)
                        % READ_PORTS;
                    response_free = !(bool)read_response_valid_reg[candidate]
                        || (bool)read_ready_in()[candidate];
                    pipe_free = !(bool)read_pipe_valid_reg[candidate]
                        || response_free;
                    if (!found && pipe_free
                        && (bool)read_valid_in()[candidate]
                        && request_physical_bank(read_handle_in(),
                            read_word_in(), candidate) == bank) {
                        read_ready_comb[candidate] = 1;
                        found = true;
                    }
                }
            }
        }
        return read_ready_comb;
    }

    logic<PHYSICAL_BANKS>& bank_read_comb_func()
    {
        uint32_t port;
        uint32_t bank;
        bank_read_comb = 0;
        bank = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            if ((bool)read_valid_in()[port]
                && (bool)read_ready_comb_func()[port]) {
                bank = request_physical_bank(read_handle_in(),
                    read_word_in(), port);
                bank_read_comb[bank] = 1;
            }
        }
        return bank_read_comb;
    }

    logic<PHYSICAL_BANKS * PHYSICAL_ROW_BITS>& bank_addr_comb_func()
    {
        uint32_t stream;
        uint32_t port;
        uint32_t bank;
        uint32_t bit;
        uint32_t physical0;
        uint32_t physical1;
        uint32_t row;
        RxRAMWritePair pair;
        bank_addr_comb = 0;
        bank = 0;
        row = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            pair = write_pair_for_stream(stream);
            physical0 = stream * 2 + ((uint32_t)pair.row0 & 1);
            physical1 = stream * 2 + ((uint32_t)pair.row1 & 1);
            if ((bool)pair.valid0) {
                row = (uint32_t)pair.row0 >> 1;
                for (bit = 0; bit < PHYSICAL_ROW_BITS; ++bit) {
                    bank_addr_comb[physical0 * PHYSICAL_ROW_BITS + bit] =
                        (row >> bit) & 1;
                }
            }
            if ((bool)pair.valid1) {
                row = (uint32_t)pair.row1 >> 1;
                for (bit = 0; bit < PHYSICAL_ROW_BITS; ++bit) {
                    bank_addr_comb[physical1 * PHYSICAL_ROW_BITS + bit] =
                        (row >> bit) & 1;
                }
            }
        }
        for (port = 0; port < READ_PORTS; ++port) {
            if ((bool)read_valid_in()[port]
                && (bool)read_ready_comb_func()[port]) {
                bank = request_physical_bank(read_handle_in(),
                    read_word_in(), port);
                if (!(bool)bank_write_valid_comb_func()[bank]) {
                    row = request_logical_row(read_handle_in(),
                        read_word_in(), port) >> 1;
                    for (bit = 0; bit < PHYSICAL_ROW_BITS; ++bit) {
                        bank_addr_comb[bank * PHYSICAL_ROW_BITS + bit] =
                            (row >> bit) & 1;
                    }
                }
            }
        }
        return bank_addr_comb;
    }

    logic<STREAMS>& input_ready_comb_func()
    {
        uint32_t stream;
        uint32_t count;
        input_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            count = (uint32_t)completion_count_reg[stream];
            if (count != 0 && (bool)packet_ready_in()[stream]) {
                --count;
            }
            input_ready_comb[stream] = count < COMPLETION_FIFO_WORDS
                && (uint32_t)next_row_reg[stream] < LOGICAL_ROWS - 3;
        }
        return input_ready_comb;
    }

    logic<STREAMS>& packet_valid_comb_func()
    {
        uint32_t stream;
        packet_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            packet_valid_comb[stream] =
                (uint32_t)completion_count_reg[stream] != 0;
        }
        return packet_valid_comb;
    }

    logic<STREAMS * HANDLE_BITS>& packet_handle_comb_func()
    {
        uint32_t stream;
        uint32_t bit;
        uint32_t head;
        packet_handle_comb = 0;
        head = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((uint32_t)completion_count_reg[stream] != 0) {
                head = (uint32_t)completion_head_reg[stream];
                for (bit = 0; bit < HANDLE_BITS; ++bit) {
                    packet_handle_comb[stream * HANDLE_BITS + bit] =
                        completion_handle_reg[stream][head][bit];
                }
            }
        }
        return packet_handle_comb;
    }

    logic<STREAMS * FRAME_LENGTH_BITS>& packet_length_comb_func()
    {
        uint32_t stream;
        uint32_t bit;
        uint32_t head;
        packet_length_comb = 0;
        head = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((uint32_t)completion_count_reg[stream] != 0) {
                head = (uint32_t)completion_head_reg[stream];
                for (bit = 0; bit < FRAME_LENGTH_BITS; ++bit) {
                    packet_length_comb[stream * FRAME_LENGTH_BITS + bit] =
                        completion_length_reg[stream][head][bit];
                }
            }
        }
        return packet_length_comb;
    }

    logic<READ_PORTS * LANE_WIDTH>& read_data_comb_func()
    {
        uint32_t port;
        uint32_t bit;
        read_data_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            for (bit = 0; bit < LANE_WIDTH; ++bit) {
                read_data_comb[port * LANE_WIDTH + bit] =
                    read_response_data_reg[port][bit];
            }
        }
        return read_data_comb;
    }

    logic<READ_PORTS>& read_valid_comb_func()
    {
        uint32_t port;
        read_valid_comb = 0;
        for (port = 0; port < READ_PORTS; ++port) {
            read_valid_comb[port] = read_response_valid_reg[port];
        }
        return read_valid_comb;
    }

    logic<320> read_bank_data(uint32_t bank)
    {
        logic<320> value;
        value = 0;
#define RX_RAM_READ_BANK(number) \
        if (bank == number) { value = banks[number].q_out(); }
        RX_RAM_FOR_EACH_PHYSICAL_BANK(RX_RAM_READ_BANK)
#undef RX_RAM_READ_BANK
        return value;
    }

public:
#ifndef SYNTHESIS
    uint32_t debug_completion_count() const
    {
        uint32_t total = 0;
        for (uint32_t stream = 0; stream < STREAMS; ++stream) {
            total += (uint32_t)completion_count_reg[stream];
        }
        return total;
    }
#endif

    void _assign()
    {
#define RX_RAM_BIND_BANK(number) \
        banks[number].addr_in = _ASSIGN(u<PHYSICAL_ROW_BITS>(bank_addr_comb_func().bits( \
            number * PHYSICAL_ROW_BITS + PHYSICAL_ROW_BITS - 1, number * PHYSICAL_ROW_BITS))); \
        banks[number].data_in = _ASSIGN(bank_write_data_comb_func().bits( \
            number * LANE_WIDTH + LANE_WIDTH - 1, number * LANE_WIDTH)); \
        banks[number].wr_in = _ASSIGN((bool)bank_write_valid_comb_func()[number]); \
        banks[number].rd_in = _ASSIGN((bool)bank_read_comb_func()[number]); \
        banks[number].id_in = number; \
        banks[number].__inst_name = __inst_name + "/bank" + std::to_string(number); \
        banks[number]._assign();
        RX_RAM_FOR_EACH_PHYSICAL_BANK(RX_RAM_BIND_BANK)
#undef RX_RAM_BIND_BANK

        ready_out = _ASSIGN_COMB(input_ready_comb_func());
        packet_valid_out = _ASSIGN_COMB(packet_valid_comb_func());
        packet_handle_out = _ASSIGN_COMB(packet_handle_comb_func());
        packet_length_out = _ASSIGN_COMB(packet_length_comb_func());
        read_ready_out = _ASSIGN_COMB(read_ready_comb_func());
        read_data_out = _ASSIGN_COMB(read_data_comb_func());
        read_valid_out = _ASSIGN_COMB(read_valid_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
        storage_full_out = _ASSIGN_REG(storage_full_reg);
    }

    void _work(bool reset)
    {
        uint32_t stream;
        uint32_t slot;
        uint32_t port;
        uint32_t bank;
        uint32_t byte;
        uint32_t bit;
        uint32_t flat;
        uint32_t pack_count;
        uint32_t next_row;
        uint32_t packet_start;
        uint32_t packet_length;
        uint32_t head;
        uint32_t tail;
        uint32_t completion_count;
        uint8_t input_byte;
        bool in_frame;
        bool keep;
        bool sop;
        bool eop;
        bool response_free;
        logic<320> pack_data;

        if (reset) {
            for (stream = 0; stream < STREAMS; ++stream) {
                pack_data_reg[stream]._next = 0;
                pack_count_reg[stream]._next = 0;
                next_row_reg[stream]._next = 0;
                packet_start_reg[stream]._next = 0;
                packet_length_reg[stream]._next = 0;
                in_frame_reg[stream]._next = 0;
                completion_head_reg[stream]._next = 0;
                completion_tail_reg[stream]._next = 0;
                completion_count_reg[stream]._next = 0;
                for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                    completion_handle_reg[stream][slot]._next = 0;
                    completion_length_reg[stream][slot]._next = 0;
                }
            }
            for (port = 0; port < READ_PORTS; ++port) {
                read_pipe_valid_reg[port]._next = 0;
                read_pipe_bank_reg[port]._next = 0;
                read_response_valid_reg[port]._next = 0;
                read_response_data_reg[port]._next = 0;
            }
            for (bank = 0; bank < PHYSICAL_BANKS; ++bank) {
                read_rr_reg[bank]._next = 0;
                banks[bank]._work(true);
            }
            protocol_error_reg._next = 0;
            storage_full_reg._next = 0;
            return;
        }

        for (stream = 0; stream < STREAMS; ++stream) {
            for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                completion_handle_reg[stream][slot]._next =
                    completion_handle_reg[stream][slot];
                completion_length_reg[stream][slot]._next =
                    completion_length_reg[stream][slot];
            }
            head = (uint32_t)completion_head_reg[stream];
            tail = (uint32_t)completion_tail_reg[stream];
            completion_count = (uint32_t)completion_count_reg[stream];
            if (completion_count != 0 && (bool)packet_ready_in()[stream]) {
                head = (head + 1) & (COMPLETION_FIFO_WORDS - 1);
                --completion_count;
            }

            pack_data = pack_data_reg[stream];
            pack_count = (uint32_t)pack_count_reg[stream];
            next_row = (uint32_t)next_row_reg[stream];
            packet_start = (uint32_t)packet_start_reg[stream];
            packet_length = (uint32_t)packet_length_reg[stream];
            in_frame = (bool)in_frame_reg[stream];

            if ((bool)valid_in()[stream] && !(bool)input_ready_comb_func()[stream]
                && next_row >= LOGICAL_ROWS - 3) {
                storage_full_reg._next = 1;
            }
            if ((bool)valid_in()[stream] && (bool)input_ready_comb_func()[stream]) {
                for (byte = 0; byte < LANE_BYTES; ++byte) {
                    flat = stream * LANE_BYTES + byte;
                    keep = (bool)keep_in()[flat];
                    sop = (bool)sop_in()[flat];
                    eop = (bool)eop_in()[flat];
                    if (!keep) {
                        if (sop || eop) {
                            protocol_error_reg._next = 1;
                        }
                    }
                    else {
                        if (sop) {
                            if (in_frame) {
                                protocol_error_reg._next = 1;
                            }
                            if ((next_row & 1) != 0) {
                                ++next_row;
                            }
                            pack_data = 0;
                            pack_count = 0;
                            packet_start = next_row;
                            packet_length = 0;
                            in_frame = true;
                        }
                        else if (!in_frame) {
                            protocol_error_reg._next = 1;
                        }
                        if (in_frame) {
                            input_byte = (uint8_t)data_in().bits(
                                flat * 8 + 7, flat * 8);
                            for (bit = 0; bit < 8; ++bit) {
                                pack_data[pack_count * 8 + bit] =
                                    (input_byte >> bit) & 1;
                            }
                            ++pack_count;
                            if (packet_length != (1u << FRAME_LENGTH_BITS) - 1) {
                                ++packet_length;
                            }
                            if (pack_count == LANE_BYTES) {
                                ++next_row;
                                pack_data = 0;
                                pack_count = 0;
                            }
                            if (eop) {
                                if (pack_count != 0) {
                                    ++next_row;
                                    pack_data = 0;
                                    pack_count = 0;
                                }
                                if (completion_count >= COMPLETION_FIFO_WORDS) {
                                    protocol_error_reg._next = 1;
                                }
                                else {
                                    completion_handle_reg[stream][tail]._next =
                                        (packet_start << 3) | stream;
                                    completion_length_reg[stream][tail]._next =
                                        packet_length;
                                    tail = (tail + 1) & (COMPLETION_FIFO_WORDS - 1);
                                    ++completion_count;
                                }
                                in_frame = false;
                            }
                        }
                    }
                }
            }

            pack_data_reg[stream]._next = pack_data;
            pack_count_reg[stream]._next = pack_count;
            next_row_reg[stream]._next = next_row;
            packet_start_reg[stream]._next = packet_start;
            packet_length_reg[stream]._next = packet_length;
            in_frame_reg[stream]._next = in_frame;
            completion_head_reg[stream]._next = head;
            completion_tail_reg[stream]._next = tail;
            completion_count_reg[stream]._next = completion_count;
        }

        for (bank = 0; bank < PHYSICAL_BANKS; ++bank) {
            read_rr_reg[bank]._next = read_rr_reg[bank];
        }
        for (port = 0; port < READ_PORTS; ++port) {
            read_pipe_valid_reg[port]._next = read_pipe_valid_reg[port];
            read_pipe_bank_reg[port]._next = read_pipe_bank_reg[port];
            read_response_valid_reg[port]._next =
                read_response_valid_reg[port];
            read_response_data_reg[port]._next =
                read_response_data_reg[port];

            response_free = !(bool)read_response_valid_reg[port]
                || (bool)read_ready_in()[port];
            if ((bool)read_response_valid_reg[port]
                && (bool)read_ready_in()[port]) {
                read_response_valid_reg[port]._next = 0;
            }
            if ((bool)read_pipe_valid_reg[port] && response_free) {
                read_response_data_reg[port]._next =
                    read_bank_data((uint32_t)read_pipe_bank_reg[port]);
                read_response_valid_reg[port]._next = 1;
                read_pipe_valid_reg[port]._next = 0;
            }
            if ((bool)read_valid_in()[port]
                && (bool)read_ready_comb_func()[port]) {
                bank = request_physical_bank(read_handle_in(),
                    read_word_in(), port);
                read_pipe_bank_reg[port]._next = bank;
                read_pipe_valid_reg[port]._next = 1;
                read_rr_reg[bank]._next = (port + 1) % READ_PORTS;
            }
        }

        for (bank = 0; bank < PHYSICAL_BANKS; ++bank) {
            banks[bank]._work(false);
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        uint32_t stream;
        uint32_t slot;
        uint32_t port;
        uint32_t bank;
        for (stream = 0; stream < STREAMS; ++stream) {
            pack_data_reg[stream].strobe();
            pack_count_reg[stream].strobe();
            next_row_reg[stream].strobe();
            packet_start_reg[stream].strobe();
            packet_length_reg[stream].strobe();
            in_frame_reg[stream].strobe();
            completion_head_reg[stream].strobe();
            completion_tail_reg[stream].strobe();
            completion_count_reg[stream].strobe();
            for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                completion_handle_reg[stream][slot].strobe();
                completion_length_reg[stream][slot].strobe();
            }
        }
        for (port = 0; port < READ_PORTS; ++port) {
            read_pipe_valid_reg[port].strobe();
            read_pipe_bank_reg[port].strobe();
            read_response_valid_reg[port].strobe();
            read_response_data_reg[port].strobe();
        }
        for (bank = 0; bank < PHYSICAL_BANKS; ++bank) {
            read_rr_reg[bank].strobe();
            banks[bank]._strobe();
        }
        protocol_error_reg.strobe();
        storage_full_reg.strobe();
    }
#endif

    void _strobe()
    {
        uint32_t stream, slot, port, bank;
        for (stream = 0; stream < STREAMS; ++stream) {
            pack_data_reg[stream].strobe(); pack_count_reg[stream].strobe();
            next_row_reg[stream].strobe(); packet_start_reg[stream].strobe();
            packet_length_reg[stream].strobe(); in_frame_reg[stream].strobe();
            completion_head_reg[stream].strobe();
            completion_tail_reg[stream].strobe();
            completion_count_reg[stream].strobe();
            for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                completion_handle_reg[stream][slot].strobe();
                completion_length_reg[stream][slot].strobe();
            }
        }
        for (port = 0; port < READ_PORTS; ++port) {
            read_pipe_valid_reg[port].strobe(); read_pipe_bank_reg[port].strobe();
            read_response_valid_reg[port].strobe();
            read_response_data_reg[port].strobe();
        }
        for (bank = 0; bank < PHYSICAL_BANKS; ++bank) {
            read_rr_reg[bank].strobe(); banks[bank]._strobe();
        }
        protocol_error_reg.strobe(); storage_full_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

#ifdef SYNTHESIS
template class RxRAM<160, 8, RX_RAM_BANK_DEPTH>;
template class RxRAM<320, 8, RX_RAM_BANK_DEPTH>;
#endif

#undef RX_RAM_FOR_EACH_PHYSICAL_BANK
