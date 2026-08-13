/*
 * Sustained-video firmware: one worker per four-core Tribe cluster. Every
 * descriptor is consumed; one packet in ten is streamed from RxRAM directly
 * to System and all others use PacketDMA's discard fast path.
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

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

    li      s0, FETCHER_BASE
    li      s4, 9
    li      t0, 1
    sw      t0, FETCHER_CONTROL(s0)

.Lnext_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, 9
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
.Lissue_network:
    sw      t2, FETCHER_ACTION(s0)
    j       .Lnext_descriptor

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
