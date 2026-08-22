package SystemControllerFlags_pkg;

typedef enum logic[8-1:0] {
    SYSTEM_TX_DESCRIPTOR_EOP = 'h1 <<< 'h0
} SystemControllerFlags;


endpackage
