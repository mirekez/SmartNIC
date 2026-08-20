// CPU native C++ and generated-SystemVerilog/Verilator test.  Four Tribe cores
// fetch a tiny RV32 program from the external general-memory region; the
// program writes 0x5a to uncached IOMEM, proving both region routes and the
// minimum executable CPU/L1/shared-L2 subsystem.

#include "../CPU.h"

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

namespace
{

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

class CpuTest
{
#ifdef VERILATOR
    VERILATOR_MODEL dut;
#else
    CPU dut;
#endif
    Axi4Responder<4, 256> memory_bus = {};
    Axi4Responder<4, 256> iomem_bus = {};
    std::vector<uint8_t> memory = std::vector<uint8_t>(4096, 0);
    uint32_t memory_aw = 0;
    uint32_t iomem_aw = 0;
    bool memory_have_aw = false;
    bool iomem_have_aw = false;
    bool saw_iomem_write = false;
    uint32_t iomem_value = 0;
    bool error = false;

    void fail(const char* message)
    {
        std::print("{} CPU: {}\n",
#ifdef VERILATOR
            "Verilator",
#else
            "CppHDL C++",
#endif
            message);
        error = true;
    }

    void install_program()
    {
        // lui t0,0x40000; addi t1,zero,0x5a; sw t1,0(t0); jal zero,0
        const uint32_t program[] = {
            0x400002b7u, 0x05a00313u, 0x0062a023u, 0x0000006fu};
        std::memcpy(memory.data(), program, sizeof(program));
    }

    void bind_native()
    {
#ifndef VERILATOR
        dut.memory = memory_bus;
        dut.iomem = iomem_bus;
        dut.reset_pc_in = _ASSIGN((u32)0);
        dut.boot_hartid_in = _ASSIGN((u32)0);
        dut.boot_dtb_addr_in = _ASSIGN((u32)0);
        dut.boot_priv_in = _ASSIGN((u<2>)3);
        dut.cache_invalidate_in = _ASSIGN(false);
        for (uint32_t core = 0; core < CPU::CORES; ++core) {
            dut.software_irq_in[core] = _ASSIGN(false);
            dut.timer_irq_in[core] = _ASSIGN(false);
            dut.external_irq_in[core] = _ASSIGN(false);
        }
        dut.dma_in.awvalid_in = _ASSIGN(false);
        dut.dma_in.awaddr_in = _ASSIGN((u<32>)0);
        dut.dma_in.awid_in = _ASSIGN((u<4>)0);
        dut.dma_in.wvalid_in = _ASSIGN(false);
        dut.dma_in.wdata_in = _ASSIGN((logic<256>)0);
        dut.dma_in.wstrb_in = _ASSIGN((logic<32>)0);
        dut.dma_in.wlast_in = _ASSIGN(false);
        dut.dma_in.bready_in = _ASSIGN(false);
        dut.dma_in.arvalid_in = _ASSIGN(false);
        dut.dma_in.araddr_in = _ASSIGN((u<32>)0);
        dut.dma_in.arid_in = _ASSIGN((u<4>)0);
        dut.dma_in.rready_in = _ASSIGN(false);
        dut.__inst_name = "cpu";
        dut._assign();
#endif
    }

