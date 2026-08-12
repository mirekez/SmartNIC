// Controller test for AXI4 and Avalon host-slave modes.  It programs and reads
// both 1024-entry rings, dispatches an RX buffer, then verifies that two TX
// scatter-gather descriptors produce one SOP-to-EOP packet sequence.

#include "../Controller.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <print>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

namespace
{

using Dut = Controller<8, 1024, HOST_DATA_WIDTH>;
static constexpr size_t HOST_BYTES = HOST_DATA_WIDTH / 8;

template<typename T, typename V>
static void copy_to_verilator(T& target, const V& value)
{
    std::memset(&target, 0, sizeof(target));
    std::memcpy(&target, &value, std::min(sizeof(target), sizeof(value)));
}

template<typename V, typename T>
static V copy_from_verilator(const T& source)
{
    V value = 0;
    std::memcpy(&value, &source, std::min(sizeof(source), sizeof(value)));
    return value;
}

class ControllerTest
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    Dut dut;
#endif
#if HOST_AXI4
    Axi4Driver<32, 4, HOST_DATA_WIDTH> host = {};
#else
    u<32> host_address = 0;
    bool host_read = false;
    bool host_write = false;
    logic<HOST_DATA_WIDTH> host_writedata = 0;
    logic<HOST_BYTES> host_byteenable = 0;
#endif
    logic<8> rx_empty = 0xff;
    logic<128> rx_length = 0;
    logic<8> tx_full = 0;
    logic<128> rx_count = 0;
    logic<128> tx_count = 0;
    bool dma_ready = true;
    bool completion_valid = false;
    u<3> completion_queue = 0;
    bool completion_direction = false;
    bool error = false;

    void fail(const char* message)
    {
        std::print("{} Controller {}: {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
#if HOST_AXI4
            "AXI4",
#else
            "Avalon",
#endif
            message);
        error = true;
    }

    void bind_native()
    {
#ifndef VERILATOR
#if HOST_AXI4
        dut.host_control = host;
#else
        dut.host_control.address_in = _ASSIGN(host_address);
        dut.host_control.read_in = _ASSIGN(host_read);
        dut.host_control.write_in = _ASSIGN(host_write);
        dut.host_control.writedata_in = _ASSIGN(host_writedata);
        dut.host_control.byteenable_in = _ASSIGN(host_byteenable);
#endif
        dut.rx_empty_in = _ASSIGN(rx_empty);
        dut.rx_packet_length_in = _ASSIGN(rx_length);
        dut.tx_full_in = _ASSIGN(tx_full);
        dut.rx_packet_count_in = _ASSIGN(rx_count);
        dut.tx_packet_count_in = _ASSIGN(tx_count);
        dut.dma_command_ready_in = _ASSIGN(dma_ready);
        dut.dma_completion_valid_in = _ASSIGN(completion_valid);
        dut.dma_completion_queue_in = _ASSIGN(completion_queue);
        dut.dma_completion_direction_in = _ASSIGN(completion_direction);
        dut.__inst_name = "controller";
        dut._assign();
#endif
    }

