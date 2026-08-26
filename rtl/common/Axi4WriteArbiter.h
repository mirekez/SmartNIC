#pragma once

// Two-input AXI4 arbiter used on each CPU DDR port. The ordinary Tribe/L2
// master and the packet ring master may both read or write. Transactions are
// serialized from address through response so neither master's split AXI
// channels can be attributed to the other.

#include "Axi4Master.h"

using namespace cpphdl;

enum Axi4WriteArbiterState : uint8_t
{
    AXI4_ARB_IDLE,
    AXI4_ARB_WRITE_DATA,
    AXI4_ARB_WRITE_RESPONSE,
    AXI4_ARB_READ_DATA
};

template<size_t ADDR_WIDTH, size_t ID_WIDTH, size_t DATA_WIDTH>
class Axi4WriteArbiter : public Module
{
public:
    // Inputs are target-shaped because each is driven by an AXI master.
    Axi4If<ADDR_WIDTH, ID_WIDTH, DATA_WIDTH> cpu;
    Axi4If<ADDR_WIDTH, ID_WIDTH, DATA_WIDTH> packet;
    Axi4MasterIf<ADDR_WIDTH, ID_WIDTH, DATA_WIDTH> memory;

private:
    reg<u<2>> state_reg;
    reg<u1> packet_owner_reg;

    bool packet_aw_selected()
    {
        return (uint32_t)state_reg == AXI4_ARB_IDLE
            && !cpu.arvalid_in() && !packet.arvalid_in()
            && !cpu.awvalid_in()
            && packet.awvalid_in();
    }

    bool cpu_aw_selected()
    {
        return (uint32_t)state_reg == AXI4_ARB_IDLE
            && !cpu.arvalid_in() && !packet.arvalid_in()
            && cpu.awvalid_in();
    }

    bool cpu_ar_selected()
    {
        return (uint32_t)state_reg == AXI4_ARB_IDLE
            && cpu.arvalid_in();
    }

