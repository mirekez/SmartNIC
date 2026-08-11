package DescriptorFetcher_Register_pkg;

typedef enum {
    REG_CONTROL = 'h0,
    REG_STATUS = 'h4,
    REG_ACTION = 'h8,
    REG_DESCRIPTOR_BASE = 'h20,
    REG_PACKET_ADDRESS = 'h100,
    REG_PACKET_META = 'h104,
    REG_DESTINATION_MAC_LO = 'h108,
    REG_DESTINATION_MAC_HI = 'h10C,
    REG_SOURCE_MAC_LO = 'h110,
    REG_SOURCE_MAC_HI = 'h114,
    REG_SOURCE_IP0 = 'h118,
    REG_SOURCE_IP1 = 'h11C,
    REG_SOURCE_IP2 = 'h120,
    REG_SOURCE_IP3 = 'h124,
    REG_DESTINATION_IP0 = 'h128,
    REG_DESTINATION_IP1 = 'h12C,
    REG_DESTINATION_IP2 = 'h130,
    REG_DESTINATION_IP3 = 'h134,
    REG_PORTS = 'h138,
    REG_PROTOCOL = 'h13C
} DescriptorFetcher_Register;


endpackage
