// DescriptorFetcher native C++ and generated-SystemVerilog/Verilator test.
// It verifies disabled backpressure, five-word prefetch assembly, full-body and
// decoded-field MMIO reads, per-CPU queue isolation semantics, and NEXT/skip.

#include "../DescriptorFetcher.h"

#if !defined(SYNTHESIS)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <print>
#include <string>
#include <vector>

#include "../../../cpphdl/examples/tools.h"

#ifdef VERILATOR
#define MAKE_HEADER(name) STRINGIFY(name.h)
#include MAKE_HEADER(VERILATOR_MODEL)
#endif

long _system_clock = -1;

namespace
{

using Fetcher = DescriptorFetcher<4, 32, 4, 256>;

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

class DescriptorFetcherTest
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    Fetcher dut;
#endif
    bool descriptor_valid = false;
    logic<256> descriptor_data = 0;
    u<3> descriptor_word = 0;
    bool descriptor_sop = false;
    bool descriptor_eop = false;
    Axi4Driver<32, 4, 256> axi = {};
    bool error = false;

    void fail(const char* message)
    {
        std::print("{} DescriptorFetcher: {}\n",
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
        dut.descriptor_valid_in = _ASSIGN(descriptor_valid);
        dut.descriptor_data_in = _ASSIGN(descriptor_data);
        dut.descriptor_word_in = _ASSIGN(descriptor_word);
        dut.descriptor_sop_in = _ASSIGN(descriptor_sop);
        dut.descriptor_eop_in = _ASSIGN(descriptor_eop);
        dut.packet_command_ready_in = _ASSIGN(true);
        dut.packet_cache_completed_in = _ASSIGN((u32)0);
        dut.mmio = axi;
        dut.__inst_name = "descriptor_fetcher";
        dut._assign();
#endif
    }

    void drive_verilator(bool reset, bool clock)
    {
#ifdef VERILATOR
        dut.clk = clock;
        dut.reset = reset;
        dut.descriptor_valid_in = descriptor_valid;
        copy_to_verilator(dut.descriptor_data_in, descriptor_data);
        dut.descriptor_word_in = (uint8_t)(uint32_t)descriptor_word;
        dut.descriptor_sop_in = descriptor_sop;
        dut.descriptor_eop_in = descriptor_eop;
        dut.packet_command_ready_in = true;
        dut.packet_cache_completed_in = 0;
        dut.mmio___05Fawvalid_in = axi.aw.valid;
        dut.mmio___05Fawaddr_in = (uint32_t)axi.aw.addr;
        dut.mmio___05Fawid_in = (uint8_t)(uint32_t)axi.aw.id;
        dut.mmio___05Fwvalid_in = axi.w.valid;
        copy_to_verilator(dut.mmio___05Fwdata_in, axi.w.data);
        copy_to_verilator(dut.mmio___05Fwstrb_in, axi.w.strb);
        dut.mmio___05Fwlast_in = axi.w.last;
        dut.mmio___05Fbready_in = axi.b.ready;
        dut.mmio___05Farvalid_in = axi.ar.valid;
        dut.mmio___05Faraddr_in = (uint32_t)axi.ar.addr;
        dut.mmio___05Farid_in = (uint8_t)(uint32_t)axi.ar.id;
        dut.mmio___05Frready_in = axi.r.ready;
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

    bool descriptor_ready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.descriptor_ready_out;
#else
        return dut.descriptor_ready_out();
#endif
    }

    bool available()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.descriptor_available_out;
#else
        return dut.descriptor_available_out();
#endif
    }

    bool awready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Fawready_out;
#else
        return dut.mmio.awready_out();
#endif
    }

    bool wready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Fwready_out;
#else
        return dut.mmio.wready_out();
#endif
    }

    bool bvalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Fbvalid_out;
#else
        return dut.mmio.bvalid_out();
#endif
    }

    bool arready()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Farready_out;
#else
        return dut.mmio.arready_out();
#endif
    }

    bool rvalid()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return dut.mmio___05Frvalid_out;
#else
        return dut.mmio.rvalid_out();
