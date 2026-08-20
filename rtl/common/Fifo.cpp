#pragma once

// Reusable module-only copy of cpphdl/examples/basic/Fifo.cpp.  The interface
// and pointer/full behavior are retained; the example program and diagnostics
// are intentionally omitted from synthesizable common RTL.

#include <cpphdl.h>
#include "Memory.cpp"
#include "ClockDomains.h"

using namespace cpphdl;

template<size_t FIFO_WIDTH_BYTES, size_t FIFO_DEPTH, bool SHOWAHEAD = true,
    bool OUTPUT_REG = false>
class Fifo : public Module
{
    static_assert(FIFO_DEPTH > 1
            && (FIFO_DEPTH & (FIFO_DEPTH - 1)) == 0,
        "Fifo depth must be a power of two greater than one");

    // Registered-output FIFOs use the memory's synchronous read register
    // directly. Keeping the register inside SmartNicMemory lets FPGA tools
    // infer block RAM instead of expanding an asynchronous array read into
    // LUTs or flip-flops.
    SmartNicMemory<FIFO_WIDTH_BYTES, FIFO_DEPTH,
        OUTPUT_REG ? false : SHOWAHEAD, true> mem;

public:
    _PORT(bool) write_in;
    _PORT(logic<FIFO_WIDTH_BYTES * 8>) write_data_in;
    _PORT(bool) read_in;
    _PORT(logic<FIFO_WIDTH_BYTES * 8>) read_data_out;
    _PORT(bool) empty_out;
    _PORT(bool) full_out;
    _PORT(bool) clear_in;
    _PORT(bool) afull_out;

private:
    reg<u<clog2(FIFO_DEPTH)>> wp_reg;
    reg<u<clog2(FIFO_DEPTH)>> rp_reg;
    reg<u1> full_reg;
    reg<u1> afull_reg;
    reg<u1> read_valid_reg;

    bool full_comb;
    bool empty_comb;
    bool mem_read_comb;
    bool mem_write_comb;
    logic<FIFO_WIDTH_BYTES * 8> read_data_comb;

    bool& full_comb_func()
    {
        if (OUTPUT_REG) {
            full_comb = wp_reg == rp_reg && (bool)full_reg
                && (bool)read_valid_reg;
        }
        else {
            full_comb = wp_reg == rp_reg && (bool)full_reg;
        }
        return full_comb;
    }

    bool& empty_comb_func()
    {
        if (OUTPUT_REG) {
            empty_comb = !(bool)read_valid_reg;
        }
        else {
            empty_comb = wp_reg == rp_reg && !(bool)full_reg;
        }
        return empty_comb;
    }

    logic<FIFO_WIDTH_BYTES * 8>& read_data_comb_func()
    {
        read_data_comb = mem.read_data_out();
        return read_data_comb;
    }

    bool& mem_read_comb_func()
    {
        if (OUTPUT_REG) {
            bool mem_empty;
            bool output_needs_word;
            mem_empty = wp_reg == rp_reg && !(bool)full_reg;
            output_needs_word = !(bool)read_valid_reg || read_in();
            mem_read_comb = output_needs_word && !mem_empty;
        }
        else {
            mem_read_comb = read_in();
        }
        return mem_read_comb;
    }

    bool& mem_write_comb_func()
    {
        if (OUTPUT_REG) {
            bool mem_full;
            mem_full = wp_reg == rp_reg && (bool)full_reg;
            mem_write_comb = write_in()
                && (!mem_full || mem_read_comb_func());
        }
        else {
            mem_write_comb = write_in();
        }
        return mem_write_comb;
    }

public:
#ifndef SYNTHESIS
    uint32_t debug_count() const
    {
        if (full_reg) return FIFO_DEPTH;
        const uint32_t write = (uint32_t)wp_reg;
        const uint32_t read = (uint32_t)rp_reg;
        return write >= read ? write - read : FIFO_DEPTH - read + write;
    }
#endif

    void _assign()
    {
        mem.write_data_in = write_data_in;
        mem.write_in = _ASSIGN_COMB(mem_write_comb_func());
        mem.write_mask_in = _ASSIGN(~logic<FIFO_WIDTH_BYTES>(0));
        mem.write_addr_in = _ASSIGN_REG(wp_reg);
        mem.read_in = _ASSIGN_COMB(mem_read_comb_func());
        mem.read_addr_in = _ASSIGN_REG(rp_reg);
        mem.__inst_name = __inst_name + "/mem";
        mem._assign();

        read_data_out = _ASSIGN_COMB(read_data_comb_func());
        empty_out = _ASSIGN_COMB(empty_comb_func());
        full_out = _ASSIGN_COMB(full_comb_func());
        afull_out = _ASSIGN_REG(afull_reg);
    }

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        bool mem_read;
        bool mem_write;
        bool output_read;
        uint32_t count;

        mem._work(reset);
        if (reset) {
            wp_reg.clr();
            rp_reg.clr();
            full_reg.clr();
            afull_reg.clr();
            read_valid_reg.clr();
            return;
        }

        if (OUTPUT_REG) {
            mem_read = mem_read_comb_func();
            mem_write = mem_write_comb_func();
            output_read = read_in() && (bool)read_valid_reg;
            if (mem_write) {
                wp_reg._next = wp_reg + 1;
            }
            if (mem_read) {
                rp_reg._next = rp_reg + 1;
                read_valid_reg._next = 1;
            }
            else if (output_read) {
                read_valid_reg._next = 0;
            }
            if (mem_write && !mem_read && wp_reg + 1 == rp_reg) {
                full_reg._next = 1;
            }
            if (mem_read && !mem_write) {
                full_reg._next = 0;
            }
            count = (bool)full_reg ? FIFO_DEPTH
                : ((uint32_t)wp_reg >= (uint32_t)rp_reg
                    ? (uint32_t)wp_reg - (uint32_t)rp_reg
                    : FIFO_DEPTH - (uint32_t)rp_reg + (uint32_t)wp_reg);
            afull_reg._next = count + ((bool)read_valid_reg ? 1 : 0)
                >= FIFO_DEPTH / 2;
        }
        else {
            mem_read = read_in() && !empty_comb_func();
            mem_write = write_in() && (!full_comb_func() || mem_read);
            if (mem_write) {
                wp_reg._next = wp_reg + 1;
            }
            if (mem_read) {
                rp_reg._next = rp_reg + 1;
            }
            if (mem_write && !mem_read && wp_reg + 1 == rp_reg) {
                full_reg._next = 1;
            }
            if (mem_read && !mem_write) {
                full_reg._next = 0;
            }
            count = (bool)full_reg ? FIFO_DEPTH
                : ((uint32_t)wp_reg >= (uint32_t)rp_reg
                    ? (uint32_t)wp_reg - (uint32_t)rp_reg
                    : FIFO_DEPTH - (uint32_t)rp_reg + (uint32_t)wp_reg);
            afull_reg._next = count >= FIFO_DEPTH / 2;
        }

        if (clear_in()) {
            wp_reg._next = 0;
            rp_reg._next = 0;
            full_reg._next = 0;
            read_valid_reg._next = 0;
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        mem._strobe();
        wp_reg.strobe();
        rp_reg.strobe();
        full_reg.strobe();
        afull_reg.strobe();
        read_valid_reg.strobe();
    }
#endif

    void _strobe()
    {
        mem._strobe();
        wp_reg.strobe();
        rp_reg.strobe();
        full_reg.strobe();
        afull_reg.strobe();
        read_valid_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class Fifo<160, 64, true, false>;
