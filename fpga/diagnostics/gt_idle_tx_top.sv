`timescale 1ns/1ps
`default_nettype none

// License-independent physical TX test.  Only generated GTXE2 primitive
// wrappers are used; no 10G Ethernet MAC or PCS/PMA encrypted core is present.
module gt_idle_tx_top #(
    // Diagnostic-only cage selector. The production/default image drives all
    // four lanes; lane-identification builds override this with a one-hot mask.
    parameter [3:0] GTX_TX_MASK = 4'b1111,
    parameter [3:0] SFP_TX_ENABLE_MASK = 4'b1111
) (
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
    inout  wire       main_i2c_scl,
    inout  wire       main_i2c_sda,
    output wire       main_i2c_mux_reset_n
);
    wire refclk;
    wire coreclk;
    wire txusrclk;
    wire txusrclk2;
    wire qplllock;
    wire qplloutclk;
    wire qplloutrefclk;
    wire qpllreset;
    wire gttxreset;
    wire gtrxreset;
    wire txuserrdy;
    wire areset_coreclk;
    wire reset_counter_done;
    wire [3:0] txoutclk;
    wire [3:0] txresetdone;
    wire [3:0] rxresetdone;
    wire [31:0] rxdata [0:3];
    wire [1:0] rxheader [0:3];
    wire [3:0] rxdatavalid;
    wire [3:0] rxheadervalid;
    wire [3:0] rxgearboxslip;
    wire [3:0] rx_block_locked;
    wire [6:0] rx_current_invalid [0:3];
    wire [6:0] rx_last_invalid [0:3];
    wire [7:0] rx_slip_count [0:3];
    wire [15:0] rx_header_count [0:3];

    // The generated GTX controller expects its asynchronous reset to be
    // asserted after configuration.  Its internal synchronizers use that
    // assertion to load their C_RVAL state; tying areset low can leave
    // TXUSERRDY and the GT reset sequence dormant on hardware.
    reg [8:0] startup_reset_count = 9'd0;
    reg startup_reset_reg = 1'b1;
    reg [15:0] txusrclk_probe_count = 16'd0;
    always @(posedge coreclk) begin
        if (!startup_reset_count[8]) begin
            startup_reset_count <= startup_reset_count + 1'b1;
            startup_reset_reg <= 1'b1;
        end else begin
            startup_reset_reg <= 1'b0;
        end
    end
    always @(posedge txusrclk2)
        txusrclk_probe_count <= txusrclk_probe_count + 1'b1;

    wire [31:0] idle_txdata;
    wire [1:0] idle_txheader;
    wire [6:0] idle_txsequence;

    // The board inverts these active-high FPGA enables with one NMOS per
    // cage, pulling each SFP module's active-high TX_DISABLE input low.
    assign sfp_tx_en = SFP_TX_ENABLE_MASK;

    bd_1a40_xpcs_0_shared_clock_and_reset clock_reset_inst (
        .areset(startup_reset_reg),
        .refclk_p(eth_refclk_p),
        .refclk_n(eth_refclk_n),
        .refclk(refclk),
        .txoutclk(txoutclk[0]),
        .coreclk(coreclk),
        .qplllock(qplllock),
        .areset_coreclk(areset_coreclk),
        .gttxreset(gttxreset),
        .gtrxreset(gtrxreset),
        .txuserrdy(txuserrdy),
        .txusrclk(txusrclk),
        .txusrclk2(txusrclk2),
        .qpllreset(qpllreset),
        .reset_counter_done(reset_counter_done)
    );

    bd_1a40_xpcs_0_gt_common common_inst (
        .refclk(refclk),
        .qpllreset(startup_reset_reg),
        .qplllock(qplllock),
        .qplloutclk(qplloutclk),
        .qplloutrefclk(qplloutrefclk)
    );

    gt_idle_64b66b idle_source_inst (
        .clk(txusrclk2),
        .reset(!txresetdone[0]),
        .txdata(idle_txdata),
        .txheader(idle_txheader),
        .txsequence(idle_txsequence)
    );

    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : lanes
            wire [15:0] drpdo_unused;
            wire drprdy_unused;
            wire [7:0] dmonitor_unused;
            wire eyescan_unused;
            wire rxprbs_unused;
            wire [2:0] rxbufstatus_unused;
            wire rxoutclk_unused;
            wire [1:0] txbufstatus_unused;
            wire txoutclkfabric_unused;
            wire txoutclkpcs_unused;

            bd_1a40_xpcs_0_gtwizard_10gbaser_multi_GT lane_inst (
                .gt0_drpaddr_in(9'd0),
                .gt0_drpclk_in(coreclk),
                .gt0_drpdi_in(16'd0),
                .gt0_drpdo_out(drpdo_unused),
                .gt0_drpen_in(1'b0),
                .gt0_drprdy_out(drprdy_unused),
                .gt0_drpwe_in(1'b0),
                .gt0_dmonitorout_out(dmonitor_unused),
                .gt0_loopback_in(3'b000),
                .gt0_rxrate_in(3'b000),
                .gt0_eyescanreset_in(1'b0),
                // Do not derive USERREADY from TXUSRCLK: TXOUTCLK can stop
                // during QPLL reset, which deadlocks the generated
                // TXUSRCLK-domain synchronizer.  Stable QPLL lock is the
                // prerequisite USERREADY represents.
                .gt0_rxuserrdy_in(1'b1),
                .gt0_eyescandataerror_out(eyescan_unused),
                .gt0_eyescantrigger_in(1'b0),
                .gt0_rxcdrhold_in(1'b0),
                .gt0_rxusrclk_in(txusrclk),
                .gt0_rxusrclk2_in(txusrclk2),
                .gt0_rxdata_out(rxdata[lane]),
                .gt0_rxprbserr_out(rxprbs_unused),
                .gt0_rxprbssel_in(3'b000),
                .gt0_rxprbscntreset_in(1'b0),
                .gt0_gtxrxp_in(sfp_rx_p[lane]),
                .gt0_gtxrxn_in(sfp_rx_n[lane]),
                .gt0_rxbufreset_in(1'b0),
                .gt0_rxbufstatus_out(rxbufstatus_unused),
                .gt0_rxdfeagchold_in(1'b0),
                .gt0_rxdfelpmreset_in(1'b0),
                .gt0_rxoutclk_out(rxoutclk_unused),
                .gt0_rxdatavalid_out(rxdatavalid[lane]),
                .gt0_rxheader_out(rxheader[lane]),
                .gt0_rxheadervalid_out(rxheadervalid[lane]),
                .gt0_rxgearboxslip_in(rxgearboxslip[lane]),
                .gt0_gtrxreset_in(startup_reset_reg),
                .gt0_rxpcsreset_in(1'b0),
                .gt0_rxpmareset_in(1'b0),
                .gt0_rxlpmen_in(1'b1),
                .gt0_rxpolarity_in(1'b0),
                .gt0_rxresetdone_out(rxresetdone[lane]),
                .gt0_txpostcursor_in(5'd0),
                .gt0_txprecursor_in(5'd0),
                .gt0_gttxreset_in(startup_reset_reg),
                .gt0_txuserrdy_in(1'b1),
                .gt0_txusrclk_in(txusrclk),
                .gt0_txusrclk2_in(txusrclk2),
                .gt0_txprbsforceerr_in(1'b0),
                .gt0_txbufstatus_out(txbufstatus_unused),
                .gt0_txdiffctrl_in(4'd14),
                .gt0_txinhibit_in(!GTX_TX_MASK[lane]),
                .gt0_txmaincursor_in(7'd0),
                .gt0_txdata_in(idle_txdata),
                .gt0_gtxtxn_out(sfp_tx_n[lane]),
                .gt0_gtxtxp_out(sfp_tx_p[lane]),
                .gt0_txoutclk_out(txoutclk[lane]),
                .gt0_txoutclkfabric_out(txoutclkfabric_unused),
                .gt0_txoutclkpcs_out(txoutclkpcs_unused),
                .gt0_txheader_in(idle_txheader),
                .gt0_txsequence_in(idle_txsequence),
                .gt0_txpcsreset_in(1'b0),
                .gt0_txpmareset_in(1'b0),
                .gt0_txresetdone_out(txresetdone[lane]),
                .gt0_txpolarity_in(1'b0),
                .gt0_txprbssel_in(3'b000),
                .gt0_qplloutclk_in(qplloutclk),
                .gt0_qplloutrefclk_in(qplloutrefclk)
            );

            gt_rx_header_checker checker_inst (
                .clk(txusrclk2),
                .reset(!rxresetdone[lane]),
                .header_valid(rxheadervalid[lane]),
                .header(rxheader[lane]),
                .gearbox_slip(rxgearboxslip[lane]),
                .block_locked(rx_block_locked[lane]),
                .current_invalid(rx_current_invalid[lane]),
                .last_invalid(rx_last_invalid[lane]),
                .slip_count(rx_slip_count[lane]),
                .header_count(rx_header_count[lane])
            );
        end
    endgenerate

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
    sfp_i2c_diag #(.CLOCK_HZ(156_250_000), .I2C_HZ(10_000)) sfp_diagnostics (
        .clk(coreclk), .reset(areset_coreclk),
        .scl(main_i2c_scl), .sda(main_i2c_sda),
        .mux_reset_n(main_i2c_mux_reset_n), .done(sfp_diag_done),
        .mux_found(sfp_diag_mux_found), .mux_address(sfp_diag_mux_address),
        .port_valid(sfp_diag_port_valid), .identifier(sfp_diag_identifier),
        .tx_bias(sfp_diag_tx_bias), .tx_power(sfp_diag_tx_power),
        .rx_power(sfp_diag_rx_power), .status(sfp_diag_status),
        .nack_count(sfp_diag_nack_count));

    reg [21:0] sfp_display_counter = 22'd0;
    always @(posedge coreclk)
        sfp_display_counter <= sfp_display_counter + 1'b1;
    wire sfp_selected_port = sfp_display_counter[21];
    wire [7:0] sfp_meta = {
        sfp_selected_port, sfp_diag_done, sfp_diag_mux_found,
        sfp_diag_port_valid[sfp_selected_port], sfp_diag_mux_address[3:0]};
    // One compact all-cage status snapshot: LOS[3:0], RXRESETDONE[3:0],
    // TXRESETDONE[3:0], followed by global reset/QPLL state.
    wire [15:0] sfp_flags = {
        sfp_los, rxresetdone, txresetdone,
        reset_counter_done, qplllock, startup_reset_reg, !startup_reset_reg};
    wire [95:0] sfp_probe_data = {
        sfp_diag_status[sfp_selected_port],
        sfp_diag_rx_power[sfp_selected_port],
        sfp_diag_tx_power[sfp_selected_port],
        sfp_diag_tx_bias[sfp_selected_port],
        sfp_diag_identifier[sfp_selected_port], sfp_meta,
        sfp_diag_nack_count, sfp_flags};

    UARTProbe #(
        .CLOCK_HZ(156_250_000), .BAUD(115_200),
        .SAMPLE_DIV(15_625), .DEPTH(1_024),
        // "SF4D": four-cage SFP/GTX diagnostic status layout.
        .SCHEMA(32'h44344653), .AUTO_DUMP_CYCLES(312_500_000)
    ) loopback_probe (
        .clk(coreclk),
        .reset(areset_coreclk),
        .uart_rx_in(uart_usb_txd),
        .dump_trigger_in(uart_usb_rts),
        .uart_tx_out(uart_usb_rxd),
        .probe_in(sfp_probe_data),
        .dumping_out()
    );

    wire unused = &{1'b0, sfp_los, reset_counter_done, txresetdone,
                    rxresetdone};
endmodule

`default_nettype wire
