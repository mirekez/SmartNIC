/*
 * Demo firmware: one worker per four-core Tribe cluster. It is intentionally
 * identical to the verified capture program so video instrumentation cannot
 * alter packet processing behavior.
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
    .equ DMA_COMPLETED,       0x018
    .equ DMA_SOURCE,          0x01c

    .equ DMA_CPU_SYSTEM,      1
    .equ DMA_NETWORK_CPU,     3
    .equ PACKET_BUFFER,       0x00010000
    .equ PACKET_STRIDE,       0x00000800

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

    li      s0, FETCHER_BASE
    li      s1, DMA_BASE
    li      s2, PACKET_BUFFER
    li      t0, 1
    sw      t0, FETCHER_CONTROL(s0)

.Lnext_descriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, 1
    beqz    t0, .Lnext_descriptor

    lw      a0, FETCHER_PACKET_ADDR(s0)
    lw      a1, FETCHER_PACKET_META(s0)
    slli    a1, a1, 16
    srli    a1, a1, 16

    /* RxRAM -> coherent L2 packet buffer. */
    lw      s3, DMA_COMPLETED(s1)
    sw      a0, DMA_RX_HANDLE(s1)
    sw      a1, DMA_LENGTH(s1)
    sw      s2, DMA_DESTINATION(s1)
    li      t0, DMA_NETWORK_CPU
    sw      t0, DMA_FLAGS(s1)
    li      t0, 1
    sw      t0, DMA_COMMAND(s1)
.Lwait_network_cpu:
    lw      t0, DMA_COMPLETED(s1)
    beq     t0, s3, .Lwait_network_cpu

    /*
     * Touch the first 40 packet bytes from firmware. Ten real RV32 loads span
     * two 32-byte cache lines and therefore make the packet prefix visible in
     * this cluster's L1 D-cache. Packet buffers advance by 2 KiB so every
     * packet causes fresh refills instead of hitting a stale line.
     */
    mv      t1, s2
    addi    t2, s2, 40
.Ltouch_prefix:
    lw      t3, 0(t1)
    addi    t1, t1, 4
    bltu    t1, t2, .Ltouch_prefix

    /* coherent L2 packet buffer -> matching System RxQueue. */
    mv      s3, t0
    sw      a1, DMA_LENGTH(s1)
    sw      s2, DMA_SOURCE(s1)
    li      t0, DMA_CPU_SYSTEM
    sw      t0, DMA_FLAGS(s1)
    li      t0, 1
    sw      t0, DMA_COMMAND(s1)
.Lwait_cpu_system:
    lw      t0, DMA_COMPLETED(s1)
    beq     t0, s3, .Lwait_cpu_system

    li      t0, 1
    sw      t0, FETCHER_ACTION(s0)
    li      t0, PACKET_STRIDE
    add     s2, s2, t0
    j       .Lnext_descriptor

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
