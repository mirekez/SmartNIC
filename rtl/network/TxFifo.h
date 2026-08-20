#pragma once

// Packet-committed transmit FIFO with one 160/320-bit DMA write port and an
// two-word read window. Two interleaved banks let OutputMerger consume a
// complete aggregate output word per clock.  Words remain invisible until an
// EOP commits the complete packet, so a DMA pause cannot underflow the wire.

#include <cpphdl.h>
#include "../common/ClockDomains.h"
#include "../common/Memory.cpp"

using namespace cpphdl;

#define TX_FIFO_FOR_EACH_BANK(M) M(0) M(1)

template<size_t LANE_WIDTH = 64, size_t FIFO_WORDS = 2048>
class TxFifo : public Module
{
public:
    static constexpr size_t WINDOW_WORDS = 2;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t MAX_LANE_WIDTH = 64;
    static constexpr size_t MAX_LANE_BYTES = MAX_LANE_WIDTH / 8;
    static constexpr size_t BANK_DEPTH = FIFO_WORDS / WINDOW_WORDS;
    static constexpr size_t ENTRY_BYTES = 10;
    static constexpr size_t ENTRY_BITS = ENTRY_BYTES * 8;
    static constexpr size_t KEEP_OFFSET = LANE_WIDTH;
    static constexpr size_t SOP_OFFSET = KEEP_OFFSET + LANE_BYTES;
    static constexpr size_t EOP_OFFSET = SOP_OFFSET + 1;
    static constexpr size_t POINTER_BITS = clog2(FIFO_WORDS);
    static constexpr size_t COUNT_BITS = clog2(FIFO_WORDS + 1);

    static_assert(LANE_WIDTH == 64,
        "TxFifo supports 64-bit 10GbE MAC words");
    static_assert(FIFO_WORDS >= 16
            && (FIFO_WORDS & (FIFO_WORDS - 1)) == 0,
        "TxFifo depth must be a power of two of at least 16 words");
    static_assert((FIFO_WORDS % WINDOW_WORDS) == 0,
        "TxFifo depth must divide evenly over eight banks");

    _PORT(bool) valid_in;
    _PORT(logic<LANE_WIDTH>) data_in;
    _PORT(logic<LANE_BYTES>) keep_in;
    _PORT(bool) sop_in;
    _PORT(bool) eop_in;
    _PORT(bool) ready_out;

    // Prefix-valid show-ahead window. read_count_in consumes 0..2 words.
    _PORT(logic<WINDOW_WORDS * LANE_WIDTH>) data_out;
    _PORT(logic<WINDOW_WORDS * LANE_BYTES>) keep_out;
    _PORT(logic<WINDOW_WORDS>) sop_out;
    _PORT(logic<WINDOW_WORDS>) eop_out;
    _PORT(logic<WINDOW_WORDS>) valid_out;
    _PORT(u<4>) read_count_in;

    _PORT(bool) clear_in;
    _PORT(bool) almost_full_out;
    _PORT(bool) protocol_error_out;

private:
    // The control and bank mapping stay in CppHDL.  Each physical bank is a
    // synchronous-read RAM; bank_read_row() prefetches the row that becomes
    // current after this cycle's dequeue.  This maps the 1K x 80-bit banks to
    // BRAM instead of building an asynchronous 1K-deep mux from LUTRAM.
    SmartNicMemory<ENTRY_BYTES, BANK_DEPTH, false, true> banks[WINDOW_WORDS];

    reg<u<POINTER_BITS>> head_reg;
    reg<u<POINTER_BITS>> tail_reg;
    reg<u<COUNT_BITS>> total_count_reg;
    reg<u<COUNT_BITS>> committed_count_reg;
    reg<u<COUNT_BITS>> pending_count_reg;
    reg<u1> in_packet_reg;
    reg<u1> protocol_error_reg;

    logic<ENTRY_BITS> input_entry_comb;
    logic<ENTRY_BITS>& input_entry_comb_func()
    {
        input_entry_comb = 0;
        input_entry_comb.bits(LANE_WIDTH - 1, 0) = data_in();
        input_entry_comb.bits(KEEP_OFFSET + LANE_BYTES - 1,
            KEEP_OFFSET) = keep_in();
        input_entry_comb[SOP_OFFSET] = sop_in();
        input_entry_comb[EOP_OFFSET] = eop_in();
        return input_entry_comb;
    }

