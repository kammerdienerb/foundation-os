#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

KERN=$(realpath build/kernel/bin/foundation_kernel_x86_64.elf)

mkdir -p ${DIR}/../run
cd ${DIR}/../run

# img=../build/loader/bin/foundation_uefi_x86_64.bin
iso=../build/iso/foundation_x86_64.iso

# qemu-system-x86_64         \
#     -cpu qemu64            \
#     -smp 2                 \
#     -pflash x86_64/OVMF.fd \
#     -hda ${img}            \
#     -net none

if echo $@ | grep -- "--debug" >/dev/null; then
    qemu-system-x86_64         \
        -s -S                  \
        -no-reboot             \
        -no-shutdown           \
        -cpu qemu64            \
        -smp 2                 \
        -pflash x86_64/OVMF.fd \
        -cdrom ${iso}          \
        -net none &
    gdb ${KERN} -ex "target remote localhost:1234" &
    wait
else
    qemu-system-x86_64         \
        -no-reboot             \
        -no-shutdown           \
        -serial stdio          \
        -cpu qemu64            \
        -smp 2                 \
        -pflash x86_64/OVMF.fd \
        -cdrom ${iso}          \
        -net none
fi
