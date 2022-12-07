#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}/..

if [ -z ${ARCH} ]; then
    echo "ARCH not set for mk_disk_img.sh"
    exit 1
fi

mkdir -p build/iso/${ARCH}/boot/grub || exit $?

printf 'set timeout=1\nmenuentry "Foundation (%s)" {\n  insmod all_video\n  multiboot2 /boot/foundation_kernel_%s.elf\n}' ${ARCH} ${ARCH} > build/iso/${ARCH}/boot/grub/grub.cfg

cp build/kernel/bin/foundation_kernel_${ARCH}.elf build/iso/${ARCH}/boot || exit $?

grub-mkrescue -o build/iso/foundation_${ARCH}.iso build/iso/${ARCH} || exit $?

deps/mkgpt/mkgpt -o build/loader/bin/foundation_uefi_${ARCH}.bin --image-size 4096 --part build/loader/bin/UEFI_${ARCH}_FAT.img --type system
