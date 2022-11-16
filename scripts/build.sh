#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}/..

if [ -t 1 ]; then
    CBLACK=$'\e[30m'
    CRED=$'\e[31m'
    CGREEN=$'\e[32m'
    CYELLOW=$'\e[33m'
    CBLUE=$'\e[34m'
    CMAGENTA=$'\e[35m'
    CCYAN=$'\e[36m'
    CWHITE=$'\e[37m'
    CRESET=$'\e[0m'
fi


### Setup vars ###
# JOBS="yes"

if [ $(uname) = "Linux" ]; then
    CLANG="clang"
    LLD_LINK="lld-link"
elif [ $(uname) = "Darwin" ]; then
    LLVM_PATH=$(brew --prefix llvm)
    LLVM_BIN_PATH=${LLVM_PATH}/bin
    CLANG="${LLVM_BIN_PATH}/clang"
    LLD_LINK="${LLVM_BIN_PATH}/lld-link"
fi

SIMON=~/projects/simon/build/bin/simon
SI_FLAGS=""
SI_FLAGS+=" --c-source --output=build/kernel/src/foundation_kernel.c"
# SI_FLAGS+=" -v"
# SI_FLAGS+=" --dump-symbols"

CONFIG=config

function si_source {
    sed 's/ *:= */=/g; s/; *$//g' < $1
}

source <(si_source src/arch_list.si)    || exit $?
source <(si_source config/${CONFIG}.si) || exit $?

export ARCH=${!CONFIG_ARCH}


function clean {
    if [ -t 1 ]; then
        printf "%sCleaning..%s\n" ${CBLUE} ${CRESET}
    else
        echo "Cleaning.."
    fi
    rm    -rf build            || exit $?
    mkdir -p  build            || exit $?
    mkdir -p  build/loader/obj || exit $?
    mkdir -p  build/loader/bin || exit $?
    mkdir -p  build/loader/img || exit $?
    mkdir -p  build/kernel/src || exit $?
    mkdir -p  build/kernel/obj || exit $?
    mkdir -p  build/kernel/bin || exit $?
}

function build_loader {
    if [ -t 1 ]; then
        printf "%sBuilding loader..%s\n" ${CBLUE} ${CRESET}
    else
        echo "Building loader.."
    fi

    CFLAGS="-target ${ARCH}-unknown-windows \
            -ffreestanding                  \
            -fshort-wchar                   \
            -mno-red-zone                   \
            -Isrc/loader/efi -Isrc/loader/efi/${ARCH} -Isrc/loader/efi/protocol"

    LDFLAGS="-target ${ARCH}-unknown-windows \
            -nostdlib                        \
            -Wl,-entry:uefi_loader_main      \
            -Wl,-subsystem:efi_application   \
            -fuse-ld=lld-link"

    ${CLANG} $CFLAGS  -c -o build/loader/obj/uefi_loader.o src/loader/uefi_loader.c                                         || exit $?
    ${CLANG} $CFLAGS  -c -o build/loader/obj/uefi_loader_data.o src/loader/data.c                                           || exit $?
    ${CLANG} $LDFLAGS    -o build/loader/bin/BOOTX64.EFI build/loader/obj/uefi_loader.o build/loader/obj/uefi_loader_data.o || exit $?
}

function build_kernel {
#     SI_SRC="src/arch_list.si config/${CONFIG}.si "
    SI_SRC="src/arch_list.si "
    SI_SRC+="$(find src/kernel/arch/${ARCH} -name "*.si") "
    SI_SRC+="$(find src/kernel -path src/kernel/arch -prune -false -o -name "*.si") "

    if [ -t 1 ]; then
        printf "%sBuilding kernel..%s\n" ${CBLUE} ${CRESET}
    else
        echo "Building kernel.."
    fi
    ${SIMON} ${SI_FLAGS} ${SI_SRC} || exit 1
}

function make_images {
    if [ -t 1 ]; then
        printf "%sCreating images..%s\n" ${CBLUE} ${CRESET}
    else
        echo "Creating images.."
    fi

    scripts/mk_fat_img.sh  || exit $?
    scripts/mk_disk_img.sh || exit $?
}


### Reporting elapsed time ###
export TIMEFORMAT="${CMAGENTA}    took %Rs${RESET}"

function tm {
    time $@
#     if [ "$JOBS" = "yes" ]; then
#         $@
#         ret=$?
#     else
#         exec 3>&1
#         tm_out=$(time "$@" 2>&1 1>&3)
#         ret=$?
#         exec 3>&-
#
#         if [ $ret == "0" ]; then
#             printf "$tm_out"
#         fi
#     fi
#     return $ret
}

### Do it. ###

pids=()

function do_wait {
    if [ "$JOBS" = "yes" ]; then
        for p in ${pids[@]}; do
            wait $p || exit $?
        done
        pids=()
    fi
}

function do_run {
    if [ "$JOBS" = "yes" ]; then
        tm $@ &
        pids+=($!)
    else
        tm $@ || exit $?
    fi
}

function main {
    do_run clean        || exit $?

    do_wait

    do_run build_loader || exit $?
    do_run build_kernel || exit $?

    do_wait

    do_run make_images  || exit $?
}

main || exit $?

do_wait

if [ -t 1 ]; then
    printf "%sTotal time: ${SECONDS}s%s\n" ${CMAGENTA} ${CRESET}
else
    echo "Total time: ${SECONDS}s"
fi
