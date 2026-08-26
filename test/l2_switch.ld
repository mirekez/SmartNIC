ENTRY(_start)

SECTIONS
{
    /* The sustained harness uses a 1 MiB packet ring in the lower half of its
       2 MiB DDR. Firmware and MAC tables share the upper half. */
    . = 0x00100000;
    .text : ALIGN(4)
    {
        KEEP(*(.text.start))
        *(.text*)
    }
    /DISCARD/ :
    {
        *(.comment*)
        *(.riscv.attributes*)
    }
}
