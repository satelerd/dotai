#!/usr/bin/env bash
# Build the sandbox, run the teleport e2e suite inside it, tear it down.
# Real ssh/rsync/git — never the host $HOME. Requires Docker.
#
#   tests/run.sh            # build + run, auto-cleanup
#   KEEP=1 tests/run.sh     # leave the container up for poking around
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
img="dotai-tp-test"
name="dotai-tp-test-run-$$"

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }

cleanup(){ [[ "${KEEP:-0}" == 1 ]] || docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "▶ building sandbox image…"
docker build -q -t "$img" "$here" >/dev/null

echo "▶ starting container…"
docker run -d --name "$name" -v "$repo:/opt/dotai:ro" "$img" >/dev/null

# wait for sshd to accept connections
for _ in $(seq 1 20); do
  docker exec "$name" bash -lc 'ssh -o StrictHostKeyChecking=no -o ConnectTimeout=1 tester@localhost true' \
    >/dev/null 2>&1 && break
  sleep 0.5
done

echo "▶ running e2e suite…"
rc=0
docker exec -u tester "$name" bash /opt/dotai/tests/in_container.sh || rc=$?

[[ "${KEEP:-0}" == 1 ]] && echo "container kept: $name (docker exec -u tester -it $name bash)"
exit $rc
