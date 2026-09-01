#pragma once

// Small synchronous elastic FIFO for RxRAM lines.  Its input-ready signal is
// derived only from registered occupancy: downstream L2 backpressure cannot
// propagate combinationally through PacketDMA and the SmartNIC read gearbox
// into the RxRAM BRAM address path.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t DATA_WIDTH = 256, size_t DEPTH = 4>
class RxLineBuffer : public Module
{
public:
    static constexpr size_t KEEP_WIDTH = DATA_WIDTH / 8;
    static constexpr size_t PTR_BITS = DEPTH <= 2 ? 1 : clog2(DEPTH);
    static constexpr size_t COUNT_BITS = clog2(DEPTH + 1);

    static_assert(DATA_WIDTH % 8 == 0,
        "RxLineBuffer data width must contain complete bytes");
    static_assert(DEPTH >= 2 && (DEPTH & (DEPTH - 1)) == 0,
        "RxLineBuffer depth must be a power of two of at least two");

    _PORT(bool) valid_in;
    _PORT(logic<DATA_WIDTH>) data_in;
    _PORT(logic<KEEP_WIDTH>) keep_in;
    _PORT(bool) sop_in;
    _PORT(bool) eop_in;
    _PORT(bool) ready_out;

    _PORT(bool) valid_out;
    _PORT(logic<DATA_WIDTH>) data_out;
    _PORT(logic<KEEP_WIDTH>) keep_out;
    _PORT(bool) sop_out;
    _PORT(bool) eop_out;
    _PORT(bool) ready_in;

private:
    reg<logic<DATA_WIDTH>> data_reg[DEPTH];
    reg<logic<KEEP_WIDTH>> keep_reg[DEPTH];
    reg<u1> sop_reg[DEPTH];
    reg<u1> eop_reg[DEPTH];
    reg<u<PTR_BITS>> head_reg;
    reg<u<PTR_BITS>> tail_reg;
    reg<u<COUNT_BITS>> count_reg;

    bool ready_comb;
    bool valid_comb;
    logic<DATA_WIDTH> data_comb;
    logic<KEEP_WIDTH> keep_comb;
    bool sop_comb;
    bool eop_comb;

    bool& ready_comb_func()
    {
        // Deliberately do not include ready_in.  This registered occupancy
        // boundary is the timing cut; after a completely full FIFO it may
        // insert one recovery bubble, but never drops or duplicates a line.
        ready_comb = (uint32_t)count_reg < DEPTH;
        return ready_comb;
    }

    bool& valid_comb_func()
    {
        valid_comb = (uint32_t)count_reg != 0;
        return valid_comb;
    }

    logic<DATA_WIDTH>& data_comb_func()
    {
        data_comb = data_reg[(uint32_t)head_reg];
        return data_comb;
    }

    logic<KEEP_WIDTH>& keep_comb_func()
    {
        keep_comb = keep_reg[(uint32_t)head_reg];
        return keep_comb;
    }

    bool& sop_comb_func()
    {
        sop_comb = sop_reg[(uint32_t)head_reg];
        return sop_comb;
    }

    bool& eop_comb_func()
    {
        eop_comb = eop_reg[(uint32_t)head_reg];
        return eop_comb;
    }

public:
    void _assign()
    {
        ready_out = _ASSIGN_COMB(ready_comb_func());
        valid_out = _ASSIGN_COMB(valid_comb_func());
        data_out = _ASSIGN_COMB(data_comb_func());
        keep_out = _ASSIGN_COMB(keep_comb_func());
        sop_out = _ASSIGN_COMB(sop_comb_func());
        eop_out = _ASSIGN_COMB(eop_comb_func());
    }

    void _work(bool reset)
    {
        uint32_t head;
        uint32_t tail;
        uint32_t count;
        bool push;
        bool pop;

        // Do this before indexing payload storage.  On the first reset clock
        // the C++ simulation's pointer registers do not yet contain reset
        // values; evaluating a speculative push first could index outside the
        // FIFO and corrupt unrelated model state.
        if (reset) {
            head_reg.clr();
            tail_reg.clr();
            count_reg.clr();
            return;
        }

        head = (uint32_t)head_reg;
        tail = (uint32_t)tail_reg;
        count = (uint32_t)count_reg;
        push = valid_in() && ready_comb_func();
        pop = valid_comb_func() && ready_in();

        if (push) {
            data_reg[tail]._next = data_in();
            keep_reg[tail]._next = keep_in();
            sop_reg[tail]._next = sop_in();
            eop_reg[tail]._next = eop_in();
            tail = (tail + 1) & (DEPTH - 1);
        }
        if (pop) head = (head + 1) & (DEPTH - 1);
        if (push && !pop) ++count;
        else if (pop && !push) --count;

        head_reg._next = head;
        tail_reg._next = tail;
        count_reg._next = count;

    }

    void _strobe()
    {
        uint32_t slot;
        for (slot = 0; slot < DEPTH; ++slot) {
            data_reg[slot].strobe();
            keep_reg[slot].strobe();
            sop_reg[slot].strobe();
            eop_reg[slot].strobe();
        }
        head_reg.strobe();
        tail_reg.strobe();
        count_reg.strobe();
    }
};

template class RxLineBuffer<256, 4>;