    void drive_verilator(bool reset, bool clock)
    {
#ifdef VERILATOR
        dut.clk = clock;
        dut.reset = reset;
#if HOST_AXI4
        dut.host_control___05Fawvalid_in = host.aw.valid;
        dut.host_control___05Fawaddr_in = (uint32_t)host.aw.addr;
        dut.host_control___05Fawid_in = (uint8_t)(uint32_t)host.aw.id;
        dut.host_control___05Fwvalid_in = host.w.valid;
        copy_to_verilator(dut.host_control___05Fwdata_in, host.w.data);
        dut.host_control___05Fwstrb_in = (uint32_t)(uint64_t)host.w.strb;
        dut.host_control___05Fwlast_in = host.w.last;
        dut.host_control___05Fbready_in = host.b.ready;
        dut.host_control___05Farvalid_in = host.ar.valid;
        dut.host_control___05Faraddr_in = (uint32_t)host.ar.addr;
        dut.host_control___05Farid_in = (uint8_t)(uint32_t)host.ar.id;
        dut.host_control___05Frready_in = host.r.ready;
#else
        dut.host_control___05Faddress_in = (uint32_t)host_address;
        dut.host_control___05Fread_in = host_read;
        dut.host_control___05Fwrite_in = host_write;
        copy_to_verilator(dut.host_control___05Fwritedata_in, host_writedata);
        dut.host_control___05Fbyteenable_in = (uint32_t)(uint64_t)host_byteenable;
#endif
        dut.rx_empty_in = (uint8_t)(uint64_t)rx_empty;
        copy_to_verilator(dut.rx_packet_length_in, rx_length);
        dut.tx_full_in = (uint8_t)(uint64_t)tx_full;
        copy_to_verilator(dut.rx_packet_count_in, rx_count);
        copy_to_verilator(dut.tx_packet_count_in, tx_count);
        dut.dma_command_ready_in = dma_ready;
        dut.dma_completion_valid_in = completion_valid;
        dut.dma_completion_queue_in = (uint8_t)(uint32_t)completion_queue;
        dut.dma_completion_direction_in = completion_direction;
        dut.eval();
#else
        (void)reset;
        (void)clock;
#endif
    }

    void cycle(bool reset = false)
    {
#ifdef VERILATOR
        drive_verilator(reset, false);
        drive_verilator(reset, true);
        drive_verilator(reset, false);
#else
        dut._work(reset);
        dut._strobe();
#endif
        ++_system_clock;
    }

#if HOST_AXI4
    bool awready()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.host_control___05Fawready_out;
#else
        return dut.host_control.awready_out();
#endif
    }
    bool wready()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.host_control___05Fwready_out;
#else
        return dut.host_control.wready_out();
#endif
    }
    bool bvalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.host_control___05Fbvalid_out;
#else
        return dut.host_control.bvalid_out();
#endif
    }
    bool arready()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.host_control___05Farready_out;
#else
        return dut.host_control.arready_out();
#endif
    }
    bool rvalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.host_control___05Frvalid_out;
#else
        return dut.host_control.rvalid_out();
#endif
    }
    logic<HOST_DATA_WIDTH> rdata()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<HOST_DATA_WIDTH>>(
            dut.host_control___05Frdata_out);
#else
        return dut.host_control.rdata_out();
#endif
    }
#else
    bool readdatavalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.host_control___05Freaddatavalid_out;
#else
        return dut.host_control.readdatavalid_out();
#endif
    }
    logic<HOST_DATA_WIDTH> readdata()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<HOST_DATA_WIDTH>>(
            dut.host_control___05Freaddata_out);
#else
        return dut.host_control.readdata_out();
#endif
    }
#endif

    void write32(uint32_t address, uint32_t value)
    {
        uint32_t lane = address & (HOST_BYTES - 1);
#if HOST_AXI4
        host.aw.valid = true;
        host.aw.addr = address;
        host.aw.id = 1;
        host.b.ready = true;
        while (!awready()) cycle();
        cycle();
        host.aw.valid = false;
        host.w.valid = true;
        host.w.data = 0;
        host.w.data.bits(lane * 8 + 31, lane * 8) = value;
        host.w.strb = 0;
        host.w.strb.bits(lane + 3, lane) = 0xf;
        host.w.last = true;
        while (!wready()) cycle();
        cycle();
        host.w.valid = false;
        if (!bvalid()) fail("missing AXI write response");
        cycle();
        host.b.ready = false;
#else
        host_address = address;
        host_writedata = 0;
        host_writedata.bits(lane * 8 + 31, lane * 8) = value;
        host_byteenable = 0;
        host_byteenable.bits(lane + 3, lane) = 0xf;
        host_write = true;
        cycle();
        host_write = false;
#endif
    }

    uint32_t read32(uint32_t address)
    {
        uint32_t lane = address & (HOST_BYTES - 1);
#if HOST_AXI4
        host.ar.valid = true;
        host.ar.addr = address;
        host.ar.id = 2;
        while (!arready()) cycle();
        cycle();
        host.ar.valid = false;
        if (!rvalid()) fail("missing AXI read response");
        uint32_t value = (uint32_t)rdata().bits(lane * 8 + 31, lane * 8);
        host.r.ready = true;
        cycle();
        host.r.ready = false;
        return value;
#else
        host_address = address;
        host_read = true;
        cycle();
        host_read = false;
        if (!readdatavalid()) fail("missing Avalon read response");
        return (uint32_t)readdata().bits(lane * 8 + 31, lane * 8);
#endif
    }

    bool command_valid()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.dma_command_valid_out;
