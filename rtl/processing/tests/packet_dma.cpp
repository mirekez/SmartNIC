// PacketDMA native C++ and generated-SystemVerilog/Verilator test.  It models
// the coherent 256-bit L2 port and checks all four packet transfer directions.

#include "../PacketDMA.h"

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

using Dma = PacketDMA<16, 14, 8, 32, 4, 256>;

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

class PacketDmaTest
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    Dma dut;
#endif
    Axi4Driver<32, 4, 256> mmio = {};
    Axi4Responder<4, 256> l2 = {};

    bool rx_read_ready = false;
    bool rx_valid = false;
    logic<256> rx_data = 0;
    logic<32> rx_keep = 0;
    bool rx_sop = false;
    bool rx_eop = false;

    bool descriptor_command_valid = false;
    u<16> descriptor_command_handle = 0;
    u<14> descriptor_command_length = 0;
    bool descriptor_command_system = false;

    bool system_rx_valid = false;
    logic<256> system_rx_data = 0;
    logic<32> system_rx_keep = 0;
    bool system_rx_sop = false;
    bool system_rx_eop = false;
    bool system_tx_ready = true;
    bool network_tx_ready = true;

    uint32_t pending_aw = 0;
    bool have_aw = false;
    std::vector<uint8_t> memory = std::vector<uint8_t>(8192, 0);
    std::vector<uint8_t> system_output;
    std::vector<uint8_t> network_output;
    bool system_output_sop = false;
    bool system_output_eop = false;
    bool network_output_sop = false;
    bool network_output_eop = false;
    std::mt19937 random{0x51a7d00d};
    bool error = false;

    void fail(const char* message)
    {
        std::print("{} PacketDMA: {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            message);
        error = true;
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.mmio = mmio;
        dut.l2_dma = l2;
        dut.descriptor_command_valid_in = _ASSIGN(descriptor_command_valid);
        dut.descriptor_command_handle_in = _ASSIGN(descriptor_command_handle);
        dut.descriptor_command_length_in = _ASSIGN(descriptor_command_length);
        dut.descriptor_command_system_in = _ASSIGN(descriptor_command_system);
        dut.rx_read_ready_in = _ASSIGN(rx_read_ready);
        dut.rx_valid_in = _ASSIGN(rx_valid);
        dut.rx_data_in = _ASSIGN(rx_data);
        dut.rx_keep_in = _ASSIGN(rx_keep);
        dut.rx_sop_in = _ASSIGN(rx_sop);
        dut.rx_eop_in = _ASSIGN(rx_eop);
        dut.system_rx_valid_in = _ASSIGN(system_rx_valid);
        dut.system_rx_data_in = _ASSIGN(system_rx_data);
        dut.system_rx_keep_in = _ASSIGN(system_rx_keep);
        dut.system_rx_sop_in = _ASSIGN(system_rx_sop);
        dut.system_rx_eop_in = _ASSIGN(system_rx_eop);
        dut.system_tx_ready_in = _ASSIGN(system_tx_ready);
        dut.network_tx_ready_in = _ASSIGN(network_tx_ready);
        dut.__inst_name = "packet_dma";
        dut._assign();
#endif
    }

    void drive_verilator(bool reset, bool clock)
    {
#ifdef VERILATOR
        dut.clk = clock;
        dut.reset = reset;
        dut.descriptor_command_valid_in = descriptor_command_valid;
        dut.descriptor_command_handle_in = (uint32_t)descriptor_command_handle;
        dut.descriptor_command_length_in =
            (uint32_t)descriptor_command_length;
        dut.descriptor_command_system_in = descriptor_command_system;
        dut.rx_read_ready_in = rx_read_ready;
        dut.rx_valid_in = rx_valid;
        copy_to_verilator(dut.rx_data_in, rx_data);
        dut.rx_keep_in = (uint32_t)(uint64_t)rx_keep;
        dut.rx_sop_in = rx_sop;
        dut.rx_eop_in = rx_eop;
        dut.system_rx_valid_in = system_rx_valid;
        copy_to_verilator(dut.system_rx_data_in, system_rx_data);
        dut.system_rx_keep_in = (uint32_t)(uint64_t)system_rx_keep;
        dut.system_rx_sop_in = system_rx_sop;
        dut.system_rx_eop_in = system_rx_eop;
        dut.system_tx_ready_in = system_tx_ready;
        dut.network_tx_ready_in = network_tx_ready;

        dut.mmio___05Fawvalid_in = mmio.aw.valid;
        dut.mmio___05Fawaddr_in = (uint32_t)mmio.aw.addr;
        dut.mmio___05Fawid_in = (uint8_t)(uint32_t)mmio.aw.id;
        dut.mmio___05Fwvalid_in = mmio.w.valid;
        copy_to_verilator(dut.mmio___05Fwdata_in, mmio.w.data);
        dut.mmio___05Fwstrb_in = (uint32_t)(uint64_t)mmio.w.strb;
        dut.mmio___05Fwlast_in = mmio.w.last;
        dut.mmio___05Fbready_in = mmio.b.ready;
        dut.mmio___05Farvalid_in = mmio.ar.valid;
        dut.mmio___05Faraddr_in = (uint32_t)mmio.ar.addr;
        dut.mmio___05Farid_in = (uint8_t)(uint32_t)mmio.ar.id;
        dut.mmio___05Frready_in = mmio.r.ready;

        dut.l2_dma___05Fawready_in = l2.aw.ready;
        dut.l2_dma___05Fwready_in = l2.w.ready;
        dut.l2_dma___05Fbvalid_in = l2.b.valid;
        dut.l2_dma___05Fbid_in = (uint8_t)(uint32_t)l2.b.id;
        dut.l2_dma___05Farready_in = l2.ar.ready;
        dut.l2_dma___05Frvalid_in = l2.r.valid;
        copy_to_verilator(dut.l2_dma___05Frdata_in, l2.r.data);
        dut.l2_dma___05Frlast_in = l2.r.last;
        dut.l2_dma___05Frid_in = (uint8_t)(uint32_t)l2.r.id;
        dut.eval();
#else
        (void)reset;
        (void)clock;
#endif
    }

    bool l2_awvalid()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Fawvalid_out;
#else
        return dut.l2_dma.awvalid_out();
#endif
    }
    uint32_t l2_awaddr()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Fawaddr_out;
