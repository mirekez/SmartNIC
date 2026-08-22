// AXI4 MasterDMA test. It transfers an RxQueue packet
// into simulated host memory, then reads two scatter-gather fragments from
// host memory and verifies their SOP/EOP assembly into one TxQueue packet.

#include "../MasterDMA.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <print>
#include <random>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

namespace
{

using Dma = MasterDMA<HOST_ADDR_WIDTH, 64, 4, 16>;

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

class MasterDmaTest
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    Dma dut;
#endif
    bool command_valid = false;
    bool command_direction = false;
    u<3> command_queue = 0;
    u<HOST_ADDR_WIDTH> command_address = 0;
    u<16> command_length = 0;
    bool command_sop = false;
    bool command_eop = false;
    bool queue_input_valid = false;
    logic<256> queue_input_data = 0;
    logic<32> queue_input_keep = 0;
    bool queue_input_sop = false;
    bool queue_input_eop = false;
    bool queue_output_ready = true;
    std::vector<uint8_t> host_memory = std::vector<uint8_t>(4096, 0);
    std::vector<uint8_t> queue_output;
    uint32_t output_beats = 0;
    uint32_t output_sops = 0;
    uint32_t output_eops = 0;
    std::mt19937 random{0x4d4d4101};
    bool error = false;

    Axi4Responder<4, 64> host = {};
    uint64_t pending_aw = 0;
    bool have_aw = false;
    bool snap_awvalid = false;
    uint64_t snap_awaddr = 0;
    bool snap_wvalid = false;
    logic<64> snap_wdata = 0;
    logic<8> snap_wstrb = 0;
    bool snap_bready = false;
    bool snap_arvalid = false;
    uint64_t snap_araddr = 0;
    bool snap_rready = false;

    void fail(const char* message)
    {
        std::print("{} MasterDMA {}: {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            "AXI4",
            message);
        error = true;
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.command_valid_in = _ASSIGN(command_valid);
        dut.command_direction_in = _ASSIGN(command_direction);
        dut.command_queue_in = _ASSIGN(command_queue);
        dut.command_address_in = _ASSIGN(command_address);
        dut.command_length_in = _ASSIGN(command_length);
        dut.command_sop_in = _ASSIGN(command_sop);
        dut.command_eop_in = _ASSIGN(command_eop);
        dut.queue_input_valid_in = _ASSIGN(queue_input_valid);
        dut.queue_input_data_in = _ASSIGN(queue_input_data);
        dut.queue_input_keep_in = _ASSIGN(queue_input_keep);
        dut.queue_input_sop_in = _ASSIGN(queue_input_sop);
        dut.queue_input_eop_in = _ASSIGN(queue_input_eop);
        dut.queue_output_ready_in = _ASSIGN(queue_output_ready);
        dut.host = host;
        dut.__inst_name = "master_dma";
        dut._assign();
#endif
    }

    void drive_verilator(bool reset, bool clock)
    {
#ifdef VERILATOR
        dut.clk = clock;
        dut.reset = reset;
        dut.command_valid_in = command_valid;
        dut.command_direction_in = command_direction;
        dut.command_queue_in = (uint8_t)(uint32_t)command_queue;
        dut.command_address_in = (uint64_t)command_address;
        dut.command_length_in = (uint16_t)(uint32_t)command_length;
        dut.command_sop_in = command_sop;
        dut.command_eop_in = command_eop;
        dut.queue_input_valid_in = queue_input_valid;
        copy_to_verilator(dut.queue_input_data_in, queue_input_data);
        dut.queue_input_keep_in = (uint32_t)(uint64_t)queue_input_keep;
        dut.queue_input_sop_in = queue_input_sop;
        dut.queue_input_eop_in = queue_input_eop;
        dut.queue_output_ready_in = queue_output_ready;
        dut.host___05Fawready_in = host.aw.ready;
        dut.host___05Fwready_in = host.w.ready;
        dut.host___05Fbvalid_in = host.b.valid;
        dut.host___05Fbid_in = (uint8_t)(uint32_t)host.b.id;
        dut.host___05Farready_in = host.ar.ready;
        dut.host___05Frvalid_in = host.r.valid;
        copy_to_verilator(dut.host___05Frdata_in, host.r.data);
        dut.host___05Frlast_in = host.r.last;
        dut.host___05Frid_in = (uint8_t)(uint32_t)host.r.id;
        dut.eval();
#else
        (void)reset;
        (void)clock;
#endif
    }

#define DMA_VALUE(name) \
    dma_value_##name()
    bool dma_value_command_ready()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.command_ready_out;
#else
        return dut.command_ready_out();
#endif
    }
    bool dma_value_queue_input_ready()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.queue_input_ready_out;
#else
        return dut.queue_input_ready_out();
