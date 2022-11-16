#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}/..

if [ -z ${ARCH} ]; then
    echo "ARCH not set for mk_fat_img.sh"
    exit 1
fi

fat_img=build/loader/bin/UEFI_${ARCH}_FAT.img

if [ $(uname) = "Darwin" ]; then
    dd if=/dev/zero of=${fat_img} bs=1k count=1440 >/dev/null 2>&1
    ret=$?
    if ! test $ret ; then
        echo "dd failed"
        exit $?
    fi
else
    DDSTATUS="none"
    if dd --help | grep -q 'status=noxfer' >/dev/null 2>&1; then
        DDSTATUS="noxfer"
    fi

    dd if=/dev/zero of=${fat_img} bs=1k count=1440 status=${DDSTATUS} || exit $?
fi

mformat -i ${fat_img} -f 1440 ::                             || exit $?
mmd -i ${fat_img} ::/EFI                                     || exit $?
mmd -i ${fat_img} ::/EFI/BOOT                                || exit $?
mcopy -i ${fat_img} build/loader/bin/BOOTX64.EFI ::/EFI/BOOT || exit $?
