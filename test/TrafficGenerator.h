#pragma once

// Test-only aggregate Ethernet source. Beats are loaded before start and are
// then emitted on consecutive net-clock cycles. Ethernet cannot retry a beat,
// so downstream backpressure is counted as a wire-speed failure while the
// source continues advancing.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t LANE_WIDTH, size_t DEPTH = 1024>
class TrafficGenerator : public Module
{
public:
    static constexpr size_t LANES = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t DATA_BITS = LANES * LANE_WIDTH;
    static constexpr size_t BYTE_LANES = LANES * LANE_BYTES;
    static constexpr size_t STORAGE_BITS = DATA_BITS + 3 * BYTE_LANES;
    static constexpr size_t STORAGE_BYTES = STORAGE_BITS / 8;
    static constexpr size_t INDEX_BITS = clog2(DEPTH);
    static constexpr size_t COUNT_BITS = clog2(DEPTH + 1);

    static_assert(STORAGE_BITS % 8 == 0);
    static_assert(DEPTH >= 2 && (DEPTH & (DEPTH - 1)) == 0);

    _PORT(bool) load_valid_in;
    _PORT(logic<DATA_BITS>) load_data_in;
    _PORT(logic<BYTE_LANES>) load_keep_in;
    _PORT(logic<BYTE_LANES>) load_sop_in;
    _PORT(logic<BYTE_LANES>) load_eop_in;
    _PORT(bool) load_ready_out;
    _PORT(bool) start_in;
    _PORT(bool) clear_in;

    _PORT(bool) valid_out;
    _PORT(logic<DATA_BITS>) data_out;
    _PORT(logic<BYTE_LANES>) keep_out;
    _PORT(logic<BYTE_LANES>) sop_out;
    _PORT(logic<BYTE_LANES>) eop_out;
    _PORT(bool) ready_in;

    _PORT(bool) running_out;
    _PORT(bool) done_out;
    _PORT(u<32>) emitted_beats_out;
    _PORT(u<32>) backpressure_cycles_out;
    _PORT(bool) protocol_error_out;

private:
    memory<u8, STORAGE_BYTES, DEPTH> beats;
    reg<u<COUNT_BITS>> load_count_reg;
    reg<u<INDEX_BITS>> read_index_reg;
    reg<u1> running_reg;
    reg<u1> done_reg;
    reg<u<32>> emitted_reg;
    reg<u<32>> backpressure_reg;
    reg<u1> protocol_error_reg;

    logic<STORAGE_BITS> load_word_comb;
    logic<STORAGE_BITS> read_word_comb;

    logic<STORAGE_BITS>& load_word_comb_func()
    {
        load_word_comb = 0;
        load_word_comb.bits(DATA_BITS - 1, 0) = load_data_in();
        load_word_comb.bits(DATA_BITS + BYTE_LANES - 1, DATA_BITS) =
            load_keep_in();
        load_word_comb.bits(DATA_BITS + 2 * BYTE_LANES - 1,
            DATA_BITS + BYTE_LANES) = load_sop_in();
        load_word_comb.bits(STORAGE_BITS - 1,
            DATA_BITS + 2 * BYTE_LANES) = load_eop_in();
        return load_word_comb;
    }

    logic<STORAGE_BITS>& read_word_comb_func()
    {
        read_word_comb = beats[(uint32_t)read_index_reg];
        return read_word_comb;
    }

public:
    void _assign()
    {
        load_ready_out = _ASSIGN(!running_reg
            && (uint32_t)load_count_reg < DEPTH);
        valid_out = _ASSIGN(running_reg);
        data_out = _ASSIGN((logic<DATA_BITS>)read_word_comb_func().bits(
            DATA_BITS - 1, 0));
        keep_out = _ASSIGN((logic<BYTE_LANES>)read_word_comb_func().bits(
            DATA_BITS + BYTE_LANES - 1, DATA_BITS));
        sop_out = _ASSIGN((logic<BYTE_LANES>)read_word_comb_func().bits(
            DATA_BITS + 2 * BYTE_LANES - 1, DATA_BITS + BYTE_LANES));
        eop_out = _ASSIGN((logic<BYTE_LANES>)read_word_comb_func().bits(
            STORAGE_BITS - 1, DATA_BITS + 2 * BYTE_LANES));
        running_out = _ASSIGN_REG(running_reg);
        done_out = _ASSIGN_REG(done_reg);
        emitted_beats_out = _ASSIGN_REG(emitted_reg);
        backpressure_cycles_out = _ASSIGN_REG(backpressure_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work_net_clk(bool reset)
    {
        if (clear_in()) {
            load_count_reg.clr();
            read_index_reg.clr();
            running_reg.clr();
            done_reg.clr();
            emitted_reg.clr();
            backpressure_reg.clr();
            protocol_error_reg.clr();
        }
        else {
            if (load_valid_in()) {
                if (load_ready_out()) {
                    beats[(uint32_t)load_count_reg] = load_word_comb_func();
                    load_count_reg._next = load_count_reg + 1;
                }
                else protocol_error_reg._next = true;
            }
            if (start_in()) {
                if (running_reg || (uint32_t)load_count_reg == 0) {
                    protocol_error_reg._next = true;
                }
                else {
                    read_index_reg.clr();
                    emitted_reg.clr();
                    backpressure_reg.clr();
                    done_reg.clr();
                    running_reg._next = true;
                }
            }
            if (running_reg) {
                emitted_reg._next = emitted_reg + 1;
                if (!ready_in()) backpressure_reg._next = backpressure_reg + 1;
                if ((uint32_t)read_index_reg + 1
                    == (uint32_t)load_count_reg) {
                    running_reg.clr();
                    done_reg._next = true;
                }
                else read_index_reg._next = read_index_reg + 1;
            }
        }
        if (reset) {
            load_count_reg.clr();
            read_index_reg.clr();
            running_reg.clr();
            done_reg.clr();
            emitted_reg.clr();
            backpressure_reg.clr();
            protocol_error_reg.clr();
        }
    }

    void _strobe_net_clk()
    {
        beats.apply();
        load_count_reg.strobe();
        read_index_reg.strobe();
        running_reg.strobe();
        done_reg.strobe();
        emitted_reg.strobe();
        backpressure_reg.strobe();
        protocol_error_reg.strobe();
    }
};
