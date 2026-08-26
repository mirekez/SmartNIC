/*
 * One capture worker runs in every four-core Tribe cluster. DescriptorFetcher
 * Functional mode loads every packet into a private L2/DDR circular buffer.
 * The sustained-throughput build retains the discard/direct-System path so it
 * measures the 400G network pipeline rather than Tribe's current per-line L1
 * invalidation mailbox. Both modes send every tenth local packet to host.
 */

#ifndef CAPTURE_DDR_RING
#define CAPTURE_DDR_RING 1
#endif

    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function

    .equ FETCHER_BASE,        0x40000000
    .equ FETCHER_CONTROL,     0x000
    .equ FETCHER_STATUS,      0x004
    .equ FETCHER_ACTION,      0x008
    .equ FETCHER_AUTO_MASK,   0x00c
    .equ FETCHER_PACKET_META, 0x104
    .equ FETCHER_PACKET_BUF,  0x140

    .equ FETCHER_ENABLE,      1
    .equ FETCHER_AUTO_L2,     2
    .equ FETCHER_AVAILABLE,   1
    .equ FETCHER_DMA_READY,   8
    .equ FETCHER_LOADED,      16
    .equ FETCHER_NEXT,        1
    .equ FETCHER_DISCARD,     2
    .equ FETCHER_SYSTEM,      4

    .equ DMA_BASE,            0x40001000
    .equ DMA_LENGTH,          0x004
    .equ DMA_FLAGS,           0x00c
    .equ DMA_COMMAND,         0x010
    .equ DMA_STATUS,          0x014
    .equ DMA_SOURCE,          0x01c
    .equ DMA_COMMAND_LOCK,    0x030

    .equ DMA_CPU_SYSTEM,      1
    .equ DMA_COMMAND_PUSH,    1
    .equ DMA_COMMAND_READY,   2
    .equ PACKET_RING_MASK,    511

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

#if CAPTURE_DDR_RING
    li      s0, FETCHER_BASE
    li      s1, DMA_BASE
    li      s4, 9              /* First captured packet is the local #10. */
    csrr    s5, mhartid
    addi    s5, s5, 1          /* Nonzero per-cluster lock owner token. */
    li      t0, PACKET_RING_MASK
    sw      t0, FETCHER_AUTO_MASK(s0)
    li      t0, FETCHER_ENABLE | FETCHER_AUTO_L2
    sw      t0, FETCHER_CONTROL(s0)

.Lnext_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, FETCHER_AVAILABLE | FETCHER_LOADED
    li      t1, FETCHER_AVAILABLE | FETCHER_LOADED
    bne     t0, t1, .Lnext_descriptor

    addi    s4, s4, 1
    li      t1, 10
    bltu    s4, t1, .Lrelease
    li      s4, 0

    /* Wait for command FIFO space, then acquire the short-lived staging lock. */
.Ldma_ready:
    lw      t0, DMA_STATUS(s1)
    andi    t0, t0, DMA_COMMAND_READY
    beqz    t0, .Ldma_ready
.Llock:
    sw      s5, DMA_COMMAND_LOCK(s1)
    lw      t0, DMA_COMMAND_LOCK(s1)
    bne     t0, s5, .Llock

    lw      t0, FETCHER_PACKET_META(s0)
    li      t1, 0x3fff
    and     t0, t0, t1
    lw      t1, FETCHER_PACKET_BUF(s0)
    sw      t0, DMA_LENGTH(s1)
    sw      t1, DMA_SOURCE(s1)
    li      t2, DMA_CPU_SYSTEM
    sw      t2, DMA_FLAGS(s1)
    li      t2, DMA_COMMAND_PUSH
    sw      t2, DMA_COMMAND(s1)
    sw      zero, DMA_COMMAND_LOCK(s1)

.Lrelease:
    li      t0, FETCHER_NEXT
    sw      t0, FETCHER_ACTION(s0)
    j       .Lnext_descriptor
#else
    li      s0, FETCHER_BASE
    li      s4, 9              /* First captured packet is the local #10. */
    li      t0, FETCHER_ENABLE
    sw      t0, FETCHER_CONTROL(s0)

.Lnext_fast_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, FETCHER_AVAILABLE | FETCHER_DMA_READY
    li      t1, FETCHER_AVAILABLE | FETCHER_DMA_READY
    bne     t0, t1, .Lnext_fast_descriptor
    addi    s4, s4, 1
    li      t1, 10
    bltu    s4, t1, .Lfast_discard
    li      s4, 0
    li      t2, FETCHER_NEXT | FETCHER_SYSTEM
    j       .Lfast_issue
.Lfast_discard:
    li      t2, FETCHER_NEXT | FETCHER_DISCARD
.Lfast_issue:
    sw      t2, FETCHER_ACTION(s0)
    j       .Lnext_fast_descriptor
#endif

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
