/*
** boot.S
** This code is mainly from http://ringzeroandlower.com/2017/08/08/x86-64-kernel-boot.html,
** though, I've modified it an added some of my own comments/annotations.
**
** When we enter _start, we expect to be:
**     1. in 32-bit protected mode
**     2. loaded by a multiboot2-compliant bootloader
** We need to:
**     1. Set up 64-bit long mode
**     2. Prepare an execution environment for Simon code (stack, paging, etc.)
**     3. Jump to our kernel main routine (kmain)
*/



#include "gdt.h"
#include "mmu.h"
#include "kernel.h"
#include "multiboot2.h"
#include "msr.h"

#define TWO_MEGABYTES_SHIFT (21)
#define TWO_MEGABYTES       (1 << TWO_MEGABYTES_SHIFT)


/*
** Set up our multiboot2 header.
** We want to ask for a linear framebuffer so that we can draw stuff
** to the screen.
*/

.SET HEADER_LENGTH, header_end - header_start
.SET CHECKSUM, -(MULTIBOOT2_HEADER_MAGIC + MULTIBOOT_ARCHITECTURE_I386 + HEADER_LENGTH)
.section .multiboot
header_start:
    .long MULTIBOOT2_HEADER_MAGIC
    .long MULTIBOOT_ARCHITECTURE_I386
    .long HEADER_LENGTH
    .long CHECKSUM

    // multiboot tags go here

    .short MULTIBOOT2_HEADER_TAG_CONSOLE_FLAGS
    .short 0  // flags
    .long  12 // size
    .long  0  // console_flags (don't need -- using framebuffer)

    .short MULTIBOOT2_HEADER_TAG_INFORMATION_REQUEST
    .short 0           // flags
    .long  8 + (1 * 4) // size
    .long  MULTIBOOT_TAG_TYPE_FRAMEBUFFER

    .short MULTIBOOT2_HEADER_TAG_FRAMEBUFFER
    .short 0  // flags
    .long  20 // size
    .long  0  // width  (don't care)
    .long  0  // height (don't care)
    .long  0  // depth  (don't care)

    .short MULTIBOOT_HEADER_TAG_END
    .short 0  // flags, none set
    .long  8  // size, including itself (short + short + long)
header_end:


/*
** The following section is our boot entry code that runs in _32-bit_
** protected mode.
** It's going to set us up for the jump to long mode.
*/
.code32

.section .bss
//    symbol                     size                    alignment
.comm pml4,                      PML4_SIZE,              PML4_ALIGNMENT
.comm low_pdpt,                  PDPT_SIZE,              PDPT_ALIGNMENT
.comm high_pdpt,                 PDPT_SIZE,              PDPT_ALIGNMENT
.comm low_page_directory_table,  PAGE_DIRECTORY_SIZE,    PAGE_DIRECTORY_ALIGNMENT
.comm high_page_directory_table, PAGE_DIRECTORY_SIZE,    PAGE_DIRECTORY_ALIGNMENT
.comm tmp_stack,                 KERNEL_BOOT_STACK_SIZE, KERNEL_BOOT_STACK_ALIGNMENT
.comm save_multiboot_magic,      4,                      4

.data
.align GDT_TABLE_ALIGNMENT
gdt_table:
        .8byte GDT_FIRST_ENTRY
        .8byte GDT_KERNEL_ENTRY

gdt_table_end:
        .skip (GDT_TABLE_SIZE - (gdt_table_end - gdt_table))

gdt_ptr:
         .short GDT_TABLE_SIZE - 1
         .long gdt_table


.section .text
.global _start
.type _start, @function
_start:
        // Save EAX so that we can get it later.
        // This is supposed to have our multiboot2 magic number.
        movl %eax, save_multiboot_magic

        // Set us up with some stack space.
        movl $tmp_stack + KERNEL_BOOT_STACK_SIZE, %esp


        movl $low_pdpt, %eax
        or $(MMU_PRESENT | MMU_WRITABLE), %eax
        movl %eax, pml4 + (PML4_ADDR_TO_ENTRY_INDEX(KERNEL_PHYSICAL_START) * PML4_ENTRY_SIZE)

        movl $high_pdpt, %eax
        or $(MMU_PRESENT | MMU_WRITABLE), %eax
        movl %eax, pml4 + (PML4_ADDR_TO_ENTRY_INDEX(KERNEL_VIRTUAL_START) * PML4_ENTRY_SIZE)

        movl $low_page_directory_table, %eax
        or $(MMU_PRESENT | MMU_WRITABLE), %eax
        movl %eax, low_pdpt + (PDPT_ADDR_TO_ENTRY_INDEX(KERNEL_PHYSICAL_START) * PDPT_ENTRY_SIZE)

        movl $high_page_directory_table, %eax
        or $(MMU_PRESENT | MMU_WRITABLE), %eax
        movl %eax, high_pdpt + (PDPT_ADDR_TO_ENTRY_INDEX(KERNEL_VIRTUAL_START) * PDPT_ENTRY_SIZE)

        mov $0, %ecx

        movl $_kernel_physical_end, %esi
        shrl $TWO_MEGABYTES_SHIFT, %esi
        addl $1, %esi

page_directory_table_loop:
        movl $TWO_MEGABYTES, %eax
        mul %ecx
        or $(MMU_PRESENT | MMU_WRITABLE | MMU_PDE_TWO_MB), %eax
        movl %eax, low_page_directory_table(, %ecx, PAGE_DIRECTORY_ENTRY_SIZE)
        movl %eax, high_page_directory_table(, %ecx, PAGE_DIRECTORY_ENTRY_SIZE)

        inc %ecx
        cmp %esi, %ecx
        jne page_directory_table_loop  // if not equal redo loop

        movl $pml4, %eax
        movl %eax, %cr3

        movl $KERNEL_CR4, %eax
        movl %eax, %cr4

        movl $MSR_EFER, %ecx
        rdmsr
        or $MSR_EFER_LME, %eax
        wrmsr

        movl $KERNEL_CR0, %eax
        movl %eax, %cr0

        lgdt gdt_ptr

        // Restore multiboot2 magic back into EAX
        movl save_multiboot_magic, %eax

        ljmp $(KERNEL_GDT_ENTRY * GDT_ENTRY_SIZE), $_start64

        cli
        hlt

.code64

.section .bss

.global multiboot_magic
.comm multiboot_magic, 4, 4
.global multiboot_info_addr
.comm multiboot_info_addr, 8, 8

.section .text

.global _start64
.type _start64, @function
_start64:
        // Save the multiboot magic and info address, which are in EAX, EBX per the spec
        // (were saved in earlier code)
        movl %eax, multiboot_magic
        movl %ebx, multiboot_info_addr

        // Setup segment selectors
        movw $0, %ax
        movw %ax, %ds
        movw %ax, %es
        movw %ax, %fs
        movw %ax, %gs
        movw %ax, %ss

        call kmain

        // Should never reach here
        cli
        hlt
1:
        jmp 1b
