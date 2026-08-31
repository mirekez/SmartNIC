`timescale 1ns/1ps
`default_nettype none

// Minimal, read-only SFP diagnostic controller for KlusterLab r2.0.  The
// board's Main_I2C bus reaches a TCA9548A switch; channels 3 and 4 are SFP0
// and SFP1.  This controller scans the legal TCA addresses, selects each
// channel, and reads the SFF-8472 identifier and live DDM measurements.
module sfp_i2c_diag #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer I2C_HZ = 100_000
) (
    input  wire        clk,
    input  wire        reset,
    inout  wire        scl,
    inout  wire        sda,
    output wire        mux_reset_n,
    output reg         done,
    output reg         mux_found,
    output reg  [6:0]  mux_address,
    output reg  [1:0]  port_valid,
    output reg  [7:0]  identifier [0:1],
    output reg  [15:0] tx_bias    [0:1],
    output reg  [15:0] tx_power   [0:1],
    output reg  [15:0] rx_power   [0:1],
    output reg  [7:0]  status     [0:1],
    output reg  [7:0]  nack_count
);
    localparam integer HALF_DIV = CLOCK_HZ / (I2C_HZ * 2);
    localparam [2:0] CMD_START = 3'd0;
    localparam [2:0] CMD_STOP  = 3'd1;
    localparam [2:0] CMD_WRITE = 3'd2;
    localparam [2:0] CMD_READ_ACK  = 3'd3;
    localparam [2:0] CMD_READ_NACK = 3'd4;

    assign mux_reset_n = 1'b1;

    reg scl_low = 1'b0;
    reg sda_low = 1'b0;
    wire scl_in;
    wire sda_in;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl_in = scl;
    assign sda_in = sda;

    reg engine_busy = 1'b0;
    reg engine_done = 1'b0;
    reg engine_ack = 1'b0;
    reg [2:0] engine_cmd = CMD_STOP;
    reg [7:0] engine_tx = 8'hff;
    reg [7:0] engine_rx = 8'h00;
    reg [3:0] engine_phase = 4'd0;
    reg [2:0] engine_bit = 3'd7;
    reg [15:0] half_counter = 16'd0;
    reg command_start = 1'b0;
    reg [2:0] command_cmd = CMD_STOP;
    reg [7:0] command_data = 8'hff;

    // Byte-level open-drain I2C engine.  It deliberately has no push-pull
    // state, so it remains electrically safe if the bus is occupied or stuck.
    always @(posedge clk) begin
        engine_done <= 1'b0;
        if (reset) begin
            engine_busy <= 1'b0;
            engine_done <= 1'b0;
            engine_ack <= 1'b0;
            engine_phase <= 4'd0;
            engine_bit <= 3'd7;
            engine_rx <= 8'h00;
            half_counter <= 16'd0;
            scl_low <= 1'b0;
            sda_low <= 1'b0;
        end else if (!engine_busy) begin
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            if (command_start) begin
                engine_busy <= 1'b1;
                engine_cmd <= command_cmd;
                engine_tx <= command_data;
                engine_rx <= 8'h00;
                engine_ack <= 1'b0;
                engine_phase <= 4'd0;
                engine_bit <= 3'd7;
                half_counter <= HALF_DIV - 1;
            end
        end else if (half_counter != 0) begin
            half_counter <= half_counter - 1'b1;
        end else begin
            half_counter <= HALF_DIV - 1;
            case (engine_cmd)
            CMD_START: begin
                case (engine_phase)
                // A repeated START must first release SDA while SCL is still
                // low.  Releasing both lines on the same FPGA edge can look
                // like a STOP to the mux/SFP and leaves the EEPROM pointer
                // transaction byte-shifted.
                0: begin scl_low <= 1'b1; sda_low <= 1'b0;
                         engine_phase <= 1; end
                1: begin scl_low <= 1'b0; engine_phase <= 2; end
                2: begin engine_phase <= 3; end
                3: begin sda_low <= 1'b1; engine_phase <= 4; end
                4: begin engine_phase <= 5; end
                default: begin scl_low <= 1'b1; engine_busy <= 1'b0;
                         engine_done <= 1'b1; end
                endcase
            end
            CMD_STOP: begin
                case (engine_phase)
                0: begin scl_low <= 1'b1; sda_low <= 1'b1;
                         engine_phase <= 1; end
                1: begin scl_low <= 1'b0; engine_phase <= 2; end
                default: begin sda_low <= 1'b0; engine_busy <= 1'b0;
                         engine_done <= 1'b1; end
                endcase
            end
            CMD_WRITE: begin
                if (engine_phase == 0) begin
                    scl_low <= 1'b1;
                    sda_low <= ~engine_tx[engine_bit];
                    engine_phase <= 1;
                end else if (engine_phase == 1) begin
                    scl_low <= 1'b0;
                    engine_phase <= 2;
                end else if (engine_phase == 2) begin
                    // Hold SCL high for a full half-period.  Sampling an ACK
                    // in the same FPGA edge which releases an open-drain SCL
                    // is too early once board/device propagation is included.
                    engine_phase <= 3;
                end else if (engine_phase == 3) begin
                    scl_low <= 1'b1;
                    if (engine_bit != 0) begin
                        engine_bit <= engine_bit - 1'b1;
                        engine_phase <= 0;
                    end else begin
                        engine_phase <= 4;
                    end
                end else if (engine_phase == 4) begin
                    sda_low <= 1'b0;
                    engine_phase <= 5;
                end else if (engine_phase == 5) begin
                    scl_low <= 1'b0;
                    engine_phase <= 6;
                end else if (engine_phase == 6) begin
                    engine_ack <= ~sda_in;
                    engine_phase <= 7;
                end else begin
                    scl_low <= 1'b1;
                    engine_busy <= 1'b0;
                    engine_done <= 1'b1;
                end
            end
            default: begin // READ_ACK or READ_NACK
                if (engine_phase == 0) begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    engine_phase <= 1;
                end else if (engine_phase == 1) begin
                    scl_low <= 1'b0;
                    engine_phase <= 2;
                end else if (engine_phase == 2) begin
                    engine_rx[engine_bit] <= sda_in;
                    engine_phase <= 3;
                end else if (engine_phase == 3) begin
                    scl_low <= 1'b1;
                    if (engine_bit != 0) begin
                        engine_bit <= engine_bit - 1'b1;
                        engine_phase <= 0;
                    end else begin
                        engine_phase <= 4;
                    end
                end else if (engine_phase == 4) begin
                    sda_low <= (engine_cmd == CMD_READ_ACK);
                    engine_phase <= 5;
                end else if (engine_phase == 5) begin
                    scl_low <= 1'b0;
                    engine_phase <= 6;
                end else if (engine_phase == 6) begin
                    engine_phase <= 7;
                end else begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    engine_busy <= 1'b0;
                    engine_done <= 1'b1;
                end
            end
            endcase
        end
    end

    localparam [2:0] JOB_SCAN = 3'd0;
    localparam [2:0] JOB_SELECT = 3'd1;
    localparam [2:0] JOB_ID = 3'd2;
    localparam [2:0] JOB_DDM = 3'd3;
    localparam [2:0] JOB_FINISH = 3'd4;
    reg [2:0] job = JOB_SCAN;
    reg [4:0] phase = 5'd0;
    reg [6:0] scan_address = 7'h70;
    reg port = 1'b0;
    reg [4:0] read_index = 5'd0;
    reg waiting = 1'b0;
    reg [20:0] startup_wait = 21'd0;

    // Transaction sequencer.  A failed device ACK is recorded but all STOPs
    // are still issued, allowing later scans/dumps to complete deterministically.
    always @(posedge clk) begin
        command_start <= 1'b0;
        if (reset) begin
            done <= 1'b0;
            mux_found <= 1'b0;
            mux_address <= 7'h00;
            port_valid <= 2'b00;
            identifier[0] <= 8'h00;
            identifier[1] <= 8'h00;
            tx_bias[0] <= 16'h0000;
            tx_bias[1] <= 16'h0000;
            tx_power[0] <= 16'h0000;
            tx_power[1] <= 16'h0000;
            rx_power[0] <= 16'h0000;
            rx_power[1] <= 16'h0000;
            status[0] <= 8'h00;
            status[1] <= 8'h00;
            nack_count <= 8'h00;
            job <= JOB_SCAN;
            phase <= 5'd0;
            scan_address <= 7'h70;
            port <= 1'b0;
            read_index <= 5'd0;
            waiting <= 1'b0;
            startup_wait <= 21'd0;
        end else if (startup_wait != 21'h1fffff) begin
            startup_wait <= startup_wait + 1'b1;
        end else if (!done) begin
            if (waiting) begin
                if (engine_done) begin
                    waiting <= 1'b0;
                    // Capture ACK/data at the phase which just completed.
                    if (job == JOB_SCAN && phase == 1) begin
                        if (engine_ack && !mux_found) begin
                            mux_found <= 1'b1;
                            mux_address <= scan_address;
                        end
                    end else if ((job == JOB_SELECT && (phase == 1 || phase == 2)) ||
                                 (job == JOB_ID && (phase == 1 || phase == 2 || phase == 4)) ||
                                 (job == JOB_DDM && (phase == 1 || phase == 2 || phase == 4))) begin
                        if (!engine_ack && nack_count != 8'hff)
                            nack_count <= nack_count + 1'b1;
                    end
                    if (job == JOB_ID && phase == 5)
                        identifier[port] <= engine_rx;
                    if (job == JOB_DDM && phase == 5) begin
                        case (read_index)
                        4: tx_bias[port][15:8] <= engine_rx;  // byte 100
                        5: tx_bias[port][7:0]  <= engine_rx;
                        6: tx_power[port][15:8] <= engine_rx; // byte 102
                        7: tx_power[port][7:0]  <= engine_rx;
                        8: rx_power[port][15:8] <= engine_rx; // byte 104
                        9: rx_power[port][7:0]  <= engine_rx;
                        14: status[port] <= engine_rx;        // byte 110
                        default: ;
                        endcase
                        if (read_index == 14)
                            port_valid[port] <= 1'b1;
                    end

                    if (job == JOB_SCAN) begin
                        if (phase == 2) begin
                            if (scan_address == 7'h77) begin
                                if (mux_found) begin
                                    job <= JOB_SELECT;
                                    phase <= 0;
                                end else begin
                                    job <= JOB_FINISH;
                                    phase <= 0;
                                end
                            end else begin
                                scan_address <= scan_address + 1'b1;
                                phase <= 0;
                            end
                        end else phase <= phase + 1'b1;
                    end else if (job == JOB_SELECT) begin
                        if (phase == 3) begin job <= JOB_ID; phase <= 0; end
                        else phase <= phase + 1'b1;
                    end else if (job == JOB_ID) begin
                        if (phase == 6) begin job <= JOB_DDM; phase <= 0;
                            read_index <= 0; end
                        else phase <= phase + 1'b1;
                    end else if (job == JOB_DDM) begin
                        if (phase == 5 && read_index != 14) begin
                            read_index <= read_index + 1'b1;
                            phase <= 5;
                        end else if (phase == 6) begin
                            if (!port) begin
                                port <= 1'b1;
                                job <= JOB_SELECT;
                                phase <= 0;
                            end else begin
                                job <= JOB_FINISH;
                                phase <= 0;
                            end
                        end else phase <= phase + 1'b1;
                    end else begin
                        done <= 1'b1;
                    end
                end
            end else if (!engine_busy) begin
                command_start <= 1'b1;
                waiting <= 1'b1;
                case (job)
                JOB_SCAN: begin
                    case (phase)
                    0: command_cmd <= CMD_START;
                    1: begin command_cmd <= CMD_WRITE;
                             command_data <= {scan_address, 1'b0}; end
                    default: command_cmd <= CMD_STOP;
                    endcase
                end
                JOB_SELECT: begin
                    case (phase)
                    0: command_cmd <= CMD_START;
                    1: begin command_cmd <= CMD_WRITE;
                             command_data <= {mux_address, 1'b0}; end
                    2: begin command_cmd <= CMD_WRITE;
                             command_data <= port ? 8'h10 : 8'h08; end
                    default: command_cmd <= CMD_STOP;
                    endcase
                end
                JOB_ID: begin
                    case (phase)
                    0: command_cmd <= CMD_START;
                    1: begin command_cmd <= CMD_WRITE; command_data <= 8'ha0; end
                    2: begin command_cmd <= CMD_WRITE; command_data <= 8'h00; end
                    3: command_cmd <= CMD_START;
                    4: begin command_cmd <= CMD_WRITE; command_data <= 8'ha1; end
                    5: command_cmd <= CMD_READ_NACK;
                    default: command_cmd <= CMD_STOP;
                    endcase
                end
                JOB_DDM: begin
                    case (phase)
                    0: command_cmd <= CMD_START;
                    1: begin command_cmd <= CMD_WRITE; command_data <= 8'ha2; end
                    2: begin command_cmd <= CMD_WRITE; command_data <= 8'h60; end
                    3: command_cmd <= CMD_START;
                    4: begin command_cmd <= CMD_WRITE; command_data <= 8'ha3; end
                    5: command_cmd <= (read_index == 14) ?
                        CMD_READ_NACK : CMD_READ_ACK;
                    default: command_cmd <= CMD_STOP;
                    endcase
                end
                default: begin
                    command_start <= 1'b0;
                    waiting <= 1'b0;
                    done <= 1'b1;
                end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
