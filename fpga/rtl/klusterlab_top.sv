`timescale 1ns/1ps
`default_nettype none

module klusterlab_top #(
    // Lossless bridge policy.  Keep enabled for normal operation.  It can be
    // disabled in a diagnostic build when a peer has broken 802.3x behavior.
    parameter bit HONOR_RX_PAUSE = 1'b1,
    parameter bit USE_PROCESSING_STUB = 1'b1
) (
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
    output wire [1:0] sfp_tx_en,
    // JTAG-SMT3 USB-UART signal names are from the bridge's perspective:
    // its RXD/CTS are FPGA outputs, while its TXD/RTS are FPGA inputs.
    input  wire       uart_usb_txd,
    input  wire       uart_usb_rts,
    output wire       uart_usb_rxd,
    output wire       uart_usb_cts
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

    // CTS is active low. Keep the USB bridge permitted; UARTProbe below uses
    // TXD as its command input and drives RXD with framed binary captures.
    assign uart_usb_cts = 1'b0;

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
    // The legacy Xilinx 10G MAC uses active-high GOOD-frame polarity on
    // m_axis_rx_tuser (unlike newer Ethernet subsystem IP).
    wire [1:0]  mac_rx_good;
    wire [1:0]  mac_rx_valid;
    wire [63:0] mac_tx_data [0:1];
    wire [7:0]  mac_tx_keep [0:1];
    wire [1:0]  mac_tx_last;
    wire [1:0]  mac_tx_valid;
    wire [1:0]  mac_tx_ready;
    wire [25:0] mac_tx_statistics [0:1];
    wire [1:0]  mac_tx_statistics_valid;
    wire [29:0] mac_rx_statistics [0:1];
    wire [1:0]  mac_rx_statistics_valid;
    wire [1:0]  nic_rx_almost_full;
    reg  [1:0]  mac_pause_valid = 2'b00;
    reg  [15:0] mac_pause_data [0:1];
    reg  [1:0]  mac_pause_active = 2'b00;
    reg  [16:0] mac_pause_refresh [0:1];

    // Logical lane 0 is constrained to board SFP2/fpga2 and logical lane 1 to
    // board SFP3/fpga1. Configuration-vector bit 1 enables each MAC;
    // VLAN/custom-preamble and
    // PCS loopback remain disabled.  FCS is generated/checked by the MAC.
    // The TX and RX vectors share bit positions only partially and therefore
    // must not be one common constant.  TX bit 10 enables Deficit Idle Count
    // for maximum legal Ethernet throughput; RX bit 10 instead means fault
    // inhibit and stays clear.  Bit 5 enables ordinary 802.3x flow control.
    // Vector bytes [79:32] are transmitted least-significant byte first.
    localparam [79:0] MAC0_TX_CONFIG =
        {48'h100000000002, 32'h00000422}; // source 02:00:00:00:00:10
    localparam [79:0] MAC1_TX_CONFIG =
        {48'h110000000002, 32'h00000422}; // source 02:00:00:00:00:11
    // Match the globally assigned pause destination 01:80:C2:00:00:01.
    // RX bit 5 enables received 802.3x flow control and bit 1 enables the MAC.
    localparam [79:0] MAC_RX_CONFIG =
        {48'h010000C28001,
         (HONOR_RX_PAUSE ? 32'h00000022 : 32'h00000002)};
    localparam [535:0] PCS_CONFIG = 536'd0;

    eth10g_master eth0 (
        .tx_axis_aresetn(~startup_reset), .rx_axis_aresetn(~startup_reset),
        .tx_ifg_delay(8'd0), .dclk(startup_clk_50),
        .txp(sfp_tx_p[0]), .txn(sfp_tx_n[0]),
        .rxp(sfp_rx_p[0]), .rxn(sfp_rx_n[0]),
        .signal_detect(~sfp_los[0]), .tx_fault(1'b0),
        .tx_disable(eth_tx_disable[0]), .pcspma_status(eth_status[0]),
        .sim_speedup_control(1'b0), .rxrecclk_out(),
        .mac_tx_configuration_vector(MAC0_TX_CONFIG),
        .mac_rx_configuration_vector(MAC_RX_CONFIG), .mac_status_vector(),
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
        .s_axis_pause_tdata(mac_pause_data[0]),
        .s_axis_pause_tvalid(mac_pause_valid[0]),
        .m_axis_rx_tdata(mac_rx_data[0]), .m_axis_rx_tkeep(mac_rx_keep[0]),
        .m_axis_rx_tlast(mac_rx_last[0]), .m_axis_rx_tuser(mac_rx_good[0]),
        .m_axis_rx_tvalid(mac_rx_valid[0]),
        .tx_statistics_valid(mac_tx_statistics_valid[0]),
        .tx_statistics_vector(mac_tx_statistics[0]),
        .rx_statistics_valid(mac_rx_statistics_valid[0]),
        .rx_statistics_vector(mac_rx_statistics[0]));

    eth10g_slave eth1 (
        .tx_axis_aresetn(~startup_reset), .rx_axis_aresetn(~startup_reset),
        .tx_ifg_delay(8'd0), .dclk(startup_clk_50),
        .txp(sfp_tx_p[1]), .txn(sfp_tx_n[1]),
        .rxp(sfp_rx_p[1]), .rxn(sfp_rx_n[1]),
        .signal_detect(~sfp_los[1]), .tx_fault(1'b0),
        .tx_disable(eth_tx_disable[1]), .pcspma_status(eth_status[1]),
        .sim_speedup_control(1'b0), .rxrecclk_out(),
        .mac_tx_configuration_vector(MAC1_TX_CONFIG),
        .mac_rx_configuration_vector(MAC_RX_CONFIG), .mac_status_vector(),
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
        .s_axis_pause_tdata(mac_pause_data[1]),
        .s_axis_pause_tvalid(mac_pause_valid[1]),
        .m_axis_rx_tdata(mac_rx_data[1]), .m_axis_rx_tkeep(mac_rx_keep[1]),
        .m_axis_rx_tlast(mac_rx_last[1]), .m_axis_rx_tuser(mac_rx_good[1]),
        .m_axis_rx_tvalid(mac_rx_valid[1]),
        .tx_statistics_valid(mac_tx_statistics_valid[1]),
        .tx_statistics_vector(mac_tx_statistics[1]),
        .rx_statistics_valid(mac_rx_statistics_valid[1]),
        .rx_statistics_vector(mac_rx_statistics[1]));

    // KlusterLab r2.0 does not route these pins directly to SFP TX_DISABLE.
    // Each TX_EN drives the gate of an N-MOSFET which pulls the module's
    // active-high TX_DISABLE input low.  Keep both optical/electrical
    // transmitters enabled throughout board bring-up.  The PCS tx_disable
    // outputs are retained below as probe status; they also control the GTX
    // TXINHIBIT internally and must not be reused as board enables.
    assign sfp_tx_en = 2'b11;

    (* ASYNC_REG = "TRUE" *) reg [3:0] net_reset_sync = 4'hf;
    always @(posedge net_clk)
        net_reset_sync <= {net_reset_sync[2:0],
            (startup_reset | ~eth_reset_done)};
    wire design_reset = net_reset_sync[3];

    // Lossless clock compensation between each independently clocked remote
    // transmitter and the common FPGA transmit clock.  InputBalancer raises
    // its per-port high-water mark at half of its 16 KiB elastic FIFO.  Send
    // maximum-quanta XOFF at that point, refresh it while pressure remains,
    // and send a zero-quanta XON as soon as the FIFO drains below half.  The
    // remaining 8 KiB covers PAUSE propagation plus an in-flight jumbo frame.
    integer pause_lane;
    always @(posedge net_clk) begin
        mac_pause_valid <= 2'b00;
        if (design_reset) begin
            mac_pause_active <= 2'b00;
            for (pause_lane = 0; pause_lane < 2;
                 pause_lane = pause_lane + 1) begin
                mac_pause_data[pause_lane] <= 16'd0;
                mac_pause_refresh[pause_lane] <= 17'd0;
            end
        end else begin
            for (pause_lane = 0; pause_lane < 2;
                 pause_lane = pause_lane + 1) begin
                if (nic_rx_almost_full[pause_lane]
                    && !mac_pause_active[pause_lane]) begin
                    mac_pause_active[pause_lane] <= 1'b1;
                    mac_pause_data[pause_lane] <= 16'hffff;
                    mac_pause_valid[pause_lane] <= 1'b1;
                    mac_pause_refresh[pause_lane] <= 17'd0;
                end else if (!nic_rx_almost_full[pause_lane]
                    && mac_pause_active[pause_lane]) begin
                    mac_pause_active[pause_lane] <= 1'b0;
                    mac_pause_data[pause_lane] <= 16'h0000;
                    mac_pause_valid[pause_lane] <= 1'b1;
                    mac_pause_refresh[pause_lane] <= 17'd0;
                end else if (mac_pause_active[pause_lane]) begin
                    if (mac_pause_refresh[pause_lane] == 17'h1ffff) begin
                        mac_pause_data[pause_lane] <= 16'hffff;
                        mac_pause_valid[pause_lane] <= 1'b1;
                        mac_pause_refresh[pause_lane] <= 17'd0;
                    end else begin
                        mac_pause_refresh[pause_lane]
                            <= mac_pause_refresh[pause_lane] + 1'b1;
                    end
                end else begin
                    mac_pause_refresh[pause_lane] <= 17'd0;
                end
            end
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

    // PG072 tx_statistics_vector[25] identifies a MAC-generated pause frame.
    // Keep this sticky for post-failure UART diagnostics; JTAG/ILA is not
    // available on the target.
    reg [1:0] mac_pause_transmitted_sticky = 2'b00;
    reg [1:0] mac_pause_received_sticky = 2'b00;
    always @(posedge net_clk) begin
        if (design_reset) begin
            mac_pause_transmitted_sticky <= 2'b00;
            mac_pause_received_sticky <= 2'b00;
        end else begin
            if (mac_tx_statistics_valid[0] && mac_tx_statistics[0][25])
                mac_pause_transmitted_sticky[0] <= 1'b1;
            if (mac_tx_statistics_valid[1] && mac_tx_statistics[1][25])
                mac_pause_transmitted_sticky[1] <= 1'b1;
            // PG072 rx_statistics_vector[27] is asserted only for a valid
            // PAUSE frame that matched and was acted on by the MAC.
            if (mac_rx_statistics_valid[0] && mac_rx_statistics[0][27])
                mac_pause_received_sticky[0] <= 1'b1;
            if (mac_rx_statistics_valid[1] && mac_rx_statistics[1][27])
                mac_pause_received_sticky[1] <= 1'b1;
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
    wire [1:0] smart_tx_ready = {
        (!lane1_present || mac_tx_ready[1]),
        (!lane0_present || mac_tx_ready[0])};
    assign mac_tx_data[0] = smart_tx_data[63:0];
    assign mac_tx_data[1] = smart_tx_data[127:64];
    assign mac_tx_keep[0] = smart_tx_keep[7:0];
    assign mac_tx_keep[1] = smart_tx_keep[15:8];
    assign mac_tx_last[0] = |smart_tx_eop[7:0];
    assign mac_tx_last[1] = |smart_tx_eop[15:8];
    // AXI valid must not depend on ready. OutputMerger holds its word while
    // smart_tx_ready is low; each active MAC therefore sees stable valid/data
    // until its transfer is accepted.
    assign mac_tx_valid[0] = smart_tx_valid && lane0_present;
    assign mac_tx_valid[1] = smart_tx_valid && lane1_present;

    wire descriptor_valid;
    wire [255:0] descriptor_data;
    wire [2:0] descriptor_word;
    wire descriptor_sop, descriptor_eop, descriptor_ready;
    wire [1:0] rx_read_valid, rx_read_ready;
    wire [33:0] rx_read_handle;
    wire [27:0] rx_read_length;
    wire [1:0] l2_rx_valid, l2_rx_ready, l2_rx_sop, l2_rx_eop;
    wire [511:0] l2_rx_data;
    wire [63:0] l2_rx_keep;
    wire [1:0] l2_tx_valid, l2_tx_ready, l2_tx_sop, l2_tx_eop;
    wire [511:0] l2_tx_data;
    wire [63:0] l2_tx_keep;
    wire nic_protocol_error;
    wire nic_storage_full;
    wire nic_rx_ready;

    SmartNIC #(.BANK_DEPTH(4096), .RX_FIFO_DEPTH(64),
               .TX_FIFO_WORDS(2048), .ENABLE_RAW(1)) nic (
        .net_clk(net_clk), .l2_clk(net_clk), .reset(design_reset),
        .net_rx_valid_in(net_rx_valid), .net_rx_data_in(net_rx_data),
        .net_rx_keep_in(net_rx_keep), .net_rx_sop_in(net_rx_sop),
        .net_rx_eop_in(net_rx_eop), .net_rx_raw_in(1'b1),
        .net_rx_ready_out(nic_rx_ready),
        .net_rx_almost_full_out(nic_rx_almost_full),
        .net_tx_valid_out(smart_tx_valid),
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

    wire processing_protocol_error;
    wire processing_probe_dumping;
    wire pcie_system_clock;
    wire pcie_link_up;
    wire pcie_system_reset;
    wire system_protocol_error;
    wire [11:0] pcie_system_activity;
    (* ASYNC_REG = "TRUE" *) reg [5:0] status_async_sync1 = 6'b000000;
    (* ASYNC_REG = "TRUE" *) reg [5:0] status_async_sync2 = 6'b000000;
    always @(posedge net_clk) begin
        status_async_sync1 <= {
            eth_tx_disable[1], eth_tx_disable[0],
            pcie_system_reset, pcie_link_up, sfp_los[1], sfp_los[0]};
        status_async_sync2 <= status_async_sync1;
    end
    reg [1:0] mac_rx_error_sticky = 2'b00;
    always @(posedge net_clk) begin
        if (design_reset)
            mac_rx_error_sticky <= 2'b00;
        else begin
            // For this legacy XGEMAC, m_axis_rx_tuser=1 means GOOD and zero
            // means BAD.  It is meaningful only on a valid final beat.
            if (mac_rx_valid[0] && mac_rx_last[0] && !mac_rx_good[0])
                mac_rx_error_sticky[0] <= 1'b1;
            if (mac_rx_valid[1] && mac_rx_last[1] && !mac_rx_good[1])
                mac_rx_error_sticky[1] <= 1'b1;
        end
    end
    wire [15:0] stub_system_status = {
        mac_pause_transmitted_sticky[1],
        mac_pause_transmitted_sticky[0],
        eth_status[1][0], eth_status[0][0],
        nic_storage_full, nic_protocol_error,
        mac_rx_error_sticky[1], mac_rx_error_sticky[0],
        mac_pause_received_sticky[1], mac_pause_received_sticky[0], design_reset,
        net_reset_from_ip, eth_reset_counter_done,
        eth_reset_done, eth_qpll_lock, startup_locked};
    wire proc_to_system_valid, proc_to_system_ready;
    wire [255:0] proc_to_system_data;
    wire [31:0] proc_to_system_keep;
    wire proc_to_system_sop, proc_to_system_eop;
    wire proc_from_system_valid, proc_from_system_ready;
    wire [255:0] proc_from_system_data;
    wire [31:0] proc_from_system_keep;
    wire proc_from_system_sop, proc_from_system_eop;

    generate if (USE_PROCESSING_STUB) begin : processing_stub_mode
        ProcessingStub #(.HANDLE_BITS(17)) processing_stub (
            .clk(net_clk), .reset(design_reset),
            .descriptor_valid_in(descriptor_valid),
            .descriptor_data_in(descriptor_data),
            .descriptor_word_in(descriptor_word),
            .descriptor_sop_in(descriptor_sop),
            .descriptor_eop_in(descriptor_eop),
            .descriptor_ready_out(descriptor_ready),
            .rx_read_valid_out(rx_read_valid),
            .rx_read_handle_out(rx_read_handle),
            .rx_read_length_out(rx_read_length),
            .rx_read_ready_in(rx_read_ready),
            .rx_valid_in(l2_rx_valid), .rx_data_in(l2_rx_data),
            .rx_keep_in(l2_rx_keep), .rx_sop_in(l2_rx_sop),
            .rx_eop_in(l2_rx_eop), .rx_ready_out(l2_rx_ready),
            .tx_valid_out(l2_tx_valid), .tx_data_out(l2_tx_data),
            .tx_keep_out(l2_tx_keep), .tx_sop_out(l2_tx_sop),
            .tx_eop_out(l2_tx_eop), .tx_ready_in(l2_tx_ready),
            .system_status_in(stub_system_status),
            .mac_tx_status_in({mac_tx_ready[1], mac_tx_valid[1],
                               mac_tx_ready[0], mac_tx_valid[0]}),
            .uart_rx_in(uart_usb_txd), .uart_trigger_in(uart_usb_rts),
            .uart_tx_out(uart_usb_rxd),
            .probe_dumping_out(processing_probe_dumping),
            .protocol_error_out(processing_protocol_error));
        assign proc_to_system_valid = 1'b0;
        assign proc_to_system_data = 256'd0;
        assign proc_to_system_keep = 32'd0;
        assign proc_to_system_sop = 1'b0;
        assign proc_to_system_eop = 1'b0;
        assign proc_from_system_ready = 1'b1;
    end else begin : processing_cpu_mode
        wire proc_rx_read_valid;
        wire [16:0] proc_rx_read_handle;
        wire [13:0] proc_rx_read_length;
        wire proc_rx_ready;
        wire proc_tx_valid;
        wire [255:0] proc_tx_data;
        wire [31:0] proc_tx_keep;
        wire proc_tx_sop, proc_tx_eop, proc_tx_ready;
        wire [7:0] proc_tx_port;
        wire proc_dma_busy, proc_dma_error, proc_fetcher_error;
        wire [31:0] proc_dma_completed;
        wire [3:0] proc_dma_error_reason;
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

        assign rx_read_valid = {1'b0, proc_rx_read_valid};
        assign rx_read_handle = {17'd0, proc_rx_read_handle};
        assign rx_read_length = {14'd0, proc_rx_read_length};
        assign l2_rx_ready = {1'b0, proc_rx_ready};
        assign l2_tx_valid = {
            proc_tx_valid && proc_tx_port[0],
            proc_tx_valid && !proc_tx_port[0]};
        assign l2_tx_data = {proc_tx_data, proc_tx_data};
        assign l2_tx_keep = {proc_tx_keep, proc_tx_keep};
        assign l2_tx_sop = {
            proc_tx_sop && proc_tx_port[0],
            proc_tx_sop && !proc_tx_port[0]};
        assign l2_tx_eop = {
            proc_tx_eop && proc_tx_port[0],
            proc_tx_eop && !proc_tx_port[0]};
        assign proc_tx_ready = proc_tx_port[0]
            ? l2_tx_ready[1] : l2_tx_ready[0];

        axi_boot_bram #(
            .BYTES(131072), .INIT_FILE("cpu_loopback.mem")
        ) boot_memory (
            .clk(net_clk), .reset(design_reset),
            .awvalid(ddr_awvalid[0]), .awready(ddr_awready[0]),
            .awaddr(ddr_awaddr[0]), .awid(ddr_awid[0]),
            .wvalid(ddr_wvalid[0]), .wready(ddr_wready[0]),
            .wdata(ddr_wdata[0]), .wstrb(ddr_wstrb[0]),
            .wlast(ddr_wlast[0]), .bvalid(ddr_bvalid[0]),
            .bready(ddr_bready[0]), .bid(ddr_bid[0]),
            .arvalid(ddr_arvalid[0]), .arready(ddr_arready[0]),
            .araddr(ddr_araddr[0]), .arid(ddr_arid[0]),
            .rvalid(ddr_rvalid[0]), .rready(ddr_rready[0]),
            .rdata(ddr_rdata[0]), .rlast(ddr_rlast[0]),
            .rid(ddr_rid[0]));

        genvar irq_i;
        for (irq_i = 0; irq_i < 4; irq_i = irq_i + 1) begin : irq_tieoff
            assign software_irq[irq_i] = 1'b0;
            assign timer_irq[irq_i] = 1'b0;
            assign external_irq[irq_i] = 1'b0;
        end
        assign cache_invalidate[0] = 1'b0;

        Processing #(.HANDLE_BITS(17)) processing (
            .clk(net_clk), .l2_clock(net_clk), .reset(design_reset),
            .descriptor_valid_in(descriptor_valid),
            .descriptor_data_in(descriptor_data),
            .descriptor_word_in(descriptor_word),
            .descriptor_sop_in(descriptor_sop),
            .descriptor_eop_in(descriptor_eop),
            .descriptor_ready_out(descriptor_ready),
            .rx_read_valid_out(proc_rx_read_valid),
            .rx_read_handle_out(proc_rx_read_handle),
            .rx_read_length_out(proc_rx_read_length),
            .rx_read_ready_in(rx_read_ready[0]),
            .rx_valid_in(l2_rx_valid[0]), .rx_data_in(l2_rx_data[255:0]),
            .rx_keep_in(l2_rx_keep[31:0]), .rx_sop_in(l2_rx_sop[0]),
            .rx_eop_in(l2_rx_eop[0]), .rx_ready_out(proc_rx_ready),
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
            .to_network_data_out(proc_tx_data),
            .to_network_keep_out(proc_tx_keep),
            .to_network_sop_out(proc_tx_sop),
            .to_network_eop_out(proc_tx_eop),
            .to_network_port_out(proc_tx_port),
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
            .cache_invalidate_in(cache_invalidate),
            .debug_dma_busy_out(proc_dma_busy),
            .debug_dma_error_out(proc_dma_error),
            .debug_fetcher_error_out(proc_fetcher_error),
            .debug_dma_completed_out(proc_dma_completed),
            .debug_dma_error_reason_out(proc_dma_error_reason));

        reg [15:0] descriptor_count = 16'd0;
        reg [15:0] rx_word_count = 16'd0;
        reg [15:0] tx_word_count = 16'd0;
        reg [15:0] tx_packet_count = 16'd0;
        always @(posedge net_clk) begin
            if (design_reset) begin
                descriptor_count <= 16'd0;
                rx_word_count <= 16'd0;
                tx_word_count <= 16'd0;
                tx_packet_count <= 16'd0;
            end else begin
                if (descriptor_valid && descriptor_ready && descriptor_eop)
                    descriptor_count <= descriptor_count + 1'b1;
                if (l2_rx_valid[0] && proc_rx_ready)
                    rx_word_count <= rx_word_count + 1'b1;
                if (proc_tx_valid && proc_tx_ready)
                    tx_word_count <= tx_word_count + 1'b1;
                if (proc_tx_valid && proc_tx_ready && proc_tx_eop)
                    tx_packet_count <= tx_packet_count + 1'b1;
            end
        end
        wire [15:0] cpu_probe_flags = {
            (nic_protocol_error | nic_storage_full), proc_fetcher_error,
            proc_dma_error, proc_dma_busy, proc_tx_ready, proc_tx_valid,
            proc_rx_ready, l2_rx_valid[0], rx_read_ready[0],
            proc_rx_read_valid, descriptor_ready, descriptor_valid,
            eth_status[1][0], eth_status[0][0], eth_qpll_lock,
            startup_locked};
        wire [7:0] cpu_probe_status = {4'd0, proc_dma_error_reason};
        wire [7:0] cpu_probe_event = {
            proc_tx_port[0], proc_tx_eop, proc_tx_sop, l2_rx_eop[0],
            l2_rx_sop[0], descriptor_eop, descriptor_sop,
            proc_dma_completed[0]};
        wire [95:0] cpu_probe_data = {
            tx_packet_count, tx_word_count, rx_word_count, descriptor_count,
            cpu_probe_event, cpu_probe_status, cpu_probe_flags};
        UARTProbe #(
            .CLOCK_HZ(156250000), .BAUD(115200), .SAMPLE_DIV(15625),
            .DEPTH(1024), .SCHEMA(32'h55504350)
        ) cpu_uart_probe (
            .clk(net_clk), .reset(design_reset),
            .uart_rx_in(uart_usb_txd), .dump_trigger_in(uart_usb_rts),
            .uart_tx_out(uart_usb_rxd), .probe_in(cpu_probe_data),
            .dumping_out(processing_probe_dumping));
        assign processing_protocol_error =
            proc_dma_error | proc_fetcher_error;
    end endgenerate

    pcie_system host_system (
        .startup_reset(startup_reset), .l2_clock(net_clk),
        .pcie_perst_n(pcie_perst_n), .pcie_refclk_p(pcie_refclk_p),
        .pcie_refclk_n(pcie_refclk_n), .pcie_rx_p(pcie_rx_p),
        .pcie_rx_n(pcie_rx_n), .pcie_tx_p(pcie_tx_p), .pcie_tx_n(pcie_tx_n),
        .l2_rx_valid(proc_to_system_valid),
        .l2_rx_data(proc_to_system_data),
        .l2_rx_keep(proc_to_system_keep),
        .l2_rx_sop(proc_to_system_sop),
        .l2_rx_eop(proc_to_system_eop),
        .l2_rx_ready(proc_to_system_ready),
        .l2_tx_valid(proc_from_system_valid),
        .l2_tx_data(proc_from_system_data),
        .l2_tx_keep(proc_from_system_keep),
        .l2_tx_sop(proc_from_system_sop),
        .l2_tx_eop(proc_from_system_eop),
        .l2_tx_ready(proc_from_system_ready),
        .system_clock(pcie_system_clock), .link_up(pcie_link_up),
        .system_reset(pcie_system_reset), .protocol_error(system_protocol_error),
        .activity(pcie_system_activity));

    // All ChipScope/ILA probes are intentionally disabled.  This target has
    // no usable JTAG connection, so retaining debug hubs or probe fanout only
    // consumes routing resources without providing observability.
endmodule

`default_nettype wire