#else
        return (uint32_t)dut.l2_dma.awaddr_out();
#endif
    }
    bool l2_wvalid()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Fwvalid_out;
#else
        return dut.l2_dma.wvalid_out();
#endif
    }
    logic<256> l2_wdata()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<256>>(dut.l2_dma___05Fwdata_out);
#else
        return dut.l2_dma.wdata_out();
#endif
    }
    logic<32> l2_wstrb()
    {
#ifdef VERILATOR
        return logic<32>(dut.l2_dma___05Fwstrb_out);
#else
        return dut.l2_dma.wstrb_out();
#endif
    }
    bool l2_bready()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Fbready_out;
#else
        return dut.l2_dma.bready_out();
#endif
    }
    bool l2_arvalid()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Farvalid_out;
#else
        return dut.l2_dma.arvalid_out();
#endif
    }
    uint32_t l2_araddr()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Faraddr_out;
#else
        return (uint32_t)dut.l2_dma.araddr_out();
#endif
    }
    bool l2_rready()
    {
#ifdef VERILATOR
        return dut.l2_dma___05Frready_out;
#else
        return dut.l2_dma.rready_out();
#endif
    }

    bool system_tx_valid_out()
    {
#ifdef VERILATOR
        return dut.system_tx_valid_out;
#else
        return dut.system_tx_valid_out();
#endif
    }
    logic<256> system_tx_data_out()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<256>>(dut.system_tx_data_out);
#else
        return dut.system_tx_data_out();
#endif
    }
    logic<32> system_tx_keep_out()
    {
#ifdef VERILATOR
        return logic<32>(dut.system_tx_keep_out);
#else
        return dut.system_tx_keep_out();
#endif
    }
    bool system_tx_sop_out()
    {
#ifdef VERILATOR
        return dut.system_tx_sop_out;
#else
        return dut.system_tx_sop_out();
#endif
    }
    bool system_tx_eop_out()
    {
#ifdef VERILATOR
        return dut.system_tx_eop_out;
#else
        return dut.system_tx_eop_out();
#endif
    }
    bool network_tx_valid_out()
    {
#ifdef VERILATOR
        return dut.network_tx_valid_out;
#else
        return dut.network_tx_valid_out();
#endif
    }
    logic<256> network_tx_data_out()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<256>>(dut.network_tx_data_out);
