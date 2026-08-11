#pragma once

// Packet-committed transmit FIFO with one 160/320-bit DMA write port and an
// eight-word read window.  Eight interleaved banks let OutputMerger consume a
// complete aggregate output word per clock.  Words remain invisible until an
// EOP commits the complete packet, so a DMA pause cannot underflow the wire.

#include <cpphdl.h>
#include "../common/ClockDomains.h"

using namespace cpphdl;

#define TX_FIFO_FOR_EACH_BANK(M) M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7)

template<size_t LANE_WIDTH = 160, size_t FIFO_WORDS = 1024>
class TxFifo : public Module
{
public:
    static constexpr size_t WINDOW_WORDS = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t MAX_LANE_WIDTH = 320;
    static constexpr size_t MAX_LANE_BYTES = MAX_LANE_WIDTH / 8;
    static constexpr size_t BANK_DEPTH = FIFO_WORDS / WINDOW_WORDS;
    static constexpr size_t POINTER_BITS = clog2(FIFO_WORDS);
    static constexpr size_t COUNT_BITS = clog2(FIFO_WORDS + 1);

    static_assert(LANE_WIDTH == 160 || LANE_WIDTH == 320,
        "TxFifo supports 160-bit and 320-bit words");
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

    // Prefix-valid show-ahead window.  read_count_in consumes 0..8 words.
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
#define TX_FIFO_DECLARE_BANK(number) \
    memory<logic<MAX_LANE_WIDTH>, 1, BANK_DEPTH> data_bank_##number; \
    memory<logic<MAX_LANE_BYTES>, 1, BANK_DEPTH> keep_bank_##number; \
    memory<logic<1>, 1, BANK_DEPTH> sop_bank_##number; \
    memory<logic<1>, 1, BANK_DEPTH> eop_bank_##number;
    TX_FIFO_FOR_EACH_BANK(TX_FIFO_DECLARE_BANK)
#undef TX_FIFO_DECLARE_BANK

    reg<u<POINTER_BITS>> head_reg;
    reg<u<POINTER_BITS>> tail_reg;
    reg<u<COUNT_BITS>> total_count_reg;
    reg<u<COUNT_BITS>> committed_count_reg;
    reg<u<COUNT_BITS>> pending_count_reg;
    reg<u1> in_packet_reg;
    reg<u1> protocol_error_reg;

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
        uint32_t row;
        logic<MAX_LANE_WIDTH> entry;
        window_data_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            row = logical >> 3;
            entry = 0;
#define TX_FIFO_READ_DATA(number) \
            if (bank == number) entry = data_bank_##number[row];
            TX_FIFO_FOR_EACH_BANK(TX_FIFO_READ_DATA)
#undef TX_FIFO_READ_DATA
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
        uint32_t row;
        logic<MAX_LANE_BYTES> entry;
        window_keep_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            row = logical >> 3;
            entry = 0;
#define TX_FIFO_READ_KEEP(number) \
            if (bank == number) entry = keep_bank_##number[row];
            TX_FIFO_FOR_EACH_BANK(TX_FIFO_READ_KEEP)
#undef TX_FIFO_READ_KEEP
            for (byte = 0; byte < LANE_BYTES; ++byte) {
                window_keep_comb[slot * LANE_BYTES + byte] = entry[byte];
            }
        }
        return window_keep_comb;
    }

    _LAZY_COMB(window_sop_comb, logic<WINDOW_WORDS>)
        size_t slot;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        logic<1> entry;
        window_sop_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            row = logical >> 3;
            entry = 0;
#define TX_FIFO_READ_SOP(number) \
            if (bank == number) entry = sop_bank_##number[row];
            TX_FIFO_FOR_EACH_BANK(TX_FIFO_READ_SOP)
#undef TX_FIFO_READ_SOP
            window_sop_comb[slot] = entry;
        }
        return window_sop_comb;
    }

    _LAZY_COMB(window_eop_comb, logic<WINDOW_WORDS>)
        size_t slot;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        logic<1> entry;
        window_eop_comb = 0;
        for (slot = 0; slot < WINDOW_WORDS; ++slot) {
            logical = ((uint32_t)head_reg + slot) & (FIFO_WORDS - 1);
            bank = logical & (WINDOW_WORDS - 1);
            row = logical >> 3;
            entry = 0;
#define TX_FIFO_READ_EOP(number) \
            if (bank == number) entry = eop_bank_##number[row];
            TX_FIFO_FOR_EACH_BANK(TX_FIFO_READ_EOP)
#undef TX_FIFO_READ_EOP
            window_eop_comb[slot] = entry;
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
        ready_out = _ASSIGN_COMB(ready_comb_func());
        data_out = _ASSIGN_COMB(window_data_comb_func());
        keep_out = _ASSIGN_COMB(window_keep_comb_func());
        sop_out = _ASSIGN_COMB(window_sop_comb_func());
        eop_out = _ASSIGN_COMB(window_eop_comb_func());
        valid_out = _ASSIGN_COMB(window_valid_comb_func());
        almost_full_out = _ASSIGN_COMB(almost_full_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work(bool reset)
    {
        size_t byte;
        uint32_t pop;
        uint32_t head;
        uint32_t tail;
        uint32_t total;
        uint32_t committed;
        uint32_t pending;
        uint32_t bank;
        uint32_t row;
        bool in_packet;
        bool seen_zero;
        bool malformed_keep;
        bool incomplete_keep;
        logic<MAX_LANE_WIDTH> data_entry;
        logic<MAX_LANE_BYTES> keep_entry;

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

            data_entry = 0;
            keep_entry = 0;
            for (byte = 0; byte < LANE_WIDTH; ++byte) {
                data_entry[byte] = data_in()[byte];
            }
            for (byte = 0; byte < LANE_BYTES; ++byte) {
                keep_entry[byte] = keep_in()[byte];
            }
            bank = tail & (WINDOW_WORDS - 1);
            row = tail >> 3;
#define TX_FIFO_WRITE_BANK(number) \
            if (bank == number) { \
                data_bank_##number[row] = data_entry; \
                keep_bank_##number[row] = keep_entry; \
                sop_bank_##number[row] = sop_in(); \
                eop_bank_##number[row] = eop_in(); \
            }
            TX_FIFO_FOR_EACH_BANK(TX_FIFO_WRITE_BANK)
#undef TX_FIFO_WRITE_BANK
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
#define TX_FIFO_APPLY_BANK(number) \
        data_bank_##number.apply(); \
        keep_bank_##number.apply(); \
        sop_bank_##number.apply(); \
        eop_bank_##number.apply();
        TX_FIFO_FOR_EACH_BANK(TX_FIFO_APPLY_BANK)
#undef TX_FIFO_APPLY_BANK
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
#define TX_FIFO_APPLY_LEGACY_BANK(number) \
        data_bank_##number.apply(); keep_bank_##number.apply(); \
        sop_bank_##number.apply(); eop_bank_##number.apply();
        TX_FIFO_FOR_EACH_BANK(TX_FIFO_APPLY_LEGACY_BANK)
#undef TX_FIFO_APPLY_LEGACY_BANK
        head_reg.strobe(); tail_reg.strobe(); total_count_reg.strobe();
        committed_count_reg.strobe(); pending_count_reg.strobe();
        in_packet_reg.strobe(); protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class TxFifo<160, 1024>;
template class TxFifo<320, 1024>;

#undef TX_FIFO_FOR_EACH_BANK