    void drive_verilator(bool reset, bool clock, bool l2_clock)
    {
#ifdef VERILATOR
        dut.clk = clock;
        dut.l2_clock = l2_clock;
        dut.reset = reset;
        dut.reset_pc_in = 0;
        dut.boot_hartid_in = 0;
        dut.boot_dtb_addr_in = 0;
        dut.boot_priv_in = 3;
        dut.cache_invalidate_in = false;
        for (uint32_t core = 0; core < CPU::CORES; ++core) {
            dut.software_irq_in[core] = 0;
            dut.timer_irq_in[core] = 0;
            dut.external_irq_in[core] = 0;
        }

        dut.dma_in___05Fawvalid_in = false;
        dut.dma_in___05Fawaddr_in = 0;
        dut.dma_in___05Fawid_in = 0;
        dut.dma_in___05Fwvalid_in = false;
        copy_to_verilator(dut.dma_in___05Fwdata_in, logic<256>(0));
        dut.dma_in___05Fwstrb_in = 0;
        dut.dma_in___05Fwlast_in = false;
        dut.dma_in___05Fbready_in = false;
        dut.dma_in___05Farvalid_in = false;
        dut.dma_in___05Faraddr_in = 0;
        dut.dma_in___05Farid_in = 0;
        dut.dma_in___05Frready_in = false;

        dut.memory___05Fawready_in = memory_bus.aw.ready;
        dut.memory___05Fwready_in = memory_bus.w.ready;
        dut.memory___05Fbvalid_in = memory_bus.b.valid;
        dut.memory___05Fbid_in = (uint8_t)(uint32_t)memory_bus.b.id;
        dut.memory___05Farready_in = memory_bus.ar.ready;
        dut.memory___05Frvalid_in = memory_bus.r.valid;
        copy_to_verilator(dut.memory___05Frdata_in, memory_bus.r.data);
        dut.memory___05Frlast_in = memory_bus.r.last;
        dut.memory___05Frid_in = (uint8_t)(uint32_t)memory_bus.r.id;

        dut.iomem___05Fawready_in = iomem_bus.aw.ready;
        dut.iomem___05Fwready_in = iomem_bus.w.ready;
        dut.iomem___05Fbvalid_in = iomem_bus.b.valid;
        dut.iomem___05Fbid_in = (uint8_t)(uint32_t)iomem_bus.b.id;
        dut.iomem___05Farready_in = iomem_bus.ar.ready;
        dut.iomem___05Frvalid_in = iomem_bus.r.valid;
        copy_to_verilator(dut.iomem___05Frdata_in, iomem_bus.r.data);
        dut.iomem___05Frlast_in = iomem_bus.r.last;
        dut.iomem___05Frid_in = (uint8_t)(uint32_t)iomem_bus.r.id;
        dut.eval();
#else
        (void)reset;
        (void)clock;
        (void)l2_clock;
#endif
    }

#define CPU_MASTER_ACCESSORS(prefix) \
    bool prefix##_awvalid() { \
        /* NOLINTNEXTLINE */ \
        return CPU_MASTER_VALUE(prefix, awvalid_out); \
    } \
    uint32_t prefix##_awaddr() { return CPU_MASTER_VALUE(prefix, awaddr_out); } \
    bool prefix##_wvalid() { return CPU_MASTER_VALUE(prefix, wvalid_out); } \
    logic<256> prefix##_wdata() { return CPU_MASTER_WIDE(prefix, wdata_out, 256); } \
    logic<32> prefix##_wstrb() { return CPU_MASTER_WIDE(prefix, wstrb_out, 32); } \
    bool prefix##_bready() { return CPU_MASTER_VALUE(prefix, bready_out); } \
    bool prefix##_arvalid() { return CPU_MASTER_VALUE(prefix, arvalid_out); } \
    uint32_t prefix##_araddr() { return CPU_MASTER_VALUE(prefix, araddr_out); } \
    uint32_t prefix##_arid() { return CPU_MASTER_VALUE(prefix, arid_out); } \
    bool prefix##_rready() { return CPU_MASTER_VALUE(prefix, rready_out); }

#ifdef VERILATOR
#define CPU_MASTER_VALUE(prefix, signal) dut.prefix##___05F##signal
#define CPU_MASTER_WIDE(prefix, signal, width) \
    copy_from_verilator<logic<width>>(dut.prefix##___05F##signal)
#else
#define CPU_MASTER_VALUE(prefix, signal) dut.prefix.signal()
#define CPU_MASTER_WIDE(prefix, signal, width) dut.prefix.signal()
#endif
    CPU_MASTER_ACCESSORS(memory)
    CPU_MASTER_ACCESSORS(iomem)
#undef CPU_MASTER_ACCESSORS
#undef CPU_MASTER_VALUE
#undef CPU_MASTER_WIDE

    void update_target(Axi4Responder<4, 256>& bus, bool awvalid,
        uint32_t awaddr, bool wvalid, logic<256> wdata, logic<32> wstrb,
        bool bready, bool arvalid, uint32_t araddr, uint32_t arid,
        bool rready, bool iomem)
    {
        uint32_t& saved_aw = iomem ? iomem_aw : memory_aw;
        bool& have_aw = iomem ? iomem_have_aw : memory_have_aw;
        if (bus.b.valid && bready) bus.b.valid = false;
        if (bus.r.valid && rready) bus.r.valid = false;
        if (awvalid && bus.aw.ready) {
            saved_aw = awaddr;
            have_aw = true;
        }
        if (wvalid && bus.w.ready) {
            if (!have_aw) fail("write data arrived before write address");
            if (iomem) {
                iomem_value = (uint32_t)wdata.bits(31, 0);
                saw_iomem_write = true;
            }
            else {
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    if (wstrb[byte] && saved_aw + byte < memory.size()) {
                        memory[saved_aw + byte] =
                            (uint8_t)wdata.bits(byte * 8 + 7, byte * 8);
                    }
                }
            }
            have_aw = false;
            bus.b.valid = true;
            bus.b.id = 0;
        }
        if (arvalid && bus.ar.ready && !bus.r.valid) {
            bus.r.data = 0;
            if (!iomem) {
                for (uint32_t byte = 0; byte < 32; ++byte) {
                    if (araddr + byte < memory.size()) {
                        bus.r.data.bits(byte * 8 + 7, byte * 8) =
                            memory[araddr + byte];
                    }
                }
            }
            bus.r.valid = true;
            bus.r.last = true;
            bus.r.id = arid;
        }
    }

