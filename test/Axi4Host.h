#pragma once

// Test-only AXI4 host endpoint.  The control initiator accesses System's
// register and descriptor-ring slave, while the DMA target models host memory
// reached through the outbound PCIe AXI window.

#include "../Config.h"
#include "../rtl/common/Axi4Master.h"
#include "../cpphdl/tribe_cpu/common/Axi4Ram.h"

using namespace cpphdl;

enum Axi4HostControlState : uint8_t
{
    AXI4_HOST_IDLE,
    AXI4_HOST_WRITE,
    AXI4_HOST_WRITE_RESPONSE,
    AXI4_HOST_READ_ADDRESS,
    AXI4_HOST_READ_DATA
};

template<size_t MEMORY_BYTES = 4 * 1024 * 1024>
class Axi4Host : public Module
{
public:
    static constexpr size_t DATA_WIDTH = HOST_DATA_WIDTH;
    static constexpr size_t DATA_BYTES = DATA_WIDTH / 8;
    static constexpr size_t WORDS = MEMORY_BYTES / DATA_BYTES;

    static_assert(MEMORY_BYTES % DATA_BYTES == 0);
    static_assert((WORDS & (WORDS - 1)) == 0);

    Axi4MasterIf<32, 4, DATA_WIDTH> control;
    Axi4Ram<HOST_ADDR_WIDTH, 4, DATA_WIDTH, WORDS> dma_memory;

    // One request at a time is sufficient for the software-style test driver.
    // The AXI channels below still handshake independently and may stall.
    _PORT(bool) driver_request_valid_in;
    _PORT(bool) driver_request_write_in;
    _PORT(u32) driver_address_in;
    _PORT(logic<DATA_WIDTH>) driver_writedata_in;
    _PORT(logic<DATA_BYTES>) driver_wstrb_in;
    _PORT(bool) driver_request_ready_out;
    _PORT(bool) driver_response_valid_out;
    _PORT(logic<DATA_WIDTH>) driver_readdata_out;
    _PORT(bool) protocol_error_out;

private:
    reg<u8> control_state_reg;
    reg<u<32>> control_address_reg;
    reg<logic<DATA_WIDTH>> control_writedata_reg;
    reg<logic<DATA_BYTES>> control_wstrb_reg;
    reg<u1> write_address_done_reg;
    reg<u1> write_data_done_reg;
    reg<logic<DATA_WIDTH>> response_data_reg;
    reg<u1> response_valid_reg;
    reg<u1> protocol_error_reg;

    bool dma_write_address_invalid()
    {
        return dma_memory.axi_in.awvalid_in()
            && dma_memory.axi_in.awready_out()
            && (uint64_t)dma_memory.axi_in.awaddr_in() >= MEMORY_BYTES;
    }

    bool dma_read_address_invalid()
    {
        return dma_memory.axi_in.arvalid_in()
            && dma_memory.axi_in.arready_out()
            && (uint64_t)dma_memory.axi_in.araddr_in() >= MEMORY_BYTES;
    }

public:
    void _assign()
    {
        control.awvalid_out = _ASSIGN((uint32_t)control_state_reg
            == AXI4_HOST_WRITE && !write_address_done_reg);
        control.awaddr_out = _ASSIGN_REG(control_address_reg);
        control.awid_out = _ASSIGN((u<4>)0);
        control.wvalid_out = _ASSIGN((uint32_t)control_state_reg
            == AXI4_HOST_WRITE && !write_data_done_reg);
        control.wdata_out = _ASSIGN_REG(control_writedata_reg);
        control.wstrb_out = _ASSIGN_REG(control_wstrb_reg);
        control.wlast_out = _ASSIGN(true);
        control.bready_out = _ASSIGN((uint32_t)control_state_reg
            == AXI4_HOST_WRITE_RESPONSE);
        control.arvalid_out = _ASSIGN((uint32_t)control_state_reg
            == AXI4_HOST_READ_ADDRESS);
        control.araddr_out = _ASSIGN_REG(control_address_reg);
        control.arid_out = _ASSIGN((u<4>)0);
        control.rready_out = _ASSIGN((uint32_t)control_state_reg
            == AXI4_HOST_READ_DATA);

        driver_request_ready_out = _ASSIGN((uint32_t)control_state_reg
            == AXI4_HOST_IDLE);
        driver_response_valid_out = _ASSIGN_REG(response_valid_reg);
        driver_readdata_out = _ASSIGN_REG(response_data_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);

        dma_memory.debugen_in = false;
        dma_memory.__inst_name = __inst_name + "/dma_memory";
        dma_memory._assign();
    }

