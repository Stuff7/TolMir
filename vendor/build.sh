#!/bin/bash

vendor="$PWD/$(dirname "$BASH_SOURCE")"

cd "$vendor/libarchive"
git clean -xdf && git restore .
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_WERROR=OFF \
  -DENABLE_OPENSSL=OFF \
  -DENABLE_LZMA=ON \
  -DENABLE_LZ4=OFF \
  -DENABLE_ZSTD=OFF \
  -DENABLE_ZLIB=ON \
  -DENABLE_BZip2=OFF \
  -DENABLE_UNZIP=ON \
  -DENABLE_TAR=OFF \
  -DENABLE_CPIO=OFF \
  -DENABLE_CAT=OFF \
  -DENABLE_TEST=OFF
cd build && make

cd "$vendor/zlib"
git clean -xdf && git restore .
cmake -S . -B build.included \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DZLIB_BUILD_EXAMPLES=OFF
cd build.included && make

cd "$vendor/xz"
git clean -xdf && git restore .
./autogen.sh
./configure --disable-shared
make
