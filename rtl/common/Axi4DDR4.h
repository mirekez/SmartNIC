#pragma once

// Synthesizable single-beat AXI4 to narrow DDR controller adapter. Tribe's
// shared L2 presents one 256-bit AXI beat at a time; the adapter serializes it
// into M-bit native DDR words and reassembles reads without changing the CPU
// memory interface.

#include <cpphdl.h>
#include "../../cpphdl/tribe_cpu/common/Axi4.h"

using namespace cpphdl;

enum Axi4DDR4State : uint8_t
{
    AXI4_DDR4_IDLE,
    AXI4_DDR4_WAIT_WRITE_DATA,
    AXI4_DDR4_WRITE_WORD,
    AXI4_DDR4_WRITE_RESPONSE,
    AXI4_DDR4_READ_WORD,
    AXI4_DDR4_READ_WAIT,
    AXI4_DDR4_READ_RESPONSE
};

template<size_t AXI_ADDR_WIDTH = 31, size_t AXI_ID_WIDTH = 4,
    size_t AXI_DATA_WIDTH = 256, size_t DDR_DATA_WIDTH = 32>
class Axi4DDR4 : public Module
{
public:
    static constexpr size_t AXI_BYTES = AXI_DATA_WIDTH / 8;
    static constexpr size_t DDR_BYTES = DDR_DATA_WIDTH / 8;
    static constexpr size_t WORDS_PER_BEAT = AXI_DATA_WIDTH / DDR_DATA_WIDTH;
    static constexpr size_t WORD_INDEX_BITS = WORDS_PER_BEAT <= 1
        ? 1 : clog2(WORDS_PER_BEAT);

    static_assert(AXI_DATA_WIDTH % DDR_DATA_WIDTH == 0);
    static_assert(DDR_DATA_WIDTH % 8 == 0);
    static_assert((WORDS_PER_BEAT & (WORDS_PER_BEAT - 1)) == 0);

    Axi4If<AXI_ADDR_WIDTH, AXI_ID_WIDTH, AXI_DATA_WIDTH> axi;

    // Native request/response port. Address is a byte address. A controller
    // may insert arbitrary request and read-response latency.
    _PORT(bool) ddr_valid_out;
    _PORT(bool) ddr_write_out;
    _PORT(u<AXI_ADDR_WIDTH>) ddr_address_out;
    _PORT(logic<DDR_DATA_WIDTH>) ddr_writedata_out;
    _PORT(logic<DDR_BYTES>) ddr_byteenable_out;
    _PORT(bool) ddr_ready_in;
    _PORT(bool) ddr_readdatavalid_in;
    _PORT(logic<DDR_DATA_WIDTH>) ddr_readdata_in;

private:
    reg<u<3>> state_reg;
    reg<u<AXI_ADDR_WIDTH>> address_reg;
    reg<u<AXI_ID_WIDTH>> id_reg;
    reg<u<WORD_INDEX_BITS>> word_reg;
    reg<logic<AXI_DATA_WIDTH>> write_data_reg;
    reg<logic<AXI_BYTES>> write_strobe_reg;
    reg<logic<AXI_DATA_WIDTH>> read_data_reg;

    logic<DDR_DATA_WIDTH> ddr_write_data_comb;
    logic<DDR_BYTES> ddr_byte_enable_comb;

    logic<DDR_DATA_WIDTH>& ddr_write_data_comb_func()
    {
        uint32_t bit;
        ddr_write_data_comb = 0;
        for (bit = 0; bit < DDR_DATA_WIDTH; ++bit) {
            ddr_write_data_comb[bit] = write_data_reg[
                (uint32_t)word_reg * DDR_DATA_WIDTH + bit];
        }
        return ddr_write_data_comb;
    }

