#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
"${EMCC:-emcc}" Sources/OverhearDSP/OverhearDSP.c \
  -I Sources/OverhearDSP/include -O3 --no-entry \
  -s STANDALONE_WASM=1 -s INITIAL_MEMORY=16777216 \
  -s EXPORTED_FUNCTIONS='["_malloc","_free","_OverhearDSPCreate","_OverhearDSPDestroy","_OverhearDSPSetPlace","_OverhearDSPSetBlend","_OverhearDSPProcessInterleavedStereo"]' \
  -o web/lib/overhear.wasm
