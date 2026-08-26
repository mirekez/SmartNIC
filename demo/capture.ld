ENTRY(_start)

SECTIONS
{
    . = 0;
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
