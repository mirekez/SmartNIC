// Packet-preserving CDC and byte-width gearbox.  The source packs bytes into
// 64-byte asynchronous-FIFO chunks; the destination emits its native word
// width.  A chunk never crosses a packet boundary, and ready/valid backpressure
// is preserved in both domains.

template<size_t SRC_WIDTH, size_t DST_WIDTH, size_t FIFO_DEPTH = 16>
class ASYNC_PACKET_STREAM_CLASS : public Module
{
public:
    static constexpr size_t SRC_BYTES = SRC_WIDTH / 8;
    static constexpr size_t DST_BYTES = DST_WIDTH / 8;
    static constexpr size_t CHUNK_BYTES = 64;
    static constexpr size_t CHUNK_BITS = CHUNK_BYTES * 8;
    static constexpr size_t ENTRY_BITS = CHUNK_BITS + 10;
    static constexpr size_t BUFFER_BYTES = 128;
    static constexpr size_t BUFFER_BITS = BUFFER_BYTES * 8;

    static_assert(SRC_WIDTH % 8 == 0 && DST_WIDTH % 8 == 0,
        "AsyncPacketStream widths must contain whole bytes");
    static_assert(SRC_BYTES <= CHUNK_BYTES && DST_BYTES <= CHUNK_BYTES,
        "AsyncPacketStream endpoint width exceeds one chunk");

    _PORT(bool) valid_in;
    _PORT(logic<SRC_WIDTH>) data_in;
    _PORT(logic<SRC_BYTES>) keep_in;
    _PORT(bool) sop_in;
    _PORT(bool) eop_in;
    _PORT(bool) ready_out = _ASSIGN_COMB(source_ready_comb_func());

    _PORT(bool) valid_out = _ASSIGN_COMB(output_valid_comb_func());
    _PORT(logic<DST_WIDTH>) data_out = _ASSIGN_COMB(output_data_comb_func());
    _PORT(logic<DST_BYTES>) keep_out = _ASSIGN_COMB(output_keep_comb_func());
    _PORT(bool) sop_out = _ASSIGN_REG(output_sop_reg);
    _PORT(bool) eop_out = _ASSIGN_COMB(output_eop_comb_func());
    _PORT(bool) ready_in;

private:
    ASYNC_PACKET_FIFO_CLASS<ENTRY_BITS, FIFO_DEPTH> fifo;

    // Source-domain byte accumulator.
    reg<logic<BUFFER_BITS>> source_data_reg;
    reg<u<8>> source_count_reg;
    reg<u1> source_sop_reg;
    reg<u1> source_eop_reg;

    // Destination-domain byte accumulator.
    reg<logic<BUFFER_BITS>> output_data_reg;
    reg<u<8>> output_count_reg;
    reg<u1> output_sop_reg;
    reg<u1> output_eop_reg;

    bool fifo_write_valid_comb;
    logic<ENTRY_BITS> fifo_write_data_comb;
    bool source_ready_comb;
    bool fifo_read_ready_comb;
    bool output_valid_comb;
    logic<DST_WIDTH> output_data_comb;
    logic<DST_BYTES> output_keep_comb;
    bool output_eop_comb;

    bool& fifo_write_valid_comb_func()
    {
        fifo_write_valid_comb = (uint32_t)source_count_reg >= CHUNK_BYTES
            || ((bool)source_eop_reg && (uint32_t)source_count_reg != 0);
        return fifo_write_valid_comb;
    }

    logic<ENTRY_BITS>& fifo_write_data_comb_func()
    {
        uint32_t byte;
        uint32_t count;
        fifo_write_data_comb = 0;
        count = (uint32_t)source_count_reg;
        if (count > CHUNK_BYTES) count = CHUNK_BYTES;
        for (byte = 0; byte < CHUNK_BYTES; ++byte) {
            if (byte < count) {
                fifo_write_data_comb.bits(byte * 8 + 7, byte * 8) =
                    source_data_reg.bits(byte * 8 + 7, byte * 8);
            }
        }
        fifo_write_data_comb.bits(CHUNK_BITS + 6, CHUNK_BITS) = count;
        fifo_write_data_comb[CHUNK_BITS + 7] = source_sop_reg;
        fifo_write_data_comb[CHUNK_BITS + 8] = source_eop_reg
            && (uint32_t)source_count_reg <= CHUNK_BYTES;
        return fifo_write_data_comb;
    }