    logic<DDR_BYTES>& ddr_byte_enable_comb_func()
    {
        uint32_t byte;
        ddr_byte_enable_comb = 0;
        for (byte = 0; byte < DDR_BYTES; ++byte) {
            ddr_byte_enable_comb[byte] = write_strobe_reg[
                (uint32_t)word_reg * DDR_BYTES + byte];
        }
        return ddr_byte_enable_comb;
    }

public:
    void _assign()
    {
        axi.awready_out = _ASSIGN((uint32_t)state_reg == AXI4_DDR4_IDLE);
        axi.wready_out = _ASSIGN((uint32_t)state_reg
                == AXI4_DDR4_WAIT_WRITE_DATA
            || (WORDS_PER_BEAT == 1
                && (uint32_t)state_reg == AXI4_DDR4_IDLE
                && axi.awvalid_in() && ddr_ready_in()));
        axi.bvalid_out = _ASSIGN((uint32_t)state_reg
            == AXI4_DDR4_WRITE_RESPONSE);
        axi.bid_out = _ASSIGN_REG(id_reg);
        axi.arready_out = _ASSIGN((uint32_t)state_reg == AXI4_DDR4_IDLE
            && !axi.awvalid_in());
        axi.rvalid_out = _ASSIGN((uint32_t)state_reg
            == AXI4_DDR4_READ_RESPONSE);
        axi.rdata_out = _ASSIGN_REG(read_data_reg);
        axi.rlast_out = _ASSIGN((uint32_t)state_reg
            == AXI4_DDR4_READ_RESPONSE);
        axi.rid_out = _ASSIGN_REG(id_reg);

        ddr_valid_out = _ASSIGN((uint32_t)state_reg == AXI4_DDR4_WRITE_WORD
            || (uint32_t)state_reg == AXI4_DDR4_READ_WORD
            || (WORDS_PER_BEAT == 1
                && (uint32_t)state_reg == AXI4_DDR4_IDLE
                && axi.awvalid_in() && axi.wvalid_in()));
        ddr_write_out = _ASSIGN((uint32_t)state_reg
                == AXI4_DDR4_WRITE_WORD
            || (WORDS_PER_BEAT == 1
                && (uint32_t)state_reg == AXI4_DDR4_IDLE
                && axi.awvalid_in() && axi.wvalid_in()));
        ddr_address_out = _ASSIGN((WORDS_PER_BEAT == 1
                && (uint32_t)state_reg == AXI4_DDR4_IDLE
                && axi.awvalid_in() && axi.wvalid_in())
            ? (u<AXI_ADDR_WIDTH>)axi.awaddr_in()
            : (u<AXI_ADDR_WIDTH>)(address_reg
                + (uint32_t)word_reg * DDR_BYTES));
        ddr_writedata_out = _ASSIGN((WORDS_PER_BEAT == 1
                && (uint32_t)state_reg == AXI4_DDR4_IDLE
                && axi.awvalid_in() && axi.wvalid_in())
            ? (logic<DDR_DATA_WIDTH>)axi.wdata_in()
            : (logic<DDR_DATA_WIDTH>)ddr_write_data_comb_func());
        ddr_byteenable_out = _ASSIGN((WORDS_PER_BEAT == 1
                && (uint32_t)state_reg == AXI4_DDR4_IDLE
                && axi.awvalid_in() && axi.wvalid_in())
            ? (logic<DDR_BYTES>)axi.wstrb_in()
            : (logic<DDR_BYTES>)ddr_byte_enable_comb_func());
    }

    void _work(bool reset)
    {
        uint32_t bit;
        if ((uint32_t)state_reg == AXI4_DDR4_IDLE) {
            if (axi.awvalid_in() && axi.awready_out()) {
                address_reg._next = axi.awaddr_in();
                id_reg._next = axi.awid_in();
                if (WORDS_PER_BEAT == 1 && axi.wvalid_in()
                    && axi.wready_out() && ddr_ready_in()) {
                    state_reg._next = AXI4_DDR4_WRITE_RESPONSE;
                }
                else state_reg._next = AXI4_DDR4_WAIT_WRITE_DATA;
            }
            else if (axi.arvalid_in() && axi.arready_out()) {
                address_reg._next = axi.araddr_in();
                id_reg._next = axi.arid_in();
                word_reg._next = 0;
                read_data_reg._next = 0;
                state_reg._next = AXI4_DDR4_READ_WORD;
            }
        }
        else if ((uint32_t)state_reg == AXI4_DDR4_WAIT_WRITE_DATA
            && axi.wvalid_in() && axi.wready_out()) {
            write_data_reg._next = axi.wdata_in();
            write_strobe_reg._next = axi.wstrb_in();
            word_reg._next = 0;
            state_reg._next = AXI4_DDR4_WRITE_WORD;
        }
        else if ((uint32_t)state_reg == AXI4_DDR4_WRITE_WORD
            && ddr_ready_in()) {
            if ((uint32_t)word_reg + 1 == WORDS_PER_BEAT) {
                state_reg._next = AXI4_DDR4_WRITE_RESPONSE;
            }
            else word_reg._next = word_reg + 1;
        }
        else if ((uint32_t)state_reg == AXI4_DDR4_WRITE_RESPONSE
            && axi.bready_in()) {
            state_reg._next = AXI4_DDR4_IDLE;
        }
        else if ((uint32_t)state_reg == AXI4_DDR4_READ_WORD
            && ddr_ready_in()) {
            state_reg._next = AXI4_DDR4_READ_WAIT;
        }
        else if ((uint32_t)state_reg == AXI4_DDR4_READ_WAIT
            && ddr_readdatavalid_in()) {
            for (bit = 0; bit < DDR_DATA_WIDTH; ++bit) {
                read_data_reg._next[(uint32_t)word_reg * DDR_DATA_WIDTH + bit]
                    = ddr_readdata_in()[bit];
            }
            if ((uint32_t)word_reg + 1 == WORDS_PER_BEAT) {
                state_reg._next = AXI4_DDR4_READ_RESPONSE;
            }
            else {
                word_reg._next = word_reg + 1;
                state_reg._next = AXI4_DDR4_READ_WORD;
            }
        }
        else if ((uint32_t)state_reg == AXI4_DDR4_READ_RESPONSE
            && axi.rready_in()) {
            state_reg._next = AXI4_DDR4_IDLE;
        }

        if (reset) {
            state_reg.clr();
            address_reg.clr();
            id_reg.clr();
            word_reg.clr();
            write_data_reg.clr();
            write_strobe_reg.clr();
            read_data_reg.clr();
        }
    }

    void _strobe()
    {
        state_reg.strobe();
        address_reg.strobe();
        id_reg.strobe();
        word_reg.strobe();
        write_data_reg.strobe();
        write_strobe_reg.strobe();
        read_data_reg.strobe();
    }
};

template class Axi4DDR4<31, 4, 256, 32>;