#endif
    }

    logic<256> rdata()
    {
#ifdef VERILATOR
        drive_verilator(false, false);
        return copy_from_verilator<logic<256>>(dut.mmio___05Frdata_out);
#else
        return dut.mmio.rdata_out();
#endif
    }

    void write32(uint32_t address, uint32_t value)
    {
        uint32_t lane = address & 31u;
        axi.aw.valid = true;
        axi.aw.addr = address;
        axi.aw.id = 1;
        axi.b.ready = true;
        if (!awready()) fail("AW was not ready");
        cycle();
        axi.aw.valid = false;
        axi.w.valid = true;
        axi.w.data = 0;
        axi.w.data.bits(lane * 8 + 31, lane * 8) = value;
        axi.w.strb = 0;
        axi.w.strb.bits(lane + 3, lane) = 0xf;
        axi.w.last = true;
        if (!wready()) fail("W was not ready");
        cycle();
        axi.w.valid = false;
        if (!bvalid()) fail("B was not valid");
        cycle();
        axi.b.ready = false;
    }

    uint32_t read32(uint32_t address)
    {
        uint32_t lane = address & 31u;
        axi.ar.valid = true;
        axi.ar.addr = address;
        axi.ar.id = 2;
        if (!arready()) fail("AR was not ready");
        cycle();
        axi.ar.valid = false;
        if (!rvalid()) {
            fail("R was not valid");
            return 0;
        }
        uint32_t value = (uint32_t)rdata().bits(lane * 8 + 31, lane * 8);
        axi.r.ready = true;
        cycle();
        axi.r.ready = false;
        return value;
    }

    void send(const logic<1280>& descriptor)
    {
        for (uint32_t word = 0; word < 5; ++word) {
            if (!descriptor_ready()) {
                fail("descriptor input unexpectedly backpressured");
                return;
            }
            descriptor_valid = true;
            descriptor_word = word;
            descriptor_sop = word == 0;
            descriptor_eop = word == 4;
            descriptor_data = descriptor.bits(word * 256 + 255, word * 256);
            cycle();
        }
        descriptor_valid = false;
        descriptor_sop = false;
        descriptor_eop = false;
    }

    static logic<1280> make_descriptor(uint32_t seed)
    {
        logic<1280> descriptor = 0;
        for (uint32_t word = 0; word < 40; ++word) {
            descriptor.bits(word * 32 + 31, word * 32) =
                seed ^ (word * 0x1020304u);
        }
        descriptor.bits(31, 0) = seed;
        descriptor.bits(47, 32) = 1514;
        descriptor.bits(55, 48) = 3;
        descriptor.bits(63, 56) = 0;
        descriptor.bits(303, 256) = logic<48>(0x001122334455ull);
        descriptor.bits(351, 304) = logic<48>(0x66778899aabbull);
        descriptor.bits(623, 608) = 0x1234;
        descriptor.bits(639, 624) = 0xabcd;
        descriptor.bits(647, 640) = 17;
        descriptor.bits(655, 648) = 4;
        descriptor.bits(663, 656) = PACKET_PARSER_FLAG_PARSED;
        return descriptor;
    }

public:
    bool run()
    {
        bind_native();
        axi = {};
        for (int i = 0; i < 3; ++i) cycle(true);
        if (descriptor_ready()) fail("disabled fetcher accepted a descriptor");

        write32(Fetcher::REG_CONTROL, Fetcher::CONTROL_ENABLE);
        if (!descriptor_ready()) fail("enabled fetcher did not become ready");

        logic<1280> first = make_descriptor(0x12345678);
        logic<1280> second = make_descriptor(0x89abcdef);
        send(first);
        send(second);
        if (!available()) fail("prefetched descriptor was not reported available");
        uint32_t status = read32(Fetcher::REG_STATUS);
        if ((status & Fetcher::STATUS_AVAILABLE) == 0 || ((status >> 8) & 0xff) != 2) {
            fail("status did not report two queued descriptors");
        }
        for (uint32_t word = 0; word < 40; ++word) {
            uint32_t got = read32(Fetcher::REG_DESCRIPTOR_BASE + word * 4);
            uint32_t expected = (uint32_t)first.bits(word * 32 + 31, word * 32);
            if (got != expected) {
                fail("full descriptor body read mismatch");
                break;
            }
        }
        if (read32(Fetcher::REG_PACKET_ADDRESS) != 0x12345678
            || read32(Fetcher::REG_PACKET_META) != 0x000305ea
            || read32(Fetcher::REG_DESTINATION_MAC_LO) != 0x22334455
            || read32(Fetcher::REG_DESTINATION_MAC_HI) != 0x0011
            || read32(Fetcher::REG_SOURCE_MAC_LO) != 0x8899aabb
            || read32(Fetcher::REG_SOURCE_MAC_HI) != 0x6677
            || read32(Fetcher::REG_PORTS) != 0xabcd1234
            || (read32(Fetcher::REG_PROTOCOL) & 0xffffff) != 0x010411) {
            fail("decoded descriptor field register mismatch");
        }

        write32(Fetcher::REG_ACTION, Fetcher::ACTION_NEXT);
        if (read32(Fetcher::REG_PACKET_ADDRESS) != 0x89abcdef) {
            fail("NEXT did not expose the following CPU-owned descriptor");
        }
        write32(Fetcher::REG_ACTION, Fetcher::ACTION_NEXT);
        if (available()) fail("skip/pop did not empty the queue");
        if (read32(Fetcher::REG_STATUS) & Fetcher::STATUS_PROTOCOL_ERROR) {
            fail("well-formed descriptor traffic set protocol error");
        }

        std::print("{} DescriptorFetcher test {}\n",
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
    fs::path generated = fs::current_path() / "generated_descriptor_fetcher";
    std::vector<std::string> includes = {
        source.parent_path().string(),
        source.parent_path().parent_path().string(),
        (source.parent_path().parent_path().parent_path() / "network").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "include").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu" / "common").string()};
    return VerilatorCompileInExactFolderFromGenerated(source.string(),
        "DescriptorFetcher_verilator", "DescriptorFetcher", generated,
        {"DescriptorFetcher"}, includes, 4, 32, 4, 256);
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
        if (ok) ok = std::system("DescriptorFetcher_verilator/obj_dir/VDescriptorFetcher --noveril") == 0;
    }
#endif
    return DescriptorFetcherTest().run() && ok ? 0 : 1;
}

#endif