    bool& source_ready_comb_func()
    {
        uint32_t remaining;
        bool emit;
        bool eop_remaining;
        remaining = (uint32_t)source_count_reg;
        emit = fifo_write_valid_comb_func() && fifo.write_ready_out();
        eop_remaining = source_eop_reg;
        if (emit) {
            if (remaining > CHUNK_BYTES) remaining -= CHUNK_BYTES;
            else remaining = 0;
            if ((uint32_t)source_count_reg <= CHUNK_BYTES) {
                eop_remaining = false;
            }
        }
        source_ready_comb = !eop_remaining
            && remaining + SRC_BYTES <= BUFFER_BYTES;
        return source_ready_comb;
    }

    bool& output_valid_comb_func()
    {
        output_valid_comb = (uint32_t)output_count_reg >= DST_BYTES
            || ((bool)output_eop_reg && (uint32_t)output_count_reg != 0);
        return output_valid_comb;
    }

    logic<DST_WIDTH>& output_data_comb_func()
    {
        uint32_t byte;
        output_data_comb = 0;
        for (byte = 0; byte < DST_BYTES; ++byte) {
            if (byte < (uint32_t)output_count_reg) {
                output_data_comb.bits(byte * 8 + 7, byte * 8) =
                    output_data_reg.bits(byte * 8 + 7, byte * 8);
            }
        }
        return output_data_comb;
    }

    logic<DST_BYTES>& output_keep_comb_func()
    {
        uint32_t byte;
        output_keep_comb = 0;
        for (byte = 0; byte < DST_BYTES; ++byte) {
            output_keep_comb[byte] = byte < (uint32_t)output_count_reg;
        }
        return output_keep_comb;
    }

    bool& output_eop_comb_func()
    {
        output_eop_comb = output_eop_reg
            && (uint32_t)output_count_reg <= DST_BYTES;
        return output_eop_comb;
    }

    bool& fifo_read_ready_comb_func()
    {
        uint32_t remaining;
        bool output_fire;
        bool eop_remaining;
        remaining = (uint32_t)output_count_reg;
        output_fire = output_valid_comb_func() && ready_in();
        eop_remaining = output_eop_reg;
        if (output_fire) {
            if (remaining > DST_BYTES) remaining -= DST_BYTES;
            else remaining = 0;
            if ((uint32_t)output_count_reg <= DST_BYTES) {
                eop_remaining = false;
            }
        }
        fifo_read_ready_comb = !eop_remaining
            && remaining + CHUNK_BYTES <= BUFFER_BYTES;
        return fifo_read_ready_comb;
    }

    void work_source(bool reset)
    {
        logic<BUFFER_BITS> data;
        uint32_t count;
        uint32_t byte;
        uint32_t shifted;
        bool sop;
        bool eop;
        bool emit;

        data = source_data_reg;
        count = (uint32_t)source_count_reg;
        sop = source_sop_reg;
        eop = source_eop_reg;
        emit = fifo_write_valid_comb_func() && fifo.write_ready_out();
        if (emit) {
            shifted = count > CHUNK_BYTES ? count - CHUNK_BYTES : 0;
            // Emission always removes one fixed-size FIFO chunk.  Expressing
            // this as a constant shift avoids generating an out-of-range
            // variable part-select for the upper half of the accumulator and
            // maps to wiring instead of a byte-indexed mux.
            if (count > CHUNK_BYTES) data = data >> CHUNK_BITS;
            else data = 0;
            count = shifted;
            sop = false;
            if (shifted == 0) eop = false;
        }
        if (valid_in() && source_ready_comb_func()) {
            for (byte = 0; byte < SRC_BYTES; ++byte) {
                if ((bool)keep_in()[byte]) {
                    data.bits(count * 8 + 7, count * 8) =
                        data_in().bits(byte * 8 + 7, byte * 8);
                    ++count;
                }
            }
            if (sop_in()) sop = true;
            if (eop_in()) eop = true;
        }
        source_data_reg._next = data;
        source_count_reg._next = count;
        source_sop_reg._next = sop;
        source_eop_reg._next = eop;
        if (reset) {
            source_data_reg.clr();
            source_count_reg.clr();
            source_sop_reg.clr();
            source_eop_reg.clr();
        }
    }

