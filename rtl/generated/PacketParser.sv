`default_nettype none

import Predef_pkg::*;
import PacketParserFields_pkg::*;
import PacketParserWord_pkg::*;
import PacketParserFlags_pkg::*;
import PacketParserCursor_pkg::*;


module PacketParser #(
    parameter LANE_WIDTH = 'h40
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
,   input wire[2-1:0] raw_in
,   output wire[2-1:0] ready_out
,   output PacketParserWord[2-1:0] data_out
,   output wire[128-1:0] keep_out
,   output wire[2-1:0] valid_out
,   output wire[2-1:0] last_out
,   output wire[2-1:0] raw_out
,   input wire[2-1:0] ready_in
,   output wire protocol_error_out
);
    parameter  STREAMS = 64'h2;
    parameter  LANE_BYTES = LANE_WIDTH/'h8;
    parameter  INPUT_BITS = STREAMS*LANE_WIDTH;
    parameter  INPUT_BYTES = STREAMS*LANE_BYTES;
    parameter  HEADER_BITS = 64'h600;
    parameter  HEADER_COUNT_BITS = 64'h8;
    parameter  FRAME_LENGTH_BITS = 64'hE;
    parameter  OUTPUT_WORD_BITS = 64'h200;
    parameter  OUTPUT_BYTES = 64'h40;
    parameter  OUTPUT_FIFO_WORDS = 64'h4;


    // regs and combs
    reg[1536-1:0] aligned_header_reg[2];
    reg[8-1:0] header_count_reg[2];
    reg[14-1:0] frame_length_reg[2];
    reg in_frame_reg[2];
    reg frame_raw_reg[2];
    reg header_truncated_reg[2];
    reg[512-1:0] fifo_data_reg[2][4];
    reg[64-1:0] fifo_keep_reg[2][4];
    reg fifo_last_reg[2][4];
    reg fifo_raw_reg[2][4];
    reg[2-1:0] fifo_head_reg[2];
    reg[2-1:0] fifo_tail_reg[2];
    reg[3-1:0] fifo_count_reg[2];
    reg protocol_error_reg;
    PacketParserWord[2-1:0] output_data_comb;
    logic[128-1:0] output_keep_comb;
    logic[2-1:0] output_valid_comb;
    logic[2-1:0] output_last_comb;
    logic[2-1:0] output_raw_comb;
    logic[2-1:0] input_ready_comb;

    // members

    // tmp variables
    logic[1536-1:0] aligned_header_reg_tmp[2];
    logic[8-1:0] header_count_reg_tmp[2];
    logic[14-1:0] frame_length_reg_tmp[2];
    logic in_frame_reg_tmp[2];
    logic frame_raw_reg_tmp[2];
    logic header_truncated_reg_tmp[2];
    logic[512-1:0] fifo_data_reg_tmp[2][4];
    logic[64-1:0] fifo_keep_reg_tmp[2][4];
    logic fifo_last_reg_tmp[2][4];
    logic fifo_raw_reg_tmp[2][4];
    logic[2-1:0] fifo_head_reg_tmp[2];
    logic[2-1:0] fifo_tail_reg_tmp[2];
    logic[3-1:0] fifo_count_reg_tmp[2];
    logic protocol_error_reg_tmp;


    function logic[7:0] get_byte (
        input logic[1536-1:0] bytes
,       input logic[31:0] offset
    );
        return unsigned'(8'(bytes[offset*'h8 +:8]));
    endfunction

    function logic[15:0] get_be16 (
        input logic[1536-1:0] bytes
,       input logic[31:0] offset
    );
        return unsigned'(16'((((unsigned'(16'(get_byte(bytes, offset))) <<< 'h8)) | unsigned'(16'(get_byte(bytes, (offset + 'h1)))))));
    endfunction

    function logic[31:0] get_be32 (
        input logic[1536-1:0] bytes
,       input logic[31:0] offset
    );
        return ((((unsigned'(32'(get_byte(bytes, offset))) <<< 'h18)) | ((unsigned'(32'(get_byte(bytes, (offset + 'h1)))) <<< 'h10))) | ((unsigned'(32'(get_byte(bytes, (offset + 'h2)))) <<< 'h8))) | unsigned'(32'(get_byte(bytes, (offset + 'h3))));
    endfunction

    function logic[48-1:0] get_be48 (
        input logic[1536-1:0] bytes
,       input logic[31:0] offset
    );
        logic[48-1:0] value;
        logic[31:0] _byte;
        value = 'h0;
        for (_byte='h0;_byte < 'h6;_byte=_byte+1) begin
            value = (value << 'h8) | get_byte(bytes, offset + _byte);
        end
        return value;
    endfunction

    function logic[128-1:0] get_be128 (
        input logic[1536-1:0] bytes
,       input logic[31:0] offset
    );
        logic[128-1:0] value;
        logic[31:0] _byte;
        value = 'h0;
        for (_byte='h0;_byte < 'h10;_byte=_byte+1) begin
            value = (value << 'h8) | get_byte(bytes, offset + _byte);
        end
        return value;
    endfunction

    function logic range_valid (
        input logic[31:0] offset
,       input logic[31:0] bytes
,       input logic[31:0] length
    );
        return (offset<=length && bytes<=(length - offset)) && (offset + bytes)<='hC0;
    endfunction

    function logic[7:0] saturating_count (input logic[31:0] count);
        return unsigned'(8'(((count > 'h3) ? ('h3) : (count))));
    endfunction

    function PacketParserFields set_meta_counts (
        input PacketParserFields fields
,       input logic[31:0] version
,       input logic[31:0] vlan_count
,       input logic[31:0] mpls_count
    );
        fields.ip_meta = unsigned'(8'(unsigned'(8'((((version & 'hF)) | ((unsigned'(32'(saturating_count(vlan_count))) <<< 'h4))) | ((unsigned'(32'(saturating_count(mpls_count))) <<< 'h6))))));
        return fields;
    endfunction

    function PacketParserFields skip_ipv4_options (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input logic[31:0] offset
,       input logic[31:0] option_bytes
,       input PacketParserFields fields
    );
        if (option_bytes > 'h28) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT))));
            return fields;
        end
        if (!range_valid(offset, option_bytes, length)) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return fields;
        end
        return fields;
    endfunction

    function PacketParserFields skip_tcp_options (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input logic[31:0] offset
,       input logic[31:0] option_bytes
,       input PacketParserFields fields
    );
        logic[31:0] cursor;
        logic[31:0] kind;
        logic[31:0] option_length;
        if (option_bytes > 'h28) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT))));
            return fields;
        end
        if (!range_valid(offset, option_bytes, length)) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return fields;
        end
        cursor='h0;
        while (cursor < option_bytes) begin
            kind=get_byte(bytes, offset + cursor);
            if (kind == 'h0) begin
                cursor=option_bytes;
            end
            else begin
                if (kind == 'h1) begin
                    cursor=cursor+1;
                end
                else begin
                    if (cursor + 'h1>=option_bytes) begin
                        fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                        return fields;
                    end
                    else begin
                        option_length=get_byte(bytes, (offset + cursor) + 'h1);
                        if ((option_length < 'h2) || ((cursor + option_length) > option_bytes)) begin
                            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                            return fields;
                        end
                        cursor+=option_length;
                    end
                end
            end
        end
        return fields;
    endfunction

    function logic fields_ok (input PacketParserFields fields);
        return ((unsigned'(8'(fields.flags)) & ((PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT)))) == 'h0;
    endfunction

    function PacketParserFields parse_transport (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input logic[31:0] offset
,       input logic[31:0] protocol
,       input PacketParserFields fields
    );
        logic[31:0] tcp_header_bytes;
        if ((protocol != 'h6) && (protocol != 'h11)) begin
            return fields;
        end
        if (!range_valid(offset, (protocol == 'h6) ? ('h14) : ('h8), length)) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return fields;
        end
        fields.source_port = unsigned'(16'(unsigned'(16'(get_be16(bytes, offset)))));
        fields.destination_port = unsigned'(16'(unsigned'(16'(get_be16(bytes, offset + 'h2)))));
        if (protocol == 'h6) begin
            tcp_header_bytes=unsigned'(32'(((get_byte(bytes, (offset + 'hC)) >>> 'h4))))*'h4;
            if (tcp_header_bytes < 'h14) begin
                fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                return fields;
            end
            fields = skip_tcp_options(bytes, length, offset + 'h14, tcp_header_bytes - 'h14, fields);
            if (!fields_ok(fields)) begin
                return fields;
            end
        end
        fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_TRANSPORT))));
        return fields;
    endfunction

    function PacketParserFields parse_ipv4 (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input logic[31:0] offset
,       input PacketParserFields fields
    );
        logic[31:0] header_bytes;
        logic[31:0] fragment;
        logic[31:0] protocol;
        if (!range_valid(offset, 'h14, length) || (((get_byte(bytes, offset) >>> 'h4)) != 'h4)) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return fields;
        end
        header_bytes=unsigned'(32'(((get_byte(bytes, offset) & 'hF))))*'h4;
        if (header_bytes < 'h14) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return fields;
        end
        fields = skip_ipv4_options(bytes, length, offset + 'h14, header_bytes - 'h14, fields);
        if (!fields_ok(fields)) begin
            return fields;
        end
        fields.source_ip = get_be32(bytes, offset + 'hC);
        fields.destination_ip = get_be32(bytes, offset + 'h10);
        protocol=get_byte(bytes, offset + 'h9);
        fields.protocol = unsigned'(8'(unsigned'(8'(protocol))));
        fragment=get_be16(bytes, offset + 'h6);
        if (((fragment & 'h3FFF)) != 'h0) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_FRAGMENT))));
        end
        if (((fragment & 'h1FFF)) == 'h0) begin
            fields = parse_transport(bytes, length, offset + header_bytes, protocol, fields);
        end
        return fields;
    endfunction

    function logic is_ipv6_extension (input logic[31:0] next_header);
        return (((((next_header == 'h0) || (next_header == 'h2B)) || (next_header == 'h2C)) || (next_header == 'h33)) || (next_header == 'h3C)) || (next_header == 'h87);
    endfunction

    function PacketParserCursor skip_ipv6_options (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input PacketParserCursor cursor
    );
        logic[31:0] headers;
        logic[31:0] skipped;
        logic[31:0] extension_bytes;
        logic[31:0] fragment;
        headers='h0;
        skipped='h0;
        cursor.noninitial_fragment = unsigned'(1'h0);
        while (is_ipv6_extension(unsigned'(32'(cursor.selector)))) begin
            if (headers>='h4) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            if (!range_valid(unsigned'(32'(cursor.offset)), 'h8, length)) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            if (unsigned'(32'(cursor.selector)) == 'h2C) begin
                extension_bytes='h8;
                fragment=get_be16(bytes, unsigned'(32'(cursor.offset)) + 'h2);
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_FRAGMENT))));
                if (((fragment & 'hFFF8)) != 'h0) begin
                    cursor.noninitial_fragment = unsigned'(1'h1);
                end
            end
            else begin
                if (unsigned'(32'(cursor.selector)) == 'h33) begin
                    extension_bytes=((unsigned'(32'(get_byte(bytes, (unsigned'(32'(cursor.offset)) + 'h1)))) + 'h2))*'h4;
                end
                else begin
                    extension_bytes=((unsigned'(32'(get_byte(bytes, (unsigned'(32'(cursor.offset)) + 'h1)))) + 'h1))*'h8;
                end
            end
            if ((skipped + extension_bytes) > 'h60) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            if (!range_valid(unsigned'(32'(cursor.offset)), extension_bytes, length)) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            cursor.selector = unsigned'(32'(unsigned'(32'(get_byte(bytes, unsigned'(32'(cursor.offset)))))));
            cursor.offset = unsigned'(32'(unsigned'(32'(unsigned'(32'(cursor.offset)) + extension_bytes))));
            skipped+=extension_bytes;
            headers=headers+1;
        end
        return cursor;
    endfunction

    function PacketParserFields parse_ipv6 (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input logic[31:0] offset
,       input PacketParserFields fields
    );
        PacketParserCursor cursor;
        if (!range_valid(offset, 'h28, length) || (((get_byte(bytes, offset) >>> 'h4)) != 'h6)) begin
            fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return fields;
        end
        fields.source_ip = get_be128(bytes, offset + 'h8);
        fields.destination_ip = get_be128(bytes, offset + 'h18);
        cursor = 0;
        cursor.fields = fields;
        cursor.selector = unsigned'(32'(unsigned'(32'(get_byte(bytes, offset + 'h6)))));
        cursor.offset = unsigned'(32'(unsigned'(32'(offset + 'h28))));
        cursor.ok = unsigned'(1'h1);
        cursor = skip_ipv6_options(bytes, length, cursor);
        fields = cursor.fields;
        if (!cursor.ok) begin
            return fields;
        end
        fields.protocol = unsigned'(8'(unsigned'(8'(unsigned'(32'(cursor.selector))))));
        if (!cursor.noninitial_fragment) begin
            fields = parse_transport(bytes, length, unsigned'(32'(cursor.offset)), unsigned'(32'(cursor.selector)), fields);
        end
        return fields;
    endfunction

    function PacketParserCursor skip_vlan_headers (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input PacketParserCursor cursor
    );
        cursor.count = unsigned'(32'h0);
        while (((unsigned'(32'(cursor.selector)) == 'h8100) || (unsigned'(32'(cursor.selector)) == 'h88A8)) || (unsigned'(32'(cursor.selector)) == 'h9100)) begin
            if (cursor.count>='h4) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            if (!range_valid(unsigned'(32'(cursor.offset)), 'h4, length)) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            if (unsigned'(32'(cursor.count)) < 'h2) begin
                cursor.fields.vlan_tci[unsigned'(32'(cursor.count))] = unsigned'(16'(unsigned'(16'(get_be16(bytes, unsigned'(32'(cursor.offset)))))));
            end
            cursor.selector = unsigned'(32'(unsigned'(32'(get_be16(bytes, unsigned'(32'(cursor.offset)) + 'h2)))));
            cursor.offset = unsigned'(32'(unsigned'(32'(unsigned'(32'(cursor.offset)) + 'h4))));
            cursor.count = unsigned'(32'(unsigned'(32'(unsigned'(32'(cursor.count)) + 'h1))));
            cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_VLAN))));
        end
        return cursor;
    endfunction

    function PacketParserCursor skip_mpls_headers (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input PacketParserCursor cursor
    );
        logic[31:0] entry;
        logic bottom;
        cursor.count = unsigned'(32'h0);
        bottom=0;
        while (!bottom) begin
            if (cursor.count>='h4) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_LIMIT))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            if (!range_valid(unsigned'(32'(cursor.offset)), 'h4, length)) begin
                cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                cursor.ok = unsigned'(1'h0);
                return cursor;
            end
            entry=get_be32(bytes, unsigned'(32'(cursor.offset)));
            if (unsigned'(32'(cursor.count)) < 'h2) begin
                cursor.fields.mpls[unsigned'(32'(cursor.count))] = unsigned'(32'(unsigned'(32'(entry))));
            end
            bottom=((entry & 'h100)) != 'h0;
            cursor.offset = unsigned'(32'(unsigned'(32'(unsigned'(32'(cursor.offset)) + 'h4))));
            cursor.count = unsigned'(32'(unsigned'(32'(unsigned'(32'(cursor.count)) + 'h1))));
            cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MPLS))));
        end
        return cursor;
    endfunction

    function PacketParserWord parse_frame (
        input logic[1536-1:0] bytes
,       input logic[31:0] length
,       input logic truncated
    );
        PacketParserWord word;
        PacketParserCursor cursor;
        logic[31:0] vlan_count;
        logic[31:0] mpls_count;
        logic[31:0] version;
        logic ok;
        word.raw = 'h0;
        word.fields = 0;
        vlan_count='h0;
        mpls_count='h0;
        version='h0;
        ok=1;
        if (!range_valid('h0, 'hE, length)) begin
            word.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(word.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
            return word;
        end
        word.fields.destination_mac = get_be48(bytes, 'h0);
        word.fields.source_mac = get_be48(bytes, 'h6);
        cursor = 0;
        cursor.fields = word.fields;
        cursor.offset = unsigned'(32'hE);
        cursor.selector = unsigned'(32'(unsigned'(32'(get_be16(bytes, 'hC)))));
        cursor.ok = unsigned'(1'h1);
        cursor = skip_vlan_headers(bytes, length, cursor);
        vlan_count=unsigned'(32'(cursor.count));
        if (cursor.ok && (((unsigned'(32'(cursor.selector)) == 'h8847) || (unsigned'(32'(cursor.selector)) == 'h8848)))) begin
            cursor = skip_mpls_headers(bytes, length, cursor);
            mpls_count=unsigned'(32'(cursor.count));
            if (cursor.ok && range_valid(unsigned'(32'(cursor.offset)), 'h1, length)) begin
                version=get_byte(bytes, unsigned'(32'(cursor.offset))) >>> 'h4;
            end
            else begin
                if (cursor.ok) begin
                    cursor.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(cursor.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                    cursor.ok = unsigned'(1'h0);
                end
            end
        end
        else begin
            if (unsigned'(32'(cursor.selector)) == 'h800) begin
                version='h4;
            end
            else begin
                if (unsigned'(32'(cursor.selector)) == 'h86DD) begin
                    version='h6;
                end
            end
        end
        word.fields = cursor.fields;
        ok=cursor.ok;
        if (ok && (version == 'h4)) begin
            word.fields = parse_ipv4(bytes, length, unsigned'(32'(cursor.offset)), word.fields);
            ok=fields_ok(word.fields);
        end
        else begin
            if (ok && (version == 'h6)) begin
                word.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(word.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_IPV6))));
                word.fields = parse_ipv6(bytes, length, unsigned'(32'(cursor.offset)), word.fields);
                ok=fields_ok(word.fields);
            end
            else begin
                if (ok) begin
                    word.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(word.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_MALFORMED))));
                    ok=0;
                end
            end
        end
        if (ok) begin
            word.fields.flags = unsigned'(8'(unsigned'(8'(unsigned'(8'(word.fields.flags)) | PacketParserFlags_pkg::PACKET_PARSER_FLAG_PARSED))));
        end
        word.fields = set_meta_counts(word.fields, version, vlan_count, mpls_count);
        return word;
    endfunction

    always_comb begin : output_data_comb_func  // output_data_comb_func
        logic[31:0] stream;
        logic[31:0] head;
        PacketParserWord word;
        head='h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            word.raw = 'h0;
            if (unsigned'(32'(fifo_count_reg[stream])) != 'h0) begin
                head=unsigned'(32'(fifo_head_reg[stream]));
                word.raw = fifo_data_reg[stream][head];
            end
            output_data_comb[stream] = word;
        end
    end

    always_comb begin : output_keep_comb_func  // output_keep_comb_func
        logic[31:0] stream;
        logic[31:0] _byte;
        logic[31:0] head;
        head='h0;
        output_keep_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (unsigned'(32'(fifo_count_reg[stream])) != 'h0) begin
                head=unsigned'(32'(fifo_head_reg[stream]));
                for (_byte='h0;_byte < OUTPUT_BYTES;_byte=_byte+1) begin
                    output_keep_comb[(stream*OUTPUT_BYTES) + _byte] = fifo_keep_reg[stream][head][_byte];
                end
            end
        end
    end

    always_comb begin : output_valid_comb_func  // output_valid_comb_func
        logic[31:0] stream;
        output_valid_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            output_valid_comb[stream] = unsigned'(32'(fifo_count_reg[stream])) != 'h0;
        end
    end

    always_comb begin : output_last_comb_func  // output_last_comb_func
        logic[31:0] stream;
        logic[31:0] head;
        head='h0;
        output_last_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (unsigned'(32'(fifo_count_reg[stream])) != 'h0) begin
                head=unsigned'(32'(fifo_head_reg[stream]));
                output_last_comb[stream] = fifo_last_reg[stream][head];
            end
        end
    end

    always_comb begin : output_raw_comb_func  // output_raw_comb_func
        logic[31:0] stream;
        logic[31:0] head;
        head='h0;
        output_raw_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            if (unsigned'(32'(fifo_count_reg[stream])) != 'h0) begin
                head=unsigned'(32'(fifo_head_reg[stream]));
                output_raw_comb[stream] = fifo_raw_reg[stream][head];
            end
        end
    end

    always_comb begin : input_ready_comb_func  // input_ready_comb_func
        logic[31:0] stream;
        logic[31:0] count;
        input_ready_comb = 'h0;
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            count=unsigned'(32'(fifo_count_reg[stream]));
            if ((count != 'h0) && ready_in[stream]) begin
                --count;
            end
            input_ready_comb[stream] = count<=OUTPUT_FIFO_WORDS - 'h2;
        end
    end

    generate  // _assign
        assign ready_out = input_ready_comb;
        assign data_out = output_data_comb;
        assign keep_out = output_keep_comb;
        assign valid_out = output_valid_comb;
        assign last_out = output_last_comb;
        assign raw_out = output_raw_comb;
        assign protocol_error_out = protocol_error_reg;
    endgenerate

    task _work_net_clk (input logic reset);
    begin: _work_net_clk
        logic[31:0] stream;
        logic[31:0] slot;
        logic[31:0] _byte;
        logic[31:0] _bit;
        logic[31:0] flat;
        logic[31:0] head;
        logic[31:0] tail;
        logic[31:0] fifo_count;
        logic[31:0] header_count;
        logic[31:0] frame_length;
        logic[31:0] raw_word;
        logic[31:0] raw_byte;
        logic in_frame;
        logic frame_raw;
        logic header_truncated;
        logic keep;
        logic sop;
        logic eop;
        logic[7:0] input_byte;
        PacketParserWord parsed;
        logic[512-1:0] raw_data;
        logic[64-1:0] raw_keep;
        if (reset) begin
            for (stream='h0;stream < STREAMS;stream=stream+1) begin
                aligned_header_reg_tmp[stream] = 'h0;
                header_count_reg_tmp[stream] = 'h0;
                frame_length_reg_tmp[stream] = 'h0;
                in_frame_reg_tmp[stream] = unsigned'(1'h0);
                frame_raw_reg_tmp[stream] = unsigned'(1'h0);
                header_truncated_reg_tmp[stream] = unsigned'(1'h0);
                fifo_head_reg_tmp[stream] = 'h0;
                fifo_tail_reg_tmp[stream] = 'h0;
                fifo_count_reg_tmp[stream] = 'h0;
                for (slot='h0;slot < OUTPUT_FIFO_WORDS;slot=slot+1) begin
                    fifo_data_reg_tmp[stream][slot] = 'h0;
                    fifo_keep_reg_tmp[stream][slot] = 'h0;
                    fifo_last_reg_tmp[stream][slot] = unsigned'(1'h0);
                    fifo_raw_reg_tmp[stream][slot] = unsigned'(1'h0);
                end
            end
            protocol_error_reg_tmp = unsigned'(1'h0);
            disable _work_net_clk;
        end
        for (stream='h0;stream < STREAMS;stream=stream+1) begin
            aligned_header_reg_tmp[stream] = aligned_header_reg[stream];
            header_count_reg_tmp[stream] = header_count_reg[stream];
            frame_length_reg_tmp[stream] = frame_length_reg[stream];
            in_frame_reg_tmp[stream] = in_frame_reg[stream];
            frame_raw_reg_tmp[stream] = frame_raw_reg[stream];
            header_truncated_reg_tmp[stream] = header_truncated_reg[stream];
            for (slot='h0;slot < OUTPUT_FIFO_WORDS;slot=slot+1) begin
                fifo_data_reg_tmp[stream][slot] = fifo_data_reg[stream][slot];
                fifo_keep_reg_tmp[stream][slot] = fifo_keep_reg[stream][slot];
                fifo_last_reg_tmp[stream][slot] = fifo_last_reg[stream][slot];
                fifo_raw_reg_tmp[stream][slot] = fifo_raw_reg[stream][slot];
            end
            head=unsigned'(32'(fifo_head_reg[stream]));
            tail=unsigned'(32'(fifo_tail_reg[stream]));
            fifo_count=unsigned'(32'(fifo_count_reg[stream]));
            if ((fifo_count != 'h0) && ready_in[stream]) begin
                head=((head + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
                --fifo_count;
            end
            header_count=unsigned'(32'(header_count_reg[stream]));
            frame_length=unsigned'(32'(frame_length_reg[stream]));
            in_frame=in_frame_reg[stream];
            frame_raw=frame_raw_reg[stream];
            header_truncated=header_truncated_reg[stream];
            if (valid_in[stream] && input_ready_comb[stream]) begin
                for (_byte='h0;_byte < LANE_BYTES;_byte=_byte+1) begin
                    flat=(stream*LANE_BYTES) + _byte;
                    keep=keep_in[flat];
                    sop=sop_in[flat];
                    eop=eop_in[flat];
                    if (!keep) begin
                        if (sop || eop) begin
                            protocol_error_reg_tmp = unsigned'(1'h1);
                        end
                    end
                    else begin
                        if (sop) begin
                            if (in_frame) begin
                                protocol_error_reg_tmp = unsigned'(1'h1);
                            end
                            aligned_header_reg_tmp[stream] = 'h0;
                            header_count='h0;
                            frame_length='h0;
                            header_truncated=0;
                            frame_raw=raw_in[stream];
                            in_frame=1;
                        end
                        else begin
                            if (!in_frame) begin
                                protocol_error_reg_tmp = unsigned'(1'h1);
                            end
                        end
                        if (in_frame) begin
                            input_byte=unsigned'(8'(data_in[flat*'h8 +:8]));
                            if (header_count < 'hC0) begin
                                for (_bit='h0;_bit < 'h8;_bit=_bit+1) begin
                                    aligned_header_reg_tmp[stream][(header_count*'h8) + _bit] = ((input_byte >>> _bit)) & 'h1;
                                end
                                header_count=header_count+1;
                            end
                            else begin
                                header_truncated=1;
                            end
                            if (frame_length != ((('h1 <<< FRAME_LENGTH_BITS)) - 'h1)) begin
                                frame_length=frame_length+1;
                            end
                            if (eop) begin
                                if (frame_raw) begin
                                    for (raw_word='h0;raw_word < 'h2;raw_word=raw_word+1) begin
                                        raw_data = 'h0;
                                        raw_keep = 'h0;
                                        for (raw_byte='h0;raw_byte < OUTPUT_BYTES;raw_byte=raw_byte+1) begin
                                            if (((raw_word*OUTPUT_BYTES) + raw_byte) < header_count) begin
                                                input_byte=get_byte(aligned_header_reg_tmp[stream], (raw_word*OUTPUT_BYTES) + raw_byte);
                                                raw_data[raw_byte*'h8 +:8] = input_byte;
                                                raw_keep[raw_byte] = 'h1;
                                            end
                                        end
                                        fifo_data_reg_tmp[stream][tail] = raw_data;
                                        fifo_keep_reg_tmp[stream][tail] = raw_keep;
                                        fifo_last_reg_tmp[stream][tail] = unsigned'(1'(raw_word == 'h1));
                                        fifo_raw_reg_tmp[stream][tail] = unsigned'(1'h1);
                                        tail=((tail + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
                                        fifo_count=fifo_count+1;
                                    end
                                end
                                else begin
                                    parsed = parse_frame(aligned_header_reg_tmp[stream], frame_length, header_truncated);
                                    fifo_data_reg_tmp[stream][tail] = parsed.raw;
                                    fifo_keep_reg_tmp[stream][tail] = ~('h0);
                                    fifo_last_reg_tmp[stream][tail] = unsigned'(1'h1);
                                    fifo_raw_reg_tmp[stream][tail] = unsigned'(1'h0);
                                    tail=((tail + 'h1)) & ((OUTPUT_FIFO_WORDS - 'h1));
                                    fifo_count=fifo_count+1;
                                end
                                in_frame=0;
                            end
                            else begin
                                if (eop) begin
                                    protocol_error_reg_tmp = unsigned'(1'h1);
                                end
                            end
                        end
                        else begin
                            if (eop) begin
                                protocol_error_reg_tmp = unsigned'(1'h1);
                            end
                        end
                    end
                end
            end
            header_count_reg_tmp[stream] = unsigned'(HEADER_COUNT_BITS'(unsigned'(HEADER_COUNT_BITS'(header_count))));
            frame_length_reg_tmp[stream] = unsigned'(FRAME_LENGTH_BITS'(unsigned'(FRAME_LENGTH_BITS'(frame_length))));
            in_frame_reg_tmp[stream] = unsigned'(1'(in_frame));
            frame_raw_reg_tmp[stream] = unsigned'(1'(frame_raw));
            header_truncated_reg_tmp[stream] = unsigned'(1'(header_truncated));
            fifo_head_reg_tmp[stream] = unsigned'(2'(unsigned'(2'(head))));
            fifo_tail_reg_tmp[stream] = unsigned'(2'(unsigned'(2'(tail))));
            fifo_count_reg_tmp[stream] = unsigned'(3'(unsigned'(3'(fifo_count))));
        end
    end
    endtask

    task _work (input logic reset);
    begin: _work
    end
    endtask

    task _work_l2_clk (input logic unused);
    begin: _work_l2_clk
    end
    endtask

    always_ff @(posedge net_clk) begin
        aligned_header_reg_tmp = aligned_header_reg;
        header_count_reg_tmp = header_count_reg;
        frame_length_reg_tmp = frame_length_reg;
        in_frame_reg_tmp = in_frame_reg;
        frame_raw_reg_tmp = frame_raw_reg;
        header_truncated_reg_tmp = header_truncated_reg;
        fifo_data_reg_tmp = fifo_data_reg;
        fifo_keep_reg_tmp = fifo_keep_reg;
        fifo_last_reg_tmp = fifo_last_reg;
        fifo_raw_reg_tmp = fifo_raw_reg;
        fifo_head_reg_tmp = fifo_head_reg;
        fifo_tail_reg_tmp = fifo_tail_reg;
        fifo_count_reg_tmp = fifo_count_reg;
        protocol_error_reg_tmp = protocol_error_reg;

        _work_net_clk(reset);

        aligned_header_reg <= aligned_header_reg_tmp;
        header_count_reg <= header_count_reg_tmp;
        frame_length_reg <= frame_length_reg_tmp;
        in_frame_reg <= in_frame_reg_tmp;
        frame_raw_reg <= frame_raw_reg_tmp;
        header_truncated_reg <= header_truncated_reg_tmp;
        fifo_data_reg <= fifo_data_reg_tmp;
        fifo_keep_reg <= fifo_keep_reg_tmp;
        fifo_last_reg <= fifo_last_reg_tmp;
        fifo_raw_reg <= fifo_raw_reg_tmp;
        fifo_head_reg <= fifo_head_reg_tmp;
        fifo_tail_reg <= fifo_tail_reg_tmp;
        fifo_count_reg <= fifo_count_reg_tmp;
        protocol_error_reg <= protocol_error_reg_tmp;
    end

    always_ff @(posedge l2_clk) begin

        _work_l2_clk(reset);

    end


endmodule