#else
        return dut.dma_command_valid_out();
#endif
    }
    bool command_direction_value()
    {
#ifdef VERILATOR
        return dut.dma_command_direction_out;
#else
        return dut.dma_command_direction_out();
#endif
    }
    uint32_t command_queue_value()
    {
#ifdef VERILATOR
        return dut.dma_command_queue_out;
#else
        return (uint32_t)dut.dma_command_queue_out();
#endif
    }
    uint64_t command_address_value()
    {
#ifdef VERILATOR
        return dut.dma_command_address_out;
#else
        return (uint64_t)dut.dma_command_address_out();
#endif
    }
    uint32_t command_length_value()
    {
#ifdef VERILATOR
        return dut.dma_command_length_out;
#else
        return (uint32_t)dut.dma_command_length_out();
#endif
    }
    bool command_sop_value()
    {
#ifdef VERILATOR
        return dut.dma_command_sop_out;
#else
        return dut.dma_command_sop_out();
#endif
    }
    bool command_eop_value()
    {
#ifdef VERILATOR
        return dut.dma_command_eop_out;
#else
        return dut.dma_command_eop_out();
#endif
    }
    bool protocol_error_value()
    {
#ifdef VERILATOR
        return dut.protocol_error_out;
#else
        return dut.protocol_error_out();
#endif
    }

    void write_descriptor(uint32_t base, uint32_t index, uint64_t address,
        uint32_t length, uint32_t queue, uint32_t flags)
    {
        uint32_t entry = base + index * Dut::RING_ENTRY_BYTES;
        write32(entry + 0, (uint32_t)address);
        write32(entry + 4, (uint32_t)(address >> 32));
        write32(entry + 8, length | (queue << 16) | (flags << 24));
        write32(entry + 12, 0);
    }

    void expect_command(bool direction, uint32_t queue, uint64_t address,
        uint32_t length, bool sop, bool eop)
    {
        for (uint32_t timeout = 0; timeout < 1000 && !command_valid(); ++timeout) {
            cycle();
        }
        if (!command_valid()) {
            fail("command dispatch timed out");
            return;
        }
        if (command_direction_value() != direction
            || command_queue_value() != queue
            || command_address_value() != address
            || command_length_value() != length
            || command_sop_value() != sop
            || command_eop_value() != eop) {
            fail("dispatched command fields mismatch");
        }
        cycle(); // command_ready handshake
        completion_direction = direction;
        completion_queue = queue;
        completion_valid = true;
        cycle();
        completion_valid = false;
    }

