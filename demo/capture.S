/*
 * Sustained-video firmware: one worker per four-core Tribe cluster. Every
 * packet is copied from RxRAM into the cluster's coherent L2 packet buffer.
 * The CPU touches the first 40 bytes of every tenth packet through L1 D-cache
 * and then sends that packet from L2 to the matching System RxQueue.
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
    .equ FETCHER_PACKET_BUF,  0x140
    .equ FETCHER_LOADED,      0x10

    .equ DMA_BASE,            0x40001000
    .equ DMA_RX_HANDLE,       0x000
    .equ DMA_LENGTH,          0x004
    .equ DMA_DESTINATION,     0x008
    .equ DMA_FLAGS,           0x00c
    .equ DMA_COMMAND,         0x010
    .equ DMA_COMPLETED,       0x018
    .equ DMA_SOURCE,          0x01c

    .equ DMA_CPU_SYSTEM,      1
    .equ DMA_NETWORK_CPU,     3
    .equ DMA_CACHE_ALLOCATE,  4
    .equ DMA_PACKET_STAGING,  64
    .equ PACKET_BUFFER,       0x00010000

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

    li      s0, FETCHER_BASE
    li      s1, DMA_BASE
    li      s4, 9
    li      t0, 3              /* Enable descriptor pre-read and auto L2 load. */
    sw      t0, FETCHER_CONTROL(s0)

.Lnext_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, 1
    beqz    t0, .Lnext_descriptor

    lw      a1, FETCHER_PACKET_META(s0)
    slli    a1, a1, 16
    srli    a1, a1, 16
    lw      s2, FETCHER_PACKET_BUF(s0)
.Lwait_network_cpu:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, FETCHER_LOADED
    beqz    t0, .Lwait_network_cpu

    addi    s4, s4, 1
    li      t1, 10
    bltu    s4, t1, .Lretire
    li      s4, 0

    /* Every tenth packet: two real L1 D-cache line touches. */
    mv      t1, s2
    addi    t2, s2, 40
.Ltouch_prefix:
    lw      t3, 0(t1)
    addi    t1, t1, 4
    bltu    t1, t2, .Ltouch_prefix

    /* Every tenth packet: coherent L2 packet buffer -> System RxQueue. */
    lw      s3, DMA_COMPLETED(s1)
    sw      a1, DMA_LENGTH(s1)
    sw      s2, DMA_SOURCE(s1)
    li      t0, DMA_CPU_SYSTEM | DMA_PACKET_STAGING
    sw      t0, DMA_FLAGS(s1)
    li      t0, 1
    sw      t0, DMA_COMMAND(s1)
.Lwait_cpu_system:
    lw      t0, DMA_COMPLETED(s1)
    beq     t0, s3, .Lwait_cpu_system

.Lretire:
    li      t0, 1              /* NEXT after packet processing is complete. */
    sw      t0, FETCHER_ACTION(s0)
    j       .Lnext_descriptor

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