    uint32_t bank_read_row(size_t bank)
    {
        uint32_t head = (uint32_t)head_reg;
        uint32_t pop = (uint32_t)read_count_in();
        if (pop <= WINDOW_WORDS
            && pop <= (uint32_t)committed_count_reg) {
            head = (head + pop) & (FIFO_WORDS - 1);
        }
        const uint32_t head_bank = head & (WINDOW_WORDS - 1);
        return ((head >> 1) + (bank < head_bank ? 1 : 0))
            & (BANK_DEPTH - 1);
    }

    u<clog2(BANK_DEPTH)> bank_write_addr_comb;
    u<clog2(BANK_DEPTH)>& bank_write_addr_comb_func()
    {
        bank_write_addr_comb = (uint32_t)tail_reg >> 1;
        return bank_write_addr_comb;
    }

#define TX_FIFO_DECLARE_BANK_COMBS(number) \
    bool bank_write_##number##_comb; \
    bool& bank_write_##number##_comb_func() \
    { \
        bank_write_##number##_comb = valid_in() && ready_comb_func() \
            && (((uint32_t)tail_reg & (WINDOW_WORDS - 1)) == number); \
        return bank_write_##number##_comb; \
    } \
    u<clog2(BANK_DEPTH)> bank_read_addr_##number##_comb; \
    u<clog2(BANK_DEPTH)>& bank_read_addr_##number##_comb_func() \
    { \
        bank_read_addr_##number##_comb = bank_read_row(number); \
        return bank_read_addr_##number##_comb; \
    }
    TX_FIFO_FOR_EACH_BANK(TX_FIFO_DECLARE_BANK_COMBS)
#undef TX_FIFO_DECLARE_BANK_COMBS

    _LAZY_COMB(ready_comb, bool)
        uint32_t count;
        uint32_t pop;
        count = (uint32_t)total_count_reg;
        pop = (uint32_t)read_count_in();
        if (pop <= count) {
            count -= pop;
        }
        ready_comb = count < FIFO_WORDS;
        return ready_comb;
    }

    _LAZY_COMB(window_valid_comb, logic<WINDOW_WORDS>)
        size_t slot;
        window_valid_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            window_valid_comb[slot] = slot < (uint32_t)committed_count_reg;
        }
        return window_valid_comb;
    }

    _LAZY_COMB(window_data_comb, logic<WINDOW_WORDS * LANE_WIDTH>)
        size_t slot;
        size_t bit;
        uint32_t logical;
        uint32_t bank;
        logic<ENTRY_BITS> entry;
        window_data_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            entry = banks[bank].read_data_out();
            for (bit = 0; bit < LANE_WIDTH; ++bit) {
                window_data_comb[slot * LANE_WIDTH + bit] = entry[bit];
            }
        }
        return window_data_comb;
    }

    _LAZY_COMB(window_keep_comb, logic<WINDOW_WORDS * LANE_BYTES>)
        size_t slot;
        size_t byte;
        uint32_t logical;
        uint32_t bank;
        logic<ENTRY_BITS> entry;
        window_keep_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            entry = banks[bank].read_data_out();
            for (byte = 0; byte < LANE_BYTES; ++byte) {
                window_keep_comb[slot * LANE_BYTES + byte] =
                    entry[KEEP_OFFSET + byte];
            }
        }
        return window_keep_comb;
    }

    _LAZY_COMB(window_sop_comb, logic<WINDOW_WORDS>)
        size_t slot;
        uint32_t logical;
        uint32_t bank;
        logic<ENTRY_BITS> entry;
        window_sop_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            entry = banks[bank].read_data_out();
            window_sop_comb[slot] = entry[SOP_OFFSET];
        }
        return window_sop_comb;
    }

    _LAZY_COMB(window_eop_comb, logic<WINDOW_WORDS>)
        size_t slot;
        uint32_t logical;
        uint32_t bank;
        logic<ENTRY_BITS> entry;
        window_eop_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            entry = banks[bank].read_data_out();
            window_eop_comb[slot] = entry[EOP_OFFSET];
        }
        return window_eop_comb;
    }

    _LAZY_COMB(almost_full_comb, bool)
        almost_full_comb = (uint32_t)total_count_reg
            >= FIFO_WORDS - WINDOW_WORDS;
        return almost_full_comb;
    }

