#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/start-local.sh

Options:
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

docker compose up -d ollama chat2m-gateway

echo "Chat2M local chat is running."
echo "Gateway is available inside the compose network at http://chat2m-gateway:8080"
echo "Model:  configured in data/config/runtime.env"
