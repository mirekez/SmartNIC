// Gray-pointer asynchronous FIFO based on cpphdl/examples/cdc/Fifo2clk.cpp.
// This implementation file is included twice with a different class name and
// fixed direction.  Separate module types prevent CppHDL from specializing a
// boolean direction parameter to only the first converted instance.

template<size_t WIDTH, size_t DEPTH = 16>
class ASYNC_FIFO_CLASS : public Module
{
public:
    static constexpr size_t ADDR_BITS = clog2(DEPTH);
    static constexpr size_t PTR_BITS = ADDR_BITS + 1;

    static_assert(DEPTH >= 4 && (DEPTH & (DEPTH - 1)) == 0,
        "AsyncFifo depth must be a power of two and at least four");

    _PORT(bool) write_valid_in;
    _PORT(logic<WIDTH>) write_data_in;
    _PORT(bool) write_ready_out = _ASSIGN_COMB(write_ready_comb_func());

    _PORT(bool) read_ready_in;
    _PORT(bool) read_valid_out = _ASSIGN_COMB(read_valid_comb_func());
    _PORT(logic<WIDTH>) read_data_out = _ASSIGN_COMB(read_data_comb_func());

private:
    memory<logic<WIDTH>, 1, DEPTH> data_mem;

    reg<u<PTR_BITS>> write_bin_reg;
    reg<u<PTR_BITS>> write_gray_reg;
    reg<u<PTR_BITS>> read_gray_write1_reg;
    reg<u<PTR_BITS>> read_gray_write2_reg;

    reg<u<PTR_BITS>> read_bin_reg;
    reg<u<PTR_BITS>> read_gray_reg;
    reg<u<PTR_BITS>> write_gray_read1_reg;
    reg<u<PTR_BITS>> write_gray_read2_reg;

    bool write_ready_comb;
    bool read_valid_comb;
    logic<WIDTH> read_data_comb;

    bool& write_ready_comb_func()
    {
        u<PTR_BITS> full_gray;
        full_gray = read_gray_write2_reg
            ^ u<PTR_BITS>((1u << ADDR_BITS) | (1u << (ADDR_BITS - 1)));
        write_ready_comb = write_gray_reg != full_gray;
        return write_ready_comb;
    }

    bool& read_valid_comb_func()
    {
        read_valid_comb = read_gray_reg != write_gray_read2_reg;
        return read_valid_comb;
    }

    logic<WIDTH>& read_data_comb_func()
    {
        read_data_comb = data_mem[(uint32_t)read_bin_reg & (DEPTH - 1)];
        return read_data_comb;
    }

    void work_write(bool reset)
    {
        u<PTR_BITS> next;
        read_gray_write1_reg._next = read_gray_reg;
        read_gray_write2_reg._next = read_gray_write1_reg;
        if (write_valid_in() && write_ready_comb_func()) {
            data_mem[(uint32_t)write_bin_reg & (DEPTH - 1)] = write_data_in();
            next = write_bin_reg + 1;
            write_bin_reg._next = next;
            write_gray_reg._next = next ^ (next >> 1);
        }
        if (reset) {
            write_bin_reg.clr();
            write_gray_reg.clr();
            read_gray_write1_reg.clr();
            read_gray_write2_reg.clr();
        }
    }

    void work_read(bool reset)
    {
        u<PTR_BITS> next;
        write_gray_read1_reg._next = write_gray_reg;
        write_gray_read2_reg._next = write_gray_read1_reg;
        if (read_ready_in() && read_valid_comb_func()) {
            next = read_bin_reg + 1;
            read_bin_reg._next = next;
            read_gray_reg._next = next ^ (next >> 1);
        }
        if (reset) {
            read_bin_reg.clr();
            read_gray_reg.clr();
            write_gray_read1_reg.clr();
            write_gray_read2_reg.clr();
        }
    }

public:
    void _assign() {}

    void ASYNC_FIFO_FIRST_WORK(bool reset)
    {
#if ASYNC_FIFO_WRITE_ON_NET
        work_write(reset);
#else
        work_read(reset);
#endif
    }
    void ASYNC_FIFO_FIRST_STROBE()
    {
#if ASYNC_FIFO_WRITE_ON_NET
        data_mem.apply();
        write_bin_reg.strobe();
        write_gray_reg.strobe();
        read_gray_write1_reg.strobe();
        read_gray_write2_reg.strobe();
#else
        read_bin_reg.strobe();
        read_gray_reg.strobe();
        write_gray_read1_reg.strobe();
        write_gray_read2_reg.strobe();
#endif
    }
    void ASYNC_FIFO_SECOND_WORK(bool reset)
    {
#if ASYNC_FIFO_WRITE_ON_NET
        work_read(reset);
#else
        work_write(reset);
#endif
    }
    void ASYNC_FIFO_SECOND_STROBE()
    {
#if ASYNC_FIFO_WRITE_ON_NET
        read_bin_reg.strobe();
        read_gray_reg.strobe();
        write_gray_read1_reg.strobe();
        write_gray_read2_reg.strobe();
#else
        data_mem.apply();
        write_bin_reg.strobe();
        write_gray_reg.strobe();
        read_gray_write1_reg.strobe();
        read_gray_write2_reg.strobe();
#endif
    }

};
