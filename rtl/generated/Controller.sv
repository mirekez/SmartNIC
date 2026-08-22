`default_nettype none

import Predef_pkg::*;
import SystemRingDescriptor_pkg::*;
import SystemRingDescriptorWord_pkg::*;
import MasterDmaDirection_pkg::*;
import SystemControllerFlags_pkg::*;


module Controller #(
    parameter QUEUES = 'h1
,   parameter RING_DEPTH = 'h400
,   parameter DATA_WIDTH = 'h40
 )
 (
    input wire l2_clock
,   input wire system_clock
,   input wire reset
,   input wire host_control__awvalid_in
,   output wire host_control__awready_out
,   input wire[32-1:0] host_control__awaddr_in
,   input wire[4-1:0] host_control__awid_in
,   input wire host_control__wvalid_in
,   output wire host_control__wready_out
,   input wire[64-1:0] host_control__wdata_in
,   input wire[64/'h8-1:0] host_control__wstrb_in
,   input wire host_control__wlast_in
,   output wire host_control__bvalid_out
,   input wire host_control__bready_in
,   output wire[4-1:0] host_control__bid_out
,   input wire host_control__arvalid_in
,   output wire host_control__arready_out
,   input wire[32-1:0] host_control__araddr_in
,   input wire[4-1:0] host_control__arid_in
,   output wire host_control__rvalid_out
,   input wire host_control__rready_in
,   output wire[64-1:0] host_control__rdata_out
,   output wire host_control__rlast_out
,   output wire[4-1:0] host_control__rid_out
,   input wire[QUEUES-1:0] rx_empty_in
,   input wire[QUEUES*'h10-1:0] rx_packet_length_in
,   input wire[QUEUES-1:0] tx_full_in
,   input wire[QUEUES*'h10-1:0] rx_packet_count_in
,   input wire[QUEUES*'h10-1:0] tx_packet_count_in
,   output wire dma_command_valid_out
,   input wire dma_command_ready_in
,   output wire dma_command_direction_out
,   output wire[3-1:0] dma_command_queue_out
,   output wire[32-1:0] dma_command_address_out
,   output wire[16-1:0] dma_command_length_out
,   output wire dma_command_sop_out
,   output wire dma_command_eop_out
,   input wire dma_completion_valid_in
,   input wire[3-1:0] dma_completion_queue_in
,   input wire dma_completion_direction_in
,   output wire[QUEUES-1:0] rx_queue_empty_out
,   output wire[RING_BITS-1:0] rx_consumer_out
,   output wire[RING_BITS-1:0] tx_consumer_out
,   output wire protocol_error_out
);
    localparam  DATA_BYTES = DATA_WIDTH/'h8;
    localparam  RING_BITS = $clog2(RING_DEPTH);
    localparam  REG_CONTROL = 'h0;
    localparam  REG_STATUS = 'h4;
    localparam  REG_RX_PRODUCER = 'h10;
    localparam  REG_RX_CONSUMER = 'h14;
    localparam  REG_TX_PRODUCER = 'h18;
    localparam  REG_TX_CONSUMER = 'h1C;
    localparam  REG_COMPLETED = 'h20;
    localparam  REG_QUEUE_BASE = 'h100;
    localparam  REG_QUEUE_STRIDE = 'h20;
    localparam  REG_RX_RING_BASE = 'h10000;
    localparam  REG_TX_RING_BASE = 'h20000;
    localparam  RING_ENTRY_BYTES = 'h10;
    localparam  CONTROL_ENABLE = 'h1;


    // regs and combs
    reg enabled_reg;
    reg[RING_BITS-1:0] rx_producer_reg;
    reg[RING_BITS-1:0] rx_consumer_reg;
    reg[RING_BITS-1:0] tx_producer_reg;
    reg[RING_BITS-1:0] tx_consumer_reg;
    reg tx_packet_start_reg;
    reg[3-1:0] tx_packet_queue_reg;
    reg command_valid_reg;
    reg command_direction_reg;
    reg[3-1:0] command_queue_reg;
    reg[32-1:0] command_address_reg;
    reg[16-1:0] command_length_reg;
    reg command_sop_reg;
    reg command_eop_reg;
    reg dma_active_reg;
    reg active_direction_reg;
    reg[32-1:0] completed_reg;
    reg protocol_error_reg;
    reg[32-1:0] write_address_reg;
    reg[4-1:0] write_id_reg;
    reg write_address_valid_reg;
    reg write_response_valid_reg;
    reg[4-1:0] read_id_reg;
    reg[DATA_WIDTH-1:0] read_data_reg;
    reg read_valid_reg;
    logic[128-1:0] rx_ring_write_data_comb;
    logic[16-1:0] rx_ring_write_mask_comb;
    logic[128-1:0] tx_ring_write_data_comb;
    logic[16-1:0] tx_ring_write_mask_comb;
    logic[DATA_WIDTH-1:0] register_read_comb;
    logic[RING_BITS-1:0] rx_ring_write_addr_comb;
    logic[RING_BITS-1:0] rx_ring_read_addr_comb;
    logic[RING_BITS-1:0] tx_ring_write_addr_comb;
    logic[RING_BITS-1:0] tx_ring_read_addr_comb;
    logic rx_ring_write_comb;
    logic tx_ring_write_comb;

    // members
    wire[$clog2(RING_DEPTH)-1:0] rx_ring__write_addr_in;
    wire rx_ring__write_in;
    wire['h10*'h8-1:0] rx_ring__write_data_in;
    wire['h10-1:0] rx_ring__write_mask_in;
    wire[$clog2(RING_DEPTH)-1:0] rx_ring__read_addr_in;
    wire rx_ring__read_in;
    wire['h10*'h8-1:0] rx_ring__read_data_out;
    SystemMemory #(
        'h10
,       RING_DEPTH
,       1
,       0
    ) rx_ring (
        .l2_clock(l2_clock)
,       .system_clock(system_clock)
,       .reset(reset)
,       .write_addr_in(rx_ring__write_addr_in)
,       .write_in(rx_ring__write_in)
,       .write_data_in(rx_ring__write_data_in)
,       .write_mask_in(rx_ring__write_mask_in)
,       .read_addr_in(rx_ring__read_addr_in)
,       .read_in(rx_ring__read_in)
,       .read_data_out(rx_ring__read_data_out)
    );
    wire[$clog2(RING_DEPTH)-1:0] tx_ring__write_addr_in;
    wire tx_ring__write_in;
    wire['h10*'h8-1:0] tx_ring__write_data_in;
    wire['h10-1:0] tx_ring__write_mask_in;
    wire[$clog2(RING_DEPTH)-1:0] tx_ring__read_addr_in;
    wire tx_ring__read_in;
    wire['h10*'h8-1:0] tx_ring__read_data_out;
    SystemMemory #(
        'h10
,       RING_DEPTH
,       1
,       0
    ) tx_ring (
        .l2_clock(l2_clock)
,       .system_clock(system_clock)
,       .reset(reset)
,       .write_addr_in(tx_ring__write_addr_in)
,       .write_in(tx_ring__write_in)
,       .write_data_in(tx_ring__write_data_in)
,       .write_mask_in(tx_ring__write_mask_in)
,       .read_addr_in(tx_ring__read_addr_in)
,       .read_in(tx_ring__read_in)
,       .read_data_out(tx_ring__read_data_out)
    );

    // tmp variables
    logic enabled_reg_tmp;
    logic[RING_BITS-1:0] rx_producer_reg_tmp;
    logic[RING_BITS-1:0] rx_consumer_reg_tmp;
    logic[RING_BITS-1:0] tx_producer_reg_tmp;
    logic[RING_BITS-1:0] tx_consumer_reg_tmp;
    logic tx_packet_start_reg_tmp;
    logic[3-1:0] tx_packet_queue_reg_tmp;
    logic command_valid_reg_tmp;
    logic command_direction_reg_tmp;
    logic[3-1:0] command_queue_reg_tmp;
    logic[32-1:0] command_address_reg_tmp;
    logic[16-1:0] command_length_reg_tmp;
    logic command_sop_reg_tmp;
    logic command_eop_reg_tmp;
    logic dma_active_reg_tmp;
    logic active_direction_reg_tmp;
    logic[32-1:0] completed_reg_tmp;
    logic protocol_error_reg_tmp;
    logic[32-1:0] write_address_reg_tmp;
    logic[4-1:0] write_id_reg_tmp;
    logic write_address_valid_reg_tmp;
    logic write_response_valid_reg_tmp;
    logic[4-1:0] read_id_reg_tmp;
    logic[DATA_WIDTH-1:0] read_data_reg_tmp;
    logic read_valid_reg_tmp;


    function logic[31:0] bus_write_address ();
        return unsigned'(32'(write_address_reg));
    endfunction

    function logic bus_write_fire ();
        return host_control__wvalid_in && host_control__wready_out;
    endfunction

    function logic[64-1:0] bus_write_data ();
        return host_control__wdata_in;
    endfunction

    function logic[8-1:0] bus_write_mask ();
        return host_control__wstrb_in;
    endfunction

    function logic[31:0] write_word_value ();
        logic[31:0] address;
        logic[31:0] lane;
        address=bus_write_address();
        lane=address & ((DATA_BYTES - 'h1));
        return unsigned'(32'(bus_write_data()[lane*'h8 +:32]));
    endfunction

    function logic[31:0] bus_read_address ();
        return unsigned'(32'(host_control__araddr_in));
    endfunction

    function logic bus_read_fire ();
        return host_control__arvalid_in && host_control__arready_out;
    endfunction

    function logic address_in_ring (
        input logic[31:0] address
,       input logic[31:0] base
    );
        return address>=base && (address < (base + (RING_DEPTH*RING_ENTRY_BYTES)));
    endfunction

    function logic[31:0] ring_index (
        input logic[31:0] address
,       input logic[31:0] base
    );
        return ((address - base))/RING_ENTRY_BYTES;
    endfunction

    function logic[31:0] ring_word (
        input logic[31:0] address
,       input logic[31:0] base
    );
        return ((((address - base)) & ((RING_ENTRY_BYTES - 'h1))))/'h4;
    endfunction

    always_comb begin : rx_ring_write_data_comb_func  // rx_ring_write_data_comb_func
        logic[31:0] _bit;
        logic[31:0] word;
        logic[31:0] value;
        rx_ring_write_data_comb = 'h0;
        word=ring_word(bus_write_address(), REG_RX_RING_BASE);
        value=write_word_value();
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            rx_ring_write_data_comb[(word*'h20) + _bit] = ((value >>> _bit)) & 'h1;
        end
    end

    always_comb begin : rx_ring_write_mask_comb_func  // rx_ring_write_mask_comb_func
        logic[31:0] _byte;
        logic[31:0] word;
        logic[31:0] lane;
        rx_ring_write_mask_comb = 'h0;
        word=ring_word(bus_write_address(), REG_RX_RING_BASE);
        lane=bus_write_address() & ((DATA_BYTES - 'h1));
        for (_byte='h0;_byte < 'h4;_byte=_byte+1) begin
            rx_ring_write_mask_comb[(word*'h4) + _byte] = bus_write_mask()[lane + _byte];
        end
    end

    always_comb begin : tx_ring_write_data_comb_func  // tx_ring_write_data_comb_func
        logic[31:0] _bit;
        logic[31:0] word;
        logic[31:0] value;
        tx_ring_write_data_comb = 'h0;
        word=ring_word(bus_write_address(), REG_TX_RING_BASE);
        value=write_word_value();
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            tx_ring_write_data_comb[(word*'h20) + _bit] = ((value >>> _bit)) & 'h1;
        end
    end

    always_comb begin : tx_ring_write_mask_comb_func  // tx_ring_write_mask_comb_func
        logic[31:0] _byte;
        logic[31:0] word;
        logic[31:0] lane;
        tx_ring_write_mask_comb = 'h0;
        word=ring_word(bus_write_address(), REG_TX_RING_BASE);
        lane=bus_write_address() & ((DATA_BYTES - 'h1));
        for (_byte='h0;_byte < 'h4;_byte=_byte+1) begin
            tx_ring_write_mask_comb[(word*'h4) + _byte] = bus_write_mask()[lane + _byte];
        end
    end

    function logic[31:0] descriptor_word_value (
        input logic[128-1:0] descriptor
,       input logic[31:0] word
    );
        logic[31:0] _bit;
        logic[31:0] value;
        value='h0;
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            if (descriptor[(word*'h20) + _bit]) begin
                value|='h1 <<< _bit;
            end
        end
        return value;
    endfunction

    function logic[31:0] queue_value (
        input logic[16-1:0] values
,       input logic[31:0] queue
    );
        logic[31:0] _bit;
        logic[31:0] value;
        value='h0;
        for (_bit='h0;_bit < 'h10;_bit=_bit+1) begin
            if (values[(queue*'h10) + _bit]) begin
                value|='h1 <<< _bit;
            end
        end
        return value;
    endfunction

    function logic descriptor_address_valid (input logic[64-1:0] address);
        return ((unsigned'(64'(address)) >>> 'h20)) == 'h0;
    endfunction

    function logic[31:0] register_value (input logic[31:0] address);
        logic[31:0] queue;
        logic[31:0] offset;
        if (address == REG_CONTROL) begin
            return (enabled_reg) ? (CONTROL_ENABLE) : ('h0);
        end
        if (address == REG_STATUS) begin
            return (((dma_active_reg) ? ('h1) : ('h0)) | ((command_valid_reg) ? ('h2) : ('h0))) | ((protocol_error_reg) ? ('h4) : ('h0));
        end
        if (address == REG_RX_PRODUCER) begin
            return unsigned'(32'(rx_producer_reg));
        end
        if (address == REG_RX_CONSUMER) begin
            return unsigned'(32'(rx_consumer_reg));
        end
        if (address == REG_TX_PRODUCER) begin
            return unsigned'(32'(tx_producer_reg));
        end
        if (address == REG_TX_CONSUMER) begin
            return unsigned'(32'(tx_consumer_reg));
        end
        if (address == REG_COMPLETED) begin
            return unsigned'(32'(completed_reg));
        end
        if (address>=REG_QUEUE_BASE && (address < (REG_QUEUE_BASE + (QUEUES*REG_QUEUE_STRIDE)))) begin
            queue=((address - REG_QUEUE_BASE))/REG_QUEUE_STRIDE;
            offset=((address - REG_QUEUE_BASE)) & ((REG_QUEUE_STRIDE - 'h1));
            if (offset == 'h0) begin
                return ((rx_empty_in[queue]) ? ('h1) : ('h0)) | ((tx_full_in[queue]) ? ('h2) : ('h0));
            end
            if (offset == 'h4) begin
                return queue_value(rx_packet_count_in, queue);
            end
            if (offset == 'h8) begin
                return queue_value(tx_packet_count_in, queue);
            end
            if (offset == 'hC) begin
                return queue_value(rx_packet_length_in, queue);
            end
        end
        if (address_in_ring(address, REG_RX_RING_BASE)) begin
            return descriptor_word_value(rx_ring__read_data_out, ring_word(address, REG_RX_RING_BASE));
        end
        if (address_in_ring(address, REG_TX_RING_BASE)) begin
            return descriptor_word_value(tx_ring__read_data_out, ring_word(address, REG_TX_RING_BASE));
        end
        return 'h0;
    endfunction

    always_comb begin : register_read_comb_func  // register_read_comb_func
        logic[31:0] address;
        logic[31:0] lane;
        logic[31:0] _bit;
        logic[31:0] value;
        register_read_comb = 'h0;
        address=bus_read_address();
        lane=address & ((DATA_BYTES - 'h1));
        value=register_value(address & ~'h3);
        for (_bit='h0;_bit < 'h20;_bit=_bit+1) begin
            register_read_comb[(lane*'h8) + _bit] = ((value >>> _bit)) & 'h1;
        end
    end

    function logic[31:0] selected_ring_read_address (
        input logic[31:0] base
,       input logic[31:0] consumer
    );
        logic[31:0] address;
        address=bus_read_address();
        if (bus_read_fire() && address_in_ring(address, base)) begin
            return ring_index(address, base);
        end
        return consumer;
    endfunction

    always_comb begin : rx_ring_write_addr_comb_func  // rx_ring_write_addr_comb_func
        rx_ring_write_addr_comb = ring_index(bus_write_address(), REG_RX_RING_BASE);
    end

    always_comb begin : rx_ring_read_addr_comb_func  // rx_ring_read_addr_comb_func
        rx_ring_read_addr_comb = selected_ring_read_address(REG_RX_RING_BASE, unsigned'(32'(rx_consumer_reg)));
    end

    always_comb begin : tx_ring_write_addr_comb_func  // tx_ring_write_addr_comb_func
        tx_ring_write_addr_comb = ring_index(bus_write_address(), REG_TX_RING_BASE);
    end

    always_comb begin : tx_ring_read_addr_comb_func  // tx_ring_read_addr_comb_func
        tx_ring_read_addr_comb = selected_ring_read_address(REG_TX_RING_BASE, unsigned'(32'(tx_consumer_reg)));
    end

    always_comb begin : rx_ring_write_comb_func  // rx_ring_write_comb_func
        rx_ring_write_comb=bus_write_fire() && address_in_ring(bus_write_address(), REG_RX_RING_BASE);
    end

    always_comb begin : tx_ring_write_comb_func  // tx_ring_write_comb_func
        tx_ring_write_comb=bus_write_fire() && address_in_ring(bus_write_address(), REG_TX_RING_BASE);
    end

    generate  // _assign
        assign rx_ring__write_addr_in = rx_ring_write_addr_comb;
        assign rx_ring__write_in = rx_ring_write_comb;
        assign rx_ring__write_data_in = rx_ring_write_data_comb;
        assign rx_ring__write_mask_in = rx_ring_write_mask_comb;
        assign rx_ring__read_addr_in = rx_ring_read_addr_comb;
        assign rx_ring__read_in = 1;
        assign tx_ring__write_addr_in = tx_ring_write_addr_comb;
        assign tx_ring__write_in = tx_ring_write_comb;
        assign tx_ring__write_data_in = tx_ring_write_data_comb;
        assign tx_ring__write_mask_in = tx_ring_write_mask_comb;
        assign tx_ring__read_addr_in = tx_ring_read_addr_comb;
        assign tx_ring__read_in = 1;
        assign host_control__awready_out = !write_address_valid_reg && !write_response_valid_reg;
        assign host_control__wready_out = write_address_valid_reg && !write_response_valid_reg;
        assign host_control__bvalid_out = write_response_valid_reg;
        assign host_control__bid_out = write_id_reg;
        assign host_control__arready_out = !read_valid_reg;
        assign host_control__rvalid_out = read_valid_reg;
        assign host_control__rdata_out = read_data_reg;
        assign host_control__rlast_out = read_valid_reg;
        assign host_control__rid_out = read_id_reg;
        assign dma_command_valid_out = command_valid_reg;
        assign dma_command_direction_out = command_direction_reg;
        assign dma_command_queue_out = command_queue_reg;
        assign dma_command_address_out = command_address_reg;
        assign dma_command_length_out = command_length_reg;
        assign dma_command_sop_out = command_sop_reg;
        assign dma_command_eop_out = command_eop_reg;
        assign rx_queue_empty_out = rx_empty_in;
        assign rx_consumer_out = rx_consumer_reg;
        assign tx_consumer_out = tx_consumer_reg;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work (input logic reset);
    begin: _work
        logic[31:0] address;
        logic[31:0] value;
        logic[31:0] queue;
        logic[31:0] packet_length;
        SystemRingDescriptorWord descriptor;
        if (host_control__awvalid_in && host_control__awready_out) begin
            write_address_reg_tmp = unsigned'(32'(unsigned'(32'(host_control__awaddr_in))));
            write_id_reg_tmp = host_control__awid_in;
            write_address_valid_reg_tmp = unsigned'(1'(1));
        end
        if (host_control__wvalid_in && host_control__wready_out) begin
            write_address_valid_reg_tmp = unsigned'(1'(0));
            write_response_valid_reg_tmp = unsigned'(1'(1));
        end
        if (write_response_valid_reg && host_control__bready_in) begin
            write_response_valid_reg_tmp = unsigned'(1'(0));
        end
        if (host_control__arvalid_in && host_control__arready_out) begin
            read_id_reg_tmp = host_control__arid_in;
            read_data_reg_tmp = register_read_comb;
            read_valid_reg_tmp = unsigned'(1'(1));
        end
        if (read_valid_reg && host_control__rready_in) begin
            read_valid_reg_tmp = unsigned'(1'(0));
        end
        if (bus_write_fire()) begin
            address=bus_write_address() & ~'h3;
            value=write_word_value();
            if (address == REG_CONTROL) begin
                enabled_reg_tmp = unsigned'(1'(value & CONTROL_ENABLE));
            end
            else begin
                if (address == REG_RX_PRODUCER) begin
                    rx_producer_reg_tmp = value;
                end
                else begin
                    if (address == REG_TX_PRODUCER) begin
                        tx_producer_reg_tmp = value;
                    end
                end
            end
        end
        if (command_valid_reg && dma_command_ready_in) begin
            command_valid_reg_tmp = unsigned'(1'(0));
            dma_active_reg_tmp = unsigned'(1'(1));
            active_direction_reg_tmp = command_direction_reg;
        end
        if (dma_completion_valid_in) begin
            if ((!dma_active_reg || (dma_completion_direction_in != active_direction_reg)) || (dma_completion_queue_in != command_queue_reg)) begin
                protocol_error_reg_tmp = unsigned'(1'(1));
            end
            else begin
                if (active_direction_reg == MasterDmaDirection_pkg::MASTER_DMA_QUEUE_TO_HOST) begin
                    rx_consumer_reg_tmp = rx_consumer_reg + 'h1;
                end
                else begin
                    tx_consumer_reg_tmp = tx_consumer_reg + 'h1;
                    tx_packet_start_reg_tmp = command_eop_reg;
                end
            end
            dma_active_reg_tmp = unsigned'(1'(0));
            completed_reg_tmp = completed_reg + 'h1;
        end
        if (((enabled_reg && !command_valid_reg) && !dma_active_reg) && !bus_read_fire()) begin
            if (unsigned'(32'(rx_consumer_reg)) != unsigned'(32'(rx_producer_reg))) begin
                descriptor.raw = rx_ring__read_data_out;
                queue=unsigned'(32'(descriptor.descriptor.queue));
                packet_length='h0;
                if (queue < QUEUES) begin
                    packet_length=queue_value(rx_packet_length_in, queue);
                end
                if (((((queue < QUEUES) && !rx_empty_in[queue]) && (packet_length != 'h0)) && descriptor_address_valid(unsigned'(64'(descriptor.descriptor.address)))) && descriptor.descriptor.length>=packet_length) begin
                    command_direction_reg_tmp = unsigned'(1'(MasterDmaDirection_pkg::MASTER_DMA_QUEUE_TO_HOST));
                    command_queue_reg_tmp = queue;
                    command_address_reg_tmp = unsigned'(32'(descriptor.descriptor.address));
                    command_length_reg_tmp = packet_length;
                    command_sop_reg_tmp = unsigned'(1'(1));
                    command_eop_reg_tmp = unsigned'(1'(1));
                    command_valid_reg_tmp = unsigned'(1'(1));
                end
                else begin
                    if ((queue>=QUEUES || !descriptor_address_valid(unsigned'(64'(descriptor.descriptor.address)))) || (((unsigned'(32'(descriptor.descriptor.length)) < packet_length) && (packet_length != 'h0)))) begin
                        protocol_error_reg_tmp = unsigned'(1'(1));
                    end
                end
            end
            else begin
                if (unsigned'(32'(tx_consumer_reg)) != unsigned'(32'(tx_producer_reg))) begin
                    descriptor.raw = tx_ring__read_data_out;
                    queue=unsigned'(32'(descriptor.descriptor.queue));
                    if (((((queue < QUEUES) && !tx_full_in[queue]) && (unsigned'(32'(descriptor.descriptor.length)) != 'h0)) && descriptor_address_valid(unsigned'(64'(descriptor.descriptor.address)))) && ((tx_packet_start_reg || (queue == unsigned'(32'(tx_packet_queue_reg)))))) begin
                        command_direction_reg_tmp = unsigned'(1'(MasterDmaDirection_pkg::MASTER_DMA_HOST_TO_QUEUE));
                        command_queue_reg_tmp = queue;
                        command_address_reg_tmp = unsigned'(32'(descriptor.descriptor.address));
                        command_length_reg_tmp = descriptor.descriptor.length;
                        command_sop_reg_tmp = tx_packet_start_reg;
                        command_eop_reg_tmp = unsigned'(1'(((unsigned'(32'(descriptor.descriptor.flags)) & SystemControllerFlags_pkg::SYSTEM_TX_DESCRIPTOR_EOP)) != 'h0));
                        command_valid_reg_tmp = unsigned'(1'(1));
                        if (tx_packet_start_reg) begin
                            tx_packet_queue_reg_tmp = queue;
                        end
                    end
                    else begin
                        if ((queue>=QUEUES || !descriptor_address_valid(unsigned'(64'(descriptor.descriptor.address)))) || ((!tx_packet_start_reg && (queue != unsigned'(32'(tx_packet_queue_reg)))))) begin
                            protocol_error_reg_tmp = unsigned'(1'(1));
                        end
                    end
                end
            end
        end
        if (reset) begin
            enabled_reg_tmp = '0;
            rx_producer_reg_tmp = '0;
            rx_consumer_reg_tmp = '0;
            tx_producer_reg_tmp = '0;
            tx_consumer_reg_tmp = '0;
            tx_packet_start_reg_tmp = unsigned'(1'(1));
            tx_packet_queue_reg_tmp = '0;
            command_valid_reg_tmp = '0;
            command_direction_reg_tmp = '0;
            command_queue_reg_tmp = '0;
            command_address_reg_tmp = '0;
            command_length_reg_tmp = '0;
            command_sop_reg_tmp = '0;
            command_eop_reg_tmp = '0;
            dma_active_reg_tmp = '0;
            active_direction_reg_tmp = '0;
            completed_reg_tmp = '0;
            protocol_error_reg_tmp = '0;
            write_address_reg_tmp = '0;
            write_id_reg_tmp = '0;
            write_address_valid_reg_tmp = '0;
            write_response_valid_reg_tmp = '0;
            read_id_reg_tmp = '0;
            read_data_reg_tmp = '0;
            read_valid_reg_tmp = '0;
        end
    end
    endtask

    task _work_system_clock (input logic reset);
    begin: _work_system_clock
    end
    endtask

    always_ff @(posedge l2_clock) begin
        enabled_reg_tmp = enabled_reg;
        rx_producer_reg_tmp = rx_producer_reg;
        rx_consumer_reg_tmp = rx_consumer_reg;
        tx_producer_reg_tmp = tx_producer_reg;
        tx_consumer_reg_tmp = tx_consumer_reg;
        tx_packet_start_reg_tmp = tx_packet_start_reg;
        tx_packet_queue_reg_tmp = tx_packet_queue_reg;
        command_valid_reg_tmp = command_valid_reg;
        command_direction_reg_tmp = command_direction_reg;
        command_queue_reg_tmp = command_queue_reg;
        command_address_reg_tmp = command_address_reg;
        command_length_reg_tmp = command_length_reg;
        command_sop_reg_tmp = command_sop_reg;
        command_eop_reg_tmp = command_eop_reg;
        dma_active_reg_tmp = dma_active_reg;
        active_direction_reg_tmp = active_direction_reg;
        completed_reg_tmp = completed_reg;
        protocol_error_reg_tmp = protocol_error_reg;
        write_address_reg_tmp = write_address_reg;
        write_id_reg_tmp = write_id_reg;
        write_address_valid_reg_tmp = write_address_valid_reg;
        write_response_valid_reg_tmp = write_response_valid_reg;
        read_id_reg_tmp = read_id_reg;
        read_data_reg_tmp = read_data_reg;
        read_valid_reg_tmp = read_valid_reg;

        _work(reset);

        enabled_reg <= enabled_reg_tmp;
        rx_producer_reg <= rx_producer_reg_tmp;
        rx_consumer_reg <= rx_consumer_reg_tmp;
        tx_producer_reg <= tx_producer_reg_tmp;
        tx_consumer_reg <= tx_consumer_reg_tmp;
        tx_packet_start_reg <= tx_packet_start_reg_tmp;
        tx_packet_queue_reg <= tx_packet_queue_reg_tmp;
        command_valid_reg <= command_valid_reg_tmp;
        command_direction_reg <= command_direction_reg_tmp;
        command_queue_reg <= command_queue_reg_tmp;
        command_address_reg <= command_address_reg_tmp;
        command_length_reg <= command_length_reg_tmp;
        command_sop_reg <= command_sop_reg_tmp;
        command_eop_reg <= command_eop_reg_tmp;
        dma_active_reg <= dma_active_reg_tmp;
        active_direction_reg <= active_direction_reg_tmp;
        completed_reg <= completed_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
        write_address_reg <= write_address_reg_tmp;
        write_id_reg <= write_id_reg_tmp;
        write_address_valid_reg <= write_address_valid_reg_tmp;
        write_response_valid_reg <= write_response_valid_reg_tmp;
        read_id_reg <= read_id_reg_tmp;
        read_data_reg <= read_data_reg_tmp;
        read_valid_reg <= read_valid_reg_tmp;
    end

    always_ff @(posedge system_clock) begin

        _work_system_clock(reset);

    end


endmodule
