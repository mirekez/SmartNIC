#include "VProcessingStub.h"

#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {

VProcessingStub dut;

[[noreturn]] void fail(const char* message)
{
    std::cerr << "ProcessingStub test failed: " << message << '\n';
    std::exit(1);
}

void check(bool condition, const char* message)
{
    if (!condition) fail(message);
}

void tick()
{
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.clk = 0;
    dut.eval();
}

template<typename Wide>
void clear_wide(Wide& value, unsigned words)
{
    for (unsigned word = 0; word < words; ++word) value[word] = 0;
}

void set_rx_data(unsigned source, uint32_t seed)
{
    for (unsigned word = 0; word < 8; ++word)
        dut.rx_data_in[source * 8 + word] =
            seed + word * 0x01010101U;
}

void check_tx_data(unsigned destination, uint32_t seed)
{
    for (unsigned word = 0; word < 8; ++word) {
        if (dut.tx_data_out[destination * 8 + word]
                != seed + word * 0x01010101U)
            fail("transmit data differs from the selected RxRAM port");
    }
}

void send_descriptor(uint8_t source, uint16_t handle, uint16_t length)
{
    for (unsigned word = 0; word < 5; ++word) {
        clear_wide(dut.descriptor_data_in, 8);
        if (word == 0) {
            dut.descriptor_data_in[0] = handle;
            dut.descriptor_data_in[1] = length
                | (uint32_t(source) << 16) | (1U << 24);
            dut.descriptor_data_in[2] = source;
        }
        dut.descriptor_word_in = word;
        dut.descriptor_sop_in = word == 0;
        dut.descriptor_eop_in = word == 4;
        dut.descriptor_valid_in = 1;
        dut.eval();
        check(dut.descriptor_ready_out, "descriptor was backpressured");
        tick();
    }
    dut.descriptor_valid_in = 0;
    dut.descriptor_sop_in = 0;
    dut.descriptor_eop_in = 0;
    dut.eval();

    check((dut.rx_read_valid_out & (1U << source)) != 0,
          "source-specific RxRAM command was not produced");
    check(((dut.rx_read_handle_out >> (source * 16)) & 0xffffU) == handle,
          "source-specific RxRAM handle is wrong");
    check(((dut.rx_read_length_out >> (source * 14)) & 0x3fffU) == length,
          "source-specific RxRAM length is wrong");
}

} // namespace

int main()
{
    dut.reset = 1;
    dut.uart_rx_in = 1;
    dut.uart_trigger_in = 0;
    dut.system_status_in = 0x300f;
    dut.mac_tx_status_in = 0xf;
    dut.tx_ready_in = 3;
    dut.rx_read_ready_in = 0;
    dut.rx_valid_in = 0;
    dut.rx_sop_in = 0;
    dut.rx_eop_in = 0;
    dut.rx_keep_in = 0;
    dut.descriptor_valid_in = 0;
    clear_wide(dut.descriptor_data_in, 8);
    clear_wide(dut.rx_data_in, 16);
    for (unsigned cycle = 0; cycle < 5; ++cycle) tick();
    dut.reset = 0;
    for (unsigned cycle = 0; cycle < 10; ++cycle) tick();

    // Both descriptors must be accepted before either packet is consumed.
    send_descriptor(0, 0x1234, 40);
    send_descriptor(1, 0x5678, 40);
    check(dut.rx_read_valid_out == 3,
          "two independent RxRAM commands were not held concurrently");

    dut.rx_read_ready_in = 3;
    tick();
    dut.rx_read_ready_in = 0;
    dut.eval();
    check(dut.rx_read_valid_out == 0,
          "accepted RxRAM commands did not retire independently");

    // Present both first beats, but stall Tx1. Source 1 -> Tx0 must advance
    // while source 0 -> Tx1 and its data/SOP remain held.
    dut.rx_valid_in = 3;
    dut.rx_sop_in = 3;
    dut.rx_eop_in = 0;
    dut.rx_keep_in = ~uint64_t(0);
    set_rx_data(0, 0x11223344U);
    set_rx_data(1, 0x55667788U);
    dut.tx_ready_in = 1;
    dut.eval();
    check(dut.tx_valid_out == 3, "both swapped Tx streams were not valid");
    check(dut.rx_ready_out == 2,
          "independent backpressure did not select source 1");
    check_tx_data(1, 0x11223344U);
    check_tx_data(0, 0x55667788U);
    tick();

    // Finish source 1 while source 0's original SOP is finally accepted.
    dut.rx_sop_in = 1;
    dut.rx_eop_in = 2;
    dut.rx_keep_in = (uint64_t(0xff) << 32) | 0xffffffffULL;
    set_rx_data(1, 0xa0b0c0d0U);
    dut.tx_ready_in = 3;
    dut.eval();
    check(dut.tx_sop_out == 2, "held source 0 SOP route is wrong");
    check(dut.tx_eop_out == 1, "source 1 EOP route is wrong");
    check_tx_data(0, 0xa0b0c0d0U);
    tick();

    // Finish source 0 on Tx1.
    dut.rx_valid_in = 1;
    dut.rx_sop_in = 0;
    dut.rx_eop_in = 1;
    dut.rx_keep_in = 0xff;
    set_rx_data(0, 0x10203040U);
    dut.eval();
    check(dut.tx_valid_out == 2, "source 0 last beat route is wrong");
    check(dut.tx_eop_out == 2, "source 0 EOP route is wrong");
    check_tx_data(1, 0x10203040U);
    tick();

    dut.rx_valid_in = 0;
    dut.rx_eop_in = 0;
    dut.rx_keep_in = 0;
    dut.eval();
    check(dut.tx_valid_out == 0, "Tx valid remained asserted after EOP");

    // The SmartNIC read engine can become command-ready while its width
    // converter still holds the prior packet's EOP.  Queue and accept the
    // next command in that window; forwarding must depend on stream framing,
    // not on a command-timed active flag.
    send_descriptor(0, 0x1350, 32);
    dut.rx_read_ready_in = 1;
    tick();
    dut.rx_read_ready_in = 0;
    send_descriptor(0, 0x2460, 32);
    check((dut.rx_read_valid_out & 1U) != 0,
          "lookahead RxRAM command was not queued");
    dut.rx_read_ready_in = 1;
    tick();
    dut.rx_read_ready_in = 0;
    dut.eval();
    check((dut.rx_read_valid_out & 1U) == 0,
          "lookahead RxRAM command did not retire");

    for (unsigned packet = 0; packet < 2; ++packet) {
        dut.rx_valid_in = 1;
        dut.rx_sop_in = 1;
        dut.rx_eop_in = 1;
        dut.rx_keep_in = 0xffffffffULL;
        set_rx_data(0, 0x70000000U + packet * 0x1000U);
        dut.tx_ready_in = 3;
        dut.eval();
        check(dut.tx_valid_out == 2,
              "lookahead packet was not forwarded to swapped channel");
        check(dut.tx_sop_out == 2 && dut.tx_eop_out == 2,
              "lookahead packet framing was not preserved");
        check_tx_data(1, 0x70000000U + packet * 0x1000U);
        tick();
    }
    dut.rx_valid_in = 0;
    dut.rx_sop_in = 0;
    dut.rx_eop_in = 0;
    dut.rx_keep_in = 0;

    for (unsigned cycle = 0; cycle < 80; ++cycle) tick();
    check(dut.probe_dumping_out,
          "accepted packet EOP did not trigger the UART probe");
    check(!dut.protocol_error_out, "protocol_error_out was asserted");
    std::cout
        << "ProcessingStub dual-channel concurrency/backpressure test passed\n";
    return 0;
}
