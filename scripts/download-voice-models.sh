#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
mkdir -p data/models data/config

docker compose run --rm --no-deps \
  -e VOICE_ROLE="${VOICE_ROLE:-}" \
  chat2m-speech true

echo "Voice models are ready in $ROOT_DIR/data/models"
