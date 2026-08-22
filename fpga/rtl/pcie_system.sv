`timescale 1ns/1ps
`default_nettype none

// KlusterLab PCIe endpoint and the AXI4-only SmartNIC System.  PCIe BAR0 is
// converted from full AXI4 to single-beat AXI4 before register/ring access;
// the outbound DMA path remains full 64-bit AXI4 into the PCIe bridge.
module pcie_system (
    input  wire         startup_reset,
    input  wire         l2_clock,
    input  wire         pcie_perst_n,
    input  wire         pcie_refclk_p,
    input  wire         pcie_refclk_n,
    input  wire         pcie_rx_p,
    input  wire         pcie_rx_n,
    output wire         pcie_tx_p,
    output wire         pcie_tx_n,

    input  wire         l2_rx_valid,
    input  wire [255:0] l2_rx_data,
    input  wire [31:0]  l2_rx_keep,
    input  wire         l2_rx_sop,
    input  wire         l2_rx_eop,
    output wire         l2_rx_ready,
    output wire         l2_tx_valid,
    output wire [255:0] l2_tx_data,
    output wire [31:0]  l2_tx_keep,
    output wire         l2_tx_sop,
    output wire         l2_tx_eop,
    input  wire         l2_tx_ready,

    output wire         system_clock,
    output wire         link_up,
    output wire         system_reset,
    output wire         protocol_error,
    output wire [11:0]  activity
);
    wire pcie_refclk;
    IBUFDS_GTE2 pcie_refclk_buffer (
        .I(pcie_refclk_p), .IB(pcie_refclk_n), .CEB(1'b0),
        .O(pcie_refclk), .ODIV2());

    wire pcie_axi_aresetn = pcie_perst_n && !startup_reset;
    wire pcie_axi_clock;
    wire pcie_link_up;
    assign system_clock = pcie_axi_clock;
    assign link_up = pcie_link_up;

    // Hold System and the protocol converter reset until the endpoint user
    // clock is running and link training has completed.  Assertion is
    // asynchronous; release is synchronized to the 125 MHz PCIe AXI clock.
    (* ASYNC_REG = "TRUE" *) reg [3:0] system_reset_sync = 4'hf;
    always @(posedge pcie_axi_clock or negedge pcie_axi_aresetn) begin
        if (!pcie_axi_aresetn) system_reset_sync <= 4'hf;
        else system_reset_sync <= {system_reset_sync[2:0], !pcie_link_up};
    end
    assign system_reset = system_reset_sync[3];

    // PCIe BAR0 master, before burst-to-single-beat conversion.
    wire [31:0] pcie_m_awaddr;
    wire [7:0] pcie_m_awlen;
    wire [2:0] pcie_m_awsize;
    wire [1:0] pcie_m_awburst;
    wire [2:0] pcie_m_awprot;
    wire pcie_m_awvalid, pcie_m_awready, pcie_m_awlock;
    wire [3:0] pcie_m_awcache;
    wire [63:0] pcie_m_wdata;
    wire [7:0] pcie_m_wstrb;
    wire pcie_m_wlast, pcie_m_wvalid, pcie_m_wready;
    wire [1:0] pcie_m_bresp;
    wire pcie_m_bvalid, pcie_m_bready;
    wire [31:0] pcie_m_araddr;
    wire [7:0] pcie_m_arlen;
    wire [2:0] pcie_m_arsize;
    wire [1:0] pcie_m_arburst;
    wire [2:0] pcie_m_arprot;
    wire pcie_m_arvalid, pcie_m_arready, pcie_m_arlock;
    wire [3:0] pcie_m_arcache;
    wire [63:0] pcie_m_rdata;
    wire [1:0] pcie_m_rresp;
    wire pcie_m_rlast, pcie_m_rvalid, pcie_m_rready;

    // AXI4-Lite side of the control protocol converter.
    wire [31:0] control_awaddr;
    wire [2:0] control_awprot;
    wire control_awvalid, control_awready;
    wire [63:0] control_wdata;
    wire [7:0] control_wstrb;
    wire control_wvalid, control_wready;
    wire control_bvalid, control_bready;
    wire [31:0] control_araddr;
    wire [2:0] control_arprot;
    wire control_arvalid, control_arready;
    wire [63:0] control_rdata;
    wire control_rvalid, control_rready;

    pcie_control_converter control_converter (
        .aclk(pcie_axi_clock), .aresetn(~system_reset),
        .s_axi_awaddr(pcie_m_awaddr), .s_axi_awlen(pcie_m_awlen),
        .s_axi_awsize(pcie_m_awsize), .s_axi_awburst(pcie_m_awburst),
        .s_axi_awlock(pcie_m_awlock), .s_axi_awcache(pcie_m_awcache),
        .s_axi_awprot(pcie_m_awprot), .s_axi_awregion(4'd0),
        .s_axi_awqos(4'd0), .s_axi_awvalid(pcie_m_awvalid),
        .s_axi_awready(pcie_m_awready), .s_axi_wdata(pcie_m_wdata),
        .s_axi_wstrb(pcie_m_wstrb), .s_axi_wlast(pcie_m_wlast),
        .s_axi_wvalid(pcie_m_wvalid), .s_axi_wready(pcie_m_wready),
        .s_axi_bresp(pcie_m_bresp), .s_axi_bvalid(pcie_m_bvalid),
        .s_axi_bready(pcie_m_bready), .s_axi_araddr(pcie_m_araddr),
        .s_axi_arlen(pcie_m_arlen), .s_axi_arsize(pcie_m_arsize),
        .s_axi_arburst(pcie_m_arburst), .s_axi_arlock(pcie_m_arlock),
        .s_axi_arcache(pcie_m_arcache), .s_axi_arprot(pcie_m_arprot),
        .s_axi_arregion(4'd0), .s_axi_arqos(4'd0),
        .s_axi_arvalid(pcie_m_arvalid), .s_axi_arready(pcie_m_arready),
        .s_axi_rdata(pcie_m_rdata), .s_axi_rresp(pcie_m_rresp),
        .s_axi_rlast(pcie_m_rlast), .s_axi_rvalid(pcie_m_rvalid),
        .s_axi_rready(pcie_m_rready),
        .m_axi_awaddr(control_awaddr), .m_axi_awprot(control_awprot),
        .m_axi_awvalid(control_awvalid), .m_axi_awready(control_awready),
        .m_axi_wdata(control_wdata), .m_axi_wstrb(control_wstrb),
        .m_axi_wvalid(control_wvalid), .m_axi_wready(control_wready),
        .m_axi_bresp(2'b00), .m_axi_bvalid(control_bvalid),
        .m_axi_bready(control_bready), .m_axi_araddr(control_araddr),
        .m_axi_arprot(control_arprot), .m_axi_arvalid(control_arvalid),
        .m_axi_arready(control_arready), .m_axi_rdata(control_rdata),
        .m_axi_rresp(2'b00), .m_axi_rvalid(control_rvalid),
        .m_axi_rready(control_rready));

    // System outbound DMA AXI4 signals.
    wire dma_awvalid, dma_awready;
    wire [31:0] dma_awaddr;
    wire [3:0] dma_awid;
    wire dma_wvalid, dma_wready;
    wire [63:0] dma_wdata;
    wire [7:0] dma_wstrb;
    wire dma_wlast;
    wire dma_bvalid, dma_bready;
    wire [3:0] dma_bid;
    wire dma_arvalid, dma_arready;
    wire [31:0] dma_araddr;
    wire [3:0] dma_arid;
    wire dma_rvalid, dma_rready;
    wire [63:0] dma_rdata;
    wire dma_rlast;
    wire [3:0] dma_rid;
    wire [1:0] dma_bresp, dma_rresp;

    pcie_bridge endpoint (
        .axi_aresetn(pcie_axi_aresetn), .user_link_up(pcie_link_up),
        .axi_aclk_out(pcie_axi_clock), .axi_ctl_aclk_out(), .mmcm_lock(),
        .interrupt_out(), .INTX_MSI_Request(1'b0), .INTX_MSI_Grant(),
        .MSI_enable(), .MSI_Vector_Num(5'd0), .MSI_Vector_Width(),
        .s_axi_awid(dma_awid), .s_axi_awaddr(dma_awaddr),
        .s_axi_awregion(4'd0), .s_axi_awlen(8'd0), .s_axi_awsize(3'd3),
        .s_axi_awburst(2'b01), .s_axi_awvalid(dma_awvalid),
        .s_axi_awready(dma_awready), .s_axi_wdata(dma_wdata),
        .s_axi_wstrb(dma_wstrb), .s_axi_wlast(dma_wlast),
        .s_axi_wvalid(dma_wvalid), .s_axi_wready(dma_wready),
        .s_axi_bid(dma_bid), .s_axi_bresp(dma_bresp),
        .s_axi_bvalid(dma_bvalid), .s_axi_bready(dma_bready),
        .s_axi_arid(dma_arid), .s_axi_araddr(dma_araddr),
        .s_axi_arregion(4'd0), .s_axi_arlen(8'd0), .s_axi_arsize(3'd3),
        .s_axi_arburst(2'b01), .s_axi_arvalid(dma_arvalid),
        .s_axi_arready(dma_arready), .s_axi_rid(dma_rid),
        .s_axi_rdata(dma_rdata), .s_axi_rresp(dma_rresp),
        .s_axi_rlast(dma_rlast), .s_axi_rvalid(dma_rvalid),
        .s_axi_rready(dma_rready),
        .m_axi_awaddr(pcie_m_awaddr), .m_axi_awlen(pcie_m_awlen),
        .m_axi_awsize(pcie_m_awsize), .m_axi_awburst(pcie_m_awburst),
        .m_axi_awprot(pcie_m_awprot), .m_axi_awvalid(pcie_m_awvalid),
        .m_axi_awready(pcie_m_awready), .m_axi_awlock(pcie_m_awlock),
        .m_axi_awcache(pcie_m_awcache), .m_axi_wdata(pcie_m_wdata),
        .m_axi_wstrb(pcie_m_wstrb), .m_axi_wlast(pcie_m_wlast),
        .m_axi_wvalid(pcie_m_wvalid), .m_axi_wready(pcie_m_wready),
        .m_axi_bresp(pcie_m_bresp), .m_axi_bvalid(pcie_m_bvalid),
        .m_axi_bready(pcie_m_bready), .m_axi_araddr(pcie_m_araddr),
        .m_axi_arlen(pcie_m_arlen), .m_axi_arsize(pcie_m_arsize),
        .m_axi_arburst(pcie_m_arburst), .m_axi_arprot(pcie_m_arprot),
        .m_axi_arvalid(pcie_m_arvalid), .m_axi_arready(pcie_m_arready),
        .m_axi_arlock(pcie_m_arlock), .m_axi_arcache(pcie_m_arcache),
        .m_axi_rdata(pcie_m_rdata), .m_axi_rresp(pcie_m_rresp),
        .m_axi_rlast(pcie_m_rlast), .m_axi_rvalid(pcie_m_rvalid),
        .m_axi_rready(pcie_m_rready), .pci_exp_txp(pcie_tx_p),
        .pci_exp_txn(pcie_tx_n), .pci_exp_rxp(pcie_rx_p),
        .pci_exp_rxn(pcie_rx_n), .REFCLK(pcie_refclk),
        .s_axi_ctl_awaddr(32'd0), .s_axi_ctl_awvalid(1'b0),
        .s_axi_ctl_awready(), .s_axi_ctl_wdata(32'd0),
        .s_axi_ctl_wstrb(4'd0), .s_axi_ctl_wvalid(1'b0),
        .s_axi_ctl_wready(), .s_axi_ctl_bresp(), .s_axi_ctl_bvalid(),
        .s_axi_ctl_bready(1'b1), .s_axi_ctl_araddr(32'd0),
        .s_axi_ctl_arvalid(1'b0), .s_axi_ctl_arready(),
        .s_axi_ctl_rdata(), .s_axi_ctl_rresp(), .s_axi_ctl_rvalid(),
        .s_axi_ctl_rready(1'b1));

    System system (
        .l2_clock(l2_clock), .system_clock(pcie_axi_clock),
        .reset(system_reset), .l2_rx_valid_in(l2_rx_valid),
        .l2_rx_data_in(l2_rx_data), .l2_rx_keep_in(l2_rx_keep),
        .l2_rx_sop_in(l2_rx_sop), .l2_rx_eop_in(l2_rx_eop),
        .l2_rx_ready_out(l2_rx_ready), .l2_tx_valid_out(l2_tx_valid),
        .l2_tx_data_out(l2_tx_data), .l2_tx_keep_out(l2_tx_keep),
        .l2_tx_sop_out(l2_tx_sop), .l2_tx_eop_out(l2_tx_eop),
        .l2_tx_ready_in(l2_tx_ready),
        .host_control__awvalid_in(control_awvalid),
        .host_control__awready_out(control_awready),
        .host_control__awaddr_in(control_awaddr), .host_control__awid_in(4'd0),
        .host_control__wvalid_in(control_wvalid),
        .host_control__wready_out(control_wready),
        .host_control__wdata_in(control_wdata),
        .host_control__wstrb_in(control_wstrb), .host_control__wlast_in(1'b1),
        .host_control__bvalid_out(control_bvalid),
        .host_control__bready_in(control_bready), .host_control__bid_out(),
        .host_control__arvalid_in(control_arvalid),
        .host_control__arready_out(control_arready),
        .host_control__araddr_in(control_araddr), .host_control__arid_in(4'd0),
        .host_control__rvalid_out(control_rvalid),
        .host_control__rready_in(control_rready),
        .host_control__rdata_out(control_rdata), .host_control__rlast_out(),
        .host_control__rid_out(),
        .host_dma__awvalid_out(dma_awvalid), .host_dma__awready_in(dma_awready),
        .host_dma__awaddr_out(dma_awaddr), .host_dma__awid_out(dma_awid),
        .host_dma__wvalid_out(dma_wvalid), .host_dma__wready_in(dma_wready),
        .host_dma__wdata_out(dma_wdata), .host_dma__wstrb_out(dma_wstrb),
        .host_dma__wlast_out(dma_wlast), .host_dma__bvalid_in(dma_bvalid),
        .host_dma__bready_out(dma_bready), .host_dma__bid_in(dma_bid),
        .host_dma__arvalid_out(dma_arvalid), .host_dma__arready_in(dma_arready),
        .host_dma__araddr_out(dma_araddr), .host_dma__arid_out(dma_arid),
        .host_dma__rvalid_in(dma_rvalid), .host_dma__rready_out(dma_rready),
        .host_dma__rdata_in(dma_rdata), .host_dma__rlast_in(dma_rlast),
        .host_dma__rid_in(dma_rid), .rx_queue_empty_out(),
        .tx_queue_empty_out(), .protocol_error_out(protocol_error));

    assign activity = {
        pcie_link_up, !system_reset,
        control_awvalid, control_awready, control_wvalid, control_wready,
        control_bvalid, control_bready,
        dma_awvalid, dma_awready, dma_rvalid, dma_rready};
endmodule

`default_nettype wire
