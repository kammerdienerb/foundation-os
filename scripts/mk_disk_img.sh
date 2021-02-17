#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}/..

if [ -z ${ARCH} ]; then
    echo "ARCH not set for mk_disk_img.sh"
    exit 1
fi

deps/mkgpt/mkgpt -o build/bin/foundation_uefi_${ARCH}.bin --image-size 4096 --part build/bin/UEFI_${ARCH}_FAT.img --type system
