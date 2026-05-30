#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

docker compose rm -sf chat2me-speech chat2me-asr chat2me-tts chat2me-status

echo "Chat2Me voice services stopped."
