package CPU_pkg;

parameter  CORES = 64'h4;
parameter  DATA_WIDTH = 64'h100;
parameter  ID_WIDTH = 64'h4;
parameter  MEMORY_BYTES = 64'h40000000;
parameter  IO_BYTES = 64'h400000;
parameter  EXTERNAL_ADDR_WIDTH = 64'h1F;
parameter  L1I_BYTES = 64'h800;
parameter  L1D_BYTES = 64'h400;
parameter  L2_BYTES = 64'h10000;
parameter  CACHE_LINE_BYTES = 64'h20;
parameter  L1_WAYS = 64'h2;
parameter  L2_WAYS = 64'h4;

endpackage
