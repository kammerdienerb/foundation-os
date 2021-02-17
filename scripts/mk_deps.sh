#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${DIR}/..

mkdir -p deps

cd deps

git clone https://github.com/jncronin/mkgpt
cd deps/mkgpt
automake --add-missing
autoreconf
./configure
make -j4

cd ${DIR}/..
