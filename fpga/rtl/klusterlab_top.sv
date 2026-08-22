`timescale 1ns/1ps
`default_nettype none

module klusterlab_top (
    input  wire       sys_clk_200_p,
    input  wire       sys_clk_200_n,
    input  wire       eth_refclk_p,
    input  wire       eth_refclk_n,
    input  wire       pcie_refclk_p,
    input  wire       pcie_refclk_n,
    input  wire       pcie_rx_p,
    input  wire       pcie_rx_n,
    output wire       pcie_tx_p,
    output wire       pcie_tx_n,
    input  wire       pcie_perst_n,
    input  wire [1:0] sfp_rx_p,
    input  wire [1:0] sfp_rx_n,
    output wire [1:0] sfp_tx_p,
    output wire [1:0] sfp_tx_n,
    input  wire [1:0] sfp_los,
    output wire [1:0] sfp_tx_en
);
    wire sys_clk_200_ibuf;
    wire sys_clk_200;
    wire startup_clk_fb;
    wire startup_clk_fb_buf;
    wire startup_clk_50_unbuf;
    wire startup_clk_50;
    wire startup_locked;

    IBUFDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE"),
             .IOSTANDARD("LVDS")) sys_clk_ibuf (
        .I(sys_clk_200_p), .IB(sys_clk_200_n), .O(sys_clk_200_ibuf));
    BUFG sys_clk_bufg (.I(sys_clk_200_ibuf), .O(sys_clk_200));

    // Board-independent startup/DRP clock.  The 200 MHz oscillator is present
    // immediately after configuration and does not depend on a GTX lock.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(5.000),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(5.000),
        .CLKOUT0_DIVIDE_F(20.000), .STARTUP_WAIT("FALSE")
    ) startup_mmcm (
        .CLKIN1(sys_clk_200), .CLKFBIN(startup_clk_fb_buf),
        .RST(1'b0), .PWRDWN(1'b0),
        .CLKFBOUT(startup_clk_fb), .CLKOUT0(startup_clk_50_unbuf),
        .LOCKED(startup_locked));
    BUFG startup_fb_bufg (.I(startup_clk_fb), .O(startup_clk_fb_buf));
    BUFG startup_clk_bufg (.I(startup_clk_50_unbuf), .O(startup_clk_50));

    (* ASYNC_REG = "TRUE" *) reg [7:0] por_shift = 8'h00;
    always @(posedge startup_clk_50)
        por_shift <= {por_shift[6:0], startup_locked};
    wire startup_reset = ~por_shift[7];

    wire net_clk;
    wire net_reset_from_ip;
    wire eth_reset_done;
    wire eth_reset_counter_done;
    wire eth_qpll_lock;
    wire eth_qpll_clk;
    wire eth_qpll_refclk;
    wire eth_txusrclk;
    wire eth_txusrclk2;
    wire eth_gttxreset;
    wire eth_gtrxreset;
    wire eth_txuserrdy;

    wire [1:0] eth_tx_disable;
    wire [7:0] eth_status [0:1];
    wire [63:0] mac_rx_data [0:1];
    wire [7:0]  mac_rx_keep [0:1];
    wire [1:0]  mac_rx_last;
    wire [1:0]  mac_rx_error;
    wire [1:0]  mac_rx_valid;
    wire [63:0] mac_tx_data [0:1];
    wire [7:0]  mac_tx_keep [0:1];
    wire [1:0]  mac_tx_last;
    wire [1:0]  mac_tx_valid;
    wire [1:0]  mac_tx_ready;

    // Source-domain counters make the startup and TX-user clocks observable.
    // They deliberately have no cross-domain reset: FPGA INIT supplies the
    // initial value and avoids routing startup_reset to TXUSRCLK registers.
    // Only a slow counter bit crosses into net_clk below.
    reg [7:0] dclk_heartbeat_source = 8'd0;
    reg [7:0] txusr_heartbeat_source = 8'd0;
    reg [15:0] net_heartbeat = 16'd0;
    always @(posedge startup_clk_50)
        dclk_heartbeat_source <= dclk_heartbeat_source + 1'b1;
    always @(posedge eth_txusrclk2)
        txusr_heartbeat_source <= txusr_heartbeat_source + 1'b1;

    // Configuration-vector bit 1 enables each MAC; VLAN/custom-preamble and
    // PCS loopback remain disabled.  FCS is generated/checked by the MAC.
    localparam [79:0] MAC_CONFIG = {78'd0, 2'b10};
    localparam [535:0] PCS_CONFIG = 536'd0;

    eth10g_master eth0 (
        .tx_axis_aresetn(~startup_reset), .rx_axis_aresetn(~startup_reset),
        .tx_ifg_delay(8'd0), .dclk(startup_clk_50),
        .txp(sfp_tx_p[0]), .txn(sfp_tx_n[0]),
        .rxp(sfp_rx_p[0]), .rxn(sfp_rx_n[0]),
        .signal_detect(~sfp_los[0]), .tx_fault(1'b0),
        .tx_disable(eth_tx_disable[0]), .pcspma_status(eth_status[0]),
        .sim_speedup_control(1'b0), .rxrecclk_out(),
        .mac_tx_configuration_vector(MAC_CONFIG),
        .mac_rx_configuration_vector(MAC_CONFIG), .mac_status_vector(),
        .pcs_pma_configuration_vector(PCS_CONFIG), .pcs_pma_status_vector(),
        .areset_datapathclk_out(net_reset_from_ip),
        .txusrclk_out(eth_txusrclk), .txusrclk2_out(eth_txusrclk2),
        .gttxreset_out(eth_gttxreset), .gtrxreset_out(eth_gtrxreset),
        .txuserrdy_out(eth_txuserrdy), .coreclk_out(net_clk),
        .resetdone_out(eth_reset_done),
        .reset_counter_done_out(eth_reset_counter_done),
        .qplllock_out(eth_qpll_lock), .qplloutclk_out(eth_qpll_clk),
        .qplloutrefclk_out(eth_qpll_refclk),
        .refclk_p(eth_refclk_p), .refclk_n(eth_refclk_n),
        .reset(startup_reset),
        .s_axis_tx_tdata(mac_tx_data[0]), .s_axis_tx_tkeep(mac_tx_keep[0]),
        .s_axis_tx_tlast(mac_tx_last[0]), .s_axis_tx_tready(mac_tx_ready[0]),
        .s_axis_tx_tuser(1'b0), .s_axis_tx_tvalid(mac_tx_valid[0]),
        .s_axis_pause_tdata(16'd0), .s_axis_pause_tvalid(1'b0),
        .m_axis_rx_tdata(mac_rx_data[0]), .m_axis_rx_tkeep(mac_rx_keep[0]),
        .m_axis_rx_tlast(mac_rx_last[0]), .m_axis_rx_tuser(mac_rx_error[0]),
        .m_axis_rx_tvalid(mac_rx_valid[0]),
        .tx_statistics_valid(), .tx_statistics_vector(),
        .rx_statistics_valid(), .rx_statistics_vector());

    eth10g_slave eth1 (
        .tx_axis_aresetn(~startup_reset), .rx_axis_aresetn(~startup_reset),
        .tx_ifg_delay(8'd0), .dclk(startup_clk_50),
        .txp(sfp_tx_p[1]), .txn(sfp_tx_n[1]),
        .rxp(sfp_rx_p[1]), .rxn(sfp_rx_n[1]),
        .signal_detect(~sfp_los[1]), .tx_fault(1'b0),
        .tx_disable(eth_tx_disable[1]), .pcspma_status(eth_status[1]),
        .sim_speedup_control(1'b0), .rxrecclk_out(),
        .mac_tx_configuration_vector(MAC_CONFIG),
        .mac_rx_configuration_vector(MAC_CONFIG), .mac_status_vector(),
        .pcs_pma_configuration_vector(PCS_CONFIG), .pcs_pma_status_vector(),
        .areset_coreclk(net_reset_from_ip),
        .txusrclk(eth_txusrclk), .txusrclk2(eth_txusrclk2), .txoutclk(),
        .txuserrdy(eth_txuserrdy), .tx_resetdone(), .rx_resetdone(),
        .coreclk(net_clk), .areset(net_reset_from_ip),
        .gttxreset(eth_gttxreset), .gtrxreset(eth_gtrxreset),
        .qplllock(eth_qpll_lock), .qplloutclk(eth_qpll_clk),
        .qplloutrefclk(eth_qpll_refclk),
        .reset_counter_done(eth_reset_counter_done),
        .s_axis_tx_tdata(mac_tx_data[1]), .s_axis_tx_tkeep(mac_tx_keep[1]),
        .s_axis_tx_tlast(mac_tx_last[1]), .s_axis_tx_tready(mac_tx_ready[1]),
        .s_axis_tx_tuser(1'b0), .s_axis_tx_tvalid(mac_tx_valid[1]),
        .s_axis_pause_tdata(16'd0), .s_axis_pause_tvalid(1'b0),
        .m_axis_rx_tdata(mac_rx_data[1]), .m_axis_rx_tkeep(mac_rx_keep[1]),
        .m_axis_rx_tlast(mac_rx_last[1]), .m_axis_rx_tuser(mac_rx_error[1]),
        .m_axis_rx_tvalid(mac_rx_valid[1]),
        .tx_statistics_valid(), .tx_statistics_vector(),
        .rx_statistics_valid(), .rx_statistics_vector());

    // KlusterLab labels these level-shifted nets TX_EN (active high), while
    // the Ethernet subsystem exposes SFP TX_DISABLE (active high).
    assign sfp_tx_en = ~eth_tx_disable;

    // Processing, its L1/L2 caches, PacketDMA, DescriptorFetcher, and the
    // SmartNIC streams form one synchronous 156.25 MHz island.  In particular,
    // the Processing stream ports have no asynchronous FIFO at the Network
    // boundary, so multiplying only Processing.clk to 312.5 MHz is unsafe.
    wire cpu_clk = net_clk;
    wire cpu_clk_locked = 1'b1;

    (* ASYNC_REG = "TRUE" *) reg [3:0] net_reset_sync = 4'hf;
    always @(posedge net_clk)
        net_reset_sync <= {net_reset_sync[2:0],
            (startup_reset | ~eth_reset_done | ~cpu_clk_locked)};
    wire design_reset = net_reset_sync[3];

    always @(posedge net_clk)
        if (design_reset) net_heartbeat <= 16'd0;
        else net_heartbeat <= net_heartbeat + 1'b1;

    // Synchronize one sufficiently slow toggle from each source domain and
    // count observed transitions in the ILA/net clock domain.  These counters
    // prove the clocks are alive without sampling an asynchronous multibit
    // binary count in the system ILA.
    (* ASYNC_REG = "TRUE" *) reg dclk_toggle_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg dclk_toggle_sync = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg txusr_toggle_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg txusr_toggle_sync = 1'b0;
    reg dclk_toggle_previous = 1'b0;
    reg txusr_toggle_previous = 1'b0;
    reg [7:0] dclk_heartbeat = 8'd0;
    reg [7:0] txusr_heartbeat = 8'd0;
    always @(posedge net_clk) begin
        dclk_toggle_meta <= dclk_heartbeat_source[0];
        dclk_toggle_sync <= dclk_toggle_meta;
        txusr_toggle_meta <= txusr_heartbeat_source[3];
        txusr_toggle_sync <= txusr_toggle_meta;
        dclk_toggle_previous <= dclk_toggle_sync;
        txusr_toggle_previous <= txusr_toggle_sync;
        if (design_reset) begin
            dclk_heartbeat <= 8'd0;
            txusr_heartbeat <= 8'd0;
        end
        else begin
            if (dclk_toggle_sync != dclk_toggle_previous)
                dclk_heartbeat <= dclk_heartbeat + 1'b1;
            if (txusr_toggle_sync != txusr_toggle_previous)
                txusr_heartbeat <= txusr_heartbeat + 1'b1;
        end
    end

    reg [1:0] rx_in_frame = 2'b00;
    always @(posedge net_clk) begin
        if (design_reset)
            rx_in_frame <= 2'b00;
        else begin
            if (mac_rx_valid[0]) rx_in_frame[0] <= ~mac_rx_last[0];
            if (mac_rx_valid[1]) rx_in_frame[1] <= ~mac_rx_last[1];
        end
    end

    wire net_rx_valid = |mac_rx_valid;
    wire [127:0] net_rx_data = {mac_rx_data[1], mac_rx_data[0]};
    wire [15:0] net_rx_keep = {
        (mac_rx_valid[1] ? mac_rx_keep[1] : 8'd0),
        (mac_rx_valid[0] ? mac_rx_keep[0] : 8'd0)};
    wire [15:0] net_rx_sop = {
        ((mac_rx_valid[1] && !rx_in_frame[1]) ? 8'h01 : 8'h00),
        ((mac_rx_valid[0] && !rx_in_frame[0]) ? 8'h01 : 8'h00)};
    wire [15:0] net_rx_eop = {
        ((mac_rx_valid[1] && mac_rx_last[1]) ? last_byte(mac_rx_keep[1]) : 8'h00),
        ((mac_rx_valid[0] && mac_rx_last[0]) ? last_byte(mac_rx_keep[0]) : 8'h00)};

    function automatic [7:0] last_byte(input [7:0] keep);
        integer k;
        begin
            last_byte = 8'h00;
            for (k = 0; k < 8; k = k + 1)
                if (keep[k]) last_byte = 8'b1 << k;
        end
    endfunction

    wire smart_tx_valid;
    wire [127:0] smart_tx_data;
    wire [15:0] smart_tx_keep;
    wire [15:0] smart_tx_sop;
    wire [15:0] smart_tx_eop;
    wire lane0_present = |smart_tx_keep[7:0];
    wire lane1_present = |smart_tx_keep[15:8];
    wire smart_tx_ready = (!lane0_present || mac_tx_ready[0]) &&
                          (!lane1_present || mac_tx_ready[1]);
    assign mac_tx_data[0] = smart_tx_data[63:0];
    assign mac_tx_data[1] = smart_tx_data[127:64];
    assign mac_tx_keep[0] = smart_tx_keep[7:0];
    assign mac_tx_keep[1] = smart_tx_keep[15:8];
    assign mac_tx_last[0] = |smart_tx_eop[7:0];
    assign mac_tx_last[1] = |smart_tx_eop[15:8];
    assign mac_tx_valid[0] = smart_tx_valid && lane0_present && smart_tx_ready;
    assign mac_tx_valid[1] = smart_tx_valid && lane1_present && smart_tx_ready;

    wire descriptor_valid;
    wire [255:0] descriptor_data;
    wire [2:0] descriptor_word;
    wire descriptor_sop, descriptor_eop, descriptor_ready;
    wire rx_read_valid, rx_read_ready;
    wire [15:0] rx_read_handle;
    wire [13:0] rx_read_length;
    wire l2_rx_valid, l2_rx_ready, l2_rx_sop, l2_rx_eop;
    wire [255:0] l2_rx_data;
    wire [31:0] l2_rx_keep;
    wire [1:0] l2_tx_valid, l2_tx_ready, l2_tx_sop, l2_tx_eop;
    wire [511:0] l2_tx_data;
    wire [63:0] l2_tx_keep;
    wire nic_protocol_error;
    wire nic_storage_full;

    SmartNIC #(.BANK_DEPTH(4096), .RX_FIFO_DEPTH(64),
               .TX_FIFO_WORDS(2048), .ENABLE_RAW(0)) nic (
        .net_clk(net_clk), .l2_clk(net_clk), .reset(design_reset),
        .net_rx_valid_in(net_rx_valid), .net_rx_data_in(net_rx_data),
        .net_rx_keep_in(net_rx_keep), .net_rx_sop_in(net_rx_sop),
        .net_rx_eop_in(net_rx_eop), .net_rx_raw_in(1'b0),
        .net_rx_ready_out(), .net_tx_valid_out(smart_tx_valid),
        .net_tx_data_out(smart_tx_data), .net_tx_keep_out(smart_tx_keep),
        .net_tx_sop_out(smart_tx_sop), .net_tx_eop_out(smart_tx_eop),
        .net_tx_ready_in(smart_tx_ready),
        .l2_descriptor_valid_out(descriptor_valid),
        .l2_descriptor_data_out(descriptor_data),
        .l2_descriptor_word_out(descriptor_word),
        .l2_descriptor_sop_out(descriptor_sop),
        .l2_descriptor_eop_out(descriptor_eop),
        .l2_descriptor_ready_in(descriptor_ready),
        .l2_rx_read_valid_in(rx_read_valid),
        .l2_rx_read_handle_in(rx_read_handle),
        .l2_rx_read_length_in(rx_read_length),
        .l2_rx_read_ready_out(rx_read_ready),
        .l2_rx_valid_out(l2_rx_valid), .l2_rx_data_out(l2_rx_data),
        .l2_rx_keep_out(l2_rx_keep), .l2_rx_sop_out(l2_rx_sop),
        .l2_rx_eop_out(l2_rx_eop), .l2_rx_ready_in(l2_rx_ready),
        .l2_tx_valid_in(l2_tx_valid), .l2_tx_data_in(l2_tx_data),
        .l2_tx_keep_in(l2_tx_keep), .l2_tx_sop_in(l2_tx_sop),
        .l2_tx_eop_in(l2_tx_eop), .l2_tx_ready_out(l2_tx_ready),
        .protocol_error_out(nic_protocol_error),
        .storage_full_out(nic_storage_full));

    wire proc_tx_valid;
    wire [255:0] proc_tx_data;
    wire [31:0] proc_tx_keep;
    wire proc_tx_sop, proc_tx_eop, proc_tx_ready;
    wire proc_to_system_valid, proc_to_system_ready;
    wire [255:0] proc_to_system_data;
    wire [31:0] proc_to_system_keep;
    wire proc_to_system_sop, proc_to_system_eop;
    wire proc_from_system_valid, proc_from_system_ready;
    wire [255:0] proc_from_system_data;
    wire [31:0] proc_from_system_keep;
    wire proc_from_system_sop, proc_from_system_eop;
    assign l2_tx_valid = {1'b0, proc_tx_valid};
    assign l2_tx_data = {256'd0, proc_tx_data};
    assign l2_tx_keep = {32'd0, proc_tx_keep};
    assign l2_tx_sop = {1'b0, proc_tx_sop};
    assign l2_tx_eop = {1'b0, proc_tx_eop};
    assign proc_tx_ready = l2_tx_ready[0];

    wire ddr_awvalid [0:0];
    wire ddr_awready [0:0];
    wire [30:0] ddr_awaddr [0:0];
    wire [3:0] ddr_awid [0:0];
    wire ddr_wvalid [0:0];
    wire ddr_wready [0:0];
    wire [255:0] ddr_wdata [0:0];
    wire [31:0] ddr_wstrb [0:0];
    wire ddr_wlast [0:0];
    wire ddr_bvalid [0:0];
    wire ddr_bready [0:0];
    wire [3:0] ddr_bid [0:0];
    wire ddr_arvalid [0:0];
    wire ddr_arready [0:0];
    wire [30:0] ddr_araddr [0:0];
    wire [3:0] ddr_arid [0:0];
    wire ddr_rvalid [0:0];
    wire ddr_rready [0:0];
    wire [255:0] ddr_rdata [0:0];
    wire ddr_rlast [0:0];
    wire [3:0] ddr_rid [0:0];
    wire software_irq [0:3];
    wire timer_irq [0:3];
    wire external_irq [0:3];
    wire cache_invalidate [0:0];
    // The board has no CPU program-loading protocol yet.  This AXI BRAM is
    // initialized from capture.elf by build.sh, so the reset-vector fetch at
    // address zero succeeds as soon as the CPU leaves reset.
    axi_boot_bram #(
        .BYTES(65536), .INIT_FILE("capture.mem")
    ) boot_memory (
        .clk(cpu_clk), .reset(design_reset),
        .awvalid(ddr_awvalid[0]), .awready(ddr_awready[0]),
        .awaddr(ddr_awaddr[0]), .awid(ddr_awid[0]),
        .wvalid(ddr_wvalid[0]), .wready(ddr_wready[0]),
        .wdata(ddr_wdata[0]), .wstrb(ddr_wstrb[0]),
        .wlast(ddr_wlast[0]), .bvalid(ddr_bvalid[0]),
        .bready(ddr_bready[0]), .bid(ddr_bid[0]),
        .arvalid(ddr_arvalid[0]), .arready(ddr_arready[0]),
        .araddr(ddr_araddr[0]), .arid(ddr_arid[0]),
        .rvalid(ddr_rvalid[0]), .rready(ddr_rready[0]),
        .rdata(ddr_rdata[0]), .rlast(ddr_rlast[0]), .rid(ddr_rid[0]));
    genvar irq_i;
    generate for (irq_i = 0; irq_i < 4; irq_i = irq_i + 1) begin : irq_tieoff
        assign software_irq[irq_i] = 1'b0;
        assign timer_irq[irq_i] = 1'b0;
        assign external_irq[irq_i] = 1'b0;
    end endgenerate
    assign cache_invalidate[0] = 1'b0;

    Processing processing (
        .clk(cpu_clk), .l2_clock(net_clk), .reset(design_reset),
        .descriptor_valid_in(descriptor_valid),
        .descriptor_data_in(descriptor_data), .descriptor_word_in(descriptor_word),
        .descriptor_sop_in(descriptor_sop), .descriptor_eop_in(descriptor_eop),
        .descriptor_ready_out(descriptor_ready),
        .rx_read_valid_out(rx_read_valid), .rx_read_handle_out(rx_read_handle),
        .rx_read_length_out(rx_read_length), .rx_read_ready_in(rx_read_ready),
        .rx_valid_in(l2_rx_valid), .rx_data_in(l2_rx_data),
        .rx_keep_in(l2_rx_keep), .rx_sop_in(l2_rx_sop),
        .rx_eop_in(l2_rx_eop), .rx_ready_out(l2_rx_ready),
        .to_system_valid_out(proc_to_system_valid),
        .to_system_data_out(proc_to_system_data),
        .to_system_keep_out(proc_to_system_keep),
        .to_system_sop_out(proc_to_system_sop),
        .to_system_eop_out(proc_to_system_eop),
        .to_system_ready_in(proc_to_system_ready),
        .from_system_valid_in(proc_from_system_valid),
        .from_system_data_in(proc_from_system_data),
        .from_system_keep_in(proc_from_system_keep),
        .from_system_sop_in(proc_from_system_sop),
        .from_system_eop_in(proc_from_system_eop),
        .from_system_ready_out(proc_from_system_ready),
        .to_network_valid_out(proc_tx_valid),
        .to_network_data_out(proc_tx_data), .to_network_keep_out(proc_tx_keep),
        .to_network_sop_out(proc_tx_sop), .to_network_eop_out(proc_tx_eop),
        .to_network_ready_in(proc_tx_ready),
        .ddr__awvalid_out(ddr_awvalid), .ddr__awready_in(ddr_awready),
        .ddr__awaddr_out(ddr_awaddr), .ddr__awid_out(ddr_awid),
        .ddr__wvalid_out(ddr_wvalid), .ddr__wready_in(ddr_wready),
        .ddr__wdata_out(ddr_wdata), .ddr__wstrb_out(ddr_wstrb),
        .ddr__wlast_out(ddr_wlast), .ddr__bvalid_in(ddr_bvalid),
        .ddr__bready_out(ddr_bready), .ddr__bid_in(ddr_bid),
        .ddr__arvalid_out(ddr_arvalid), .ddr__arready_in(ddr_arready),
        .ddr__araddr_out(ddr_araddr), .ddr__arid_out(ddr_arid),
        .ddr__rvalid_in(ddr_rvalid), .ddr__rready_out(ddr_rready),
        .ddr__rdata_in(ddr_rdata), .ddr__rlast_in(ddr_rlast),
        .ddr__rid_in(ddr_rid), .software_irq_in(software_irq),
        .timer_irq_in(timer_irq), .external_irq_in(external_irq),
        .cache_invalidate_in(cache_invalidate));

    wire pcie_system_clock;
    wire pcie_link_up;
    wire pcie_system_reset;
    wire system_protocol_error;
    wire [11:0] pcie_system_activity;
    pcie_system host_system (
        .startup_reset(startup_reset), .l2_clock(net_clk),
        .pcie_perst_n(pcie_perst_n), .pcie_refclk_p(pcie_refclk_p),
        .pcie_refclk_n(pcie_refclk_n), .pcie_rx_p(pcie_rx_p),
        .pcie_rx_n(pcie_rx_n), .pcie_tx_p(pcie_tx_p), .pcie_tx_n(pcie_tx_n),
        .l2_rx_valid(proc_to_system_valid), .l2_rx_data(proc_to_system_data),
        .l2_rx_keep(proc_to_system_keep), .l2_rx_sop(proc_to_system_sop),
        .l2_rx_eop(proc_to_system_eop), .l2_rx_ready(proc_to_system_ready),
        .l2_tx_valid(proc_from_system_valid), .l2_tx_data(proc_from_system_data),
        .l2_tx_keep(proc_from_system_keep), .l2_tx_sop(proc_from_system_sop),
        .l2_tx_eop(proc_from_system_eop), .l2_tx_ready(proc_from_system_ready),
        .system_clock(pcie_system_clock), .link_up(pcie_link_up),
        .system_reset(pcie_system_reset), .protocol_error(system_protocol_error),
        .activity(pcie_system_activity));

    // System/GTX/10G status capture sampled by the actual 125 MHz PCIe/System
    // clock.  Signals from Network/Processing are synchronized strictly for
    // debug visibility and do not feed functional logic.
    wire [19:0] ila_system_state_raw = {
        startup_locked, startup_reset, cpu_clk_locked, design_reset,
        net_reset_from_ip, eth_reset_done, eth_reset_counter_done,
        eth_qpll_lock, eth_gttxreset, eth_gtrxreset, eth_txuserrdy,
        sfp_los, eth_tx_disable, nic_protocol_error, nic_storage_full,
        pcie_link_up, pcie_system_reset, system_protocol_error};
    // Status bits originate in several transceiver/startup domains.  ILA
    // status is diagnostic, so independent two-flop synchronization is the
    // correct representation; cross-bit atomicity is not required.
    (* ASYNC_REG = "TRUE" *) reg [19:0] ila_system_state_meta = 20'd0;
    (* ASYNC_REG = "TRUE" *) reg [19:0] ila_system_state = 20'd0;
    wire [31:0] ila_processing_state_raw = {
        pcie_system_activity,
        proc_to_system_valid, proc_to_system_ready,
        proc_from_system_valid, proc_from_system_ready,
        ddr_awvalid[0], ddr_awready[0], ddr_wvalid[0], ddr_wready[0],
        ddr_bvalid[0], ddr_bready[0], ddr_arvalid[0], ddr_arready[0],
        ddr_rvalid[0], ddr_rready[0], descriptor_valid, descriptor_ready,
        rx_read_valid, rx_read_ready, proc_tx_valid, proc_tx_ready};
    wire [11:0] ila_mac_activity_raw = {
        mac_rx_valid, mac_rx_last, mac_rx_error,
        mac_tx_valid, mac_tx_ready, mac_tx_last};
    wire [15:0] ila_eth_status_raw = {eth_status[1], eth_status[0]};
    wire [31:0] ila_clock_activity_raw = {
        dclk_heartbeat, txusr_heartbeat, net_heartbeat};
    (* ASYNC_REG = "TRUE" *) reg [31:0] ila_processing_state_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ila_processing_state = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [11:0] ila_mac_activity_meta = 12'd0;
    (* ASYNC_REG = "TRUE" *) reg [11:0] ila_mac_activity = 12'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] ila_eth_status_meta = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] ila_eth_status = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ila_clock_activity_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ila_clock_activity = 32'd0;
    always @(posedge pcie_system_clock) begin
        ila_system_state_meta <= ila_system_state_raw;
        ila_system_state <= ila_system_state_meta;
        ila_processing_state_meta <= ila_processing_state_raw;
        ila_processing_state <= ila_processing_state_meta;
        ila_mac_activity_meta <= ila_mac_activity_raw;
        ila_mac_activity <= ila_mac_activity_meta;
        ila_eth_status_meta <= ila_eth_status_raw;
        ila_eth_status <= ila_eth_status_meta;
        ila_clock_activity_meta <= ila_clock_activity_raw;
        ila_clock_activity <= ila_clock_activity_meta;
    end

    ila_system system_debug (
        .clk(pcie_system_clock),
        .probe0(ila_system_state),
        .probe1(ila_eth_status),
        .probe2(ila_clock_activity),
        .probe3(ila_processing_state),
        .probe4(ila_mac_activity));

    /* Per-channel payload ILAs require Vivado Core or higher.  The system ILA
       above remains enabled for the Basic-licensed K325T build.
    ila_eth0 eth0_debug (
        .clk(net_clk),
        .probe0(mac_rx_data[0]), .probe1(mac_rx_keep[0]),
        .probe2(mac_rx_valid[0]), .probe3(mac_rx_last[0]),
        .probe4(mac_rx_error[0]), .probe5(mac_tx_data[0]),
        .probe6(mac_tx_keep[0]), .probe7(mac_tx_valid[0]),
        .probe8(mac_tx_ready[0]), .probe9(mac_tx_last[0]),
        .probe10(eth_status[0]), .probe11(sfp_los[0]),
        .probe12(rx_in_frame[0]), .probe13(txusr_heartbeat),
        .probe14(dclk_heartbeat));

    ila_eth1 eth1_debug (
        .clk(net_clk),
        .probe0(mac_rx_data[1]), .probe1(mac_rx_keep[1]),
        .probe2(mac_rx_valid[1]), .probe3(mac_rx_last[1]),
        .probe4(mac_rx_error[1]), .probe5(mac_tx_data[1]),
        .probe6(mac_tx_keep[1]), .probe7(mac_tx_valid[1]),
        .probe8(mac_tx_ready[1]), .probe9(mac_tx_last[1]),
        .probe10(eth_status[1]), .probe11(sfp_los[1]),
        .probe12(rx_in_frame[1]), .probe13(txusr_heartbeat),
        .probe14(dclk_heartbeat));
    */
endmodule

`default_nettype wire