    bool packet_ar_selected()
    {
        return (uint32_t)state_reg == AXI4_ARB_IDLE
            && !cpu.arvalid_in() && packet.arvalid_in();
    }

public:
    void _assign()
    {
        memory.awvalid_out = _ASSIGN(packet_aw_selected()
            || cpu_aw_selected());
        memory.awaddr_out = _ASSIGN(packet_aw_selected()
            ? (u<ADDR_WIDTH>)packet.awaddr_in()
            : (u<ADDR_WIDTH>)cpu.awaddr_in());
        memory.awid_out = _ASSIGN(packet_aw_selected()
            ? (u<ID_WIDTH>)packet.awid_in()
            : (u<ID_WIDTH>)cpu.awid_in());
        memory.wvalid_out = _ASSIGN((packet_aw_selected()
                && packet.wvalid_in())
            || ((uint32_t)state_reg == AXI4_ARB_WRITE_DATA
                && ((bool)packet_owner_reg
                    ? packet.wvalid_in() : cpu.wvalid_in())));
        memory.wdata_out = _ASSIGN(packet_aw_selected()
                || (bool)packet_owner_reg
            ? (logic<DATA_WIDTH>)packet.wdata_in()
            : (logic<DATA_WIDTH>)cpu.wdata_in());
        memory.wstrb_out = _ASSIGN(packet_aw_selected()
                || (bool)packet_owner_reg
            ? (logic<DATA_WIDTH / 8>)packet.wstrb_in()
            : (logic<DATA_WIDTH / 8>)cpu.wstrb_in());
        memory.wlast_out = _ASSIGN(packet_aw_selected()
                || (bool)packet_owner_reg
            ? packet.wlast_in() : cpu.wlast_in());
        memory.bready_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_WRITE_RESPONSE
            && ((bool)packet_owner_reg
                ? packet.bready_in() : cpu.bready_in()));
        memory.arvalid_out = _ASSIGN(cpu_ar_selected()
            || packet_ar_selected());
        memory.araddr_out = _ASSIGN(packet_ar_selected()
            ? (u<ADDR_WIDTH>)packet.araddr_in()
            : (u<ADDR_WIDTH>)cpu.araddr_in());
        memory.arid_out = _ASSIGN(packet_ar_selected()
            ? (u<ID_WIDTH>)packet.arid_in()
            : (u<ID_WIDTH>)cpu.arid_in());
        memory.rready_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_READ_DATA
            && ((bool)packet_owner_reg
                ? packet.rready_in() : cpu.rready_in()));

        packet.awready_out = _ASSIGN(packet_aw_selected()
            && memory.awready_in());
        cpu.awready_out = _ASSIGN(cpu_aw_selected()
            && memory.awready_in());
        packet.wready_out = _ASSIGN((packet_aw_selected()
                || ((uint32_t)state_reg == AXI4_ARB_WRITE_DATA
                    && (bool)packet_owner_reg))
            && memory.wready_in());
        cpu.wready_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_WRITE_DATA && !(bool)packet_owner_reg
            && memory.wready_in());
        packet.bvalid_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_WRITE_RESPONSE && (bool)packet_owner_reg
            && memory.bvalid_in());
        cpu.bvalid_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_WRITE_RESPONSE && !(bool)packet_owner_reg
            && memory.bvalid_in());
        packet.bid_out = _ASSIGN((u<ID_WIDTH>)memory.bid_in());
        cpu.bid_out = _ASSIGN((u<ID_WIDTH>)memory.bid_in());
        packet.arready_out = _ASSIGN(packet_ar_selected()
            && memory.arready_in());
        cpu.arready_out = _ASSIGN(cpu_ar_selected()
            && memory.arready_in());
        packet.rvalid_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_READ_DATA && (bool)packet_owner_reg
            && memory.rvalid_in());
        packet.rdata_out = _ASSIGN((logic<DATA_WIDTH>)memory.rdata_in());
        packet.rlast_out = _ASSIGN(memory.rlast_in());
        packet.rid_out = _ASSIGN((u<ID_WIDTH>)memory.rid_in());
        cpu.rvalid_out = _ASSIGN((uint32_t)state_reg
            == AXI4_ARB_READ_DATA && !(bool)packet_owner_reg
            && memory.rvalid_in());
        cpu.rdata_out = _ASSIGN((logic<DATA_WIDTH>)memory.rdata_in());
        cpu.rlast_out = _ASSIGN(memory.rlast_in());
        cpu.rid_out = _ASSIGN((u<ID_WIDTH>)memory.rid_in());
    }

    void _work(bool reset)
    {
        if ((uint32_t)state_reg == AXI4_ARB_IDLE) {
            if (cpu.arvalid_in() && cpu.arready_out()) {
                packet_owner_reg._next = false;
                state_reg._next = AXI4_ARB_READ_DATA;
            }
            else if (packet.arvalid_in() && packet.arready_out()) {
                packet_owner_reg._next = true;
                state_reg._next = AXI4_ARB_READ_DATA;
            }
            else if (cpu.awvalid_in() && cpu.awready_out()) {
                packet_owner_reg._next = false;
                state_reg._next = AXI4_ARB_WRITE_DATA;
            }
            else if (packet.awvalid_in() && packet.awready_out()) {
                packet_owner_reg._next = true;
                state_reg._next = packet.wvalid_in()
                        && packet.wready_out()
                    ? AXI4_ARB_WRITE_RESPONSE : AXI4_ARB_WRITE_DATA;
            }
        }
        else if ((uint32_t)state_reg == AXI4_ARB_WRITE_DATA
            && memory.wvalid_out() && memory.wready_in()) {
            state_reg._next = AXI4_ARB_WRITE_RESPONSE;
        }
        else if ((uint32_t)state_reg == AXI4_ARB_WRITE_RESPONSE
            && memory.bvalid_in() && memory.bready_out()) {
            state_reg._next = AXI4_ARB_IDLE;
        }
        else if ((uint32_t)state_reg == AXI4_ARB_READ_DATA
            && memory.rvalid_in() && memory.rready_out()
            && memory.rlast_in()) {
            state_reg._next = AXI4_ARB_IDLE;
        }

        if (reset) {
            state_reg.clr();
            packet_owner_reg.clr();
        }
    }

    void _strobe()
    {
        state_reg.strobe();
        packet_owner_reg.strobe();
    }
};
