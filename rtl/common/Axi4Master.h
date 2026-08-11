#pragma once

// AXI4 interface whose directions are named from the initiating master's
// point of view, ensuring correct generated top-level SystemVerilog ports.

#include "../../cpphdl/tribe_cpu/common/Axi4.h"

using namespace cpphdl;

template<size_t ADDR_WIDTH, size_t ID_WIDTH, size_t DATA_WIDTH>
struct Axi4MasterIf : Interface
{
    _PORT(bool) awvalid_out;
    _PORT(bool) awready_in;
    _PORT(u<ADDR_WIDTH>) awaddr_out;
    _PORT(u<ID_WIDTH>) awid_out;
    _PORT(bool) wvalid_out;
    _PORT(bool) wready_in;
    _PORT(logic<DATA_WIDTH>) wdata_out;
    _PORT(logic<DATA_WIDTH / 8>) wstrb_out;
    _PORT(bool) wlast_out;
    _PORT(bool) bvalid_in;
    _PORT(bool) bready_out;
    _PORT(u<ID_WIDTH>) bid_in;
    _PORT(bool) arvalid_out;
    _PORT(bool) arready_in;
    _PORT(u<ADDR_WIDTH>) araddr_out;
    _PORT(u<ID_WIDTH>) arid_out;
    _PORT(bool) rvalid_in;
    _PORT(bool) rready_out;
    _PORT(logic<DATA_WIDTH>) rdata_in;
    _PORT(bool) rlast_in;
    _PORT(u<ID_WIDTH>) rid_in;

    Axi4MasterIf& operator=(Axi4Responder<ID_WIDTH, DATA_WIDTH>& other)
    {
        Axi4Responder<ID_WIDTH, DATA_WIDTH>* responder = &other;
        awready_in = [responder]() { return &responder->aw.ready; };
        wready_in = [responder]() { return &responder->w.ready; };
        bvalid_in = [responder]() { return &responder->b.valid; };
        bid_in = [responder]() { return &responder->b.id; };
        arready_in = [responder]() { return &responder->ar.ready; };
        rvalid_in = [responder]() { return &responder->r.valid; };
        rdata_in = [responder]() { return &responder->r.data; };
        rlast_in = [responder]() { return &responder->r.last; };
        rid_in = [responder]() { return &responder->r.id; };
        return *this;
    }
};

#define AXI4_MASTER_FROM_TARGET_IF(dst, src) \
    (dst).awvalid_out = (src).awvalid_in; \
    (dst).awaddr_out = (src).awaddr_in; \
    (dst).awid_out = (src).awid_in; \
    (dst).wvalid_out = (src).wvalid_in; \
    (dst).wdata_out = (src).wdata_in; \
    (dst).wstrb_out = (src).wstrb_in; \
    (dst).wlast_out = (src).wlast_in; \
    (dst).bready_out = (src).bready_in; \
    (dst).arvalid_out = (src).arvalid_in; \
    (dst).araddr_out = (src).araddr_in; \
    (dst).arid_out = (src).arid_in; \
    (dst).rready_out = (src).rready_in

#define AXI4_TARGET_IF_RESPONDER_FROM_MASTER(dst, src) \
    (dst).awready_out = (src).awready_in; \
    (dst).wready_out = (src).wready_in; \
    (dst).bvalid_out = (src).bvalid_in; \
    (dst).bid_out = (src).bid_in; \
    (dst).arready_out = (src).arready_in; \
    (dst).rvalid_out = (src).rvalid_in; \
    (dst).rdata_out = (src).rdata_in; \
    (dst).rlast_out = (src).rlast_in; \
    (dst).rid_out = (src).rid_in

#define AXI4_TARGET_IF_DRIVER_FROM_MASTER(dst, src) \
    (dst).awvalid_in = (src).awvalid_out; \
    (dst).awaddr_in = (src).awaddr_out; \
    (dst).awid_in = (src).awid_out; \
    (dst).wvalid_in = (src).wvalid_out; \
    (dst).wdata_in = (src).wdata_out; \
    (dst).wstrb_in = (src).wstrb_out; \
    (dst).wlast_in = (src).wlast_out; \
    (dst).bready_in = (src).bready_out; \
    (dst).arvalid_in = (src).arvalid_out; \
    (dst).araddr_in = (src).araddr_out; \
    (dst).arid_in = (src).arid_out; \
    (dst).rready_in = (src).rready_out

#define AXI4_MASTER_RESPONDER_FROM_TARGET(dst, src) \
    (dst).awready_in = (src).awready_out; \
    (dst).wready_in = (src).wready_out; \
    (dst).bvalid_in = (src).bvalid_out; \
    (dst).bid_in = (src).bid_out; \
    (dst).arready_in = (src).arready_out; \
    (dst).rvalid_in = (src).rvalid_out; \
    (dst).rdata_in = (src).rdata_out; \
    (dst).rlast_in = (src).rlast_out; \
    (dst).rid_in = (src).rid_out

#define AXI4_MASTER_FROM_MASTER(dst, src) \
    (dst).awvalid_out = (src).awvalid_out; \
    (dst).awaddr_out = (src).awaddr_out; \
    (dst).awid_out = (src).awid_out; \
    (dst).wvalid_out = (src).wvalid_out; \
    (dst).wdata_out = (src).wdata_out; \
    (dst).wstrb_out = (src).wstrb_out; \
    (dst).wlast_out = (src).wlast_out; \
    (dst).bready_out = (src).bready_out; \
    (dst).arvalid_out = (src).arvalid_out; \
    (dst).araddr_out = (src).araddr_out; \
    (dst).arid_out = (src).arid_out; \
    (dst).rready_out = (src).rready_out

#define AXI4_MASTER_RESPONDER_FROM_MASTER(dst, src) \
    (dst).awready_in = (src).awready_in; \
    (dst).wready_in = (src).wready_in; \
    (dst).bvalid_in = (src).bvalid_in; \
    (dst).bid_in = (src).bid_in; \
    (dst).arready_in = (src).arready_in; \
    (dst).rvalid_in = (src).rvalid_in; \
    (dst).rdata_in = (src).rdata_in; \
    (dst).rlast_in = (src).rlast_in; \
    (dst).rid_in = (src).rid_in
