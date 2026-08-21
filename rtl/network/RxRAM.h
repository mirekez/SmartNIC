#pragma once

// Eight-stream receive packet store built from Tribe's synthesizable RAM.
// Each stream owns two word-interleaved sub-banks.  A packet starts at an even
// logical word and successive words alternate sub-banks, allowing an unaligned
// EOP to commit both a completed word and its final partial word in one clock.

#include "../common/RAM.h"
#include "../common/ClockDomains.h"

using namespace cpphdl;

extern long _system_clock;

#define RX_RAM_FOR_EACH_PHYSICAL_BANK(M) M(0) M(1) M(2) M(3)

struct RxRAMWritePair
{
    // Keep this helper at the maximum supported widths.  cpphdl emits class
    // template parameters on RxRAM itself, but specializes packed helper
    // return types while generating SystemVerilog.  Fixed maximum fields keep
    // one generated RxRAM usable for both 160- and 320-bit configurations.
    logic<64> data0;
    logic<64> data1;
    u<16> row0;
    u<16> row1;
    u1 valid0;
    u1 valid1;
} __PACKED;

// Registered output of the receive lane scanner.  The scanner only compacts
// bytes belonging to a frame; packing into RAM words happens one clock later.
// This boundary prevents SOP/EOP lane selection from becoming a serial path
// through the RAM write-data and completion logic.
struct RxRAMScanEvent
{
    logic<64> data0;
    logic<64> data1;
    u<4> bytes0;
    u<4> bytes1;
    u1 valid0;
    u1 valid1;
    u1 sop0;
    u1 sop1;
    u1 eop0;
    u1 eop1;
    u1 in_frame_next;
    u1 protocol_error;
} __PACKED;

template<size_t LANE_WIDTH = 64, size_t READ_PORTS = 1,
    size_t BANK_DEPTH = 4096>
class RxRAM : public Module
{
public:
    static constexpr size_t STREAMS = 2;
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
    static constexpr size_t RELEASE_SLOTS = READ_PORTS * 4;

    static_assert(LANE_WIDTH == 64,
        "RxRAM supports 64-bit 10GbE MAC words");
    static_assert(READ_PORTS > 0 && READ_PORTS <= STREAMS,
        "RxRAM requires one or two read ports");
    static_assert((BANK_DEPTH & (BANK_DEPTH - 1)) == 0,
        "RxRAM bank depth must be a power of two");
    static_assert(LOGICAL_ROW_BITS <= 16,
        "RxRAM write helper supports at most 65536 logical rows per stream");

    // Two independent InputBalancer-format streams.
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

    // Release a completed packet after its final read response is accepted.
    // Releases can arrive out of order when multiple read ports are enabled;
    // reclamation advances only after the oldest allocation is released.
    _PORT(logic<READ_PORTS>) release_valid_in;
    _PORT(logic<READ_PORTS * HANDLE_BITS>) release_handle_in;
    _PORT(logic<READ_PORTS * FRAME_LENGTH_BITS>) release_length_in;

    _PORT(bool) protocol_error_out;
    _PORT(bool) storage_full_out;

private:
    SmartNicRAM<LANE_WIDTH, BANK_DEPTH> banks[PHYSICAL_BANKS];

    reg<logic<LANE_WIDTH>> pack_data_reg[STREAMS];
    reg<u<clog2(LANE_BYTES + 1)>> pack_count_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> next_row_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> release_row_reg[STREAMS];
    reg<u<clog2(LOGICAL_ROWS + 1)>> used_rows_reg[STREAMS];
    reg<u<clog2(LOGICAL_ROWS + 1)>> allocated_rows_reg[STREAMS];
    reg<u<clog2(LOGICAL_ROWS + 1)>> released_rows_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> packet_start_reg[STREAMS];
    reg<u<FRAME_LENGTH_BITS>> packet_length_reg[STREAMS];
    reg<u1> in_frame_reg[STREAMS];
    reg<u1> scan_in_frame_reg[STREAMS];
    reg<u1> scan_valid_reg[STREAMS];
    reg<RxRAMScanEvent> scan_event_reg[STREAMS];
    reg<logic<LANE_WIDTH>> write_data0_reg[STREAMS];
    reg<logic<LANE_WIDTH>> write_data1_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> write_row0_reg[STREAMS];
    reg<u<LOGICAL_ROW_BITS>> write_row1_reg[STREAMS];
    reg<u1> write_valid0_reg[STREAMS];
    reg<u1> write_valid1_reg[STREAMS];
    reg<u1> deferred_release_valid_reg[STREAMS][RELEASE_SLOTS];
    reg<u<HANDLE_BITS>> deferred_release_handle_reg[STREAMS][RELEASE_SLOTS];
    reg<u<FRAME_LENGTH_BITS>> deferred_release_length_reg[STREAMS][RELEASE_SLOTS];

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