#else
        return dut.network_tx_data_out();
#endif
    }
    logic<32> network_tx_keep_out()
    {
#ifdef VERILATOR
        return logic<32>(dut.network_tx_keep_out);
#else
        return dut.network_tx_keep_out();
#endif
    }
    bool network_tx_sop_out()
    {
#ifdef VERILATOR
        return dut.network_tx_sop_out;
#else
        return dut.network_tx_sop_out();
#endif
    }
    bool network_tx_eop_out()
    {
#ifdef VERILATOR
        return dut.network_tx_eop_out;
#else
        return dut.network_tx_eop_out();
#endif
    }

    static void append_beat(std::vector<uint8_t>& bytes, logic<256> data,
        logic<32> keep)
    {
        for (uint32_t byte = 0; byte < 32; ++byte) {
            if (keep[byte]) {
                bytes.push_back((uint8_t)data.bits(byte * 8 + 7, byte * 8));
            }
        }
    }

    void update_l2_after_edge(bool aw_handshake, uint32_t aw_address,
        bool w_handshake, logic<256> write_data, logic<32> write_strobe,
        bool b_handshake, bool ar_handshake, uint32_t ar_address,
        bool r_handshake)
    {
        if (b_handshake) l2.b.valid = false;
        if (r_handshake) l2.r.valid = false;
        if (aw_handshake) {
            pending_aw = aw_address;
            have_aw = true;
        }
        if (w_handshake) {
            if (!have_aw) fail("AXI write data arrived without an address");
            for (uint32_t byte = 0; byte < 32; ++byte) {
                if (write_strobe[byte]) {
                    if (pending_aw + byte >= memory.size()) {
                        fail("DMA wrote outside test memory");
                    }
                    else {
                        memory[pending_aw + byte] =
                            (uint8_t)write_data.bits(byte * 8 + 7, byte * 8);
                    }
                }
            }
            have_aw = false;
            l2.b.valid = true;
            l2.b.id = 0;
        }
        if (ar_handshake) {
            l2.r.data = 0;
            for (uint32_t byte = 0; byte < 32; ++byte) {
                if (ar_address + byte < memory.size()) {
                    l2.r.data.bits(byte * 8 + 7, byte * 8) =
                        memory[ar_address + byte];
                }
            }
            l2.r.valid = true;
            l2.r.last = true;
            l2.r.id = 0;
        }
        l2.aw.ready = random() % 4 != 0;
        l2.w.ready = random() % 4 != 0;
        l2.ar.ready = random() % 4 != 0;
    }

    void cycle(bool reset = false)
    {
        drive_verilator(reset, false);
        bool aw_handshake = l2_awvalid() && l2.aw.ready;
        bool w_handshake = l2_wvalid() && l2.w.ready;
        bool b_handshake = l2.b.valid && l2_bready();
        bool ar_handshake = l2_arvalid() && l2.ar.ready;
        bool r_handshake = l2.r.valid && l2_rready();
        uint32_t aw_address = l2_awaddr();
        uint32_t ar_address = l2_araddr();
        logic<256> write_data = l2_wdata();
        logic<32> write_strobe = l2_wstrb();

        bool system_handshake = system_tx_valid_out() && system_tx_ready;
        bool network_handshake = network_tx_valid_out() && network_tx_ready;
        if (system_handshake) {
            if (system_tx_sop_out()) system_output_sop = true;
            if (system_tx_eop_out()) system_output_eop = true;
            append_beat(system_output, system_tx_data_out(), system_tx_keep_out());
        }
        if (network_handshake) {
            if (network_tx_sop_out()) network_output_sop = true;
            if (network_tx_eop_out()) network_output_eop = true;
            append_beat(network_output, network_tx_data_out(), network_tx_keep_out());
        }

#ifdef VERILATOR
        drive_verilator(reset, true);
        update_l2_after_edge(aw_handshake, aw_address, w_handshake,
            write_data, write_strobe, b_handshake, ar_handshake, ar_address,
            r_handshake);
        drive_verilator(reset, false);
#else
        dut._work(reset);
        update_l2_after_edge(aw_handshake, aw_address, w_handshake,
            write_data, write_strobe, b_handshake, ar_handshake, ar_address,
            r_handshake);
        dut._strobe();
#endif
        ++_system_clock;
    }

    bool mmio_awready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Fawready_out;
