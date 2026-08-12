# RxRAM

RxRAM accepts both 64-bit receive streams every 156.25 MHz cycle. Four physical
banks allow both writes to proceed concurrently while the single processing
read engine retrieves packet words. Handles retain the logical row and bank
information used by descriptors.

The unit test drives both writers, randomized packet sizes and alignment, then
checks handles, completion metadata, byte-exact reads, and protocol errors.
