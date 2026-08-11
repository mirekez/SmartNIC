package InputBalancerOutput1280_160_pkg;

typedef struct packed {
    logic[8-1:0] valid;
    logic[160-1:0] eop;
    logic[160-1:0] sop;
    logic[160-1:0] keep;
    logic[1280-1:0] data;
} InputBalancerOutput1280_160;


endpackage
