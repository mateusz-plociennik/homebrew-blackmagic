#!/bin/bash
# Offline checks for bin/changed-casks, with `gh` stubbed on PATH.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
export PR=1 GITHUB_REPOSITORY=owner/repo PATH="$stub:$PATH"

stub_gh() {
  printf '#!/bin/sh\n%s\n' "$1" > "$stub/gh"
  chmod +x "$stub/gh"
}

fail() { echo "FAIL: $*"; exit 1; }

stub_gh 'exit 1'
if out=$("$root/bin/changed-casks" 2>&1); then fail "gh failure was not propagated (got '$out')"; fi

stub_gh 'exit 0'
out=$("$root/bin/changed-casks") || fail "empty diff exited nonzero"
[ -z "${out// /}" ] || fail "empty diff selected '$out'"

stub_gh 'printf "%s\n" README.md Casks/blackmagic-video-assist.rb Casks/blackmagic-deleted.rb lib/x.rb'
out=$("$root/bin/changed-casks") || fail "diff exited nonzero"
[ "$out" = " blackmagic-video-assist" ] || fail "expected ' blackmagic-video-assist', got '$out'"

echo "changed-casks: all checks passed"