    void update_buses()
    {
        update_target(memory_bus, memory_awvalid(), memory_awaddr(),
            memory_wvalid(), memory_wdata(), memory_wstrb(),
            memory_bready(), memory_arvalid(), memory_araddr(),
            memory_arid(), memory_rready(), false);
        update_target(iomem_bus, iomem_awvalid(), iomem_awaddr(),
            iomem_wvalid(), iomem_wdata(), iomem_wstrb(),
            iomem_bready(), iomem_arvalid(), iomem_araddr(),
            iomem_arid(), iomem_rready(), true);
    }

    void cycle(bool reset, bool l2_edge)
    {
#ifdef VERILATOR
        drive_verilator(reset, false, false);
        update_buses();
        drive_verilator(reset, true, false);
        drive_verilator(reset, false, false);
        if (l2_edge) {
            drive_verilator(reset, false, true);
            drive_verilator(reset, false, false);
        }
#else
        dut._work(reset);
        update_buses();
        dut._strobe();
        if (l2_edge) {
            dut._work_l2_clock(reset);
            dut._strobe_l2_clock();
        }
#endif
        ++_system_clock;
    }

public:
    bool run()
    {
        static_assert(CPU::MEMORY_BYTES == CPU_MEMORY);
        static_assert(CPU::CORES == 4);
        static_assert(CPU::DATA_WIDTH == 256);
        bind_native();
        install_program();
        memory_bus.aw.ready = true;
        memory_bus.w.ready = true;
        memory_bus.ar.ready = true;
        iomem_bus.aw.ready = true;
        iomem_bus.w.ready = true;
        iomem_bus.ar.ready = true;

        for (uint32_t tick = 0; tick < 32; ++tick) cycle(true, tick % 4 == 0);
        for (uint32_t tick = 0; tick < 20000 && !saw_iomem_write; ++tick) {
            cycle(false, tick % 4 == 0);
        }
        if (!saw_iomem_write) fail("test program did not reach the IOMEM region");
        if (iomem_value != 0x5a) fail("test program wrote the wrong IOMEM value");

        std::print("{} CPU test {}\n",
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
    fs::path generated = fs::current_path() / "generated_cpu";
    std::vector<std::string> includes = {
        source.parent_path().string(),
        source.parent_path().parent_path().string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "include").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu" / "common").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu" / "spec").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu" / "cache").string(),
        (source.parent_path().parent_path().parent_path().parent_path()
            / "cpphdl" / "tribe_cpu" / "devices").string()};
    std::vector<std::string> modules = {"FileStorage", "File", "RAM", "L1Cache",
        "Axi4SlowToFastCdc", "Axi4FastToSlowCdc", "L1MemFastToSlowCdc",
        "L2CacheRamBank", "L2Cache", "Tribe", "BranchPredictor", "InterruptController",
        "Decode", "Execute", "ExecuteMem", "CSR", "MMU_TLB",
        "Writeback", "WritebackMem", "TribeTest"};
    return VerilatorCompileInExactFolderFromGenerated(source.string(),
        "CPU_verilator", "CPU", generated, modules, includes);
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
        if (ok) ok = std::system("CPU_verilator/obj_dir/VCPU --noveril") == 0;
    }
#endif
    return CpuTest().run() && ok ? 0 : 1;
}

#endif
