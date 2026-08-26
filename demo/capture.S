/*
 * Four-core video-demo firmware. Hardware prefetches every received packet
 * into one of thirty-two coherent 2 KiB L2 slots. Harts 1..3 inspect disjoint
 * packet sequences so every first 40-byte header enters an L1 D-cache. Hart 0
 * owns the shared PacketDMA staging registers, rereads every twentieth destination
 * MAC to select Network TX, and copies every fortieth packet to the host.
 */

    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function

    .equ FETCHER_BASE,        0x40000000
    .equ FETCHER_CONTROL,     0x000
    .equ FETCHER_ENABLE,      1
    .equ FETCHER_AUTO_L2,     2

    .equ DMA_BASE,            0x40001000
    .equ DMA_LENGTH,          0x004
    .equ DMA_FLAGS,           0x00c
    .equ DMA_COMMAND,         0x010
    .equ DMA_STATUS,          0x014
    .equ DMA_COMPLETED,       0x018
    .equ DMA_SOURCE,          0x01c
    .equ DMA_CACHE_COMPLETED, 0x024
    .equ DMA_NETWORK_PORT,    0x028
    .equ DMA_BUSY,            1
    .equ DMA_COMMAND_READY,   2

    .equ DMA_CPU_SYSTEM,      1
    .equ DMA_CPU_NETWORK,     2
    .equ NETWORK_INTERVAL,    20
    .equ PACKET_BUFFER,       0x00010000
    .equ PACKET_SLOT_SHIFT,   11
    .equ PACKET_SLOT_MASK,    31
    .equ PACKET_BYTES,        1516

_start:
    csrr    t0, mhartid
    andi    t0, t0, 3
    bnez    t0, .Lworker

    /* Hart 0 is the sole owner of DescriptorFetcher and PacketDMA MMIO. */
    li      s0, FETCHER_BASE
    li      s1, DMA_BASE
    li      s2, NETWORK_INTERVAL  /* next one-based TX sample sequence */
    li      s5, 2                 /* one host copy per two TX samples */
    li      t0, FETCHER_ENABLE | FETCHER_AUTO_L2
    sw      t0, FETCHER_CONTROL(s0)

.Lmanager_wait_packet:
    lw      t0, DMA_CACHE_COMPLETED(s1)
    bltu    t0, s2, .Lmanager_wait_packet

    /* Sample N occupies slot (N - 1) modulo thirty-two. */
    addi    t0, s2, -1
    andi    t0, t0, PACKET_SLOT_MASK
    slli    t0, t0, PACKET_SLOT_SHIFT
    li      s3, PACKET_BUFFER
    add     s3, s3, t0

    /* Hart 0 rereads each sampled prefix through its private L1 D-cache. */
    mv      t1, s3
    addi    t2, t1, 40
    li      s6, 0
.Ltouch_prefix:
    lw      t3, 0(t1)
    xor     s6, s6, t3
    addi    t1, t1, 4
    bltu    t1, t2, .Ltouch_prefix

    /* Read both Ethernet MACs from the packet-resident L1 lines. */
    lw      s7, 0(s3)
    lw      t3, 4(s3)
    lw      t4, 8(s3)
    slli    s8, t3, 16
    srli    s8, s8, 16
    srli    s9, t3, 16
    slli    t5, t4, 16
    or      s9, s9, t5
    srli    s10, t4, 16

    /* Complete coherent L2 -> PacketDMA -> Network TxFIFO -> physical MAC. */
.Lwait_network_command_ready:
    lw      t0, DMA_STATUS(s1)
    andi    t0, t0, DMA_COMMAND_READY
    beqz    t0, .Lwait_network_command_ready
    li      t0, PACKET_BYTES
    sw      t0, DMA_LENGTH(s1)
    sw      s3, DMA_SOURCE(s1)
    srli    t0, s7, 24
    andi    t0, t0, 1
    sw      t0, DMA_NETWORK_PORT(s1)
    li      t0, DMA_CPU_NETWORK
    sw      t0, DMA_FLAGS(s1)
    li      t0, 1
    sw      t0, DMA_COMMAND(s1)
.Lwait_cpu_network:
    lw      t0, DMA_STATUS(s1)
    andi    t0, t0, DMA_BUSY
    bnez    t0, .Lwait_cpu_network

    addi    s5, s5, -1
    bnez    s5, .Lmanager_next
    li      s5, 2

    /* Coherent L2 -> System RxQueue for every fortieth packet. */
.Lwait_host_command_ready:
    lw      t0, DMA_STATUS(s1)
    andi    t0, t0, DMA_COMMAND_READY
    beqz    t0, .Lwait_host_command_ready
    li      t0, PACKET_BYTES
    sw      t0, DMA_LENGTH(s1)
    sw      s3, DMA_SOURCE(s1)
    li      t0, DMA_CPU_SYSTEM
    sw      t0, DMA_FLAGS(s1)
    li      t0, 1
    sw      t0, DMA_COMMAND(s1)
.Lwait_cpu_system:
    lw      t0, DMA_STATUS(s1)
    andi    t0, t0, DMA_BUSY
    bnez    t0, .Lwait_cpu_system

.Lmanager_next:
    addi    s2, s2, NETWORK_INTERVAL
    j       .Lmanager_wait_packet

    /* Harts 1..3 process sequences hartid, hartid+3, ... independently.
       They never touch the shared DMA command registers, so no atomic lock is
       required despite RV32A being disabled in the product CPU profile. */
.Lworker:
    li      s0, DMA_BASE
    mv      s2, t0
.Lworker_wait:
    lw      t1, DMA_CACHE_COMPLETED(s0)
    bltu    t1, s2, .Lworker_wait
    addi    t1, s2, -1
    andi    t1, t1, PACKET_SLOT_MASK
    slli    t1, t1, PACKET_SLOT_SHIFT
    li      s3, PACKET_BUFFER
    add     s3, s3, t1
    mv      t1, s3
    addi    t2, s3, 40
    li      s6, 0
.Lworker_touch_prefix:
    lw      t3, 0(t1)
    xor     s6, s6, t3
    addi    t1, t1, 4
    bltu    t1, t2, .Lworker_touch_prefix
    addi    s2, s2, 3
    j       .Lworker_wait

    .size _start, .-_start
