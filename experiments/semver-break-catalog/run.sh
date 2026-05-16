#!/usr/bin/env bash
# Catalogue of API changes vs. consumer compatibility for Slang modules.
#
# For each case under cases/<category>/<name>/:
#   1. Stage the case's lib.slang at <tmp>/@org/lib.slang.
#   2. Compile consumer.slang against it.
#   3. Compare actual outcome (compiles / fails) against EXPECTED.
#   4. Append the result + diagnostic to results.txt.
#
# Re-run with: bash experiments/semver-break-catalog/run.sh

set -uo pipefail

SLANG_VERSION="2026.8.1"
SLANG_TARBALL="slang-${SLANG_VERSION}-linux-x86_64.tar.gz"
SLANG_URL="https://github.com/shader-slang/slang/releases/download/v${SLANG_VERSION}/${SLANG_TARBALL}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "${HERE}/.." && pwd)"
BIN_ROOT="${EXP_ROOT}/.slang-bin"
SLANGC="${BIN_ROOT}/bin/slangc"
RESULTS="${HERE}/results.txt"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

if [[ ! -x "${SLANGC}" ]]; then
  echo "==> Downloading Slang v${SLANG_VERSION}"
  mkdir -p "${BIN_ROOT}"
  tmpdir="$(mktemp -d)"
  if ! curl -fsSL -o "${tmpdir}/${SLANG_TARBALL}" "${SLANG_URL}"; then
    rm -rf "${tmpdir}"
    echo "ERROR: download failed: ${SLANG_URL}" >&2
    exit 1
  fi
  tar -xzf "${tmpdir}/${SLANG_TARBALL}" -C "${BIN_ROOT}"
  rm -rf "${tmpdir}"
fi

mkdir -p "${STAGE_DIR}/@org"

declare -i n_total=0 n_surprises=0

run_case() {
  local case_dir="$1"
  local rel="${case_dir#${HERE}/cases/}"
  local expected
  expected="$(cat "${case_dir}/EXPECTED" 2>/dev/null || echo "?")"

  cp -f "${case_dir}/lib.slang" "${STAGE_DIR}/@org/lib.slang"

  local consumer="${HERE}/consumer.slang"
  if [[ -f "${case_dir}/consumer.slang" ]]; then
    consumer="${case_dir}/consumer.slang"
  fi

  local out
  out="$("${SLANGC}" -target spirv -stage compute -entry main \
    -I "${STAGE_DIR}" -o "${STAGE_DIR}/out.spv" \
    "${consumer}" 2>&1)"
  local rc=$?
  rm -f "${STAGE_DIR}/out.spv"

  local actual
  if [[ $rc -eq 0 ]]; then actual="passes"; else actual="breaks"; fi

  local verdict="ok"
  if [[ "${expected}" != "${actual}" ]]; then
    verdict="SURPRISE"
    n_surprises+=1
  fi
  n_total+=1

  {
    echo
    echo "================================================================"
    echo "CASE     : ${rel}"
    echo "EXPECTED : ${expected}"
    echo "ACTUAL   : ${actual}    [${verdict}]"
    echo "EXIT     : ${rc}"
    if [[ -n "${out}" ]]; then
      echo "----------------------------------------------------------------"
      echo "${out}"
    fi
  } >> "${RESULTS}"
}

: > "${RESULTS}"
{
  echo "Slang semver-break catalogue"
  echo "Date  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Slangc: ${SLANG_VERSION}"
} >> "${RESULTS}"

shopt -s nullglob
for case_dir in "${HERE}"/cases/*/*/; do
  run_case "${case_dir%/}"
done
shopt -u nullglob

{
  echo
  echo "================================================================"
  echo "TOTAL    : ${n_total}"
  echo "SURPRISES: ${n_surprises}"
} >> "${RESULTS}"

echo "==> Wrote ${RESULTS}"
echo "==> ${n_total} cases, ${n_surprises} surprise(s)"
awk '
  /^CASE     :/ { c=$0; sub(/^CASE     : /,"",c) }
  /^EXPECTED :/ { e=$0; sub(/^EXPECTED : /,"",e) }
  /^ACTUAL   :/ { a=$0; sub(/^ACTUAL   : /,"",a); printf "  %-40s exp=%-7s got=%s\n", c, e, a }
' "${RESULTS}"
