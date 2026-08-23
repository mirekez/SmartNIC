    PacketParserCall PACKET_PARSER_IPV6_OPTIONS_WORK_NAME(
        uint8_t markup_pos, const logic<MARKUP_BITS>& markup_state,
        PacketParserProgress progress, const logic<64>& word,
        uint8_t word_bytes, uint8_t word_cntr,
        uint8_t extension_type, bool starting)
    {
        uint8_t selector;
        uint8_t size;
        uint8_t next_proto;
        uint8_t stored_size;
        uint16_t fragment;
        uint16_t stored_fragment;
        bool noninitial_fragment;
        PacketParserCall call;
        call.markup_state = 0;
        call.progress = progress;
        // The fixed-occurrence stage calls this worker only after checking
        // ACTIVE, terminal status, and IPV6_OPTIONS ownership.  Repeating the
        // generic header_active predicate made those state bits traverse the
        // complete byte/size calculation before returning to themselves.
        next_proto = (uint8_t)ipv6_next_proto_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE];
        stored_size = (uint8_t)ipv6_ext_size_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE];
        stored_fragment = (uint16_t)ipv6_fragment_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE];
        noninitial_fragment = (bool)noninitial_fragment_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE];
        if (starting) {
            next_proto = extension_type;
            stored_size = 0;
            stored_fragment = 0;
            noninitial_fragment = false;
        }
        selector = next_proto;
        if (byte_present(markup_pos, word_cntr, word_bytes))
            next_proto = word_byte(word, markup_pos);
        if (byte_present((uint8_t)(markup_pos + 1),
            word_cntr, word_bytes)) {
            if (selector == 44) size = 8;
            else if (selector == 51)
                size = (word_byte(word,
                    (uint8_t)(markup_pos + 1)) + 2) * 4;
            else
                size = (word_byte(word,
                    (uint8_t)(markup_pos + 1)) + 1) * 8;
            stored_size = size;
            if ((uint16_t)(markup_pos + size)
                > PACKET_PARSER_HEADER_BYTES)
                call.progress.limit = 1;
        }
        if (selector == 44) {
            stored_fragment = (uint16_t)capture_be16(word,
                u16(stored_fragment), (uint8_t)(markup_pos + 2),
                word_cntr, word_bytes);
            if (field_complete((uint8_t)(markup_pos + 2), 2,
                word_cntr, word_bytes)) {
                fragment = stored_fragment;
                if ((fragment & 0xfff8) != 0)
                    noninitial_fragment = true;
            }
        }
        size = stored_size;
        if (size != 0 && field_complete(markup_pos, size,
            word_cntr, word_bytes)) {
            selector = next_proto;
            if (noninitial_fragment) {
                call.progress.state = PACKET_HEADER_NONE;
                call.progress.done = 1;
            }
            else if (is_ipv6_extension(selector)) {
                if (PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE + 1
                    == PACKET_PARSER_MAX_IPV6_EXTENSION_HEADERS) {
                    call.progress.state = PACKET_HEADER_NONE;
                    call.progress.limit = 1;
                    call.progress.done = 1;
                }
                else {
                    call.progress.state = PACKET_HEADER_IPV6_OPTIONS;
                    call.progress.pos = u8(markup_pos + size);
                }
            }
            else {
                call.progress.pos = u8(markup_pos + size);
                call.progress.state = select_transport(selector);
                if ((uint8_t)call.progress.state == PACKET_HEADER_NONE)
                    call.progress.done = 1;
            }
        }
        ipv6_next_proto_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE]._next = u8(next_proto);
        ipv6_ext_size_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE]._next = u8(stored_size);
        ipv6_fragment_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE]._next =
            u16(stored_fragment);
        noninitial_fragment_reg[
            PACKET_PARSER_IPV6_OPTIONS_OCCURRENCE]._next =
            noninitial_fragment;
        return call;
    }
