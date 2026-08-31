`timescale 1ns/1ps
`default_nettype none

// Standalone hardware-diagnostic image.  It keeps the exact 10G master/slave
// topology used by klusterlab_top, but omits the dense SmartNIC datapath so a
// UART probe image can always be routed and used before debugging that logic.
module uart_10g_probe_top (
    input  wire       sys_clk_200_p,
    input  wire       sys_clk_200_n,
    input  wire       eth_refclk_p,
    input  wire       eth_refclk_n,
    input  wire [3:0] sfp_rx_p,
    input  wire [3:0] sfp_rx_n,
    output wire [3:0] sfp_tx_p,
    output wire [3:0] sfp_tx_n,
    input  wire [3:0] sfp_los,
    output wire [3:0] sfp_tx_en,
    input  wire       uart_usb_txd,
    input  wire       uart_usb_rts,
    output wire       uart_usb_rxd,
    output wire       uart_usb_cts,
    inout  wire       main_i2c_scl,
    inout  wire       main_i2c_sda,
    output wire       main_i2c_mux_reset_n
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
    wire [3:1] slave_tx_resetdone;
    wire [3:1] slave_rx_resetdone;
    wire [3:0] eth_tx_disable;
    wire [7:0] eth_status [0:3];
    wire [3:0] mac_rx_valid;
    wire [3:0] mac_rx_error;
    wire [3:0] mac_tx_ready;

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
        .s_axis_tx_tdata(64'd0), .s_axis_tx_tkeep(8'd0),
        .s_axis_tx_tlast(1'b0), .s_axis_tx_tready(mac_tx_ready[0]),
        .s_axis_tx_tuser(1'b0), .s_axis_tx_tvalid(1'b0),
        .s_axis_pause_tdata(16'd0), .s_axis_pause_tvalid(1'b0),
        .m_axis_rx_tdata(), .m_axis_rx_tkeep(), .m_axis_rx_tlast(),
        .m_axis_rx_tuser(mac_rx_error[0]), .m_axis_rx_tvalid(mac_rx_valid[0]),
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
        .txuserrdy(eth_txuserrdy), .tx_resetdone(slave_tx_resetdone[1]),
        .rx_resetdone(slave_rx_resetdone[1]),
        .coreclk(net_clk), .areset(net_reset_from_ip),
        .gttxreset(eth_gttxreset), .gtrxreset(eth_gtrxreset),
        .qplllock(eth_qpll_lock), .qplloutclk(eth_qpll_clk),
        .qplloutrefclk(eth_qpll_refclk),
        .reset_counter_done(eth_reset_counter_done),
        .s_axis_tx_tdata(64'd0), .s_axis_tx_tkeep(8'd0),
        .s_axis_tx_tlast(1'b0), .s_axis_tx_tready(mac_tx_ready[1]),
        .s_axis_tx_tuser(1'b0), .s_axis_tx_tvalid(1'b0),
        .s_axis_pause_tdata(16'd0), .s_axis_pause_tvalid(1'b0),
        .m_axis_rx_tdata(), .m_axis_rx_tkeep(), .m_axis_rx_tlast(),
        .m_axis_rx_tuser(mac_rx_error[1]), .m_axis_rx_tvalid(mac_rx_valid[1]),
        .tx_statistics_valid(), .tx_statistics_vector(),
        .rx_statistics_valid(), .rx_statistics_vector());

    eth10g_slave2 eth2 (
        .tx_axis_aresetn(~startup_reset), .rx_axis_aresetn(~startup_reset),
        .tx_ifg_delay(8'd0), .dclk(startup_clk_50),
        .txp(sfp_tx_p[2]), .txn(sfp_tx_n[2]),
        .rxp(sfp_rx_p[2]), .rxn(sfp_rx_n[2]),
        .signal_detect(~sfp_los[2]), .tx_fault(1'b0),
        .tx_disable(eth_tx_disable[2]), .pcspma_status(eth_status[2]),
        .sim_speedup_control(1'b0), .rxrecclk_out(),
        .mac_tx_configuration_vector(MAC_CONFIG),
        .mac_rx_configuration_vector(MAC_CONFIG), .mac_status_vector(),
        .pcs_pma_configuration_vector(PCS_CONFIG), .pcs_pma_status_vector(),
        .areset_coreclk(net_reset_from_ip),
        .txusrclk(eth_txusrclk), .txusrclk2(eth_txusrclk2), .txoutclk(),
        .txuserrdy(eth_txuserrdy), .tx_resetdone(slave_tx_resetdone[2]),
        .rx_resetdone(slave_rx_resetdone[2]),
        .coreclk(net_clk), .areset(net_reset_from_ip),
        .gttxreset(eth_gttxreset), .gtrxreset(eth_gtrxreset),
        .qplllock(eth_qpll_lock), .qplloutclk(eth_qpll_clk),
        .qplloutrefclk(eth_qpll_refclk),
        .reset_counter_done(eth_reset_counter_done),
        .s_axis_tx_tdata(64'd0), .s_axis_tx_tkeep(8'd0),
        .s_axis_tx_tlast(1'b0), .s_axis_tx_tready(mac_tx_ready[2]),
        .s_axis_tx_tuser(1'b0), .s_axis_tx_tvalid(1'b0),
        .s_axis_pause_tdata(16'd0), .s_axis_pause_tvalid(1'b0),
        .m_axis_rx_tdata(), .m_axis_rx_tkeep(), .m_axis_rx_tlast(),
        .m_axis_rx_tuser(mac_rx_error[2]), .m_axis_rx_tvalid(mac_rx_valid[2]),
        .tx_statistics_valid(), .tx_statistics_vector(),
        .rx_statistics_valid(), .rx_statistics_vector());

    eth10g_slave3 eth3 (
        .tx_axis_aresetn(~startup_reset), .rx_axis_aresetn(~startup_reset),
        .tx_ifg_delay(8'd0), .dclk(startup_clk_50),
        .txp(sfp_tx_p[3]), .txn(sfp_tx_n[3]),
        .rxp(sfp_rx_p[3]), .rxn(sfp_rx_n[3]),
        .signal_detect(~sfp_los[3]), .tx_fault(1'b0),
        .tx_disable(eth_tx_disable[3]), .pcspma_status(eth_status[3]),
        .sim_speedup_control(1'b0), .rxrecclk_out(),
        .mac_tx_configuration_vector(MAC_CONFIG),
        .mac_rx_configuration_vector(MAC_CONFIG), .mac_status_vector(),
        .pcs_pma_configuration_vector(PCS_CONFIG), .pcs_pma_status_vector(),
        .areset_coreclk(net_reset_from_ip),
        .txusrclk(eth_txusrclk), .txusrclk2(eth_txusrclk2), .txoutclk(),
        .txuserrdy(eth_txuserrdy), .tx_resetdone(slave_tx_resetdone[3]),
        .rx_resetdone(slave_rx_resetdone[3]),
        .coreclk(net_clk), .areset(net_reset_from_ip),
        .gttxreset(eth_gttxreset), .gtrxreset(eth_gtrxreset),
        .qplllock(eth_qpll_lock), .qplloutclk(eth_qpll_clk),
        .qplloutrefclk(eth_qpll_refclk),
        .reset_counter_done(eth_reset_counter_done),
        .s_axis_tx_tdata(64'd0), .s_axis_tx_tkeep(8'd0),
        .s_axis_tx_tlast(1'b0), .s_axis_tx_tready(mac_tx_ready[3]),
        .s_axis_tx_tuser(1'b0), .s_axis_tx_tvalid(1'b0),
        .s_axis_pause_tdata(16'd0), .s_axis_pause_tvalid(1'b0),
        .m_axis_rx_tdata(), .m_axis_rx_tkeep(), .m_axis_rx_tlast(),
        .m_axis_rx_tuser(mac_rx_error[3]), .m_axis_rx_tvalid(mac_rx_valid[3]),
        .tx_statistics_valid(), .tx_statistics_vector(),
        .rx_statistics_valid(), .rx_statistics_vector());

    assign sfp_tx_en = ~eth_tx_disable;

    (* ASYNC_REG = "TRUE" *) reg [3:0] net_reset_sync = 4'hf;
    always @(posedge net_clk)
        net_reset_sync <= {net_reset_sync[2:0],
            startup_reset | ~eth_reset_done};
    wire design_reset = net_reset_sync[3];

    reg [15:0] probe_net_clock_count = 16'd0;
    reg [15:0] probe_txusr_clock_count = 16'd0;
    reg [3:0] probe_rx0_count = 4'd0;
    reg [3:0] probe_rx1_count = 4'd0;
    reg [3:0] probe_tx0_count = 4'd0;
    reg [3:0] probe_tx1_count = 4'd0;
    reg [1:0] probe_rx_error_sticky = 2'b00;

    always @(posedge net_clk) begin
        probe_net_clock_count <= probe_net_clock_count + 1'b1;
        if (mac_rx_valid[0]) probe_rx0_count <= probe_rx0_count + 1'b1;
        if (mac_rx_valid[1]) probe_rx1_count <= probe_rx1_count + 1'b1;
        if (mac_tx_ready[0]) probe_tx0_count <= probe_tx0_count + 1'b1;
        if (mac_tx_ready[1]) probe_tx1_count <= probe_tx1_count + 1'b1;
        probe_rx_error_sticky <= probe_rx_error_sticky | mac_rx_error[1:0];
    end

    always @(posedge eth_txusrclk)
        probe_txusr_clock_count <= probe_txusr_clock_count + 1'b1;

    // Keep evidence of activity on both USB-to-FPGA control inputs. These
    // sticky bits are included in the autonomous dump and therefore remain
    // observable even when neither input can trigger the probe.
    (* ASYNC_REG = "TRUE" *) reg uart_txd_sync1 = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg uart_txd_sync2 = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg uart_rts_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg uart_rts_sync2 = 1'b0;
    reg uart_txd_previous = 1'b1;
    reg uart_rts_previous = 1'b0;
    reg [2:0] uart_input_warmup = 3'd0;
    reg uart_txd_edge_seen = 1'b0;
    reg uart_rts_edge_seen = 1'b0;
    always @(posedge startup_clk_50) begin
        uart_txd_sync1 <= uart_usb_txd;
        uart_txd_sync2 <= uart_txd_sync1;
        uart_rts_sync1 <= uart_usb_rts;
        uart_rts_sync2 <= uart_rts_sync1;
        if (startup_reset) begin
            uart_input_warmup <= 3'd0;
            uart_txd_previous <= 1'b1;
            uart_rts_previous <= 1'b0;
            uart_txd_edge_seen <= 1'b0;
            uart_rts_edge_seen <= 1'b0;
        end else if (uart_input_warmup != 3'd7) begin
            uart_input_warmup <= uart_input_warmup + 1'b1;
            uart_txd_previous <= uart_txd_sync2;
            uart_rts_previous <= uart_rts_sync2;
        end else begin
            uart_txd_edge_seen <= uart_txd_edge_seen
                | (uart_txd_sync2 != uart_txd_previous);
            uart_rts_edge_seen <= uart_rts_edge_seen
                | (uart_rts_sync2 != uart_rts_previous);
            uart_txd_previous <= uart_txd_sync2;
            uart_rts_previous <= uart_rts_sync2;
        end
    end

    function automatic [15:0] binary_to_gray16(input [15:0] value);
        binary_to_gray16 = value ^ (value >> 1);
    endfunction
    function automatic [3:0] binary_to_gray4(input [3:0] value);
        binary_to_gray4 = value ^ (value >> 1);
    endfunction

    wire [47:0] probe_clocks_gray_async = {
        16'd0, binary_to_gray16(probe_txusr_clock_count),
        binary_to_gray16(probe_net_clock_count)};
    wire [15:0] probe_activity_gray_async = {
        binary_to_gray4(probe_tx1_count), binary_to_gray4(probe_tx0_count),
        binary_to_gray4(probe_rx1_count), binary_to_gray4(probe_rx0_count)};
    wire [15:0] probe_flags_async = {
        eth_tx_disable[1], eth_tx_disable[0], uart_txd_edge_seen,
        probe_rx_error_sticky[1], probe_rx_error_sticky[0],
        sfp_los[1], sfp_los[0], slave_rx_resetdone[1], slave_tx_resetdone[1],
        design_reset, net_reset_from_ip, eth_reset_counter_done,
        eth_reset_done, eth_qpll_lock, startup_reset, startup_locked};
    wire [15:0] probe_status_async = {eth_status[1], eth_status[0]};

    wire sfp_diag_done;
    wire sfp_diag_mux_found;
    wire [6:0] sfp_diag_mux_address;
    wire [1:0] sfp_diag_port_valid;
    wire [7:0] sfp_diag_identifier [0:1];
    wire [15:0] sfp_diag_tx_bias [0:1];
    wire [15:0] sfp_diag_tx_power [0:1];
    wire [15:0] sfp_diag_rx_power [0:1];
    wire [7:0] sfp_diag_status [0:1];
    wire [7:0] sfp_diag_nack_count;
    sfp_i2c_diag sfp_diagnostics (
        .clk(startup_clk_50), .reset(startup_reset),
        .scl(main_i2c_scl), .sda(main_i2c_sda),
        .mux_reset_n(main_i2c_mux_reset_n), .done(sfp_diag_done),
        .mux_found(sfp_diag_mux_found),
        .mux_address(sfp_diag_mux_address),
        .port_valid(sfp_diag_port_valid),
        .identifier(sfp_diag_identifier), .tx_bias(sfp_diag_tx_bias),
        .tx_power(sfp_diag_tx_power), .rx_power(sfp_diag_rx_power),
        .status(sfp_diag_status), .nack_count(sfp_diag_nack_count));

    (* ASYNC_REG = "TRUE" *) reg [47:0] probe_clocks_gray_sync1 = 48'd0;
    (* ASYNC_REG = "TRUE" *) reg [47:0] probe_clocks_gray_sync2 = 48'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] probe_activity_gray_sync1 = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] probe_activity_gray_sync2 = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] probe_flags_sync1 = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] probe_flags_sync2 = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] probe_status_sync1 = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] probe_status_sync2 = 16'd0;

    always @(posedge startup_clk_50) begin
        probe_clocks_gray_sync1 <= probe_clocks_gray_async;
        probe_clocks_gray_sync2 <= probe_clocks_gray_sync1;
        probe_activity_gray_sync1 <= probe_activity_gray_async;
        probe_activity_gray_sync2 <= probe_activity_gray_sync1;
        probe_flags_sync1 <= probe_flags_async;
        probe_flags_sync2 <= probe_flags_sync1;
        probe_status_sync1 <= probe_status_async;
        probe_status_sync2 <= probe_status_sync1;
    end

    // Alternate the two SFP records every ~21 ms.  A normal 1024-record UART
    // dump therefore contains complete, independently tagged DDM data for
    // both ports while retaining the existing GTX/PCS/reset flags.
    reg [20:0] sfp_diag_display_counter = 21'd0;
    always @(posedge startup_clk_50)
        sfp_diag_display_counter <= sfp_diag_display_counter + 1'b1;
    wire sfp_diag_selected_port = sfp_diag_display_counter[20];
    wire [7:0] sfp_diag_meta = {
        sfp_diag_selected_port, sfp_diag_done, sfp_diag_mux_found,
        sfp_diag_port_valid[sfp_diag_selected_port],
        sfp_diag_mux_address[3:0]};
    wire [95:0] uart_probe_data = {
        sfp_diag_status[sfp_diag_selected_port],
        sfp_diag_rx_power[sfp_diag_selected_port],
        sfp_diag_tx_power[sfp_diag_selected_port],
        sfp_diag_tx_bias[sfp_diag_selected_port],
        sfp_diag_identifier[sfp_diag_selected_port], sfp_diag_meta,
        eth_status[sfp_diag_selected_port], probe_flags_sync2};
    UARTProbe #(
        .CLOCK_HZ(50_000_000), .BAUD(115_200),
        .SAMPLE_DIV(5_000), .DEPTH(1_024), .SCHEMA(32'h44504653),
        .AUTO_DUMP_CYCLES(100_000_000)
    ) uart_probe (
        .clk(startup_clk_50), .reset(startup_reset),
        .uart_rx_in(uart_usb_txd), .dump_trigger_in(uart_usb_rts),
        .uart_tx_out(uart_usb_rxd),
        .probe_in(uart_probe_data), .dumping_out());
endmodule

`default_nettype wire