#else
        return dut.mmio.awready_out();
#endif
    }
    bool mmio_wready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Fwready_out;
#else
        return dut.mmio.wready_out();
#endif
    }
    bool mmio_bvalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Fbvalid_out;
#else
        return dut.mmio.bvalid_out();
#endif
    }
    bool mmio_arready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Farready_out;
#else
        return dut.mmio.arready_out();
#endif
    }
    bool mmio_rvalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Frvalid_out;
#else
        return dut.mmio.rvalid_out();
#endif
    }
    logic<256> mmio_rdata()
    {
#ifdef VERILATOR
        return copy_from_verilator<logic<256>>(dut.mmio___05Frdata_out);
#else
        return dut.mmio.rdata_out();
#endif
    }

    void write32(uint32_t address, uint32_t value)
    {
        uint32_t lane = address & 31u;
        mmio.aw.valid = true;
        mmio.aw.addr = address;
        mmio.aw.id = 1;
        mmio.b.ready = true;
        if (!mmio_awready()) fail("MMIO AW not ready");
        cycle();
        mmio.aw.valid = false;
        mmio.w.valid = true;
        mmio.w.data = 0;
        mmio.w.data.bits(lane * 8 + 31, lane * 8) = value;
        mmio.w.strb = 0;
        mmio.w.strb.bits(lane + 3, lane) = 0xf;
        mmio.w.last = true;
        if (!mmio_wready()) fail("MMIO W not ready");
        cycle();
        mmio.w.valid = false;
        if (!mmio_bvalid()) fail("MMIO B not valid");
        cycle();
        mmio.b.ready = false;
    }

    uint32_t read32(uint32_t address)
    {
        uint32_t lane = address & 31u;
        mmio.ar.valid = true;
        mmio.ar.addr = address;
        mmio.ar.id = 2;
        if (!mmio_arready()) fail("MMIO AR not ready");
        cycle();
        mmio.ar.valid = false;
        if (!mmio_rvalid()) {
            fail("MMIO R not valid");
            return 0;
        }
        uint32_t value = (uint32_t)mmio_rdata().bits(lane * 8 + 31, lane * 8);
        mmio.r.ready = true;
        cycle();
        mmio.r.ready = false;
        return value;
    }

    bool read_command_valid()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.rx_read_valid_out;
#else
        return dut.rx_read_valid_out();
#endif
    }
    uint32_t read_handle()
    {
#ifdef VERILATOR
        return dut.rx_read_handle_out;
#else
        return (uint32_t)dut.rx_read_handle_out();
#endif
    }
    uint32_t read_length()
    {
#ifdef VERILATOR
        return dut.rx_read_length_out;
#else
        return (uint32_t)dut.rx_read_length_out();
#endif
    }
    bool rx_ready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.rx_ready_out;
#else
        return dut.rx_ready_out();
#endif
    }
    bool system_rx_ready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.system_rx_ready_out;
#else
        return dut.system_rx_ready_out();
#endif
    }
    bool busy()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.busy_out;
#else
        return dut.busy_out();
#endif
    }
    bool command_ready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.command_ready_out;
