`default_nettype none

import Predef_pkg::*;
import RxRAMScanEvent_pkg::*;
import RxRAMWritePair_pkg::*;


module RxRAM #(
    parameter LANE_WIDTH = 'h40
,   parameter READ_PORTS = 'h1
,   parameter BANK_DEPTH = 'h1000
 )
 (
    input wire net_clk
,   input wire l2_clk
,   input wire reset
,   input wire[2-1:0] valid_in
,   input wire[INPUT_BITS-1:0] data_in
,   input wire[INPUT_BYTES-1:0] keep_in
,   input wire[INPUT_BYTES-1:0] sop_in
,   input wire[INPUT_BYTES-1:0] eop_in
,   output wire[2-1:0] ready_out
,   output wire[2-1:0] packet_valid_out
,   output wire[STREAMS*HANDLE_BITS-1:0] packet_handle_out
,   output wire[28-1:0] packet_length_out
,   input wire[2-1:0] packet_ready_in
,   input wire[READ_PORTS-1:0] read_valid_in
,   input wire[READ_PORTS*HANDLE_BITS-1:0] read_handle_in
,   input wire[READ_PORTS*LOGICAL_ROW_BITS-1:0] read_word_in
,   output wire[READ_PORTS-1:0] read_ready_out
,   output wire[READ_PORTS*LANE_WIDTH-1:0] read_data_out
,   output wire[READ_PORTS-1:0] read_valid_out
,   input wire[READ_PORTS-1:0] read_ready_in
,   input wire[READ_PORTS-1:0] release_valid_in
,   input wire[READ_PORTS*HANDLE_BITS-1:0] release_handle_in
,   input wire[READ_PORTS*FRAME_LENGTH_BITS-1:0] release_length_in
,   output wire protocol_error_out
,   output wire storage_full_out
);
    localparam  STREAMS = 64'h2;
    localparam  SUBBANKS = 64'h2;
    localparam  PHYSICAL_BANKS = 64'h4;
    localparam  LANE_BYTES = LANE_WIDTH/'h8;
    localparam  INPUT_BITS = STREAMS*LANE_WIDTH;
    localparam  INPUT_BYTES = STREAMS*LANE_BYTES;
    localparam  LOGICAL_ROWS = BANK_DEPTH*SUBBANKS;
    localparam  PHYSICAL_ROW_BITS = $clog2(BANK_DEPTH);
    localparam  LOGICAL_ROW_BITS = $clog2(LOGICAL_ROWS);
    localparam  HANDLE_BITS = LOGICAL_ROW_BITS + 'h3;
    localparam  READ_RR_BITS = (READ_PORTS<='h1) ? ('h1) : ($clog2(READ_PORTS));
    localparam  FRAME_LENGTH_BITS = 64'hE;
    localparam  COMPLETION_FIFO_WORDS = 64'h4;
    localparam  RELEASE_SLOTS = READ_PORTS*'h4;
    localparam  MAX_PACKET_ROWS = ((((((((('h1 <<< FRAME_LENGTH_BITS)) - 'h1) + LANE_BYTES) - 'h1))/LANE_BYTES) + 'h1)) & ~'h1;


    // regs and combs
    reg[LANE_WIDTH-1:0] pack_data_reg[2];
    reg[$clog2(LANE_BYTES + 'h1)-1:0] pack_count_reg[2];
    reg[LOGICAL_ROW_BITS-1:0] next_row_reg[2];
    reg[LOGICAL_ROW_BITS-1:0] release_row_reg[2];
    reg[$clog2(LOGICAL_ROWS + 'h1)-1:0] used_rows_reg[2];
    reg[$clog2(LOGICAL_ROWS + 'h1)-1:0] allocated_rows_reg[2];
    reg[$clog2(LOGICAL_ROWS + 'h1)-1:0] released_rows_reg[2];
    reg[LOGICAL_ROW_BITS-1:0] packet_start_reg[2];
    reg[14-1:0] packet_length_reg[2];
    reg in_frame_reg[2];
    reg scan_in_frame_reg[2];
    reg scan_valid_reg[2];
    RxRAMScanEvent scan_event_reg[2];
    reg[LANE_WIDTH-1:0] write_data0_reg[2];
    reg[LANE_WIDTH-1:0] write_data1_reg[2];
    reg[LOGICAL_ROW_BITS-1:0] write_row0_reg[2];
    reg[LOGICAL_ROW_BITS-1:0] write_row1_reg[2];
    reg write_valid0_reg[2];
    reg write_valid1_reg[2];
    reg deferred_release_valid_reg[2][RELEASE_SLOTS];
    reg[HANDLE_BITS-1:0] deferred_release_handle_reg[2][RELEASE_SLOTS];
    reg[14-1:0] deferred_release_length_reg[2][RELEASE_SLOTS];
    reg[HANDLE_BITS-1:0] completion_handle_reg[2][4];
    reg[14-1:0] completion_length_reg[2][4];
    reg[2-1:0] completion_head_reg[2];
    reg[2-1:0] completion_tail_reg[2];
    reg[3-1:0] completion_count_reg[2];
    reg read_pipe_valid_reg[READ_PORTS];
    reg[4-1:0] read_pipe_bank_reg[READ_PORTS];
    reg read_response_valid_reg[READ_PORTS];
    reg[LANE_WIDTH-1:0] read_response_data_reg[READ_PORTS];
    reg[READ_RR_BITS-1:0] read_rr_reg[4];
    reg release_error_reg[2];
    reg ingress_error_reg[2];
    reg protocol_error_reg;
    reg storage_full_reg;
    logic[4-1:0] bank_write_valid_comb;
    logic[PHYSICAL_BANKS*LANE_WIDTH-1:0] bank_write_data_comb;
    logic[PHYSICAL_BANKS*PHYSICAL_ROW_BITS-1:0] bank_addr_comb;
    logic[4-1:0] bank_read_comb;
    logic[READ_PORTS-1:0] read_ready_comb;
    logic[2-1:0] input_ready_comb;
    logic[2-1:0] packet_valid_comb;
    logic[STREAMS*HANDLE_BITS-1:0] packet_handle_comb;
    logic[28-1:0] packet_length_comb;
    logic[READ_PORTS*LANE_WIDTH-1:0] read_data_comb;
    logic[READ_PORTS-1:0] read_valid_comb;

    // members
    genvar __i;
    wire[$clog2(BANK_DEPTH)-1:0] banks__addr_in[4];
    wire[LANE_WIDTH-1:0] banks__data_in[4];
    wire banks__wr_in[4];
    wire banks__rd_in[4];
    wire[LANE_WIDTH-1:0] banks__q_out[4];
    wire signed[31:0] banks__id_in[4];
    generate
    for (__i=0; __i < 4; __i = __i + 1) begin
        SmartNicRAM #(
        LANE_WIDTH
,       BANK_DEPTH
        ) banks (
            .net_clk(net_clk)
        ,           .l2_clk(l2_clk)
        ,           .reset(reset)
        ,           .addr_in(banks__addr_in[__i])
        ,           .data_in(banks__data_in[__i])
        ,           .wr_in(banks__wr_in[__i])
        ,           .rd_in(banks__rd_in[__i])
        ,           .q_out(banks__q_out[__i])
        ,           .id_in(banks__id_in[__i])
        );
    end
    endgenerate

    // tmp variables
    logic[LANE_WIDTH-1:0] pack_data_reg_tmp[2];
    logic[$clog2(LANE_BYTES + 'h1)-1:0] pack_count_reg_tmp[2];
    logic[LOGICAL_ROW_BITS-1:0] next_row_reg_tmp[2];
    logic[LOGICAL_ROW_BITS-1:0] release_row_reg_tmp[2];
    logic[$clog2(LOGICAL_ROWS + 'h1)-1:0] used_rows_reg_tmp[2];
    logic[$clog2(LOGICAL_ROWS + 'h1)-1:0] allocated_rows_reg_tmp[2];
    logic[$clog2(LOGICAL_ROWS + 'h1)-1:0] released_rows_reg_tmp[2];
    logic[LOGICAL_ROW_BITS-1:0] packet_start_reg_tmp[2];
    logic[14-1:0] packet_length_reg_tmp[2];
    logic in_frame_reg_tmp[2];
    logic scan_in_frame_reg_tmp[2];
    logic scan_valid_reg_tmp[2];
    RxRAMScanEvent scan_event_reg_tmp[2];
    logic[LANE_WIDTH-1:0] write_data0_reg_tmp[2];
    logic[LANE_WIDTH-1:0] write_data1_reg_tmp[2];
    logic[LOGICAL_ROW_BITS-1:0] write_row0_reg_tmp[2];
    logic[LOGICAL_ROW_BITS-1:0] write_row1_reg_tmp[2];
    logic write_valid0_reg_tmp[2];
    logic write_valid1_reg_tmp[2];
    logic deferred_release_valid_reg_tmp[2][RELEASE_SLOTS];
    logic[HANDLE_BITS-1:0] deferred_release_handle_reg_tmp[2][RELEASE_SLOTS];
    logic[14-1:0] deferred_release_length_reg_tmp[2][RELEASE_SLOTS];
    logic[HANDLE_BITS-1:0] completion_handle_reg_tmp[2][4];
    logic[14-1:0] completion_length_reg_tmp[2][4];
    logic[2-1:0] completion_head_reg_tmp[2];
    logic[2-1:0] completion_tail_reg_tmp[2];
    logic[3-1:0] completion_count_reg_tmp[2];
    logic read_pipe_valid_reg_tmp[READ_PORTS];
    logic[4-1:0] read_pipe_bank_reg_tmp[READ_PORTS];
    logic read_response_valid_reg_tmp[READ_PORTS];
    logic[LANE_WIDTH-1:0] read_response_data_reg_tmp[READ_PORTS];
    logic[READ_RR_BITS-1:0] read_rr_reg_tmp[4];
    logic release_error_reg_tmp[2];
    logic ingress_error_reg_tmp[2];
    logic protocol_error_reg_tmp;
    logic storage_full_reg_tmp;


    function logic[15:0] released_rows (input logic[15:0] length);
        return unsigned'(16'((((((length + 'hF)) >>> 'h4)) <<< 'h1)));
    endfunction

    function logic[31:0] request_handle (
        input logic[16-1:0] handles
,       input logic[31:0] port
    );
        return unsigned'(32'(handles[port*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1]));
    endfunction

    function logic[31:0] request_word (
        input logic[13-1:0] words
,       input logic[31:0] port
    );
        return unsigned'(32'(words[port*LOGICAL_ROW_BITS +:(0 + LOGICAL_ROW_BITS) - 'h1 - 0 + 1]));
    endfunction

    function logic[31:0] request_logical_row (
        input logic[16-1:0] handles
,       input logic[13-1:0] words
,       input logic[31:0] port
    );
        return ((request_handle(handles, port) >>> 'h3)) + request_word(words, port);
    endfunction

    function logic[31:0] request_physical_bank (
        input logic[16-1:0] handles
,       input logic[13-1:0] words
,       input logic[31:0] port
    );
        logic[31:0] handle;
        logic[31:0] logical;
        handle=request_handle(handles, port);
        logical=request_logical_row(handles, words, port);
        return (((handle & 'h7))*'h2) + ((logical & 'h1));
    endfunction

    function RxRAMScanEvent scan_input_for_stream (input logic[31:0] stream);
        RxRAMScanEvent _event;
        logic[31:0] _byte;
        logic[31:0] flat;
        logic[7:0] input_byte;
        logic keep;
        logic sop;
        logic eop;
        logic accepting;
        logic second_segment;
        logic first_eop;
        logic second_eop;
        _event = 0;
        accepting=scan_in_frame_reg[stream];
        second_segment=0;
        first_eop=0;
        second_eop=0;
        for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
            flat=(stream*LANE_BYTES) + _byte;
            keep=keep_in[flat];
            sop=sop_in[flat];
            eop=eop_in[flat];
            if (!keep) begin
                if (sop || eop) begin
                    _event.protocol_error = unsigned'(1'h1);
                end
            end
            else begin
                if (sop) begin
                    if (accepting || second_eop) begin
                        _event.protocol_error = unsigned'(1'h1);
                    end
                    if (first_eop) begin
                        second_segment=1;
                    end
                    accepting=1;
                    if (second_segment) begin
                        _event.sop1 = unsigned'(1'h1);
                    end
                    else begin
                        _event.sop0 = unsigned'(1'h1);
                    end
                end
                else begin
                    if (!accepting) begin
                        _event.protocol_error = unsigned'(1'h1);
                    end
                end
                if (accepting) begin
                    input_byte=unsigned'(8'(data_in[flat*'h8 +:8]));
                    if (second_segment) begin
                        _event.data1 |= input_byte << (unsigned'(8'(_event.bytes1))*'h8);
                        _event.bytes1 = unsigned'(4'(unsigned'(4'(unsigned'(8'(_event.bytes1)) + 'h1))));
                        _event.valid1 = unsigned'(1'h1);
                    end
                    else begin
                        _event.data0 |= input_byte << (unsigned'(8'(_event.bytes0))*'h8);
                        _event.bytes0 = unsigned'(4'(unsigned'(4'(unsigned'(8'(_event.bytes0)) + 'h1))));
                        _event.valid0 = unsigned'(1'h1);
                    end
                    if (eop) begin
                        if (second_segment) begin
                            _event.eop1 = unsigned'(1'h1);
                            second_eop=1;
                        end
                        else begin
                            _event.eop0 = unsigned'(1'h1);
                            first_eop=1;
                        end
                        accepting=0;
                    end
                end
                else begin
                    if (eop) begin
                        _event.protocol_error = unsigned'(1'h1);
                    end
                end
            end
        end
        _event.in_frame_next = unsigned'(1'(accepting));
        if (first_eop && second_eop) begin
            _event.protocol_error = unsigned'(1'h1);
        end
        return _event;
    endfunction

    function RxRAMWritePair write_pair_for_stream (input logic[31:0] stream);
        RxRAMWritePair pair;
        pair = 0;
        pair.data0 = write_data0_reg[stream];
        pair.data1 = write_data1_reg[stream];
        pair.row0 = write_row0_reg[stream];
        pair.row1 = write_row1_reg[stream];
        pair.valid0 = write_valid0_reg[stream];
        pair.valid1 = write_valid1_reg[stream];
        return pair;
    endfunction

    always_comb begin : bank_write_valid_comb_func  // bank_write_valid_comb_func
        logic[31:0] stream;
        logic[31:0] physical0;
        logic[31:0] physical1;
        RxRAMWritePair pair;
        bank_write_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            pair = write_pair_for_stream(stream);
            physical0=(stream*'h2) + ((unsigned'(32'(pair.row0)) & 'h1));
            physical1=(stream*'h2) + ((unsigned'(32'(pair.row1)) & 'h1));
            if (pair.valid0) begin
                bank_write_valid_comb[physical0] = 'h1;
            end
            if (pair.valid1) begin
                bank_write_valid_comb[physical1] = 'h1;
            end
        end
    end

    always_comb begin : bank_write_data_comb_func  // bank_write_data_comb_func
        logic[31:0] stream;
        logic[31:0] _bit;
        logic[31:0] physical0;
        logic[31:0] physical1;
        RxRAMWritePair pair;
        bank_write_data_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            pair = write_pair_for_stream(stream);
            physical0=(stream*'h2) + ((unsigned'(32'(pair.row0)) & 'h1));
            physical1=(stream*'h2) + ((unsigned'(32'(pair.row1)) & 'h1));
            if (pair.valid0) begin
                for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                    bank_write_data_comb[(physical0*LANE_WIDTH) + _bit] = pair.data0[_bit];
                end
            end
            if (pair.valid1) begin
                for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                    bank_write_data_comb[(physical1*LANE_WIDTH) + _bit] = pair.data1[_bit];
                end
            end
        end
    end

    always_comb begin : read_ready_comb_func  // read_ready_comb_func
        logic[31:0] bank;
        logic[31:0] offset;
        logic[31:0] port;
        logic[31:0] candidate;
        logic response_free;
        logic pipe_free;
        logic found;
        read_ready_comb = 'h0;
        candidate='h0;
        response_free=0;
        pipe_free=0;
        for (bank='h0;bank < PHYSICAL_BANKS;bank=bank+1) begin
            found=0;
            if (!bank_write_valid_comb[bank]) begin
                for (offset='h0;offset < READ_PORTS;offset=offset+1) begin
                    candidate=((unsigned'(32'(read_rr_reg[bank])) + offset)) % READ_PORTS;
                    response_free=!read_response_valid_reg[candidate] || read_ready_in[candidate];
                    pipe_free=!read_pipe_valid_reg[candidate] || response_free;
                    if (((!found && pipe_free) && read_valid_in[candidate]) && (request_physical_bank(read_handle_in, read_word_in, candidate) == bank)) begin
                        read_ready_comb[candidate] = 'h1;
                        found=1;
                    end
                end
            end
        end
    end

    always_comb begin : bank_read_comb_func  // bank_read_comb_func
        logic[31:0] port;
        logic[31:0] bank;
        bank_read_comb = 'h0;
        bank='h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            if (read_valid_in[port] && read_ready_comb[port]) begin
                bank=request_physical_bank(read_handle_in, read_word_in, port);
                bank_read_comb[bank] = 'h1;
            end
        end
    end

    always_comb begin : bank_addr_comb_func  // bank_addr_comb_func
        logic[31:0] stream;
        logic[31:0] port;
        logic[31:0] bank;
        logic[31:0] _bit;
        logic[31:0] physical0;
        logic[31:0] physical1;
        logic[31:0] row;
        RxRAMWritePair pair;
        bank_addr_comb = 'h0;
        bank='h0;
        row='h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            pair = write_pair_for_stream(stream);
            physical0=(stream*'h2) + ((unsigned'(32'(pair.row0)) & 'h1));
            physical1=(stream*'h2) + ((unsigned'(32'(pair.row1)) & 'h1));
            if (pair.valid0) begin
                row=unsigned'(32'(pair.row0)) >>> 'h1;
                for (_bit='h0;_bit < PHYSICAL_ROW_BITS;_bit=_bit+1) begin
                    bank_addr_comb[(physical0*PHYSICAL_ROW_BITS) + _bit] = ((row >>> _bit)) & 'h1;
                end
            end
            if (pair.valid1) begin
                row=unsigned'(32'(pair.row1)) >>> 'h1;
                for (_bit='h0;_bit < PHYSICAL_ROW_BITS;_bit=_bit+1) begin
                    bank_addr_comb[(physical1*PHYSICAL_ROW_BITS) + _bit] = ((row >>> _bit)) & 'h1;
                end
            end
        end
        for (port='h0;port < READ_PORTS;port=port+1) begin
            if (read_valid_in[port] && read_ready_comb[port]) begin
                bank=request_physical_bank(read_handle_in, read_word_in, port);
                if (!bank_write_valid_comb[bank]) begin
                    row=request_logical_row(read_handle_in, read_word_in, port) >>> 'h1;
                    for (_bit='h0;_bit < PHYSICAL_ROW_BITS;_bit=_bit+1) begin
                        bank_addr_comb[(bank*PHYSICAL_ROW_BITS) + _bit] = ((row >>> _bit)) & 'h1;
                    end
                end
            end
        end
    end

    always_comb begin : input_ready_comb_func  // input_ready_comb_func
        logic[31:0] stream;
        logic[31:0] count;
        logic[31:0] occupied;
        input_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            count=unsigned'(32'(completion_count_reg[stream]));
            if ((count != 'h0) && packet_ready_in[stream]) begin
                --count;
            end
            occupied=unsigned'(32'(used_rows_reg[stream])) + unsigned'(32'(allocated_rows_reg[stream]));
            input_ready_comb[stream] = (count < COMPLETION_FIFO_WORDS) && ((scan_in_frame_reg[stream] || occupied<=(LOGICAL_ROWS - MAX_PACKET_ROWS)));
        end
    end

    always_comb begin : packet_valid_comb_func  // packet_valid_comb_func
        logic[31:0] stream;
        packet_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            packet_valid_comb[stream] = unsigned'(32'(completion_count_reg[stream])) != 'h0;
        end
    end

    always_comb begin : packet_handle_comb_func  // packet_handle_comb_func
        logic[31:0] stream;
        logic[31:0] _bit;
        logic[31:0] head;
        packet_handle_comb = 'h0;
        head='h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (unsigned'(32'(completion_count_reg[stream])) != 'h0) begin
                head=unsigned'(32'(completion_head_reg[stream]));
                for (_bit='h0;_bit < HANDLE_BITS;_bit=_bit+1) begin
                    packet_handle_comb[(stream*HANDLE_BITS) + _bit] = completion_handle_reg[stream][head][_bit];
                end
            end
        end
    end

    always_comb begin : packet_length_comb_func  // packet_length_comb_func
        logic[31:0] stream;
        logic[31:0] _bit;
        logic[31:0] head;
        packet_length_comb = 'h0;
        head='h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (unsigned'(32'(completion_count_reg[stream])) != 'h0) begin
                head=unsigned'(32'(completion_head_reg[stream]));
                for (_bit='h0;_bit < FRAME_LENGTH_BITS;_bit=_bit+1) begin
                    packet_length_comb[(stream*FRAME_LENGTH_BITS) + _bit] = completion_length_reg[stream][head][_bit];
                end
            end
        end
    end

    always_comb begin : read_data_comb_func  // read_data_comb_func
        logic[31:0] port;
        logic[31:0] _bit;
        read_data_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            for (_bit='h0;_bit < LANE_WIDTH;_bit=_bit+1) begin
                read_data_comb[(port*LANE_WIDTH) + _bit] = read_response_data_reg[port][_bit];
            end
        end
    end

    always_comb begin : read_valid_comb_func  // read_valid_comb_func
        logic[31:0] port;
        read_valid_comb = 'h0;
        for (port='h0;port < READ_PORTS;port=port+1) begin
            read_valid_comb[port] = read_response_valid_reg[port];
        end
    end

    function logic[64-1:0] read_bank_data (input logic[31:0] bank);
        logic[64-1:0] value;
        value = 'h0;
        if (bank == 'h0) begin
            value = banks__q_out['h0];
        end
        if (bank == 'h1) begin
            value = banks__q_out['h1];
        end
        if (bank == 'h2) begin
            value = banks__q_out['h2];
        end
        if (bank == 'h3) begin
            value = banks__q_out['h3];
        end
        return value;
    endfunction

    generate  // _assign
        assign banks__addr_in['h0] = unsigned'(PHYSICAL_ROW_BITS'(unsigned'(PHYSICAL_ROW_BITS'(bank_addr_comb['h0*PHYSICAL_ROW_BITS +:(0 + PHYSICAL_ROW_BITS) - 'h1 - 0 + 1]))));
        assign banks__data_in['h0] = bank_write_data_comb['h0*LANE_WIDTH +:(('h0*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h0*LANE_WIDTH + 1];
        assign banks__wr_in['h0] = bank_write_valid_comb['h0];
        assign banks__rd_in['h0] = bank_read_comb['h0];
        assign banks__id_in['h0]='h0;
        assign banks__addr_in['h1] = unsigned'(PHYSICAL_ROW_BITS'(unsigned'(PHYSICAL_ROW_BITS'(bank_addr_comb['h1*PHYSICAL_ROW_BITS +:(0 + PHYSICAL_ROW_BITS) - 'h1 - 0 + 1]))));
        assign banks__data_in['h1] = bank_write_data_comb['h1*LANE_WIDTH +:(('h1*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h1*LANE_WIDTH + 1];
        assign banks__wr_in['h1] = bank_write_valid_comb['h1];
        assign banks__rd_in['h1] = bank_read_comb['h1];
        assign banks__id_in['h1]='h1;
        assign banks__addr_in['h2] = unsigned'(PHYSICAL_ROW_BITS'(unsigned'(PHYSICAL_ROW_BITS'(bank_addr_comb['h2*PHYSICAL_ROW_BITS +:(0 + PHYSICAL_ROW_BITS) - 'h1 - 0 + 1]))));
        assign banks__data_in['h2] = bank_write_data_comb['h2*LANE_WIDTH +:(('h2*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h2*LANE_WIDTH + 1];
        assign banks__wr_in['h2] = bank_write_valid_comb['h2];
        assign banks__rd_in['h2] = bank_read_comb['h2];
        assign banks__id_in['h2]='h2;
        assign banks__addr_in['h3] = unsigned'(PHYSICAL_ROW_BITS'(unsigned'(PHYSICAL_ROW_BITS'(bank_addr_comb['h3*PHYSICAL_ROW_BITS +:(0 + PHYSICAL_ROW_BITS) - 'h1 - 0 + 1]))));
        assign banks__data_in['h3] = bank_write_data_comb['h3*LANE_WIDTH +:(('h3*LANE_WIDTH) + LANE_WIDTH) - 'h1 - 'h3*LANE_WIDTH + 1];
        assign banks__wr_in['h3] = bank_write_valid_comb['h3];
        assign banks__rd_in['h3] = bank_read_comb['h3];
        assign banks__id_in['h3]='h3;
        assign ready_out = input_ready_comb;
        assign packet_valid_out = packet_valid_comb;
        assign packet_handle_out = packet_handle_comb;
        assign packet_length_out = packet_length_comb;
        assign read_ready_out = read_ready_comb;
        assign read_data_out = read_data_comb;
        assign read_valid_out = read_valid_comb;
        assign protocol_error_out = protocol_error_reg;
        assign storage_full_out = storage_full_reg;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[31:0] stream;
        logic[31:0] slot;
        logic[31:0] port;
        logic[31:0] bank;
        logic[31:0] segment;
        logic[31:0] segment_bytes;
        logic[31:0] total_count;
        logic[31:0] pack_count;
        logic[15:0] next_row;
        logic[15:0] packet_start;
        logic[15:0] packet_length;
        logic[31:0] head;
        logic[31:0] tail;
        logic[31:0] completion_count;
        logic[31:0] used_rows;
        logic[31:0] allocated_rows;
        logic[31:0] released_row_count;
        logic[31:0] release_row;
        logic[31:0] release_stream;
        logic[31:0] release_handle;
        logic[31:0] release_length;
        logic[31:0] rows;
        logic[31:0] release_slot;
        logic[31:0] drained_release_slot;
        logic[31:0] free_release_slot;
        logic[63:0] matching_release_slots;
        logic[63:0] claimed_release_slots;
        logic in_frame;
        logic segment_valid;
        logic segment_sop;
        logic segment_eop;
        logic release_slot_available;
        logic response_free;
        logic[64-1:0] pack_data;
        logic[64-1:0] segment_data;
        logic[128-1:0] combined_data;
        RxRAMWritePair write_pair;
        RxRAMScanEvent scan_event;
        if (reset) begin
            for (stream='h0;stream < STREAMS;stream=stream+1) begin
                pack_data_reg_tmp[stream] = 'h0;
                pack_count_reg_tmp[stream] = 'h0;
                next_row_reg_tmp[stream] = 'h0;
                release_row_reg_tmp[stream] = 'h0;
                used_rows_reg_tmp[stream] = 'h0;
                allocated_rows_reg_tmp[stream] = 'h0;
                released_rows_reg_tmp[stream] = 'h0;
                packet_start_reg_tmp[stream] = 'h0;
                packet_length_reg_tmp[stream] = 'h0;
                in_frame_reg_tmp[stream] = unsigned'(1'h0);
                scan_in_frame_reg_tmp[stream] = unsigned'(1'h0);
                scan_valid_reg_tmp[stream] = unsigned'(1'h0);
                scan_event_reg_tmp[stream] = 0;
                write_data0_reg_tmp[stream] = 'h0;
                write_data1_reg_tmp[stream] = 'h0;
                write_row0_reg_tmp[stream] = 'h0;
                write_row1_reg_tmp[stream] = 'h0;
                write_valid0_reg_tmp[stream] = unsigned'(1'h0);
                write_valid1_reg_tmp[stream] = unsigned'(1'h0);
                release_error_reg_tmp[stream] = unsigned'(1'h0);
                ingress_error_reg_tmp[stream] = unsigned'(1'h0);
                completion_head_reg_tmp[stream] = 'h0;
                completion_tail_reg_tmp[stream] = 'h0;
                completion_count_reg_tmp[stream] = 'h0;
                for (slot='h0;slot < COMPLETION_FIFO_WORDS;slot=slot+1) begin
                    completion_handle_reg_tmp[stream][slot] = 'h0;
                    completion_length_reg_tmp[stream][slot] = 'h0;
                end
                for (slot='h0;slot < RELEASE_SLOTS;slot=slot+1) begin
                    deferred_release_valid_reg_tmp[stream][slot] = unsigned'(1'h0);
                    deferred_release_handle_reg_tmp[stream][slot] = 'h0;
                    deferred_release_length_reg_tmp[stream][slot] = 'h0;
                end
            end
            for (port='h0;port < READ_PORTS;port=port+1) begin
                read_pipe_valid_reg_tmp[port] = unsigned'(1'h0);
                read_pipe_bank_reg_tmp[port] = 'h0;
                read_response_valid_reg_tmp[port] = unsigned'(1'h0);
                read_response_data_reg_tmp[port] = 'h0;
            end
            for (bank='h0;bank < PHYSICAL_BANKS;bank=bank+1) begin
                read_rr_reg_tmp[bank] = 'h0;
            end
            protocol_error_reg_tmp = unsigned'(1'h0);
            storage_full_reg_tmp = unsigned'(1'h0);
            disable _work_net_clk;
        end
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (release_error_reg[stream] || ingress_error_reg[stream]) begin
                protocol_error_reg_tmp = unsigned'(1'h1);
            end
            release_error_reg_tmp[stream] = unsigned'(1'h0);
            ingress_error_reg_tmp[stream] = unsigned'(1'h0);
            for (slot='h0;slot < COMPLETION_FIFO_WORDS;slot=slot+1) begin
                completion_handle_reg_tmp[stream][slot] = completion_handle_reg[stream][slot];
                completion_length_reg_tmp[stream][slot] = completion_length_reg[stream][slot];
            end
            head=unsigned'(32'(completion_head_reg[stream]));
            tail=unsigned'(32'(completion_tail_reg[stream]));
            completion_count=unsigned'(32'(completion_count_reg[stream]));
            used_rows=unsigned'(32'(used_rows_reg[stream]));
            allocated_rows='h0;
            released_row_count='h0;
            rows=unsigned'(32'(released_rows_reg[stream]));
            if (rows > used_rows) begin
                release_error_reg_tmp[stream] = unsigned'(1'h1);
            end
            else begin
                used_rows-=rows;
            end
            rows=unsigned'(32'(allocated_rows_reg[stream]));
            if ((used_rows + rows) > LOGICAL_ROWS) begin
                release_error_reg_tmp[stream] = unsigned'(1'h1);
                storage_full_reg_tmp = unsigned'(1'h1);
            end
            else begin
                used_rows+=rows;
            end
            release_row=unsigned'(32'(release_row_reg[stream]));
            matching_release_slots='h0;
            claimed_release_slots='h0;
            drained_release_slot=RELEASE_SLOTS;
            for (release_slot='h0;release_slot < RELEASE_SLOTS;release_slot=release_slot+1) begin
                if (deferred_release_valid_reg[stream][release_slot] && (((unsigned'(32'(deferred_release_handle_reg[stream][release_slot])) >>> 'h3)) == release_row)) begin
                    matching_release_slots|=unsigned'(64'('h1)) <<< release_slot;
                end
            end
            for (release_slot='h0;release_slot < RELEASE_SLOTS;release_slot=release_slot+1) begin
                if ((drained_release_slot == RELEASE_SLOTS) && (((((matching_release_slots >>> release_slot)) & 'h1)) != 'h0)) begin
                    drained_release_slot=release_slot;
                end
            end
            if (drained_release_slot != RELEASE_SLOTS) begin
                rows=released_rows(unsigned'(32'(deferred_release_length_reg[stream][drained_release_slot])));
                if (rows == 'h0) begin
                    release_error_reg_tmp[stream] = unsigned'(1'h1);
                end
                else begin
                    release_row=((release_row + rows)) & ((LOGICAL_ROWS - 'h1));
                    released_row_count+=rows;
                end
                deferred_release_valid_reg_tmp[stream][drained_release_slot] = unsigned'(1'h0);
            end
            for (port='h0;port < READ_PORTS;port=port+1) begin
                if (release_valid_in[port]) begin
                    release_handle=unsigned'(32'(release_handle_in[port*HANDLE_BITS +:(0 + HANDLE_BITS) - 'h1 - 0 + 1]));
                    release_stream=release_handle & 'h7;
                    if (release_stream == stream) begin
                        release_length=unsigned'(32'(release_length_in[port*FRAME_LENGTH_BITS +:(0 + FRAME_LENGTH_BITS) - 'h1 - 0 + 1]));
                        rows=released_rows(release_length);
                        if (rows == 'h0) begin
                            release_error_reg_tmp[stream] = unsigned'(1'h1);
                        end
                        else begin
                            free_release_slot=RELEASE_SLOTS;
                            for (release_slot='h0;release_slot < RELEASE_SLOTS;release_slot=release_slot+1) begin
                                release_slot_available=!deferred_release_valid_reg[stream][release_slot] || (release_slot == drained_release_slot);
                                if (!release_slot_available && (unsigned'(32'(deferred_release_handle_reg[stream][release_slot])) == release_handle)) begin
                                    release_error_reg_tmp[stream] = unsigned'(1'h1);
                                end
                                if (((free_release_slot == RELEASE_SLOTS) && release_slot_available) && (((((claimed_release_slots >>> release_slot)) & 'h1)) == 'h0)) begin
                                    free_release_slot=release_slot;
                                end
                            end
                            if (free_release_slot == RELEASE_SLOTS) begin
                                release_error_reg_tmp[stream] = unsigned'(1'h1);
                            end
                            else begin
                                claimed_release_slots|=unsigned'(64'('h1)) <<< free_release_slot;
                                deferred_release_valid_reg_tmp[stream][free_release_slot] = unsigned'(1'h1);
                                deferred_release_handle_reg_tmp[stream][free_release_slot] = release_handle;
                                deferred_release_length_reg_tmp[stream][free_release_slot] = release_length;
                            end
                        end
                    end
                end
            end
            if ((completion_count != 'h0) && packet_ready_in[stream]) begin
                head=((head + 'h1)) & ((COMPLETION_FIFO_WORDS - 'h1));
                --completion_count;
            end
            pack_data = pack_data_reg[stream];
            pack_count=unsigned'(32'(pack_count_reg[stream]));
            next_row=unsigned'(32'(next_row_reg[stream]));
            packet_start=unsigned'(32'(packet_start_reg[stream]));
            packet_length=unsigned'(32'(packet_length_reg[stream]));
            in_frame=in_frame_reg[stream];
            write_pair = 0;
            scan_event = scan_event_reg[stream];
            if ((valid_in[stream] && !input_ready_comb[stream]) && !scan_in_frame_reg[stream]) begin
                storage_full_reg_tmp = unsigned'(1'h1);
            end
            if (scan_valid_reg[stream]) begin
                if (scan_event.protocol_error) begin
                    ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                end
                for (segment='h0;segment < 'h2;segment=segment+1) begin
                    segment_valid=(segment == 'h0) ? (scan_event.valid0) : (scan_event.valid1);
                    segment_sop=(segment == 'h0) ? (scan_event.sop0) : (scan_event.sop1);
                    segment_eop=(segment == 'h0) ? (scan_event.eop0) : (scan_event.eop1);
                    segment_data = (segment == 'h0) ? (scan_event.data0) : (scan_event.data1);
                    segment_bytes=(segment == 'h0) ? (unsigned'(32'(scan_event.bytes0))) : (unsigned'(32'(scan_event.bytes1)));
                    if (segment_sop) begin
                        if (in_frame) begin
                            ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                        end
                        if (((next_row & 'h1)) != 'h0) begin
                            next_row=((next_row + 'h1)) & ((LOGICAL_ROWS - 'h1));
                        end
                        pack_data = 'h0;
                        pack_count='h0;
                        packet_start=next_row;
                        packet_length='h0;
                        in_frame=1;
                    end
                    if (segment_valid) begin
                        if (!in_frame) begin
                            ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                        end
                        combined_data = pack_data | (segment_data << (pack_count*'h8));
                        total_count=pack_count + segment_bytes;
                        packet_length+=segment_bytes;
                        if (total_count>=LANE_BYTES) begin
                            if (!write_pair.valid0) begin
                                write_pair.data0 = combined_data['h0 +:64];
                                write_pair.row0 = unsigned'(16'(unsigned'(16'(next_row))));
                                write_pair.valid0 = unsigned'(1'h1);
                            end
                            else begin
                                if (!write_pair.valid1) begin
                                    write_pair.data1 = combined_data['h0 +:64];
                                    write_pair.row1 = unsigned'(16'(unsigned'(16'(next_row))));
                                    write_pair.valid1 = unsigned'(1'h1);
                                end
                                else begin
                                    ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                                end
                            end
                            next_row=((next_row + 'h1)) & ((LOGICAL_ROWS - 'h1));
                            pack_data = combined_data['h40 +:64];
                            pack_count=total_count - LANE_BYTES;
                        end
                        else begin
                            pack_data = combined_data['h0 +:64];
                            pack_count=total_count;
                        end
                        if (segment_eop) begin
                            if (pack_count != 'h0) begin
                                if (!write_pair.valid0) begin
                                    write_pair.data0 = pack_data;
                                    write_pair.row0 = unsigned'(16'(unsigned'(16'(next_row))));
                                    write_pair.valid0 = unsigned'(1'h1);
                                end
                                else begin
                                    if (!write_pair.valid1) begin
                                        write_pair.data1 = pack_data;
                                        write_pair.row1 = unsigned'(16'(unsigned'(16'(next_row))));
                                        write_pair.valid1 = unsigned'(1'h1);
                                    end
                                    else begin
                                        ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                                    end
                                end
                                next_row=((next_row + 'h1)) & ((LOGICAL_ROWS - 'h1));
                            end
                            if (((next_row & 'h1)) != 'h0) begin
                                next_row=((next_row + 'h1)) & ((LOGICAL_ROWS - 'h1));
                            end
                            completion_handle_reg_tmp[stream][tail] = ((packet_start <<< 'h3)) | stream;
                            completion_length_reg_tmp[stream][tail] = packet_length;
                            tail=((tail + 'h1)) & ((COMPLETION_FIFO_WORDS - 'h1));
                            completion_count=completion_count+1;
                            allocated_rows=released_rows(packet_length);
                            pack_data = 'h0;
                            pack_count='h0;
                            in_frame=0;
                        end
                    end
                    else begin
                        if (segment_sop || segment_eop) begin
                            ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                        end
                    end
                end
            end
            allocated_rows_reg_tmp[stream] = allocated_rows;
            released_rows_reg_tmp[stream] = released_row_count;
            pack_data_reg_tmp[stream] = pack_data;
            pack_count_reg_tmp[stream] = pack_count;
            next_row_reg_tmp[stream] = next_row;
            release_row_reg_tmp[stream] = release_row;
            used_rows_reg_tmp[stream] = used_rows;
            packet_start_reg_tmp[stream] = packet_start;
            packet_length_reg_tmp[stream] = packet_length;
            in_frame_reg_tmp[stream] = unsigned'(1'(in_frame));
            write_data0_reg_tmp[stream] = write_pair.data0;
            write_data1_reg_tmp[stream] = write_pair.data1;
            write_row0_reg_tmp[stream] = write_pair.row0;
            write_row1_reg_tmp[stream] = write_pair.row1;
            write_valid0_reg_tmp[stream] = write_pair.valid0;
            write_valid1_reg_tmp[stream] = write_pair.valid1;
            scan_valid_reg_tmp[stream] = unsigned'(1'h0);
            scan_event_reg_tmp[stream] = scan_event_reg[stream];
            scan_in_frame_reg_tmp[stream] = scan_in_frame_reg[stream];
            if (valid_in[stream] && input_ready_comb[stream]) begin
                scan_event = scan_input_for_stream(stream);
                scan_event_reg_tmp[stream] = scan_event;
                scan_valid_reg_tmp[stream] = unsigned'(1'h1);
                scan_in_frame_reg_tmp[stream] = scan_event.in_frame_next;
                if (scan_event.protocol_error) begin
                    ingress_error_reg_tmp[stream] = unsigned'(1'h1);
                end
            end
            completion_head_reg_tmp[stream] = head;
            completion_tail_reg_tmp[stream] = tail;
            completion_count_reg_tmp[stream] = completion_count;
        end
        for (bank='h0;bank < PHYSICAL_BANKS;bank=bank+1) begin
            read_rr_reg_tmp[bank] = read_rr_reg[bank];
        end
        for (port='h0;port < READ_PORTS;port=port+1) begin
            read_pipe_valid_reg_tmp[port] = read_pipe_valid_reg[port];
            read_pipe_bank_reg_tmp[port] = read_pipe_bank_reg[port];
            read_response_valid_reg_tmp[port] = read_response_valid_reg[port];
            read_response_data_reg_tmp[port] = read_response_data_reg[port];
            response_free=!read_response_valid_reg[port] || read_ready_in[port];
            if (read_response_valid_reg[port] && read_ready_in[port]) begin
                read_response_valid_reg_tmp[port] = unsigned'(1'h0);
            end
            if (read_pipe_valid_reg[port] && response_free) begin
                read_response_data_reg_tmp[port] = read_bank_data(unsigned'(32'(read_pipe_bank_reg[port])));
                read_response_valid_reg_tmp[port] = unsigned'(1'h1);
                read_pipe_valid_reg_tmp[port] = unsigned'(1'h0);
            end
            if (read_valid_in[port] && read_ready_comb[port]) begin
                bank=request_physical_bank(read_handle_in, read_word_in, port);
                read_pipe_bank_reg_tmp[port] = bank;
                read_pipe_valid_reg_tmp[port] = unsigned'(1'h1);
                read_rr_reg_tmp[bank] = ((port + 'h1)) % READ_PORTS;
            end
        end
        for (bank='h0;bank < PHYSICAL_BANKS;bank=bank+1) begin
        end
    end
    endtask

    task _work (input logic reset);
    begin: _work
        _work_net_clk(reset);
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        pack_data_reg_tmp = pack_data_reg;
        pack_count_reg_tmp = pack_count_reg;
        next_row_reg_tmp = next_row_reg;
        release_row_reg_tmp = release_row_reg;
        used_rows_reg_tmp = used_rows_reg;
        allocated_rows_reg_tmp = allocated_rows_reg;
        released_rows_reg_tmp = released_rows_reg;
        packet_start_reg_tmp = packet_start_reg;
        packet_length_reg_tmp = packet_length_reg;
        in_frame_reg_tmp = in_frame_reg;
        scan_in_frame_reg_tmp = scan_in_frame_reg;
        scan_valid_reg_tmp = scan_valid_reg;
        scan_event_reg_tmp = scan_event_reg;
        write_data0_reg_tmp = write_data0_reg;
        write_data1_reg_tmp = write_data1_reg;
        write_row0_reg_tmp = write_row0_reg;
        write_row1_reg_tmp = write_row1_reg;
        write_valid0_reg_tmp = write_valid0_reg;
        write_valid1_reg_tmp = write_valid1_reg;
        deferred_release_valid_reg_tmp = deferred_release_valid_reg;
        deferred_release_handle_reg_tmp = deferred_release_handle_reg;
        deferred_release_length_reg_tmp = deferred_release_length_reg;
        completion_handle_reg_tmp = completion_handle_reg;
        completion_length_reg_tmp = completion_length_reg;
        completion_head_reg_tmp = completion_head_reg;
        completion_tail_reg_tmp = completion_tail_reg;
        completion_count_reg_tmp = completion_count_reg;
        read_pipe_valid_reg_tmp = read_pipe_valid_reg;
        read_pipe_bank_reg_tmp = read_pipe_bank_reg;
        read_response_valid_reg_tmp = read_response_valid_reg;
        read_response_data_reg_tmp = read_response_data_reg;
        read_rr_reg_tmp = read_rr_reg;
        release_error_reg_tmp = release_error_reg;
        ingress_error_reg_tmp = ingress_error_reg;
        protocol_error_reg_tmp = protocol_error_reg;
        storage_full_reg_tmp = storage_full_reg;

        _work_net_clk(reset);

        pack_data_reg <= pack_data_reg_tmp;
        pack_count_reg <= pack_count_reg_tmp;
        next_row_reg <= next_row_reg_tmp;
        release_row_reg <= release_row_reg_tmp;
        used_rows_reg <= used_rows_reg_tmp;
        allocated_rows_reg <= allocated_rows_reg_tmp;
        released_rows_reg <= released_rows_reg_tmp;
        packet_start_reg <= packet_start_reg_tmp;
        packet_length_reg <= packet_length_reg_tmp;
        in_frame_reg <= in_frame_reg_tmp;
        scan_in_frame_reg <= scan_in_frame_reg_tmp;
        scan_valid_reg <= scan_valid_reg_tmp;
        scan_event_reg <= scan_event_reg_tmp;
        write_data0_reg <= write_data0_reg_tmp;
        write_data1_reg <= write_data1_reg_tmp;
        write_row0_reg <= write_row0_reg_tmp;
        write_row1_reg <= write_row1_reg_tmp;
        write_valid0_reg <= write_valid0_reg_tmp;
        write_valid1_reg <= write_valid1_reg_tmp;
        deferred_release_valid_reg <= deferred_release_valid_reg_tmp;
        deferred_release_handle_reg <= deferred_release_handle_reg_tmp;
        deferred_release_length_reg <= deferred_release_length_reg_tmp;
        completion_handle_reg <= completion_handle_reg_tmp;
        completion_length_reg <= completion_length_reg_tmp;
        completion_head_reg <= completion_head_reg_tmp;
        completion_tail_reg <= completion_tail_reg_tmp;
        completion_count_reg <= completion_count_reg_tmp;
        read_pipe_valid_reg <= read_pipe_valid_reg_tmp;
        read_pipe_bank_reg <= read_pipe_bank_reg_tmp;
        read_response_valid_reg <= read_response_valid_reg_tmp;
        read_response_data_reg <= read_response_data_reg_tmp;
        read_rr_reg <= read_rr_reg_tmp;
        release_error_reg <= release_error_reg_tmp;
        ingress_error_reg <= ingress_error_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
        storage_full_reg <= storage_full_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
