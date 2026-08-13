/*
 * One capture worker runs on the single Tribe cluster and drains every RxRAM
 * packet. Packets 1..99 use PacketDMA's discard path; packet 100 streams
 * directly into the System RxQueue without traversing coherent L2 memory.
 */

    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function

    .equ FETCHER_BASE,        0x40000000
    .equ FETCHER_CONTROL,     0x000
    .equ FETCHER_STATUS,      0x004
    .equ FETCHER_ACTION,      0x008
    .equ FETCHER_AVAILABLE,   1
    .equ FETCHER_DMA_READY,   8
    .equ ACTION_NEXT,         1
    .equ ACTION_DMA_DISCARD,  2
    .equ ACTION_DMA_SYSTEM,   4

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

    li      s0, FETCHER_BASE
    li      t0, 1
    sw      t0, FETCHER_CONTROL(s0)
    li      s4, 0

.Lnext_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, FETCHER_AVAILABLE | FETCHER_DMA_READY
    li      t1, FETCHER_AVAILABLE | FETCHER_DMA_READY
    bne     t0, t1, .Lnext_descriptor

    addi    s4, s4, 1
    li      t1, 100
    bne     s4, t1, .Ldiscard
    li      s4, 0
    li      t2, ACTION_NEXT | ACTION_DMA_SYSTEM
    j       .Lissue

.Ldiscard:
    li      t2, ACTION_NEXT | ACTION_DMA_DISCARD

    /* Fetcher transfers descriptor handle/length directly into PacketDMA. */
.Lissue:
    sw      t2, FETCHER_ACTION(s0)
    j       .Lnext_descriptor

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
