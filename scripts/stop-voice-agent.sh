#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

docker compose -p chat2m rm -sf chat2m-wake chat2m-speech chat2m-status

echo "Chat2M voice services stopped."
