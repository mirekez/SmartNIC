/*
 * Core-0 packet loopback bring-up firmware.
 *
 * Every raw receive descriptor is copied from RxRAM into one coherent scratch
 * buffer and then transmitted to the opposite physical port.  Only one packet
 * is outstanding, deliberately making the first hardware image easy to debug.
 * Later firmware may queue several buffers or distribute work across harts.
 */

    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function

    .equ FETCHER_BASE,          0x40000000
    .equ FETCHER_CONTROL,       0x000
    .equ FETCHER_STATUS,        0x004
    .equ FETCHER_ACTION,        0x008
    .equ FETCHER_PACKET_ADDR,   0x100
    .equ FETCHER_PACKET_META,   0x104
    .equ FETCHER_SOURCE_PORT,   0x140
    .equ FETCHER_AVAILABLE,     1
    .equ FETCHER_DMA_READY,     8
    .equ ACTION_NEXT,           1

    .equ DMA_BASE,              0x40001000
    .equ DMA_RX_HANDLE,         0x000
    .equ DMA_LENGTH,            0x004
    .equ DMA_DESTINATION,       0x008
    .equ DMA_FLAGS,             0x00c
    .equ DMA_COMMAND,           0x010
    .equ DMA_STATUS,            0x014
    .equ DMA_COMMAND_COMPLETED, 0x02c
    .equ DMA_SOURCE,            0x01c
    .equ DMA_NETWORK_PORT,      0x028
    .equ DMA_CMD_READY,         2

    .equ DMA_CPU_NETWORK,       2
    .equ DMA_NETWORK_CPU,       3
    .equ PACKET_SCRATCH,        0x00010000

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lpark

    li      s0, FETCHER_BASE
    li      s1, DMA_BASE
    li      s2, 0                  /* expected main-engine completion */
    li      s3, PACKET_SCRATCH
    li      t0, 1
    sw      t0, FETCHER_CONTROL(s0)

.Ldescriptor:
    lw      t0, FETCHER_STATUS(s0)
    andi    t0, t0, FETCHER_AVAILABLE | FETCHER_DMA_READY
    li      t1, FETCHER_AVAILABLE | FETCHER_DMA_READY
    bne     t0, t1, .Ldescriptor

    lw      s4, FETCHER_PACKET_META(s0)
    slli    s4, s4, 16
    srli    s4, s4, 16             /* exact frame length */
    lw      s5, FETCHER_SOURCE_PORT(s0)
    andi    s5, s5, 1
    xori    s5, s5, 1              /* physical egress = ingress XOR 1 */
    lw      t0, FETCHER_PACKET_ADDR(s0)

    /* RxRAM -> coherent scratch memory. */
    sw      t0, DMA_RX_HANDLE(s1)
    sw      s4, DMA_LENGTH(s1)
    sw      s3, DMA_DESTINATION(s1)
    li      t1, DMA_NETWORK_CPU
    sw      t1, DMA_FLAGS(s1)
    li      t1, 1
    sw      t1, DMA_COMMAND(s1)
    sw      t1, FETCHER_ACTION(s0)

.Lwait_rx:
    lw      t0, DMA_COMMAND_COMPLETED(s1)
    beq     t0, s2, .Lwait_rx
    mv      s2, t0

.Lwait_tx_ready:
    lw      t0, DMA_STATUS(s1)
    andi    t0, t0, DMA_CMD_READY
    beqz    t0, .Lwait_tx_ready

    /* Coherent scratch memory -> opposite Network TxFIFO. */
    sw      s4, DMA_LENGTH(s1)
    sw      s3, DMA_SOURCE(s1)
    sw      s5, DMA_NETWORK_PORT(s1)
    li      t0, DMA_CPU_NETWORK
    sw      t0, DMA_FLAGS(s1)
    li      t0, 1
    sw      t0, DMA_COMMAND(s1)

.Lwait_tx:
    lw      t0, DMA_COMMAND_COMPLETED(s1)
    beq     t0, s2, .Lwait_tx
    mv      s2, t0
    j       .Ldescriptor

.Lpark:
    wfi
    j       .Lpark

    .size _start, .-_start