#else
        return dut.command_ready_out();
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

    std::vector<uint8_t> make_packet(size_t size)
    {
        std::vector<uint8_t> packet(size);
        for (auto& byte : packet) byte = (uint8_t)random();
        return packet;
    }

    void issue(uint32_t operation, uint32_t length, uint32_t source,
        uint32_t destination, uint32_t handle = 0,
        uint32_t extra_flags = Dma::FLAG_CACHE_ALLOCATE)
    {
        write32(Dma::REG_RX_HANDLE, handle);
        write32(Dma::REG_LENGTH, length);
        write32(Dma::REG_SOURCE, source);
        write32(Dma::REG_DESTINATION, destination);
        write32(Dma::REG_FLAGS, operation | extra_flags);
        write32(Dma::REG_COMMAND, Dma::COMMAND_PUSH);
    }

    void issue_descriptor(uint32_t handle, uint32_t length, bool system)
    {
        if (!command_ready()) fail("descriptor command queue was not ready");
        descriptor_command_handle = handle;
        descriptor_command_length = length;
        descriptor_command_system = system;
        descriptor_command_valid = true;
        cycle();
        descriptor_command_valid = false;
    }

    void send_input(const std::vector<uint8_t>& packet, bool network)
    {
        size_t position = 0;
        bool loaded = false;
        for (uint32_t timeout = 0; timeout < 2000 && busy(); ++timeout) {
            bool ready = network ? rx_ready() : system_rx_ready();
            if (!loaded && position < packet.size()) {
                uint32_t bytes = std::min<size_t>(32, packet.size() - position);
                logic<256>& data = network ? rx_data : system_rx_data;
                logic<32>& keep = network ? rx_keep : system_rx_keep;
                data = 0;
                keep = 0;
                for (uint32_t byte = 0; byte < bytes; ++byte) {
                    data.bits(byte * 8 + 7, byte * 8) = packet[position + byte];
                    keep[byte] = true;
                }
                if (network) {
                    rx_valid = true;
                    rx_sop = position == 0;
                    rx_eop = position + bytes == packet.size();
                }
                else {
                    system_rx_valid = true;
                    system_rx_sop = position == 0;
                    system_rx_eop = position + bytes == packet.size();
                }
                loaded = true;
            }
            ready = network ? rx_ready() : system_rx_ready();
            if (loaded && ready) {
                position += std::min<size_t>(32, packet.size() - position);
                loaded = false;
            }
            cycle();
        }
        rx_valid = false;
        system_rx_valid = false;
        if (busy()) fail("input-to-CPU operation timed out");
        if (position != packet.size()) fail("DMA did not consume the complete input packet");
    }

    void wait_for_output()
    {
        for (uint32_t timeout = 0; timeout < 2000 && busy(); ++timeout) {
            system_tx_ready = random() % 5 != 0;
            network_tx_ready = random() % 5 != 0;
            cycle();
        }
        system_tx_ready = true;
        network_tx_ready = true;
        if (busy()) fail("CPU-to-output operation timed out");
    }

    void check_memory(uint32_t address, const std::vector<uint8_t>& packet,
        const char* message)
    {
        if (!std::equal(packet.begin(), packet.end(), memory.begin() + address)) {
            fail(message);
        }
    }

