#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

mkdir -p ${DIR}/../run
cd ${DIR}/../run

img=../build/bin/foundation_uefi_x86_64.bin

qemu-system-x86_64         \
    -cpu qemu64            \
    -smp 2                 \
    -pflash x86_64/OVMF.fd \
    -hda ${img}            \
    -net none
