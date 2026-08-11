package PacketDMA_Register_pkg;

typedef enum {
    REG_RX_HANDLE = 'h0,
    REG_LENGTH = 'h4,
    REG_DESTINATION = 'h8,
    REG_FLAGS = 'hC,
    REG_COMMAND = 'h10,
    REG_STATUS = 'h14,
    REG_COMPLETED = 'h18,
    REG_SOURCE = 'h1C,
    REG_LAST_OPERATION = 'h20
} PacketDMA_Register;


endpackage
