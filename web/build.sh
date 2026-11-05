#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
"${EMCC:-emcc}" Sources/FragmentaryDSP/FragmentaryDSP.c \
  -I Sources/FragmentaryDSP/include -O3 --no-entry \
  -s STANDALONE_WASM=1 -s INITIAL_MEMORY=16777216 \
  -s EXPORTED_FUNCTIONS='["_malloc","_free","_FragmentaryDSPCreate","_FragmentaryDSPDestroy","_FragmentaryDSPSetPlace","_FragmentaryDSPSetBlend","_FragmentaryDSPProcessInterleavedStereo"]' \
  -o web/lib/fragmentary.wasm