#endif
    }
    bool dma_value_queue_output_valid()
    {
#ifdef VERILATOR
        drive_verilator(false, false); return dut.queue_output_valid_out;
#else
        return dut.queue_output_valid_out();
#endif
    }
    logic<256> dma_output_data()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<256>>(dut.queue_output_data_out);
#else
        return dut.queue_output_data_out();
#endif
    }
    logic<32> dma_output_keep()
    {
#ifdef VERILATOR
        return logic<32>(dut.queue_output_keep_out);
#else
        return dut.queue_output_keep_out();
#endif
    }
    bool dma_output_sop()
    {
#ifdef VERILATOR
        return dut.queue_output_sop_out;
#else
        return dut.queue_output_sop_out();
#endif
    }
    bool dma_output_eop()
    {
#ifdef VERILATOR
        return dut.queue_output_eop_out;
#else
        return dut.queue_output_eop_out();
#endif
    }
    bool completion_valid()
    {
#ifdef VERILATOR
        return dut.completion_valid_out;
#else
        return dut.completion_valid_out();
#endif
    }
    uint32_t completed_count()
    {
#ifdef VERILATOR
        return dut.completed_count_out;
#else
        return (uint32_t)dut.completed_count_out();
#endif
    }
    bool protocol_error()
    {
#ifdef VERILATOR
        return dut.protocol_error_out;
#else
        return dut.protocol_error_out();
#endif
    }

#define HOST_VALUE(signal) host_value_##signal()
    bool host_value_awvalid()
    {
#ifdef VERILATOR
        return dut.host___05Fawvalid_out;
#else
        return dut.host.awvalid_out();
#endif
    }
    uint64_t host_value_awaddr()
    {
#ifdef VERILATOR
        return dut.host___05Fawaddr_out;
#else
        return (uint64_t)dut.host.awaddr_out();
#endif
    }
    bool host_value_wvalid()
    {
#ifdef VERILATOR
        return dut.host___05Fwvalid_out;
#else
        return dut.host.wvalid_out();
#endif
    }
    logic<64> host_value_wdata()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<64>>(dut.host___05Fwdata_out);
#else
        return dut.host.wdata_out();
#endif
    }
    logic<8> host_value_wstrb()
    {
#ifdef VERILATOR
        return logic<8>(dut.host___05Fwstrb_out);
#else
        return dut.host.wstrb_out();
#endif
    }
    bool host_value_bready()
    {
#ifdef VERILATOR
        return dut.host___05Fbready_out;
#else
        return dut.host.bready_out();
#endif
    }
    bool host_value_arvalid()
    {
#ifdef VERILATOR
        return dut.host___05Farvalid_out;
#else
        return dut.host.arvalid_out();
#endif
    }
    uint64_t host_value_araddr()
    {
#ifdef VERILATOR
        return dut.host___05Faraddr_out;
#else
        return (uint64_t)dut.host.araddr_out();
#endif
    }
    bool host_value_rready()
    {
#ifdef VERILATOR
        return dut.host___05Frready_out;
#else
        return dut.host.rready_out();
#endif
    }

    void update_host_after_edge()
    {
        if (host.b.valid && snap_bready) host.b.valid = false;
        if (host.r.valid && snap_rready) host.r.valid = false;
        if (snap_awvalid && host.aw.ready) {
            pending_aw = snap_awaddr;
            have_aw = true;
        }
        if (snap_wvalid && host.w.ready) {
            if (!have_aw) fail("AXI W arrived without AW");
            for (uint32_t byte = 0; byte < 8; ++byte) {
                if (snap_wstrb[byte] && pending_aw + byte < host_memory.size()) {
                    host_memory[pending_aw + byte] =
                        (uint8_t)snap_wdata.bits(byte * 8 + 7, byte * 8);
                }
            }
            have_aw = false;
            host.b.valid = true;
            host.b.id = 0;
        }
        if (snap_arvalid && host.ar.ready && !host.r.valid) {
            uint64_t address = snap_araddr;
            host.r.data = 0;
            for (uint32_t byte = 0; byte < 8; ++byte) {
                if (address + byte < host_memory.size()) {
                    host.r.data.bits(byte * 8 + 7, byte * 8) =
                        host_memory[address + byte];
                }
            }
            host.r.valid = true;
            host.r.last = true;
            host.r.id = 0;
        }
        host.aw.ready = (random() & 3u) != 0;
        host.w.ready = (random() & 3u) != 0;
        host.ar.ready = (random() & 3u) != 0;
    }

    void sample_host()
    {
        snap_awvalid = HOST_VALUE(awvalid);
        snap_awaddr = HOST_VALUE(awaddr);
        snap_wvalid = HOST_VALUE(wvalid);
        snap_wdata = host_value_wdata();
        snap_wstrb = host_value_wstrb();
        snap_bready = HOST_VALUE(bready);
        snap_arvalid = HOST_VALUE(arvalid);
        snap_araddr = HOST_VALUE(araddr);
        snap_rready = HOST_VALUE(rready);
    }

    void capture_queue_output()
    {
        if (DMA_VALUE(queue_output_valid) && queue_output_ready) {
            logic<256> data = dma_output_data();
            logic<32> keep = dma_output_keep();
            output_sops += dma_output_sop();
            output_eops += dma_output_eop();
            ++output_beats;
            for (uint32_t byte = 0; byte < 32; ++byte) {
                if (keep[byte]) queue_output.push_back(
                    (uint8_t)data.bits(byte * 8 + 7, byte * 8));
            }
        }
    }

    void cycle(bool reset = false)
    {
#ifdef VERILATOR
        drive_verilator(reset, false);
        sample_host();
        capture_queue_output();
        drive_verilator(reset, true);
        update_host_after_edge();
        drive_verilator(reset, false);
#else
        sample_host();
        capture_queue_output();
        dut._work(reset);
        update_host_after_edge();
        dut._strobe();
#endif
        ++_system_clock;
    }

    void issue(bool direction, uint32_t queue, uint32_t address,
        uint32_t length, bool sop, bool eop)
    {
        while (!DMA_VALUE(command_ready)) cycle();
        command_direction = direction;
        command_queue = queue;
        command_address = address;
        command_length = length;
        command_sop = sop;
        command_eop = eop;
        command_valid = true;
        cycle();
        command_valid = false;
    }

    void drive_input_packet(const std::vector<uint8_t>& packet)
    {
        size_t offset = 0;
        while (offset < packet.size()) {
            size_t bytes = std::min<size_t>(32, packet.size() - offset);
            queue_input_data = 0;
            queue_input_keep = 0;
            for (size_t byte = 0; byte < bytes; ++byte) {
                queue_input_data.bits(byte * 8 + 7, byte * 8) = packet[offset + byte];
                queue_input_keep[byte] = 1;
            }
            queue_input_sop = offset == 0;
            queue_input_eop = offset + bytes == packet.size();
            queue_input_valid = true;
            while (!DMA_VALUE(queue_input_ready)) cycle();
            cycle();
            offset += bytes;
        }
        queue_input_valid = false;
        queue_input_sop = false;
        queue_input_eop = false;
    }

    void wait_completion(uint32_t expected)
    {
        for (uint32_t timeout = 0; timeout < 5000
            && completed_count() < expected; ++timeout) cycle();
        if (completed_count() != expected) fail("DMA completion timed out");
    }