public:
    bool run()
    {
        bind_native();
        for (int i = 0; i < 4; ++i) cycle(true);

        rx_empty[2] = 0;
        rx_length.bits(2 * 16 + 15, 2 * 16) = 60;
        rx_count.bits(2 * 16 + 15, 2 * 16) = 1;

        // Test 1: host register/ring readback and RX queue status.
        write_descriptor(Dut::REG_RX_RING_BASE, 0, 0x300, 128, 2, 0);
        if (read32(Dut::REG_RX_RING_BASE) != 0x300
            || read32(Dut::REG_RX_RING_BASE + 8) != (128u | (2u << 16))) {
            fail("RX ring readback mismatch");
        }
        uint32_t queue_status = read32(Dut::REG_QUEUE_BASE
            + 2 * Dut::REG_QUEUE_STRIDE);
        if (queue_status & 1u) fail("RX queue status incorrectly reported empty");
        if (read32(Dut::REG_QUEUE_BASE + 2 * Dut::REG_QUEUE_STRIDE + 12) != 60) {
            fail("RX front packet length register mismatch");
        }

        // Test 2: an RX ring buffer dispatches the complete queued packet.
        write32(Dut::REG_RX_PRODUCER, 1);
        write32(Dut::REG_CONTROL, Dut::CONTROL_ENABLE);
        expect_command(MASTER_DMA_QUEUE_TO_HOST, 2, 0x300, 60, true, true);
        if (read32(Dut::REG_RX_CONSUMER) != 1) fail("RX consumer did not advance");
        rx_empty[2] = 1;
        rx_count.bits(2 * 16 + 15, 2 * 16) = 0;

        // Test 3: two TX SG entries produce SOP only on the first fragment and
        // EOP only on the final fragment before advancing the TX consumer.
        write_descriptor(Dut::REG_TX_RING_BASE, 0, 0x500, 36, 5, 0);
        write_descriptor(Dut::REG_TX_RING_BASE, 1, 0x704, 44, 5,
            SYSTEM_TX_DESCRIPTOR_EOP);
        if (read32(Dut::REG_TX_RING_BASE + Dut::RING_ENTRY_BYTES + 8)
            != (44u | (5u << 16) | (1u << 24))) {
            fail("TX ring readback mismatch");
        }
        write32(Dut::REG_TX_PRODUCER, 2);
        expect_command(MASTER_DMA_HOST_TO_QUEUE, 5, 0x500, 36, true, false);
        expect_command(MASTER_DMA_HOST_TO_QUEUE, 5, 0x704, 44, false, true);
        if (read32(Dut::REG_TX_CONSUMER) != 2) fail("TX consumer did not advance");
        if (read32(Dut::REG_COMPLETED) != 3) fail("completion count mismatch");
        if (protocol_error_value()) fail("well-formed ring traffic set protocol error");

        std::print("{} Controller {} test {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
#if HOST_AXI4
            "AXI4",
#else
            "Avalon",
#endif
            error ? "FAILED" : "PASSED");
        return !error;
    }
};

static bool build_verilator()
{
#ifdef VERILATOR
    return true;
#else
    namespace fs = std::filesystem;
    fs::path source = fs::absolute(__FILE__);
#if HOST_AXI4
    const char* generated_name = "generated_controller_axi";
    const char* output_name = "Controller_axi_verilator";
    const char* previous_flags = std::getenv("CPPHDL_VERILATOR_CFLAGS");
    std::string verilator_flags = previous_flags ? previous_flags : "";
    verilator_flags += " -DHOST_AXI4=1";
    setenv("CPPHDL_VERILATOR_CFLAGS", verilator_flags.c_str(), 1);
#else
    const char* generated_name = "generated_controller_avalon";
    const char* output_name = "Controller_avalon_verilator";
#endif
    return VerilatorCompileInExactFolderFromGenerated(source.string(), output_name,
        "Controller", fs::current_path() / generated_name, {"SmartNicMemory"},
        {source.parent_path().string(), source.parent_path().parent_path().string(),
            (source.parent_path().parent_path().parent_path() / "common").string(),
            (source.parent_path().parent_path().parent_path().parent_path()
                / "cpphdl" / "include").string()});
#endif
}

} // namespace

int main(int argc, char** argv)
{
#ifdef VERILATOR
    Verilated::commandArgs(argc, argv);
#endif
    bool noveril = false;
    for (int i = 1; i < argc; ++i) noveril |= std::strcmp(argv[i], "--noveril") == 0;
    bool ok = true;
#ifndef VERILATOR
    if (!noveril) {
        ok = build_verilator();
#if HOST_AXI4
        if (ok) ok = std::system("Controller_axi_verilator/obj_dir/VController --noveril") == 0;
#else
        if (ok) ok = std::system("Controller_avalon_verilator/obj_dir/VController --noveril") == 0;
#endif
    }
#endif
    return ControllerTest().run() && ok ? 0 : 1;
}

#endif
