package PacketDMA16_14_64_32_4_256_31_64_64_Register_pkg;

typedef enum logic[32-1:0] {
    REG_RX_HANDLE = 'h0,
    REG_LENGTH = 'h4,
    REG_DESTINATION = 'h8,
    REG_FLAGS = 'hC,
    REG_COMMAND = 'h10,
    REG_STATUS = 'h14,
    REG_COMPLETED = 'h18,
    REG_SOURCE = 'h1C,
    REG_LAST_OPERATION = 'h20,
    REG_CACHE_COMPLETED = 'h24,
    REG_NETWORK_PORT = 'h28,
    REG_COMMAND_COMPLETED = 'h2C,
    REG_COMMAND_LOCK = 'h30,
    REG_CLEAR_COMPLETED = 'h34,
    REG_CLEAR_ADDRESS = 'h38,
    REG_CLEAR_NOTIFY = 'h3C,
    REG_COMMAND_ISSUED = 'h40,
    REG_CLEAR_STATUS = 'h44
} PacketDMA16_14_64_32_4_256_31_64_64_Register;


endpackage
