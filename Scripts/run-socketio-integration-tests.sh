#!/bin/sh

set -eu

command -v node >/dev/null 2>&1 || {
  echo "node is required" >&2
  exit 1
}

command -v npm >/dev/null 2>&1 || {
  echo "npm is required" >&2
  exit 1
}

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_directory="$repository_root/IntegrationTests/SocketIOReferenceServer"

npm ci --prefix "$fixture_directory"

cd "$repository_root"
RUN_SOCKETIO_INTEGRATION_TESTS=1 swift test \
  -Xswiftc -warnings-as-errors \
  --explicit-target-dependency-import-check error \
  --filter RagnarSocketIOIntegrationTests
