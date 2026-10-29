#!/usr/bin/env bash
#
# mayhem/build.sh — build libuvc's libFuzzer harnesses (test/fuzz/*.c) and its gtest suite.
# Runs in the commit image as `mayhem` in /mayhem; see the template for the build-contract ENV.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) The library itself, sanitized + DWARF 3, static only. Build dirs live under build/ (gitignored).
cmake -S . -B build/fuzz -G Ninja \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
  -DCMAKE_BUILD_TARGET=Static -DBUILD_EXAMPLE=OFF
cmake --build build/fuzz -j"$MAYHEM_JOBS" --target uvc_static

# 2) Each upstream harness twice: libFuzzer binary + run-once standalone reproducer.
#    LSan is switched off at build time (lsan_off.o); ASan and UBSan stay on and halting.
INC=(-I"$SRC/include" -I"$SRC/build/fuzz/include" -I"$SRC/test" -I/usr/include/libusb-1.0)
LIBS=("$SRC/build/fuzz/libuvc.a" -lusb-1.0 -ljpeg -lpthread)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o build/fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/fuzz/standalone_main.o
for h in fuzz_descriptor fuzz_payload; do
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${INC[@]}" \
      "$SRC/test/fuzz/$h.c" build/fuzz/lsan_off.o "${LIBS[@]}" -o "/mayhem/$h"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "${INC[@]}" \
      "$SRC/test/fuzz/$h.c" build/fuzz/standalone_main.o build/fuzz/lsan_off.o "${LIBS[@]}" -o "/mayhem/$h-standalone"
done

# 3) Upstream's gtest suite with NORMAL flags (no sanitizers) for mayhem/test.sh to run.
cmake -S . -B build/tests -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS" \
  -DBUILD_TESTING=ON -DBUILD_EXAMPLE=OFF
# (all targets: ninja's bare `test_frame` aliases vanish on reconfigure, so --target would break a re-run)
cmake --build build/tests -j"$MAYHEM_JOBS"
