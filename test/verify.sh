#!/bin/bash
# Project verify command: lint every shell file, run all tests, and check the shipped tree.
#
# Run from anywhere: `bash test/verify.sh`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

echo "shellcheck..."
shellcheck -S style bootstrap.sh fleet.sh entrypoint.sh start.sh work_queue test/*.sh examples/playground.sh

echo "spec and implementation tests..."
bash test/work_queue.spec.test.sh
bash test/orgs.spec.test.sh
bash test/entrypoint.spec.test.sh
bash test/start.spec.test.sh
bash test/dockerfile.spec.test.sh
bash test/compose.spec.test.sh
bash test/entrypoint.impl.test.sh
bash test/start.impl.test.sh
bash test/fleet.spec.test.sh
bash test/fleet.impl.test.sh
bash test/bootstrap.spec.test.sh

echo "removed-script references..."
if git grep --untracked -nE '(build-image|restart)\.sh' -- . ':(exclude)test/verify.sh'; then
    echo "ERROR: shipped files must not reference the removed scripts" >&2
    exit 1
fi

echo "verify: PASS"
