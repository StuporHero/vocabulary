#!/usr/bin/env bash
# Secondary probe: does `slangc -dump-module` already produce a stable
# representation that we could hash as a signature digest?
#
# Approach:
#   1. For each case's lib.slang, precompile to .slang-module, then run
#      `slangc -dump-module` to get the IR dump.
#   2. Hash the dump.
#   3. Compare each case's hash to the baseline's.
#   4. Cross-reference against the catalogue's predicted "breaks"/"passes":
#      a useful digest changes for every break and doesn't change for any pass.
#
# Re-run with: bash experiments/semver-break-catalog/probe-dump-module.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "${HERE}/.." && pwd)"
SLANGC="${EXP_ROOT}/.slang-bin/bin/slangc"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
OUT="${HERE}/probe-dump-module.txt"

if [[ ! -x "${SLANGC}" ]]; then
  echo "ERROR: run run.sh first to install slangc" >&2
  exit 1
fi

dump_hash() {
  local lib="$1"
  local module="${WORK}/dump.slang-module"
  rm -f "${module}"
  if ! "${SLANGC}" -emit-ir "${lib}" -o "${module}" 2>/dev/null; then
    echo "ERROR-emit"
    return
  fi
  local dump
  dump="$("${SLANGC}" -dump-module "${module}" 2>&1)"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "ERROR-dump"
    return
  fi
  printf '%s' "${dump}" | sha256sum | awk '{print $1}'
}

file_hash() {
  # The .slang-module binary embeds the source path. To make file-hashing
  # source-equivalent (independent of where the .slang file happens to live),
  # we stage the source as a canonical "lib.slang" before compiling.
  local lib="$1"
  local stage="${WORK}/canonical.slang"
  local module="${WORK}/file.slang-module"
  rm -f "${module}"
  cp -f "${lib}" "${stage}"
  if ! ( cd "${WORK}" && "${SLANGC}" -emit-ir canonical.slang -o file.slang-module 2>/dev/null ); then
    echo "ERROR-emit"
    return
  fi
  sha256sum "${module}" | awk '{print $1}'
}

: > "${OUT}"
{
  echo "Slang -dump-module probe"
  echo "Date  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "Step 1. Stability check: same baseline compiled twice."
} >> "${OUT}"

h1="$(dump_hash "${HERE}/baseline/lib.slang")"
h2="$(dump_hash "${HERE}/baseline/lib.slang")"
{
  echo "  hash 1: ${h1}"
  echo "  hash 2: ${h2}"
  if [[ "${h1}" == "${h2}" ]]; then
    echo "  -> STABLE: hashes match across runs."
  else
    echo "  -> UNSTABLE: hashes differ across runs of the same source."
  fi
} >> "${OUT}"

{
  echo ""
  echo "Step 2. Per-case digest vs baseline."
  echo "  - Main surface cases compared against baseline/lib.slang."
  echo "  - Capability cases compared against capabilities/baseline-control/lib.slang"
  echo "    (they share a different baseline; the lib.slang structure is smaller)."
  echo "  - Two digest sources compared: -dump-module text vs raw .slang-module file."
  echo ""
  printf '%-45s %-8s %-9s %-9s %s\n' "case" "expected" "dump" "file" "notes"
} >> "${OUT}"

baseline_dump_hash="${h1}"
baseline_file_hash="$(file_hash "${HERE}/baseline/lib.slang")"
cap_baseline_dump_hash="$(dump_hash "${HERE}/cases/capabilities/baseline-control/lib.slang")"
cap_baseline_file_hash="$(file_hash "${HERE}/cases/capabilities/baseline-control/lib.slang")"

classify_one() {
  local expected="$1"
  local result="$2"
  case "${expected}:${result}" in
    breaks:diff)    echo "ok" ;;
    passes:same)    echo "ok" ;;
    breaks:same)    echo "MISS" ;;
    passes:diff)    echo "OVER" ;;
    breaks:ERROR-*) echo "ok-err" ;;
    *:ERROR-*)      echo "probe-fail" ;;
    *)              echo "?" ;;
  esac
}
# Legend interpretation:
#   ok      = digest verdict agrees with empirical outcome.
#   ok-err  = library no longer compiles; either digest signals it.
#   MISS    = false negative — digest matches when consumer breaks. Lets a
#             real major change ship as minor. Dangerous.
#   OVER    = false positive — digest differs when consumer doesn't break.
#             Not "harmless": for a publish-time tool this forces a
#             major-version bump for a change that doesn't need one,
#             which trains authors to override or ignore the tool.

shopt -s nullglob
for case_dir in "${HERE}"/cases/*/*/; do
  rel="${case_dir#${HERE}/cases/}"
  rel="${rel%/}"
  expected="$(cat "${case_dir}/EXPECTED" 2>/dev/null || echo "?")"

  if [[ "${rel}" == capabilities/* ]]; then
    cmp_dump="${cap_baseline_dump_hash}"
    cmp_file="${cap_baseline_file_hash}"
  else
    cmp_dump="${baseline_dump_hash}"
    cmp_file="${baseline_file_hash}"
  fi

  dh="$(dump_hash "${case_dir}/lib.slang")"
  fh="$(file_hash "${case_dir}/lib.slang")"

  if [[ "${dh}" == ERROR-* ]]; then dr="${dh}"
  elif [[ "${dh}" == "${cmp_dump}" ]]; then dr="same"
  else dr="diff"; fi

  if [[ "${fh}" == ERROR-* ]]; then fr="${fh}"
  elif [[ "${fh}" == "${cmp_file}" ]]; then fr="same"
  else fr="diff"; fi

  dv="$(classify_one "${expected}" "${dr}")"
  fv="$(classify_one "${expected}" "${fr}")"

  printf '%-45s %-8s %-9s %-9s dump=%s file=%s\n' "${rel}" "${expected}" "${dr}" "${fr}" "${dv}" "${fv}" >> "${OUT}"
done
shopt -u nullglob

{
  echo ""
  echo "Legend:"
  echo "  ok     = digest verdict agrees with empirical outcome."
  echo "  ok-err = library no longer compiles; either digest signals it."
  echo "  MISS   = false negative — digest matches when consumer breaks."
  echo "           Lets a real major change ship as minor. Dangerous."
  echo "  OVER   = false positive — digest differs when consumer doesn't"
  echo "           break. For a publish-time tool this forces a major"
  echo "           bump that wasn't needed, which trains authors to"
  echo "           override or ignore the tool. Not 'just nuisance.'"
} >> "${OUT}"

echo "==> Wrote ${OUT}"
cat "${OUT}"
