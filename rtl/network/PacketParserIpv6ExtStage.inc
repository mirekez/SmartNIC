    PacketParserPipeWord PACKET_PARSER_IPV6_EXT_STAGE_NAME(
        PacketParserPipeWord item)
    {
        PacketParserPipeWord result;
        uint8_t markup_pos;
        uint8_t flags;
        uint8_t prior_state;
        uint8_t prior_pos;
        uint8_t output_index;
        bool active;
        bool complete;
        bool starting;
        logic<MARKUP_BITS> markup_state;
        PacketParserCall call;
        PacketParserProgress progress;
        result = item;
        starting = false;
        if ((bool)item.sop) {
            ipv6_next_proto_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 0;
            ipv6_ext_size_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 0;
            ipv6_ext_seen_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 0;
            ipv6_fragment_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 0;
            noninitial_fragment_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 0;
            progress = item.progress;
            prior_state = PACKET_HEADER_NONE;
            active = false;
            complete = false;
            ipv6_ext_progress_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = progress;
            ipv6_ext_active_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = active;
            ipv6_ext_complete_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 0;
            result.progress = progress;
            result.ipv6_ext_index = 0;
            return result;
        }
        progress = ipv6_ext_progress_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE];
        active = (bool)ipv6_ext_active_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE];
        complete = (bool)ipv6_ext_complete_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE];
        prior_state = (uint8_t)progress.state;

        // Once complete, carry the frozen result without feeding the phase
        // bit back through the full extension-header datapath.
        if (complete) {
            result.progress = progress;
            result.ipv6_ext_index =
                PACKET_PARSER_IPV6_EXT_OCCURRENCE + 1;
            if ((bool)ipv6_ext_seen_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next)
                result.fields.protocol = ipv6_next_proto_reg[
                    PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next;
            if ((bool)item.eop && (uint16_t)ipv6_fragment_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next != 0) {
                flags = (uint8_t)result.fields.flags;
                flags |= PACKET_PARSER_FLAG_FRAGMENT;
                result.fields.flags = u8(flags);
            }
            return result;
        }

        if (!active) {
            progress = item.progress;
            if ((uint8_t)item.ipv6_ext_index
                    < PACKET_PARSER_IPV6_EXT_OCCURRENCE
                || (uint8_t)progress.state
                    != PACKET_HEADER_IPV6_OPTIONS) {
                ipv6_ext_progress_reg[
                    PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = progress;
                result.progress = progress;
                result.ipv6_ext_index = item.ipv6_ext_index;
                return result;
            }
            active = true;
        }
        else {
            // ACTIVE means this fixed stage already owns its extension.  It
            // cannot become inactive until COMPLETE, so selecting between the
            // complete stored progress and upstream progress here is both
            // redundant and timing-expensive.  Only terminal status needs to
            // propagate from upstream.
            if ((bool)item.progress.error) progress.error = 1;
            if ((bool)item.progress.limit) progress.limit = 1;
            if ((bool)item.progress.done) progress.done = 1;
        }

        if ((bool)progress.error || (bool)progress.limit
            || (bool)progress.done) {
            complete = true;
            ipv6_ext_progress_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = progress;
            ipv6_ext_active_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = active;
            ipv6_ext_complete_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 1;
            result.progress = progress;
            result.ipv6_ext_index =
                PACKET_PARSER_IPV6_EXT_OCCURRENCE + 1;
            if ((bool)ipv6_ext_seen_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next)
                result.fields.protocol = ipv6_next_proto_reg[
                    PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next;
            if ((bool)item.eop && (uint16_t)ipv6_fragment_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next != 0) {
                flags = (uint8_t)result.fields.flags;
                flags |= PACKET_PARSER_FLAG_FRAGMENT;
                result.fields.flags = u8(flags);
            }
            return result;
        }
        if ((uint8_t)progress.state == PACKET_HEADER_IPV6_OPTIONS
            && (prior_state != PACKET_HEADER_IPV6_OPTIONS
                || !(bool)ipv6_ext_seen_reg[
                    PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next)) {
            starting = true;
            ipv6_ext_seen_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = 1;
        }
        markup_state = 0;
        markup_pos = (uint8_t)progress.pos;
        prior_pos = markup_pos;
        if ((uint8_t)progress.state == PACKET_HEADER_IPV6_OPTIONS) {
            call.progress = progress;
            call.markup_state = 0;
            call = PACKET_PARSER_IPV6_EXT_PARSE(markup_pos, markup_state,
                progress, item.data, (uint8_t)item.bytes,
                (uint8_t)item.word_cntr,
                (uint8_t)item.fields.protocol, starting);
            progress = call.progress;
            if ((uint8_t)progress.pos != prior_pos
                || (uint8_t)progress.state != PACKET_HEADER_IPV6_OPTIONS
                || (bool)progress.error || (bool)progress.limit
                || (bool)progress.done)
                complete = true;
        }
        output_index = PACKET_PARSER_IPV6_EXT_OCCURRENCE;
        if (complete)
            output_index = PACKET_PARSER_IPV6_EXT_OCCURRENCE + 1;
        ipv6_ext_progress_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = progress;
        ipv6_ext_active_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = active;
        ipv6_ext_complete_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next = complete;
        result.progress = progress;
        result.ipv6_ext_index = u<3>(output_index);
        if ((bool)ipv6_ext_seen_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next)
            result.fields.protocol = ipv6_next_proto_reg[
                PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next;
        if ((bool)item.eop && (uint16_t)ipv6_fragment_reg[
            PACKET_PARSER_IPV6_EXT_OCCURRENCE]._next != 0) {
            flags = (uint8_t)result.fields.flags;
            flags |= PACKET_PARSER_FLAG_FRAGMENT;
            result.fields.flags = u8(flags);
        }
        return result;
    }