    void _work_system_clock(bool reset)
    {
        bool address_done;
        bool data_done;

        dma_memory._work(reset);
        response_valid_reg._next = false;

        if (dma_write_address_invalid() || dma_read_address_invalid())
            protocol_error_reg._next = true;

        if ((uint32_t)control_state_reg == AXI4_HOST_IDLE
            && driver_request_valid_in()) {
            control_address_reg._next = driver_address_in();
            control_writedata_reg._next = driver_writedata_in();
            control_wstrb_reg._next = driver_wstrb_in();
            write_address_done_reg._next = false;
            write_data_done_reg._next = false;
            if (driver_request_write_in())
                control_state_reg._next = AXI4_HOST_WRITE;
            else control_state_reg._next = AXI4_HOST_READ_ADDRESS;
        }
        else if ((uint32_t)control_state_reg == AXI4_HOST_WRITE) {
            address_done = write_address_done_reg
                || (control.awvalid_out() && control.awready_in());
            data_done = write_data_done_reg
                || (control.wvalid_out() && control.wready_in());
            if (control.awvalid_out() && control.awready_in())
                write_address_done_reg._next = true;
            if (control.wvalid_out() && control.wready_in())
                write_data_done_reg._next = true;
            if (address_done && data_done)
                control_state_reg._next = AXI4_HOST_WRITE_RESPONSE;
        }
        else if ((uint32_t)control_state_reg == AXI4_HOST_WRITE_RESPONSE
            && control.bvalid_in()) {
            if ((uint32_t)control.bid_in() != 0)
                protocol_error_reg._next = true;
            response_data_reg._next = 0;
            response_valid_reg._next = true;
            control_state_reg._next = AXI4_HOST_IDLE;
        }
        else if ((uint32_t)control_state_reg == AXI4_HOST_READ_ADDRESS
            && control.arready_in()) {
            control_state_reg._next = AXI4_HOST_READ_DATA;
        }
        else if ((uint32_t)control_state_reg == AXI4_HOST_READ_DATA
            && control.rvalid_in()) {
            if (!control.rlast_in() || (uint32_t)control.rid_in() != 0)
                protocol_error_reg._next = true;
            response_data_reg._next = control.rdata_in();
            response_valid_reg._next = true;
            control_state_reg._next = AXI4_HOST_IDLE;
        }

        if (reset) {
            control_state_reg.clr();
            control_address_reg.clr();
            control_writedata_reg.clr();
            control_wstrb_reg.clr();
            write_address_done_reg.clr();
            write_data_done_reg.clr();
            response_data_reg.clr();
            response_valid_reg.clr();
            protocol_error_reg.clr();
        }
    }

    void _strobe_system_clock()
    {
        dma_memory._strobe();
        control_state_reg.strobe();
        control_address_reg.strobe();
        control_writedata_reg.strobe();
        control_wstrb_reg.strobe();
        write_address_done_reg.strobe();
        write_data_done_reg.strobe();
        response_data_reg.strobe();
        response_valid_reg.strobe();
        protocol_error_reg.strobe();
    }

#ifndef SYNTHESIS
    uint8_t read_byte(uint64_t address) const
    {
        if (address >= MEMORY_BYTES) return 0;
        return (uint8_t)dma_memory.ram.buffer.data[address / DATA_BYTES]
            [address % DATA_BYTES];
    }
#endif
};
