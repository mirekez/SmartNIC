/*
 * One capture worker runs in every four-core Tribe cluster. It enables the
 * local DescriptorFetcher and drains every RxRAM packet. To sustain ingress,
 * packets not selected by the one-in-ten sampler use PacketDMA's discard fast
 * path; selected packets stream directly into the corresponding System
 * RxQueue without a second traversal of the bandwidth-limited L2 AXI port.
 */

    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function

    .equ FETCHER_BASE,        0x40000000
    .equ FETCHER_CONTROL,     0x000
    .equ FETCHER_STATUS,      0x004
    .equ FETCHER_ACTION,      0x008
    .equ FETCHER_PACKET_ADDR, 0x100
    .equ FETCHER_PACKET_META, 0x104

    .equ DMA_BASE,            0x40001000
    .equ DMA_RX_HANDLE,       0x000
    .equ DMA_LENGTH,          0x004
    .equ DMA_DESTINATION,     0x008
    .equ DMA_FLAGS,           0x00c
    .equ DMA_COMMAND,         0x010
    .equ DMA_STATUS,          0x014
    .equ DMA_COMPLETED,       0x018
    .equ DMA_SOURCE,          0x01c

    .equ DMA_CPU_SYSTEM,      1
    .equ DMA_NETWORK_CPU,     3
    .equ DMA_NETWORK_DISCARD, 8
    .equ DMA_NETWORK_SYSTEM,  16
    .equ PACKET_BUFFER,       0x00010000

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

    li      s0, FETCHER_BASE
    li      s4, 9              /* First captured packet is the local #10. */
    li      t0, 1
    sw      t0, FETCHER_CONTROL(s0)

.Lnext_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, 9          /* descriptor available and DMA FIFO ready */
    li      t1, 9
    bne     t0, t1, .Lnext_descriptor

    addi    s4, s4, 1
    li      t1, 10
    bltu    s4, t1, .Ldiscard
    li      s4, 0
    li      t2, 5              /* NEXT | DMA_SYSTEM */
    j       .Lissue_network
.Ldiscard:
    li      t2, 3              /* NEXT | DMA_DISCARD */

    /* One doorbell transfers handle/length directly from Fetcher to DMA. */
.Lissue_network:
    sw      t2, FETCHER_ACTION(s0)
    j       .Lnext_descriptor

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
