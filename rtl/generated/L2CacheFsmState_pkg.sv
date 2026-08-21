package L2CacheFsmState_pkg;

typedef enum logic[64-1:0] {
    ST_IDLE = 'h0,
    ST_INIT = 'h1,
    ST_LOOKUP = 'h2,
    ST_AXI_AR = 'h3,
    ST_AXI_R = 'h4,
    ST_DONE = 'h5,
    ST_CROSS_AR0 = 'h6,
    ST_CROSS_R0 = 'h7,
    ST_CROSS_AR1 = 'h8,
    ST_CROSS_R1 = 'h9,
    ST_EVICT_AW = 'hA,
    ST_EVICT_W = 'hB,
    ST_EVICT_B = 'hC,
    ST_CROSS_WRITE_LOOKUP = 'hD,
    ST_CROSS_DONE = 'hE,
    ST_IO_AW = 'hF,
    ST_IO_W = 'h10,
    ST_IO_B = 'h11,
    ST_IO_AR = 'h12,
    ST_IO_R = 'h13,
    ST_READ = 'h14,
    ST_LOOKUP_CAPTURE = 'h15,
    ST_CROSS_WRITE_READ = 'h16,
    ST_CROSS_WRITE_CAPTURE = 'h17,
    ST_LOOKUP_RESULT = 'h18,
    ST_CROSS_WRITE_RESULT = 'h19,
    ST_AXI_R_WRITE = 'h1A,
    ST_IO_R_RESULT = 'h1B
} L2CacheFsmState;


endpackage