public:
    bool run()
    {
        bind_native();
        host.aw.ready = true;
        host.w.ready = true;
        host.ar.ready = true;
        for (int i = 0; i < 4; ++i) cycle(true);

        // Test 1: queue-to-host packet write with a partial final beat.
        std::vector<uint8_t> rx_packet(76);
        for (uint32_t i = 0; i < rx_packet.size(); ++i) rx_packet[i] = i ^ 0xa6;
        issue(MASTER_DMA_QUEUE_TO_HOST, 3, 0x104, rx_packet.size(), true, true);
        drive_input_packet(rx_packet);
        wait_completion(1);
        if (!std::equal(rx_packet.begin(), rx_packet.end(),
                host_memory.begin() + 0x104)) {
            fail("queue-to-host packet write mismatch");
        }

        // Test 2: two host-to-queue SG fragments form one framed packet.
        std::vector<uint8_t> first(36), second(44), expected;
        for (uint32_t i = 0; i < first.size(); ++i) first[i] = 0x20 + i;
        for (uint32_t i = 0; i < second.size(); ++i) second[i] = 0x80 + i;
        std::copy(first.begin(), first.end(), host_memory.begin() + 0x500);
        std::copy(second.begin(), second.end(), host_memory.begin() + 0x704);
        expected = first;
        expected.insert(expected.end(), second.begin(), second.end());
        issue(MASTER_DMA_HOST_TO_QUEUE, 5, 0x500, first.size(), true, false);
        wait_completion(2);
        issue(MASTER_DMA_HOST_TO_QUEUE, 5, 0x704, second.size(), false, true);
        wait_completion(3);
        if (queue_output != expected || output_sops != 1 || output_eops != 1) {
            fail("scatter-gather queue output mismatch");
        }
        if (protocol_error()) fail("well-formed DMA commands set protocol error");

        std::print("{} MasterDMA {} test {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            "AXI4",
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
    const char* generated_name = "generated_master_dma";
    const char* output_name = "MasterDMA_verilator";
    return VerilatorCompileInExactFolderFromGenerated(source.string(), output_name,
        "MasterDMA", fs::current_path() / generated_name, {},
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
        if (ok) ok = std::system("MasterDMA_verilator/obj_dir/VMasterDMA --noveril") == 0;
    }
#endif
    return MasterDmaTest().run() && ok ? 0 : 1;
}

#endif