    void work_output(bool reset)
    {
        logic<BUFFER_BITS> data;
        logic<ENTRY_BITS> entry;
        uint32_t count;
        uint32_t remove;
        uint32_t chunk_count;
        uint32_t byte;
        bool sop;
        bool eop;

        data = output_data_reg;
        count = (uint32_t)output_count_reg;
        sop = output_sop_reg;
        eop = output_eop_reg;
        if (output_valid_comb_func() && ready_in()) {
            remove = count > DST_BYTES ? DST_BYTES : count;
            // A full destination beat removes the compile-time DST width.  A
            // short EOP beat consumes everything.  Keeping the two cases
            // explicit prevents a wide dynamic shifter and out-of-range
            // variable reads in synthesized SystemVerilog.
            if (count > DST_BYTES) data = data >> DST_WIDTH;
            else data = 0;
            count -= remove;
            sop = false;
            if (count == 0) eop = false;
        }
        if (fifo.read_valid_out() && fifo_read_ready_comb_func()) {
            entry = fifo.read_data_out();
            chunk_count = (uint32_t)entry.bits(CHUNK_BITS + 6, CHUNK_BITS);
            for (byte = 0; byte < CHUNK_BYTES; ++byte) {
                if (byte < chunk_count) {
                    data.bits((count + byte) * 8 + 7, (count + byte) * 8) =
                        entry.bits(byte * 8 + 7, byte * 8);
                }
            }
            if ((bool)entry[CHUNK_BITS + 7]) sop = true;
            if ((bool)entry[CHUNK_BITS + 8]) eop = true;
            count += chunk_count;
        }
        output_data_reg._next = data;
        output_count_reg._next = count;
        output_sop_reg._next = sop;
        output_eop_reg._next = eop;
        if (reset) {
            output_data_reg.clr();
            output_count_reg.clr();
            output_sop_reg.clr();
            output_eop_reg.clr();
        }
    }

public:
    void _assign()
    {
        fifo.write_valid_in = _ASSIGN_COMB(fifo_write_valid_comb_func());
        fifo.write_data_in = _ASSIGN_COMB(fifo_write_data_comb_func());
        fifo.read_ready_in = _ASSIGN_COMB(fifo_read_ready_comb_func());
        fifo.__inst_name = __inst_name + "/fifo";
        fifo._assign();
    }

    void _work_net_clk(bool reset)
    {
#if ASYNC_PACKET_SOURCE_ON_NET
        work_source(reset);
#else
        work_output(reset);
#endif
#ifndef SYNTHESIS
        fifo._work_net_clk(reset);
#endif
    }
    void _strobe_net_clk()
    {
#if ASYNC_PACKET_SOURCE_ON_NET
        source_data_reg.strobe();
        source_count_reg.strobe();
        source_sop_reg.strobe();
        source_eop_reg.strobe();
#else
        output_data_reg.strobe();
        output_count_reg.strobe();
        output_sop_reg.strobe();
        output_eop_reg.strobe();
#endif
#ifndef SYNTHESIS
        fifo._strobe_net_clk();
#endif
    }
    void _work_l2_clk(bool reset)
    {
#if ASYNC_PACKET_SOURCE_ON_NET
        work_output(reset);
#else
        work_source(reset);
#endif
#ifndef SYNTHESIS
        fifo._work_l2_clk(reset);
#endif
    }
    void _strobe_l2_clk()
    {
#if ASYNC_PACKET_SOURCE_ON_NET
        output_data_reg.strobe();
        output_count_reg.strobe();
        output_sop_reg.strobe();
        output_eop_reg.strobe();
#else
        source_data_reg.strobe();
        source_count_reg.strobe();
        source_sop_reg.strobe();
        source_eop_reg.strobe();
#endif
#ifndef SYNTHESIS
        fifo._strobe_l2_clk();
#endif
    }
};