public:
    void _assign()
    {
#define TX_FIFO_BIND_BANK(number) \
        banks[number].write_addr_in = \
            _ASSIGN_COMB(bank_write_addr_comb_func()); \
        banks[number].write_in = \
            _ASSIGN_COMB(bank_write_##number##_comb_func()); \
        banks[number].write_data_in = \
            _ASSIGN_COMB(input_entry_comb_func()); \
        banks[number].write_mask_in = _ASSIGN(~logic<ENTRY_BYTES>(0)); \
        banks[number].read_addr_in = \
            _ASSIGN_COMB(bank_read_addr_##number##_comb_func()); \
        banks[number].read_in = _ASSIGN(true); \
        banks[number].__inst_name = __inst_name + "/bank" \
            + std::to_string(number); \
        banks[number]._assign();
        TX_FIFO_FOR_EACH_BANK(TX_FIFO_BIND_BANK)
#undef TX_FIFO_BIND_BANK

        ready_out = _ASSIGN_COMB(ready_comb_func());
        data_out = _ASSIGN_COMB(window_data_comb_func());
        keep_out = _ASSIGN_COMB(window_keep_comb_func());
        sop_out = _ASSIGN_COMB(window_sop_comb_func());
        eop_out = _ASSIGN_COMB(window_eop_comb_func());
        valid_out = _ASSIGN_COMB(window_valid_comb_func());
        almost_full_out = _ASSIGN_COMB(almost_full_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        size_t byte;
        size_t bank_index;
        uint32_t pop;
        uint32_t head;
        uint32_t tail;
        uint32_t total;
        uint32_t committed;
        uint32_t pending;
        bool in_packet;
        bool seen_zero;
        bool malformed_keep;
        bool incomplete_keep;

        for (bank_index = 0; bank_index < WINDOW_WORDS; ++bank_index) {
            banks[bank_index]._work(reset);
        }

        if (reset) {
            head_reg.clr();
            tail_reg.clr();
            total_count_reg.clr();
            committed_count_reg.clr();
            pending_count_reg.clr();
            in_packet_reg.clr();
            protocol_error_reg.clr();
            return;
        }

        head = (uint32_t)head_reg;
        tail = (uint32_t)tail_reg;
        total = (uint32_t)total_count_reg;
        committed = (uint32_t)committed_count_reg;
        pending = (uint32_t)pending_count_reg;
        in_packet = (bool)in_packet_reg;

        pop = (uint32_t)read_count_in();
        if (pop > WINDOW_WORDS || pop > committed) {
            if (pop != 0) protocol_error_reg._next = 1;
            pop = 0;
        }
        head = (head + pop) & (FIFO_WORDS - 1);
        total -= pop;
        committed -= pop;

        if (valid_in() && ready_comb_func()) {
            malformed_keep = false;
            incomplete_keep = false;
            seen_zero = false;
            for (byte = 0; byte < LANE_BYTES; ++byte) {
                if (!(bool)keep_in()[byte]) {
                    seen_zero = true;
                    incomplete_keep = true;
                }
                else if (seen_zero) malformed_keep = true;
            }
            if ((uint64_t)keep_in() == 0
                || (!eop_in() && incomplete_keep)
                || malformed_keep) {
                protocol_error_reg._next = 1;
            }
            if (sop_in() == in_packet || (eop_in() && !in_packet && !sop_in())) {
                protocol_error_reg._next = 1;
            }

            tail = (tail + 1) & (FIFO_WORDS - 1);
            ++total;
            if (eop_in()) {
                committed += pending + 1;
                pending = 0;
                in_packet = false;
            }
            else {
                ++pending;
                in_packet = true;
            }
        }

        head_reg._next = head;
        tail_reg._next = tail;
        total_count_reg._next = total;
        committed_count_reg._next = committed;
        pending_count_reg._next = pending;
        in_packet_reg._next = in_packet;
        if (clear_in()) {
            head_reg._next = 0;
            tail_reg._next = 0;
            total_count_reg._next = 0;
            committed_count_reg._next = 0;
            pending_count_reg._next = 0;
            in_packet_reg._next = 0;
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        for (size_t bank = 0; bank < WINDOW_WORDS; ++bank) {
            banks[bank]._strobe();
        }
        head_reg.strobe();
        tail_reg.strobe();
        total_count_reg.strobe();
        committed_count_reg.strobe();
        pending_count_reg.strobe();
        in_packet_reg.strobe();
        protocol_error_reg.strobe();
    }
#endif

    void _strobe()
    {
        for (size_t bank = 0; bank < WINDOW_WORDS; ++bank) {
            banks[bank]._strobe();
        }
        head_reg.strobe(); tail_reg.strobe(); total_count_reg.strobe();
        committed_count_reg.strobe(); pending_count_reg.strobe();
        in_packet_reg.strobe(); protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class TxFifo<64, 2048>;

#undef TX_FIFO_FOR_EACH_BANK
