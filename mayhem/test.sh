#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's gtest suite (built by mayhem/build.sh) and report CTRF counts.
# Each binary is run directly and its gtest summary parsed; a binary that prints no summary
# (crashed, hung, or neutered) counts as a failure, so a no-op program cannot pass.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

passed=0 failed=0 skipped=0
for t in test_frame test_frame_reference test_frame_mjpeg test_descriptor test_stream; do
  bin="$SRC/build/tests/test/$t"
  if [ ! -x "$bin" ]; then echo "missing test binary $bin (build.sh bug)" >&2; exit 2; fi
  out=$(timeout 300 "$bin" 2>&1); rc=$?
  echo "$out" | tail -n 5
  p=$(echo "$out" | sed -n 's/^\[  PASSED  \] \([0-9]*\) tests\?\..*/\1/p' | tail -1)
  s=$(echo "$out" | sed -n 's/^\[  SKIPPED \] \([0-9]*\) tests\?, listed below.*/\1/p' | tail -1)
  f=$(echo "$out" | sed -n 's/^\[  FAILED  \] \([0-9]*\) tests\?, listed below.*/\1/p' | tail -1)
  if [ -z "$p" ] && [ -z "$f" ] && [ -z "$s" ]; then
    # no gtest summary at all: crash/hang/neutered binary
    failed=$((failed + 1)); echo "FAIL $t: no gtest summary (rc=$rc)" >&2; continue
  fi
  passed=$((passed + ${p:-0})); failed=$((failed + ${f:-0})); skipped=$((skipped + ${s:-0}))
  if [ "$rc" -ne 0 ] && [ "${f:-0}" -eq 0 ]; then failed=$((failed + 1)); fi
done

emit_ctrf "gtest" "$passed" "$failed" "$skipped"