    // Keep the sticky, externally visible error register off the release and
    // ingress datapaths.  Each engine records a one-cycle local pulse; the
    // sticky register consumes those pulses on the following clock.
    reg<u1> release_error_reg[STREAMS];
    reg<u1> ingress_error_reg[STREAMS];
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

    static constexpr uint32_t MAX_PACKET_ROWS =
        (((1u << FRAME_LENGTH_BITS) - 1 + LANE_BYTES - 1) / LANE_BYTES + 1)
            & ~1u;

    static uint16_t released_rows(uint16_t length)
    {
        // Two 64-bit sub-bank rows are the allocation quantum.  Rounding a
        // byte length to an even number of 8-byte rows is exactly twice the
        // number of 16-byte blocks.
        return (uint16_t)(((length + 15u) >> 4) << 1);
    }

    static uint32_t request_handle(logic<READ_PORTS * HANDLE_BITS> handles,
        uint32_t port)
    {
        return (uint32_t)handles.bits(port * HANDLE_BITS + HANDLE_BITS - 1,
            port * HANDLE_BITS);
    }

    static uint32_t request_word(
        logic<READ_PORTS * LOGICAL_ROW_BITS> words, uint32_t port)
    {
        return (uint32_t)words.bits(
            port * LOGICAL_ROW_BITS + LOGICAL_ROW_BITS - 1,
            port * LOGICAL_ROW_BITS);
    }

    static uint32_t request_logical_row(
        logic<READ_PORTS * HANDLE_BITS> handles,
        logic<READ_PORTS * LOGICAL_ROW_BITS> words, uint32_t port)
    {
        return (request_handle(handles, port) >> 3)
            + request_word(words, port);
    }

    static uint32_t request_physical_bank(
        logic<READ_PORTS * HANDLE_BITS> handles,
        logic<READ_PORTS * LOGICAL_ROW_BITS> words, uint32_t port)
    {
        uint32_t handle;
        uint32_t logical;
        handle = request_handle(handles, port);
        logical = request_logical_row(handles, words, port);
        return (handle & 7) * 2 + (logical & 1);
    }

    RxRAMScanEvent scan_input_for_stream(uint32_t stream)
    {
        RxRAMScanEvent event;
        uint32_t byte;
        uint32_t flat;
        uint8_t input_byte;
        bool keep;
        bool sop;
        bool eop;
        bool accepting;
        bool second_segment;
        bool first_eop;
        bool second_eop;

        event = {};
        accepting = (bool)scan_in_frame_reg[stream];
        second_segment = false;
        first_eop = false;
        second_eop = false;
        for (byte = 0; byte < LANE_BYTES; ++byte) {
            flat = stream * LANE_BYTES + byte;
            keep = (bool)keep_in()[flat];
            sop = (bool)sop_in()[flat];
            eop = (bool)eop_in()[flat];
            if (!keep) {
                if (sop || eop) event.protocol_error = 1;
            }
            else {
                if (sop) {
                    if (accepting || second_eop) event.protocol_error = 1;
                    if (first_eop) second_segment = true;
                    accepting = true;
                    if (second_segment) event.sop1 = 1;
                    else event.sop0 = 1;
                }
                else if (!accepting) event.protocol_error = 1;
                if (accepting) {
                    input_byte = (uint8_t)data_in().bits(flat * 8 + 7,
                        flat * 8);
                    if (second_segment) {
                        event.data1 |= logic<64>(input_byte)
                            << ((uint8_t)event.bytes1 * 8);
                        event.bytes1 = u<4>((uint8_t)event.bytes1 + 1);
                        event.valid1 = 1;
                    }
                    else {
                        event.data0 |= logic<64>(input_byte)
                            << ((uint8_t)event.bytes0 * 8);
                        event.bytes0 = u<4>((uint8_t)event.bytes0 + 1);
                        event.valid0 = 1;
                    }
                    if (eop) {
                        if (second_segment) {
                            event.eop1 = 1;
                            second_eop = true;
                        }
                        else {
                            event.eop0 = 1;
                            first_eop = true;
                        }
                        accepting = false;
                    }
                }
                else if (eop) event.protocol_error = 1;
            }
        }
        event.in_frame_next = accepting;
        // The MAC cannot legally finish two Ethernet frames in one 8-byte
        // channel word.  Keep the datapath bounded to one completion/clock.
        if (first_eop && second_eop) event.protocol_error = 1;
        return event;
    }