public:
    bool run()
    {
        bind_native();
        l2.aw.ready = true;
        l2.w.ready = true;
        l2.ar.ready = true;
        for (int i = 0; i < 3; ++i) cycle(true);

        // Network RxRAM -> coherent CPU memory.
        const uint32_t handle = 0x3456;
        const uint32_t network_destination = 0x400;
        auto network_input = make_packet(77);
        issue(DMA_NETWORK_CPU, network_input.size(), 0, network_destination, handle);
        bool command_seen = false;
        for (uint32_t timeout = 0; timeout < 100 && !read_command_valid(); ++timeout) {
            cycle();
        }
        if (read_command_valid()) {
            command_seen = true;
            if (read_handle() != handle || read_length() != network_input.size()) {
                fail("RxRAM read command mismatch");
            }
            rx_read_ready = true;
            cycle();
            rx_read_ready = false;
        }
        send_input(network_input, true);
        if (!command_seen) fail("DMA never issued its RxRAM command");
        check_memory(network_destination, network_input,
            "network-to-CPU payload mismatch");

        // Hardware descriptor command: unselected ingress is drained without
        // consuming coherent L2 bandwidth or changing the packet buffer.
        auto discarded_input = make_packet(73);
        issue_descriptor(handle + 1, discarded_input.size(), false);
        for (uint32_t timeout = 0;
            timeout < 100 && !read_command_valid(); ++timeout) {
            cycle();
        }
        if (!read_command_valid()) fail("descriptor discard never issued RxRAM read");
        else if (read_handle() != handle + 1
            || read_length() != discarded_input.size()) {
            fail("descriptor discard RxRAM command mismatch");
        }
        rx_read_ready = true;
        cycle();
        rx_read_ready = false;
        send_input(discarded_input, true);
        check_memory(network_destination, network_input,
            "descriptor discard modified coherent memory");

        // Hardware descriptor command: selected ingress streams directly to
        // the System queue and observes downstream backpressure.
        auto direct_system_input = make_packet(91);
        system_output.clear();
        system_output_sop = false;
        system_output_eop = false;
        system_tx_ready = false;
        issue_descriptor(handle + 2, direct_system_input.size(), true);
        for (uint32_t timeout = 0;
            timeout < 100 && !read_command_valid(); ++timeout) {
            cycle();
        }
        if (!read_command_valid()) {
            fail("descriptor network-to-system never issued RxRAM read");
        }
        rx_read_ready = true;
        cycle();
        rx_read_ready = false;
        if (rx_ready()) fail("direct System path ignored output backpressure");
        // Advance the native model's per-cycle port cache while ready is low,
        // then release backpressure in a fresh combinational cycle.
        cycle();
        system_tx_ready = true;
        send_input(direct_system_input, true);
        if (system_output != direct_system_input) {
            std::print(stderr,
                "direct System size mismatch: expected={} received={}\n",
                direct_system_input.size(), system_output.size());
            const size_t compared = std::min(
                direct_system_input.size(), system_output.size());
            for (size_t byte = 0; byte < compared; ++byte) {
                if (system_output[byte] != direct_system_input[byte]) {
                    std::print(stderr,
                        "first direct System mismatch at byte {}: expected={:#04x} received={:#04x}\n",
                        byte, direct_system_input[byte], system_output[byte]);
                    break;
                }
            }
            fail("descriptor network-to-system payload mismatch");
        }
        if (!system_output_sop || !system_output_eop) {
            fail("descriptor network-to-system framing mismatch");
        }

        // System TxQueue -> coherent CPU memory.
        const uint32_t system_destination = 0x800;
        auto system_input = make_packet(95);
        issue(DMA_SYSTEM_CPU, system_input.size(), 0, system_destination);
        send_input(system_input, false);
        check_memory(system_destination, system_input,
            "system-to-CPU payload mismatch");

        // Coherent CPU memory -> System RxQueue.
        const uint32_t system_source = 0xc00;
        auto to_system = make_packet(61);
        std::copy(to_system.begin(), to_system.end(), memory.begin() + system_source);
        system_output.clear();
        system_output_sop = false;
        system_output_eop = false;
        issue(DMA_CPU_SYSTEM, to_system.size(), system_source, 0);
        wait_for_output();
        if (system_output != to_system) fail("CPU-to-system payload mismatch");
        if (!system_output_sop || !system_output_eop) {
            fail("CPU-to-system framing mismatch");
        }

        // Coherent CPU memory -> Network TxFIFO.
        const uint32_t network_source = 0x1000;
        auto to_network = make_packet(128);
        std::copy(to_network.begin(), to_network.end(), memory.begin() + network_source);
        network_output.clear();
        network_output_sop = false;
        network_output_eop = false;
        issue(DMA_CPU_NETWORK, to_network.size(), network_source, 0);
        wait_for_output();
        if (network_output != to_network) fail("CPU-to-network payload mismatch");
        if (!network_output_sop || !network_output_eop) {
            fail("CPU-to-network framing mismatch");
        }

        if (read32(Dma::REG_COMPLETED) != 6) fail("completion count mismatch");
        if (read32(Dma::REG_LAST_OPERATION) != DMA_CPU_NETWORK) {
            fail("last operation register mismatch");
        }
        if (protocol_error()) fail("valid transfers set protocol error");

        std::print("{} PacketDMA four-direction test {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
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
    fs::path generated = fs::current_path() / "generated_packet_dma";
    std::vector<std::string> includes = {
        source.parent_path().string(),
        source.parent_path().parent_path().string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "include").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu" / "common").string()};
    return VerilatorCompileInExactFolderFromGenerated(source.string(),
        "PacketDMA_verilator", "PacketDMA", generated, {"PacketDMA"}, includes,
        16, 14, 8, 32, 4, 256);
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
        if (ok) ok = std::system("PacketDMA_verilator/obj_dir/VPacketDMA --noveril") == 0;
    }
#endif
    return PacketDmaTest().run() && ok ? 0 : 1;
}

#endif
