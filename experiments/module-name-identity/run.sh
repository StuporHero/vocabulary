#!/usr/bin/env bash
# Probes Slang's handling of string-form module names.
#
# Question: when consumer code does `import "@a/math";` and `import "@b/math";`,
# does the linker treat them as distinct modules, or collapse them to a single
# `math` (and complain about redefinition)?
#
# Re-run with: bash experiments/module-name-identity/run.sh
# Results land in experiments/module-name-identity/results.txt.

set -uo pipefail

SLANG_VERSION="2026.8.1"
SLANG_TARBALL="slang-${SLANG_VERSION}-linux-x86_64.tar.gz"
SLANG_URL="https://github.com/shader-slang/slang/releases/download/v${SLANG_VERSION}/${SLANG_TARBALL}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "${HERE}/.." && pwd)"
BIN_ROOT="${EXP_ROOT}/.slang-bin"
SLANGC="${BIN_ROOT}/bin/slangc"
RESULTS="${HERE}/results.txt"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "${OUT_DIR}"' EXIT

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

if [[ ! -x "${SLANGC}" ]]; then
  echo "ERROR: slangc not found at ${SLANGC} after extraction" >&2
  exit 1
fi

cd "${HERE}"

run_case() {
  local label="$1"
  local ext="$2"
  local outfile="${OUT_DIR}/out.${ext}"
  shift 2
  {
    echo
    echo "================================================================"
    echo "CASE: ${label}"
    echo "CMD : slangc $* -o <out.${ext}>"
    echo "----------------------------------------------------------------"
    "${SLANGC}" "$@" -o "${outfile}" 2>&1
    local rc=$?
    echo "----------------------------------------------------------------"
    echo "EXIT: ${rc}"
    rm -f "${outfile}"
  } >> "${RESULTS}"
}

: > "${RESULTS}"
{
  echo "Slang module-name-identity probe"
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Slangc: ${SLANG_VERSION}"
} >> "${RESULTS}"

# Case 1: does `module "@a/math";` precompile to .slang-module?
run_case "1. precompile @a/math to .slang-module" slang-module \
  -emit-ir 'pkgs/@a/math.slang'

run_case "1b. precompile @b/math to .slang-module" slang-module \
  -emit-ir 'pkgs/@b/math.slang'

run_case "2. precompile plain_math to .slang-module" slang-module \
  -emit-ir 'pkgs/plain-math.slang'

# Case 3: LOAD-BEARING — consumer imports BOTH @a/math and @b/math.
# If linker keys identity on full string, both a_marker() and b_marker()
# resolve and we get clean SPIR-V. If it keys on basename, expect a
# redefinition or "module already loaded" error.
run_case "3. consumer imports BOTH @a/math and @b/math" spv \
  -target spirv -stage compute -entry main \
  -I pkgs consumer-string.slang

# Case 4: identifier-form import of plain_math (sanity)
run_case "4. identifier-form import of plain_math" spv \
  -target spirv -stage compute -entry main \
  -I pkgs consumer-ident.slang

# Case 5: consumer imports ONLY @a/math (sanity for interpreting case 3)
run_case "5. consumer imports ONLY @a/math" spv \
  -target spirv -stage compute -entry main \
  -I pkgs consumer-a-only.slang

# Case 6: a module declared with `module "conflict";` (string form, no slash)
# imported via `import conflict;` (identifier form) — do the two forms agree?
run_case "6. identifier-import of a string-declared module" spv \
  -target spirv -stage compute -entry main \
  -I pkgs-conflict consumer-conflict.slang

# Case 7: both modules export the SAME symbol name. If identity is
# string-keyed, both modules load distinctly and the consumer sees an
# ambiguous call (not a "module already loaded" / redefinition error).
run_case "7. two modules export the SAME symbol name" spv \
  -target spirv -stage compute -entry main \
  -I pkgs-collide consumer-collide.slang

echo
echo "==> Wrote ${RESULTS}"
echo "==> Summary:"
grep -E '^(CASE|EXIT)' "${RESULTS}"