    RxRAMWritePair write_pair_for_stream(uint32_t stream)
    {
        RxRAMWritePair pair;
        pair = {};
        pair.data0 = write_data0_reg[stream];
        pair.data1 = write_data1_reg[stream];
        pair.row0 = write_row0_reg[stream];
        pair.row1 = write_row1_reg[stream];
        pair.valid0 = write_valid0_reg[stream];
        pair.valid1 = write_valid1_reg[stream];
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
        uint32_t occupied;
        input_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            count = (uint32_t)completion_count_reg[stream];
            if (count != 0 && (bool)packet_ready_in()[stream]) {
                --count;
            }
            // Include the registered allocation awaiting application to
            // used_rows.  Ignoring a simultaneous release is conservative
            // and prevents one-cycle overbooking at a packet boundary.
            occupied = (uint32_t)used_rows_reg[stream]
                + (uint32_t)allocated_rows_reg[stream];
            input_ready_comb[stream] = count < COMPLETION_FIFO_WORDS
                && ((bool)scan_in_frame_reg[stream]
                    || occupied <= LOGICAL_ROWS - MAX_PACKET_ROWS);
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

    logic<64> read_bank_data(uint32_t bank)
    {
        logic<64> value;
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

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        uint32_t stream;
        uint32_t slot;
        uint32_t port;
        uint32_t bank;
        uint32_t segment;
        uint32_t segment_bytes;
        uint32_t total_count;
        uint32_t pack_count;
        uint16_t next_row;
        uint16_t packet_start;
        uint16_t packet_length;
        uint32_t head;
        uint32_t tail;
        uint32_t completion_count;
        uint32_t used_rows;
        uint32_t allocated_rows;
        uint32_t released_row_count;
        uint32_t release_row;
        uint32_t release_stream;
        uint32_t release_handle;
        uint32_t release_length;
        uint32_t rows;
        uint32_t release_slot;
        uint32_t drained_release_slot;
        uint32_t free_release_slot;
        uint64_t matching_release_slots;
        uint64_t claimed_release_slots;
        bool in_frame;
        bool segment_valid;
        bool segment_sop;
        bool segment_eop;
        bool release_slot_available;
        bool response_free;
        logic<64> pack_data;
        logic<64> segment_data;
        logic<128> combined_data;
        RxRAMWritePair write_pair;
        RxRAMScanEvent scan_event;

        if (reset) {
            for (stream = 0; stream < STREAMS; ++stream) {
                pack_data_reg[stream]._next = 0;
                pack_count_reg[stream]._next = 0;
                next_row_reg[stream]._next = 0;
                release_row_reg[stream]._next = 0;
                used_rows_reg[stream]._next = 0;
                allocated_rows_reg[stream]._next = 0;
                released_rows_reg[stream]._next = 0;
                packet_start_reg[stream]._next = 0;
                packet_length_reg[stream]._next = 0;
                in_frame_reg[stream]._next = 0;
                scan_in_frame_reg[stream]._next = 0;
                scan_valid_reg[stream]._next = 0;
                scan_event_reg[stream]._next = {};
                write_data0_reg[stream]._next = 0;
                write_data1_reg[stream]._next = 0;
                write_row0_reg[stream]._next = 0;
                write_row1_reg[stream]._next = 0;
                write_valid0_reg[stream]._next = 0;
                write_valid1_reg[stream]._next = 0;
                release_error_reg[stream]._next = 0;
                ingress_error_reg[stream]._next = 0;
                completion_head_reg[stream]._next = 0;
                completion_tail_reg[stream]._next = 0;
                completion_count_reg[stream]._next = 0;
                for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                    completion_handle_reg[stream][slot]._next = 0;
                    completion_length_reg[stream][slot]._next = 0;
                }
                for (slot = 0; slot < RELEASE_SLOTS; ++slot) {
                    deferred_release_valid_reg[stream][slot]._next = 0;
                    deferred_release_handle_reg[stream][slot]._next = 0;
                    deferred_release_length_reg[stream][slot]._next = 0;
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
            if ((bool)release_error_reg[stream]
                || (bool)ingress_error_reg[stream]) {
                protocol_error_reg._next = 1;
            }
            release_error_reg[stream]._next = 0;
            ingress_error_reg[stream]._next = 0;
            for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                completion_handle_reg[stream][slot]._next =
                    completion_handle_reg[stream][slot];
                completion_length_reg[stream][slot]._next =
                    completion_length_reg[stream][slot];
            }
            head = (uint32_t)completion_head_reg[stream];
            tail = (uint32_t)completion_tail_reg[stream];
            completion_count = (uint32_t)completion_count_reg[stream];
            used_rows = (uint32_t)used_rows_reg[stream];
            allocated_rows = 0;
            released_row_count = 0;
            rows = (uint32_t)released_rows_reg[stream];
            if (rows > used_rows) release_error_reg[stream]._next = 1;
            else used_rows -= rows;
            rows = (uint32_t)allocated_rows_reg[stream];
            if (used_rows + rows > LOGICAL_ROWS) {
                release_error_reg[stream]._next = 1;
                storage_full_reg._next = 1;
            }
            else used_rows += rows;
            release_row = (uint32_t)release_row_reg[stream];
            matching_release_slots = 0;
            claimed_release_slots = 0;
            drained_release_slot = RELEASE_SLOTS;

            // Compare every deferred entry against the current release row
            // independently.  The previous loop updated release_row inside
            // the slot walk; after unrolling that formed a serial chain of
            // handle comparisons, released_rows adders and break controls.
            // A bitmap followed by one priority selection leaves the slot
            // comparisons parallel and applies at most one release below.
            for (release_slot = 0; release_slot < RELEASE_SLOTS;
                ++release_slot) {
                if ((bool)deferred_release_valid_reg[stream][release_slot]
                    && ((uint32_t)deferred_release_handle_reg[stream]
                        [release_slot] >> 3) == release_row) {
                    matching_release_slots |=
                        (uint64_t)1 << release_slot;
                }
            }
            for (release_slot = 0; release_slot < RELEASE_SLOTS;
                ++release_slot) {
                if (drained_release_slot == RELEASE_SLOTS
                    && ((matching_release_slots >> release_slot) & 1u) != 0) {
                    drained_release_slot = release_slot;
                }
            }
            if (drained_release_slot != RELEASE_SLOTS) {
                rows = released_rows((uint32_t)deferred_release_length_reg
                    [stream][drained_release_slot]);
                // Apply and bounds-check the accumulated release credit on
                // the following cycle.  Keeping used_rows out of the match
                // walk avoids a carry chain through every slot.
                if (rows == 0) {
                    release_error_reg[stream]._next = 1;
                }
                else {
                    release_row = (release_row + rows)
                        & (LOGICAL_ROWS - 1);
                    released_row_count += rows;
                }
                deferred_release_valid_reg[stream]
                    [drained_release_slot]._next = 0;
            }
            for (port = 0; port < READ_PORTS; ++port) {
                if ((bool)release_valid_in()[port]) {
                    release_handle = (uint32_t)release_handle_in().bits(
                        port * HANDLE_BITS + HANDLE_BITS - 1,
                        port * HANDLE_BITS);
                    release_stream = release_handle & 7;
                    if (release_stream == stream) {
                        release_length = (uint32_t)release_length_in().bits(
                            port * FRAME_LENGTH_BITS + FRAME_LENGTH_BITS - 1,
                            port * FRAME_LENGTH_BITS);
                        rows = released_rows(release_length);
                        if (rows == 0) {
                            release_error_reg[stream]._next = 1;
                        }
                        else {
                            free_release_slot = RELEASE_SLOTS;
                            for (release_slot = 0;
                                release_slot < RELEASE_SLOTS; ++release_slot) {
                                release_slot_available =
                                    !(bool)deferred_release_valid_reg[stream]
                                        [release_slot]
                                    || release_slot == drained_release_slot;
                                if (!release_slot_available
                                    && (uint32_t)deferred_release_handle_reg
                                        [stream][release_slot]
                                        == release_handle) {
                                    release_error_reg[stream]._next = 1;
                                }
                                if (free_release_slot == RELEASE_SLOTS
                                    && release_slot_available
                                    && ((claimed_release_slots >> release_slot)
                                        & 1u) == 0) {
                                    free_release_slot = release_slot;
                                }
                            }
                            if (free_release_slot == RELEASE_SLOTS) {
                                release_error_reg[stream]._next = 1;
                            }
                            else {
                                claimed_release_slots |=
                                    (uint64_t)1 << free_release_slot;
                                deferred_release_valid_reg[stream]
                                    [free_release_slot]._next = 1;
                                deferred_release_handle_reg[stream]
                                    [free_release_slot]._next = release_handle;
                                deferred_release_length_reg[stream]
                                    [free_release_slot]._next = release_length;
                            }
                        }
                    }
                }
            }
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
            write_pair = {};
            scan_event = scan_event_reg[stream];

            if ((bool)valid_in()[stream] && !(bool)input_ready_comb_func()[stream]
                && !(bool)scan_in_frame_reg[stream]) {
                storage_full_reg._next = 1;
            }

            // Pack the scanner's two compact segments with one arithmetic
            // shift/OR per segment.  The registered scanner boundary removes
            // the old eight-lane serial SOP/EOP-to-write-data chain.
            if ((bool)scan_valid_reg[stream]) {
                if ((bool)scan_event.protocol_error)
                    ingress_error_reg[stream]._next = 1;
                for (segment = 0; segment < 2; ++segment) {
                    segment_valid = segment == 0
                        ? (bool)scan_event.valid0
                        : (bool)scan_event.valid1;
                    segment_sop = segment == 0
                        ? (bool)scan_event.sop0
                        : (bool)scan_event.sop1;
                    segment_eop = segment == 0
                        ? (bool)scan_event.eop0
                        : (bool)scan_event.eop1;
                    segment_data = segment == 0
                        ? scan_event.data0 : scan_event.data1;
                    segment_bytes = segment == 0
                        ? (uint32_t)scan_event.bytes0
                        : (uint32_t)scan_event.bytes1;

                    if (segment_sop) {
                        if (in_frame) ingress_error_reg[stream]._next = 1;
                        if ((next_row & 1) != 0)
                            next_row = (next_row + 1)
                                & (LOGICAL_ROWS - 1);
                        pack_data = 0;
                        pack_count = 0;
                        packet_start = next_row;
                        packet_length = 0;
                        in_frame = true;
                    }
                    if (segment_valid) {
                        if (!in_frame) ingress_error_reg[stream]._next = 1;
                        combined_data = logic<128>(pack_data)
                            | (logic<128>(segment_data) << (pack_count * 8));
                        total_count = pack_count + segment_bytes;
                        packet_length += segment_bytes;
                        if (total_count >= LANE_BYTES) {
                            if (!(bool)write_pair.valid0) {
                                write_pair.data0 = combined_data.bits(63, 0);
                                write_pair.row0 = u16(next_row);
                                write_pair.valid0 = 1;
                            }
                            else if (!(bool)write_pair.valid1) {
                                write_pair.data1 = combined_data.bits(63, 0);
                                write_pair.row1 = u16(next_row);
                                write_pair.valid1 = 1;
                            }
                            else ingress_error_reg[stream]._next = 1;
                            next_row = (next_row + 1)
                                & (LOGICAL_ROWS - 1);
                            pack_data = combined_data.bits(127, 64);
                            pack_count = total_count - LANE_BYTES;
                        }
                        else {
                            pack_data = combined_data.bits(63, 0);
                            pack_count = total_count;
                        }

                        if (segment_eop) {
                            if (pack_count != 0) {
                                if (!(bool)write_pair.valid0) {
                                    write_pair.data0 = pack_data;
                                    write_pair.row0 = u16(next_row);
                                    write_pair.valid0 = 1;
                                }
                                else if (!(bool)write_pair.valid1) {
                                    write_pair.data1 = pack_data;
                                    write_pair.row1 = u16(next_row);
                                    write_pair.valid1 = 1;
                                }
                                else ingress_error_reg[stream]._next = 1;
                                next_row = (next_row + 1)
                                    & (LOGICAL_ROWS - 1);
                            }
                            if ((next_row & 1) != 0)
                                next_row = (next_row + 1)
                                    & (LOGICAL_ROWS - 1);
                            completion_handle_reg[stream][tail]._next =
                                (packet_start << 3) | stream;
                            completion_length_reg[stream][tail]._next =
                                packet_length;
                            tail = (tail + 1)
                                & (COMPLETION_FIFO_WORDS - 1);
                            ++completion_count;
                            allocated_rows = released_rows(packet_length);
                            pack_data = 0;
                            pack_count = 0;
                            in_frame = false;
                        }
                    }
                    else if (segment_sop || segment_eop)
                        ingress_error_reg[stream]._next = 1;
                }
            }

            allocated_rows_reg[stream]._next = allocated_rows;
            released_rows_reg[stream]._next = released_row_count;

            pack_data_reg[stream]._next = pack_data;
            pack_count_reg[stream]._next = pack_count;
            next_row_reg[stream]._next = next_row;
            release_row_reg[stream]._next = release_row;
            used_rows_reg[stream]._next = used_rows;
            packet_start_reg[stream]._next = packet_start;
            packet_length_reg[stream]._next = packet_length;
            in_frame_reg[stream]._next = in_frame;
            write_data0_reg[stream]._next = write_pair.data0;
            write_data1_reg[stream]._next = write_pair.data1;
            write_row0_reg[stream]._next = write_pair.row0;
            write_row1_reg[stream]._next = write_pair.row1;
            write_valid0_reg[stream]._next = write_pair.valid0;
            write_valid1_reg[stream]._next = write_pair.valid1;

            // The prior scanner event was consumed above.  A newly accepted
            // MAC word replaces it on the same edge, sustaining one word per
            // channel per network clock without a combinational ready chain.
            scan_valid_reg[stream]._next = 0;
            scan_event_reg[stream]._next = scan_event_reg[stream];
            scan_in_frame_reg[stream]._next = scan_in_frame_reg[stream];
            if ((bool)valid_in()[stream]
                && (bool)input_ready_comb_func()[stream]) {
                scan_event = scan_input_for_stream(stream);
                scan_event_reg[stream]._next = scan_event;
                scan_valid_reg[stream]._next = 1;
                scan_in_frame_reg[stream]._next = scan_event.in_frame_next;
                if ((bool)scan_event.protocol_error)
                    ingress_error_reg[stream]._next = 1;
            }
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
            release_row_reg[stream].strobe();
            used_rows_reg[stream].strobe();
            allocated_rows_reg[stream].strobe();
            released_rows_reg[stream].strobe();
            packet_start_reg[stream].strobe();
            packet_length_reg[stream].strobe();
            in_frame_reg[stream].strobe();
            scan_in_frame_reg[stream].strobe();
            scan_valid_reg[stream].strobe();
            scan_event_reg[stream].strobe();
            write_data0_reg[stream].strobe();
            write_data1_reg[stream].strobe();
            write_row0_reg[stream].strobe();
            write_row1_reg[stream].strobe();
            write_valid0_reg[stream].strobe();
            write_valid1_reg[stream].strobe();
            release_error_reg[stream].strobe();
            ingress_error_reg[stream].strobe();
            completion_head_reg[stream].strobe();
            completion_tail_reg[stream].strobe();
            completion_count_reg[stream].strobe();
            for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                completion_handle_reg[stream][slot].strobe();
                completion_length_reg[stream][slot].strobe();
            }
            for (slot = 0; slot < RELEASE_SLOTS; ++slot) {
                deferred_release_valid_reg[stream][slot].strobe();
                deferred_release_handle_reg[stream][slot].strobe();
                deferred_release_length_reg[stream][slot].strobe();
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
            next_row_reg[stream].strobe(); release_row_reg[stream].strobe();
            used_rows_reg[stream].strobe(); packet_start_reg[stream].strobe();
            allocated_rows_reg[stream].strobe();
            released_rows_reg[stream].strobe();
            packet_length_reg[stream].strobe(); in_frame_reg[stream].strobe();
            scan_in_frame_reg[stream].strobe();
            scan_valid_reg[stream].strobe(); scan_event_reg[stream].strobe();
            write_data0_reg[stream].strobe(); write_data1_reg[stream].strobe();
            write_row0_reg[stream].strobe(); write_row1_reg[stream].strobe();
            write_valid0_reg[stream].strobe(); write_valid1_reg[stream].strobe();
            release_error_reg[stream].strobe();
            ingress_error_reg[stream].strobe();
            completion_head_reg[stream].strobe();
            completion_tail_reg[stream].strobe();
            completion_count_reg[stream].strobe();
            for (slot = 0; slot < COMPLETION_FIFO_WORDS; ++slot) {
                completion_handle_reg[stream][slot].strobe();
                completion_length_reg[stream][slot].strobe();
            }
            for (slot = 0; slot < RELEASE_SLOTS; ++slot) {
                deferred_release_valid_reg[stream][slot].strobe();
                deferred_release_handle_reg[stream][slot].strobe();
                deferred_release_length_reg[stream][slot].strobe();
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

template class RxRAM<64, 1, 4096>;

#undef RX_RAM_FOR_EACH_PHYSICAL_BANK
